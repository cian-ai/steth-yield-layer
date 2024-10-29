// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../interfaces/flashloanHelper/IFlashloanHelper.sol";
import "../../../interfaces/lido/IWstETH.sol";
import "../../../interfaces/IVault.sol";
import "../../../interfaces/aave/v3/IPoolV3.sol";
import "../../../interfaces/aave/IAaveOracle.sol";
import "../../../interfaces/renzo/IRenzoOracle.sol";
import "../../../interfaces/renzo/IRestakeManager.sol";
import "../../../interfaces/renzo/IWithdrawQueue.sol";
import "../../../interfaces/IStrategy.sol";
import "../../libraries/Errors.sol";
import "../../swap/OneInchCallerV6.sol";
import "../../common/MultiETH.sol";

contract StrategyAAVEV3EzETH is IStrategy, MultiETH, OneInchCallerV6, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    // The maximum allowable ratio for the protocol, set to 93%
    uint256 public constant MAX_PROTOCOL_RATIO = 0.93e18;

    address internal constant EZETH = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;

    address internal constant RENZO_ORACLE = 0x5a12796f7e7EBbbc8a402667d266d2e65A814042;

    address internal constant RENZO_RESTAKE_MANAGER = 0x74a09653A083691711cF8215a6ab074BB4e99ef5;

    address internal constant RENZO_WITHDRAW_QUEUE = 0x5efc9D10E42FB517456f4ac41EB5e2eBe42C8918;

    // The address of the AAVE v3 aToken for ezETH
    address internal constant A_EZETH_AAVEV3 = 0x74e5664394998f13B07aF42446380ACef637969f;

    // The address of the AAVE v3 variable debt token for wstETH
    address internal constant D_WSTETH_AAVEV3 = 0xE439edd2625772AA635B437C099C607B6eb7d35f;

    // The address of the AAVE v3 Oracle contract
    IAaveOracle internal constant ORACLE_AAVEV3 = IAaveOracle(0xE3C061981870C0C7b1f3C4F4bB36B95f1F260BE6);

    // The address of the AAVE v3 Pool contract
    IPoolV3 internal constant POOL_AAVEV3 = IPoolV3(0x4e033931ad43597d96D6bcc25c280717730B58B1);

    // The address of the Vault contract that manages user shares
    address public vault;

    // The intermediary contract for executing flashloan operations
    address public flashloanHelper;

    // The address used to prevent flashloan re-entry attacks
    address public executor;

    // The address of the position adjustment manager
    address public rebalancer;

    // The safe collateral rate for the protocol
    uint256 public safeProtocolRatio;

    event UpdateFlashloanHelper(address oldFlashloanHelper, address newFlashloanHelper);
    event UpdateRebalancer(address oldRebalancer, address newRebalancer);
    event UpdateSafeProtocolRatio(uint256 oldSafeProtocolRatio, uint256 newSafeProtocolRatio);
    event OnTransferIn(address token, uint256 amount);
    event TransferToVault(address token, uint256 amount);
    event Leverage(uint256 deposit, uint256 debtAmount, bytes swapData, uint256 flashloanSelector);
    event Deleverage(uint256 deleverageAmount, uint256 withdrawAmount, bytes swapData, uint256 flashloanSelector);
    event Repay(uint256 amount);

    /**
     * @dev Ensure that this method is only called by the Vault contract.
     */
    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.CallerNotVault();
        _;
    }

    /**
     * @dev  Ensure that this method is only called by authorized portfolio managers.
     */
    modifier onlyRebalancer() {
        if (msg.sender != rebalancer) revert Errors.CallerNotRebalancer();
        _;
    }

    /**
     * @dev Initialize the strategy with given parameters.
     * @param _initBytes Initialization data
     */
    function initialize(bytes calldata _initBytes) external initializer {
        (uint256 safeProtocolRatio_, address admin_, address flashloanHelper_, address rebalancer_) =
            abi.decode(_initBytes, (uint256, address, address, address));
        if (admin_ == address(0)) revert Errors.InvalidAdmin();
        if (flashloanHelper_ == address(0)) revert Errors.InvalidFlashloanHelper();
        if (safeProtocolRatio_ > MAX_PROTOCOL_RATIO) revert Errors.InvalidSafeProtocolRatio();
        if (rebalancer_ == address(0)) revert Errors.InvalidRebalancer();
        __Ownable_init(admin_);
        flashloanHelper = flashloanHelper_;
        safeProtocolRatio = safeProtocolRatio_;
        rebalancer = rebalancer_;
        vault = msg.sender;
        // enterProtocol();
    }

    /**
     * @dev Enter the AAVE protocol by approving tokens.
     */
    function enterProtocol() external onlyRebalancer {
        IERC20(WSTETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);
        IERC20(EZETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);

        POOL_AAVEV3.setUserEMode(3);
    }

    /**
     * @dev Update the address of the intermediary contract used for flashloan operations.
     * @param _newFlashloanHelper The new contract address.
     */
    function updateFlashloanHelper(address _newFlashloanHelper) external onlyOwner {
        if (_newFlashloanHelper == address(0)) revert Errors.InvalidFlashloanHelper();
        emit UpdateFlashloanHelper(flashloanHelper, _newFlashloanHelper);
        flashloanHelper = _newFlashloanHelper;
    }

    /**
     * @dev Add a new address to the position adjustment whitelist.
     * @param _newRebalancer The new address to be added.
     */
    function updateRebalancer(address _newRebalancer) external onlyOwner {
        if (_newRebalancer == address(0)) revert Errors.InvalidRebalancer();
        emit UpdateRebalancer(rebalancer, _newRebalancer);
        rebalancer = _newRebalancer;
    }

    function updateSafeProtocolRatio(uint256 _newRatio) external onlyOwner {
        if (_newRatio > MAX_PROTOCOL_RATIO) revert Errors.InvalidSafeProtocolRatio();
        emit UpdateSafeProtocolRatio(safeProtocolRatio, _newRatio);
        safeProtocolRatio = _newRatio;
    }

    /**
     * @dev Transfers funds from the vault contract to this contract.
     * This function is called by the vault to move tokens into this contract.
     * It uses the `safeTransferFrom` function from the SafeERC20 library to ensure the transfer is successful.
     * @param _token The address of the token to be transferred.
     * @param _amount The amount of tokens to be transferred.
     * @return A boolean indicating whether the transfer was successful.
     */
    function onTransferIn(address _token, uint256 _amount) external onlyVault returns (bool) {
        if (_token != STETH) revert Errors.InvalidAsset();
        uint256 ezETHBefore_ = IERC20(EZETH).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(STETH).safeIncreaseAllowance(RENZO_RESTAKE_MANAGER, _amount);
        IRestakeManager(RENZO_RESTAKE_MANAGER).deposit(STETH, _amount);
        uint256 ezETHGet_ = IERC20(EZETH).balanceOf(address(this)) - ezETHBefore_;
        if (ezETHGet_ == 0) revert Errors.IncorrectState();
        emit OnTransferIn(_token, _amount);
        return true;
    }

    /**
     * @dev Transfer tokens to the Vault.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     */
    function transferToVault(address _token, uint256 _amount) external onlyRebalancer {
        // Convert them all to ezETH
        IERC20(_token).safeTransfer(vault, _amount);
        emit TransferToVault(_token, _amount);
    }

    function repay(uint256 _amount) external onlyRebalancer {
        executeRepay(WSTETH, _amount);

        emit Repay(_amount);
    }

    function dummySwap(uint256 _swapInAmount) internal returns (uint256) {
        uint256 stEthAmount_ = IWstETH(WSTETH).unwrap(_swapInAmount);
        uint256 ezETHBefore_ = IERC20(EZETH).balanceOf(address(this));
        IERC20(STETH).safeIncreaseAllowance(RENZO_RESTAKE_MANAGER, stEthAmount_);
        IRestakeManager(RENZO_RESTAKE_MANAGER).deposit(STETH, stEthAmount_);
        uint256 ezETHGet_ = IERC20(EZETH).balanceOf(address(this)) - ezETHBefore_;
        if (ezETHGet_ == 0) revert Errors.IncorrectState();
        return ezETHGet_;
    }

    /**
     * @dev Wrap STETH to WSTETH.
     */
    function _wrap() internal returns (uint256) {
        uint256 stEthAmount_ = IERC20(STETH).balanceOf(address(this));
        IERC20(STETH).safeIncreaseAllowance(WSTETH, stEthAmount_);
        uint256 wstETHAmount_ = IWstETH(WSTETH).wrap(stEthAmount_);
        return wstETHAmount_;
    }

    function wrap() public onlyRebalancer {
        _wrap();
    }

    /**
     * @dev Unwrap WSTETH to STETH.
     */
    function _unwrap() internal returns (uint256) {
        uint256 wstETHAmount_ = IERC20(WSTETH).balanceOf(address(this));
        uint256 stEthAmount_ = IWstETH(WSTETH).unwrap(wstETHAmount_);
        return stEthAmount_;
    }

    function unwrap() public onlyRebalancer {
        _unwrap();
    }

    function convertToEzETH(uint256 _swapInAmount) external onlyRebalancer {
        dummySwap(_swapInAmount);
    }

    function convertFromEzETH(uint256 _swapInAmount, uint256 _minOut, bytes calldata _payload) external onlyRebalancer {
        if (_payload.length == 0) {
            // Check if there's pending withdraw request
            uint256 outstandingWithdrawRequests_ = IWithdrawQueue(RENZO_WITHDRAW_QUEUE).getOutstandingWithdrawRequests(address(this));
            if (outstandingWithdrawRequests_ > 0) {
                // Revert if there's pending withdraw request
                revert Errors.IncorrectState();
            }
            // Approve EZETH to WithdrawQueue
            IERC20(EZETH).safeIncreaseAllowance(RENZO_WITHDRAW_QUEUE, _swapInAmount);
            IWithdrawQueue(RENZO_WITHDRAW_QUEUE).withdraw(_swapInAmount, ETH);
            return;
        }
        IERC20(EZETH).safeIncreaseAllowance(ONEINCH_ROUTER, _swapInAmount);
        executeSwap(_swapInAmount, EZETH, WSTETH, _payload, _minOut);
    }

    function claimExited() public onlyRebalancer {
        uint256 outstandingWithdrawRequests_ = IWithdrawQueue(RENZO_WITHDRAW_QUEUE).getOutstandingWithdrawRequests(address(this));
        if (outstandingWithdrawRequests_ == 0) return;
        for (uint256 i = 0; i < outstandingWithdrawRequests_; i++) {
            IWithdrawQueue(RENZO_WITHDRAW_QUEUE).claim(i, address(this));
        }
        // Convert ETH balance to WstETH
        uint256 ethBalance_ = address(this).balance;
        if (ethBalance_ > 0) {
            _convertToken(ETH, WETH, 0); // Convert to WETH to make it easier to convert to WstETH
        }
    }

    /**
     * @dev Execute a leverage operation.
     * @param _deposit The amount to deposit.
     * @param _leverageAmount The amount to leverage.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     * @param _flashloanSelector The flashloan selector.
     */
    function leverage(
        uint256 _deposit,
        uint256 _leverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external onlyRebalancer {
        executeDeposit(EZETH, _deposit);
        if (_leverageAmount == 0) return;
        uint256 availableBorrowsWSTETH_ = getAvailableBorrowsWSTETH();
        if (_leverageAmount < availableBorrowsWSTETH_) {
            leverageSelf(_leverageAmount, _swapData, _swapGetMin);
        } else {
            executeFlashLoan(true, _leverageAmount, _swapData, _swapGetMin, _flashloanSelector);
        }
        checkProtocolRatio();

        emit Leverage(_deposit, _leverageAmount, _swapData, _flashloanSelector);
    }

    /**
     * @dev Execute a deleverage operation.
     * @param _withdraw The amount to withdraw.
     * @param _deleverageAmount The amount to deleverage.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     * @param _flashloanSelector The flashloan selector.
     */
    function deleverage(
        uint256 _withdraw,
        uint256 _deleverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external onlyRebalancer {
        if (_deleverageAmount > 0) {
            uint256 availableWithdrawEzETH = getAvailableWithdrawsEzETH();
            if (_deleverageAmount < availableWithdrawEzETH) deleverageSelf(_deleverageAmount, _swapData, _swapGetMin);
            else executeFlashLoan(false, _deleverageAmount, _swapData, _swapGetMin, _flashloanSelector);
        }
        executeWithdraw(EZETH, _withdraw);
        checkProtocolRatio();
        emit Deleverage(_deleverageAmount, _withdraw, _swapData, _flashloanSelector);
    }

    /**
     * @dev Callback function for flashloan operations.
     * @param _initiator The address of the initiator.
     * @param _token The address of the token.
     * @param _amount The amount of tokens.
     * @param _fee The fee for the flashloan.
     * @param _params The parameters for the flashloan.
     * @return A bytes32 value indicating success.
     */
    function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata _params)
        external
        returns (bytes32)
    {
        if (msg.sender != flashloanHelper || executor == address(0) || _initiator != address(this)) {
            revert Errors.InvalidFlashloanCall();
        }
        (bool isLeverage_, bytes memory swapData_, uint256 swapGetMin_) = abi.decode(_params, (bool, bytes, uint256));
        isLeverage_
            ? leverageCallback(_amount, _fee, swapData_, swapGetMin_)
            : deleverageCallback(_amount, _fee, swapData_, swapGetMin_);
        IERC20(_token).safeIncreaseAllowance(msg.sender, _amount + _fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /**
     * @dev Get the available borrows in ETH.
     * @return availableBorrowsWSTETH_ The amount of available borrows in ETH.
     */
    function getAvailableBorrowsWSTETH() public view returns (uint256 availableBorrowsWSTETH_) {
        (,, uint256 availableBorrowsInUsd_,,,) = POOL_AAVEV3.getUserAccountData(address(this));
        if (availableBorrowsInUsd_ > 0) {
            uint256 price_ = ORACLE_AAVEV3.getAssetPrice(WSTETH);
            availableBorrowsWSTETH_ = availableBorrowsInUsd_ * PRECISION / price_;
        }
    }

    /**
     * @dev Get the available withdrawable amount in ezETH.
     * @return maxWithdrawsWstETH_ The maximum amount of ezETH that can be withdrawn.
     */
    function getAvailableWithdrawsEzETH() public view returns (uint256 maxWithdrawsWstETH_) {
        (uint256 colInUsd_, uint256 debtInUsd_,,, uint256 ltv_,) = POOL_AAVEV3.getUserAccountData(address(this));
        if (colInUsd_ > 0) {
            uint256 colMin_ = debtInUsd_ * 1e4 / ltv_;
            uint256 maxWithdrawsInUsd_ = colInUsd_ > colMin_ ? colInUsd_ - colMin_ : 0;
            uint256 ezEthPrice_ = ORACLE_AAVEV3.getAssetPrice(EZETH);
            maxWithdrawsWstETH_ = maxWithdrawsInUsd_ * PRECISION / ezEthPrice_;
        }
    }

    function getRatio() public view returns (uint256 ratio_) {
        (uint256 ezEthAmount_, uint256 debtEzEthAmount_) = getProtocolAccountData();
        ratio_ = ezEthAmount_ == 0 ? 0 : debtEzEthAmount_ * PRECISION / ezEthAmount_;
    }

    /**
     * @dev Get the collateral ratio and its status.
     * @return collateralRatio_ The collateral ratio.
     * @return isOK_ Boolean indicating whether the ratio is within safe limits.
     */
    function getCollateralRatio() public view returns (uint256 collateralRatio_, bool isOK_) {
        (uint256 totalCollateralBase_, uint256 totalDebtBase_,,,,) = POOL_AAVEV3.getUserAccountData(address(this));
        collateralRatio_ = totalCollateralBase_ == 0 ? 0 : totalDebtBase_ * PRECISION / totalCollateralBase_;
        isOK_ = safeProtocolRatio > collateralRatio_;
    }

    /**
     * @dev Get the amount for leverage or deleverage operation.
     * @param _isDepositOrWithdraw Boolean indicating whether the operation is a deposit or withdrawal.
     * @param _depositOrWithdraw The  amount to deposit or withdraw.
     * @return isLeverage_ Boolean indicating whether the operation is leverage.
     * @return loanAmount_ The loan amount wsteth.
     */
    function getLeverageAmount(bool _isDepositOrWithdraw, uint256 _depositOrWithdraw)
        public
        view
        returns (bool isLeverage_, uint256 loanAmount_)
    {
        uint256 ezethPrice_ = ORACLE_AAVEV3.getAssetPrice(EZETH);
        uint256 wstethPrice_ = ORACLE_AAVEV3.getAssetPrice(WSTETH);
        uint256 totalCollateralWstETH_ = IERC20(A_EZETH_AAVEV3).balanceOf(address(this)) * ezethPrice_ / wstethPrice_;
        uint256 totalDebtWstETH_ = IERC20(D_WSTETH_AAVEV3).balanceOf(address(this));
        uint256 depositOrWithdrawInWstETH_ = getWstETHByEzETH(_depositOrWithdraw) * ezethPrice_ / wstethPrice_;

        totalCollateralWstETH_ = _isDepositOrWithdraw
            ? (totalCollateralWstETH_ + depositOrWithdrawInWstETH_)
            : (totalCollateralWstETH_ - depositOrWithdrawInWstETH_);
        if (totalCollateralWstETH_ != 0) {
            uint256 ratio = totalCollateralWstETH_ == 0 ? 0 : totalDebtWstETH_ * PRECISION / totalCollateralWstETH_;
            isLeverage_ = ratio < safeProtocolRatio ? true : false;
            if (isLeverage_) {
                loanAmount_ = (safeProtocolRatio * totalCollateralWstETH_ - totalDebtWstETH_ * PRECISION)
                    / (PRECISION - safeProtocolRatio);
            } else {
                loanAmount_ = (totalDebtWstETH_ * PRECISION - safeProtocolRatio * totalCollateralWstETH_)
                    / (PRECISION - safeProtocolRatio);
            }
        }
    }

    function getETHByEzETH(uint256 _ezethAmount) public view returns (uint256) {
        return _ezethAmount * 1 ether / getEzETHByETH(1 ether);
    }

    function getEzETHByETH(uint256 _ethAmount) public view returns (uint256) {
        (,, uint256 totalTVL) = IRestakeManager(RENZO_RESTAKE_MANAGER).calculateTVLs();
        return IRenzoOracle(RENZO_ORACLE).calculateMintAmount(totalTVL, _ethAmount, IERC20(EZETH).totalSupply());
    }

    function getETHByWstETH(uint256 _wstethAmount) public view returns (uint256) {
        return IWstETH(WSTETH).getStETHByWstETH(_wstethAmount);
    }

    function getWstETHByETH(uint256 _ethAmount) public view returns (uint256) {
        return IWstETH(WSTETH).getWstETHByStETH(_ethAmount);
    }

    // ezETH - > ETH -> wstETH
    function getWstETHByEzETH(uint256 _ezethAmount) public view returns (uint256) {
        if (_ezethAmount == 0) return 0;
        return getWstETHByETH(getETHByEzETH(_ezethAmount));
    }

    // wstETH - > ETH -> ezETH
    function getEzETHByWstETH(uint256 _wstethAmount) public view returns (uint256) {
        if (_wstethAmount == 0) return 0;
        return getEzETHByETH(getETHByWstETH(_wstethAmount));
    }

    /**
     * @dev Get the protocol account data.
     * @return ezEthAmount_ The amount of supplied wstETH in ezETH.
     * @return debtEzEthAmount_ The amount of debt in ETH.
     */
    function getProtocolAccountData() public view returns (uint256 ezEthAmount_, uint256 debtEzEthAmount_) {
        (bool success, bytes memory returnData) = A_EZETH_AAVEV3.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        if (!success || returnData.length == 0) ezEthAmount_ = 0;
        else ezEthAmount_ = abi.decode(returnData, (uint256));
        uint256 dwstEthAmount_ = IERC20(D_WSTETH_AAVEV3).balanceOf(address(this));
        debtEzEthAmount_ = dwstEthAmount_ == 0 ? 0 : getEzETHByWstETH(dwstEthAmount_);
    }

    /**
     * @dev Get the amount of net assets in the protocol.
     * @return net_ The amount of net assets.
     */
    function getProtocolNetAssets() public view returns (uint256 net_) {
        (uint256 ezEthAmount_, uint256 debtEzEthAmount_) = getProtocolAccountData();
        net_ = getETHByEzETH(ezEthAmount_ - debtEzEthAmount_);
    }

    /**
     * @dev Get the amount of pending unstaking operations.
     * @return pendingUnstake_ The amount of pending unstaking operations.
     */
    function getUnstakingAmount() public view returns (uint256 pendingUnstake_) {
        uint256 outstandingWithdrawRequests_ = IWithdrawQueue(RENZO_WITHDRAW_QUEUE).getOutstandingWithdrawRequests(address(this));
        if (outstandingWithdrawRequests_ == 0) return 0;
        // Loop over all pending unstaking operations
        uint256 totalAmount_ = 0;
        for (uint256 i = 0; i < outstandingWithdrawRequests_; i++) {
            IWithdrawQueue.WithdrawRequest memory request_ = IWithdrawQueue(RENZO_WITHDRAW_QUEUE).withdrawRequests(address(this), i);
            totalAmount_ += request_.amountToRedeem;
        }
        return totalAmount_;
    }

    /**
     * @dev Get the amount of assets in all lending protocols involved in this contract for the strategy pool.
     * @return netAssets The total amount of net assets.
     */
    function getNetAssets() public view returns (uint256) {
        uint256 wstETHAmount_ = IERC20(WSTETH).balanceOf(address(this));
        uint256 stETHAmount_ = IERC20(STETH).balanceOf(address(this)) + getETHByWstETH(wstETHAmount_);
        return stETHAmount_ + address(this).balance + IERC20(WETH).balanceOf(address(this)) + getETHByEzETH(IERC20(EZETH).balanceOf(address(this))) + getProtocolNetAssets() + getUnstakingAmount();
    }

    /**
     * @dev Execute a self-leverage operation.
     * @param _loanAmount The amount to loan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function leverageSelf(uint256 _loanAmount, bytes calldata _swapData, uint256 _swapGetMin) internal {
        executeBorrow(WSTETH, _loanAmount);
        IERC20(WSTETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        uint256 return_;
        if (_swapData.length == 0) {
            return_ = dummySwap(_loanAmount);
        } else {
            (return_,) = executeSwap(_loanAmount, WSTETH, EZETH, _swapData, _swapGetMin);
        }
        executeDeposit(EZETH, return_);
    }

    /**
     * @dev Execute a self-deleverage operation.
     * @param _deleverageAmount The amount to deleverage.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function deleverageSelf(uint256 _deleverageAmount, bytes calldata _swapData, uint256 _swapGetMin) internal {
        executeWithdraw(EZETH, _deleverageAmount);
        IERC20(EZETH).safeIncreaseAllowance(ONEINCH_ROUTER, _deleverageAmount);
        (uint256 return_,) = executeSwap(_deleverageAmount, EZETH, WSTETH, _swapData, _swapGetMin);
        executeRepay(WSTETH, return_);
    }

    /**
     * @dev Execute a flashloan operation.
     * @param _isLeverage Boolean indicating whether the operation is leverage.
     * @param _loanAmount The amount to loan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     * @param _flashloanSelector The flashloan selector.
     */
    function executeFlashLoan(
        bool _isLeverage,
        uint256 _loanAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) internal {
        bytes memory params_ = abi.encode(_isLeverage, _swapData, _swapGetMin);
        bytes memory dataBytes_ = abi.encode(_flashloanSelector, this.onFlashLoan.selector, params_);

        if (executor != address(0)) revert Errors.FlashloanInProgress();
        executor = msg.sender;
        IFlashloanHelper(flashloanHelper).flashLoan(
            IERC3156FlashBorrower(address(this)), WSTETH, _loanAmount, dataBytes_
        );
        executor = address(0);
    }

    /**
     * @dev Execute a deposit operation in the AAVE protocol.
     * @param _asset The address of the asset to deposit.
     * @param _amount The amount of the asset to deposit.
     */
    function executeDeposit(address _asset, uint256 _amount) internal {
        if (_asset != EZETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.supply(EZETH, _amount, address(this), 0);
    }

    /**
     * @dev Execute a withdrawal operation in the AAVE protocol.
     * @param _asset The address of the asset to withdraw.
     * @param _amount The amount of the asset to withdraw.
     */
    function executeWithdraw(address _asset, uint256 _amount) internal {
        if (_asset != EZETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.withdraw(EZETH, _amount, address(this));
    }

    /**
     * @dev Execute a borrow operation in the AAVE protocol.
     * @param _asset The address of the asset to borrow.
     * @param _amount The amount of the asset to borrow.
     */
    function executeBorrow(address _asset, uint256 _amount) internal {
        if (_asset != WSTETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.borrow(_asset, _amount, 2, 0, address(this));
    }

    /**
     * @dev Execute a repay operation in the AAVE protocol.
     * @param _asset The address of the asset to repay.
     * @param _amount The amount of the asset to repay.
     */
    function executeRepay(address _asset, uint256 _amount) internal {
        if (_asset != WSTETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.repay(_asset, _amount, 2, address(this));
    }

    /**
     * @dev Check the health status of a specific protocol after an operation
     * to prevent the strategy pool from being in a risky position.
     */
    function checkProtocolRatio() internal view {
        (, bool isOK_) = getCollateralRatio();
        if (!isOK_) revert Errors.RatioOutOfRange();
    }

    /**
     * @dev Callback function for leverage flashloan.
     * @param _loanAmount The loan amount.
     * @param _fee The fee for the flashloan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function leverageCallback(uint256 _loanAmount, uint256 _fee, bytes memory _swapData, uint256 _swapGetMin)
        internal
    {
        IERC20(WSTETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        uint256 return_;
        if (_swapData.length == 0) {
            return_ = dummySwap(_loanAmount);
        } else {
            (return_,) = executeSwap(_loanAmount, WSTETH, EZETH, _swapData, _swapGetMin);
        }
        // (uint256 return_,) = executeSwap(_loanAmount, WSTETH, EZETH, _swapData, _swapGetMin);
        executeDeposit(EZETH, return_);
        executeBorrow(WSTETH, _loanAmount + _fee);
    }

    /**
     * @dev Callback function for deleverage flashloan.
     * @param _loanAmount The loan amount.
     * @param _fee The fee for the flashloan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function deleverageCallback(uint256 _loanAmount, uint256 _fee, bytes memory _swapData, uint256 _swapGetMin)
        internal
    {
        executeRepay(WSTETH, _loanAmount);
        executeWithdraw(EZETH, _loanAmount);
        IERC20(EZETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, EZETH, WSTETH, _swapData, _swapGetMin);
        uint256 repayFlashloan_ = _loanAmount + _fee;
        uint256 borrowAgain_ = repayFlashloan_ - return_;
        executeBorrow(WSTETH, borrowAgain_);
    }
}