// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../interfaces/flashloanHelper/IFlashloanHelper.sol";
import "../../../interfaces/lido/IWstETH.sol";
import "../../../interfaces/IVault.sol";
import "../../../interfaces/aave/v3/IPoolV3.sol";
import "../../../interfaces/aave/IAaveOracle.sol";
import "../../../interfaces/kelp/ILRTDepositPool.sol";
import "../../../interfaces/kelp/ILRTOracle.sol";
import "../../../interfaces/kelp/ILRTWithdrawalManager.sol";
import "../../../interfaces/IStrategy.sol";
import "../../libraries/Errors.sol";
import "../../swap/OneInchCallerV6.sol";
import "../../common/MultiETH.sol";

/**
 * @title StrategyAAVEV3RsETH contract
 * @author Naturelab
 * @dev This contract is the actual address of the strategy pool, which
 * manages some assets in aaveV3.
 */
contract StrategyAAVEV3RsETH is IStrategy, MultiETH, OneInchCallerV6, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // The version of the contract
    string public constant VERSION = "1.0";

    // The maximum allowable ratio for the protocol, set to 91%
    uint256 public constant MAX_PROTOCOL_RATIO = 0.91e18;

    address public constant RSETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;

    // The address of the AAVE v3 aToken for rsETH
    address internal constant A_RSETH_AAVEV3 = 0x2D62109243b87C4bA3EE7bA1D91B0dD0A074d7b1;

    // The address of the AAVE v3 variable debt token for WSTETH
    address internal constant D_WSTETH_AAVEV3 = 0xC96113eED8cAB59cD8A66813bCB0cEb29F06D2e4;

    // The address of the AAVE v3 variable debt token for WETH
    address internal constant D_WETH_AAVEV3 = 0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE;

    // The address of the AAVE v3 supply token for this strategy. Now is rsETH.
    address internal constant SUPPLY_TOKEN = RSETH;

    // The address of the AAVE v3 Oracle contract
    IAaveOracle internal constant ORACLE_AAVEV3 = IAaveOracle(0x54586bE62E3c3580375aE3723C145253060Ca0C2);

    // The address of the AAVE v3 Pool contract
    IPoolV3 internal constant POOL_AAVEV3 = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    ILRTWithdrawalManager internal constant kelpWithdrawal =
        ILRTWithdrawalManager(0x62De59c08eB5dAE4b7E6F7a8cAd3006d6965ec16);

    ILRTOracle internal constant kelpOracle = ILRTOracle(0x349A73444b1a310BAe67ef67973022020d70020d);

    ILRTDepositPool internal constant kelpPool = ILRTDepositPool(0x036676389e48133B63a802f8635AD39E752D375D);

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

    bytes32 public requestId;

    event UpdateFlashloanHelper(address oldFlashloanHelper, address newFlashloanHelper);
    event UpdateRebalancer(address oldRebalancer, address newRebalancer);
    event UpdateSafeProtocolRatio(uint256 oldSafeProtocolRatio, uint256 newSafeProtocolRatio);
    event OnTransferIn(address token, uint256 amount);
    event TransferToVault(address token, uint256 amount);
    event SwapToken(uint256 amount, address srcToken, address dstToken, uint256 swapGet);
    event Stake(uint256 amount);
    event Unstake(uint256 amount);
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

    modifier tokenCheck(address _token) {
        if (_token != WETH && _token != WSTETH) revert Errors.UnsupportedToken();
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

    function convertToken(address _srcToken, address _toToken, uint256 _amount) external onlyRebalancer {
        _convertToken(_srcToken, _toToken, _amount);
    }

    function claimUnstake(address _srcToken) external onlyRebalancer {
        _claimUnstake(_srcToken);
    }

    function dummySwap(uint256 _amount, address _srcToken) internal returns (uint256) {
        uint256 rsETHAmountBefore_ = IERC20(RSETH).balanceOf(address(this));
        // If _srcToken is WETH
        if (_srcToken == WETH) {
            // Unwrap WETH to ETH
            IWETH(WETH).withdraw(_amount);
            kelpPool.depositETH{value: _amount}(0, "");
        } else if (_srcToken == WSTETH || _srcToken == STETH) {
            // Unwrap WSTETH to stETH
            uint256 stEthAmount_;
            if (_srcToken == WSTETH) {
                stEthAmount_ = IWstETH(WSTETH).unwrap(_amount);
            } else {
                stEthAmount_ = _amount;
            }
            // Approve to kelpPool
            IERC20(STETH).safeIncreaseAllowance(address(kelpPool), stEthAmount_);
            // Deposit stETH to kelpPool
            kelpPool.depositAsset(STETH, stEthAmount_, 0, "");
        }
        return IERC20(RSETH).balanceOf(address(this)) - rsETHAmountBefore_;
    }

    /**
     * @dev Transfers funds from the vault contract to this contract.
     * This function is called by the vault to move tokens into this contract.
     * It uses the `safeTransferFrom` function from the SafeERC20 library to ensure the transfer is successful.
     * @param _token The address of the token to be transferred.
     * @param _amount The amount of tokens to be transferred.
     * @return A boolean indicating whether the transfer was successful.
     */
    function onTransferIn(address _token, uint256 _amount) external override onlyVault returns (bool) {
        if (_token != STETH) revert Errors.InvalidUnderlyingToken();
        IERC20(STETH).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(STETH).safeIncreaseAllowance(address(kelpPool), _amount);
        kelpPool.depositAsset(STETH, _amount, 0, "");
        emit OnTransferIn(_token, _amount);
        return true;
    }

    /**
     * @dev Transfer tokens to the Vault.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     */
    function transferToVault(address _token, uint256 _amount) external onlyRebalancer {
        IERC20(_token).safeTransfer(vault, _amount);
        emit TransferToVault(_token, _amount);
    }

    function swapToken(
        uint256 _amount,
        address _srcToken,
        address _dstToken,
        bytes memory _swapData,
        uint256 _swapGetMin
    ) external onlyRebalancer {
        if (_srcToken != RSETH || _dstToken != STETH) revert Errors.UnSupportedOperation();
        IERC20(_srcToken).safeIncreaseAllowance(ONEINCH_ROUTER, _amount);
        uint256 return_;
        if (_swapData.length > 0) {
            (return_,) = executeSwap(_amount, _srcToken, _dstToken, _swapData, _swapGetMin);
        } else {
            return_ = dummySwap(_amount, _srcToken);
        }
        emit SwapToken(_amount, _srcToken, _dstToken, return_);
    }

    /**
     * @dev stake STETH to RSETH.
     */
    function stake(uint256 _amount) external onlyRebalancer {
        IERC20(STETH).safeIncreaseAllowance(address(kelpPool), _amount);
        kelpPool.depositAsset(STETH, _amount, 0, "");

        emit Stake(_amount);
    }

    /**
     * @dev unstake RSETH to STETH/ETH.
     */
    function unstake(uint256 _rsAmount, address _toToken) external onlyRebalancer {
        if (requestId != bytes32(0)) revert Errors.UnSupportedOperation();
        if (_toToken != STETH && _toToken != ETH) revert Errors.UnsupportedToken();
        uint256 nextUnusedNonce_ = kelpWithdrawal.nextUnusedNonce(_toToken);
        bytes32 newRequestId_ = kelpWithdrawal.getRequestId(_toToken, nextUnusedNonce_);
        IERC20(RSETH).safeIncreaseAllowance(address(kelpWithdrawal), _rsAmount);

        kelpWithdrawal.initiateWithdrawal(_toToken, _rsAmount);
        (uint256 rsETHUnstaked_,, uint256 withdrawalStartBlock_, uint256 userNonce_) =
            kelpWithdrawal.getUserWithdrawalRequest(_toToken, address(this), 0);
        if (rsETHUnstaked_ != _rsAmount || withdrawalStartBlock_ != block.number || nextUnusedNonce_ != userNonce_) {
            revert Errors.IncorrectState();
        }
        requestId = newRequestId_;

        emit Unstake(_rsAmount);
    }

    function repay(address _token, uint256 _amount) external onlyRebalancer {
        executeRepay(_token, _amount);

        emit Repay(_amount);
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
        address _borrowToken,
        uint256 _leverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external onlyRebalancer tokenCheck(_borrowToken) {
        executeDeposit(SUPPLY_TOKEN, _deposit);
        checkProtocolRatio();
        if (_leverageAmount == 0) return;
        uint256 availableBorrowsAmount_ = getAvailableBorrowsAmount(_borrowToken);
        if (_leverageAmount < availableBorrowsAmount_) {
            leverageSelf(_borrowToken, _leverageAmount, _swapData, _swapGetMin);
        } else {
            executeFlashLoan(true, _borrowToken, _leverageAmount, _swapData, _swapGetMin, _flashloanSelector);
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
        address _repayToken,
        uint256 _deleverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external onlyRebalancer tokenCheck(_repayToken) {
        if (_deleverageAmount > 0) {
            uint256 availableWithdrawsAmount = getAvailableWithdrawsAmount();
            if (_deleverageAmount < availableWithdrawsAmount) {
                deleverageSelf(_repayToken, _deleverageAmount, _swapData, _swapGetMin);
            } else {
                executeFlashLoan(false, _repayToken, _deleverageAmount, _swapData, _swapGetMin, _flashloanSelector);
            }
        }
        executeWithdraw(SUPPLY_TOKEN, _withdraw);
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
            ? leverageCallback(_token, _amount, _fee, swapData_, swapGetMin_)
            : deleverageCallback(_token, _amount, _fee, swapData_, swapGetMin_);
        IERC20(_token).safeIncreaseAllowance(msg.sender, _amount + _fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /**
     * @dev Get the available borrows in token.
     * @return availableBorrowsAmount_ The amount of available borrows in borrow token.
     */
    function getAvailableBorrowsAmount(address _token) public view returns (uint256 availableBorrowsAmount_) {
        (,, uint256 availableBorrowsInUsd_,,,) = POOL_AAVEV3.getUserAccountData(address(this));
        if (availableBorrowsInUsd_ > 0) {
            uint256 tokenPrice_ = ORACLE_AAVEV3.getAssetPrice(_token);
            availableBorrowsAmount_ = availableBorrowsInUsd_ * PRECISION / tokenPrice_;
        }
    }

    /**
     * @dev Get the available withdrawable amount in supply token.
     * @return maxWithdrawsAmount_ The maximum amount of supply token that can be withdrawn.
     */
    function getAvailableWithdrawsAmount() public view returns (uint256 maxWithdrawsAmount_) {
        (uint256 colInUsd_, uint256 debtInUsd_,,, uint256 ltv_,) = POOL_AAVEV3.getUserAccountData(address(this));
        if (colInUsd_ > 0) {
            uint256 colMin_ = debtInUsd_ * 1e4 / ltv_;
            uint256 maxWithdrawsInUsd_ = colInUsd_ > colMin_ ? colInUsd_ - colMin_ : 0;
            uint256 tokenPrice_ = ORACLE_AAVEV3.getAssetPrice(SUPPLY_TOKEN);
            maxWithdrawsAmount_ = maxWithdrawsInUsd_ * PRECISION / tokenPrice_;
        }
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

    function getRatio() public view returns (uint256) {
        (uint256 totalCollateralBase_, uint256 totalDebtBase_,,,,) = POOL_AAVEV3.getUserAccountData(address(this));
        return totalCollateralBase_ == 0 ? 0 : totalDebtBase_ * PRECISION / totalCollateralBase_;
    }

    /**
     * @dev Get the protocol account data.
     * @return stEthAmount_ The amount of supplied rsETH in stETH.
     * @return debtEthAmount_ The amount of debt in ETH.
     */
    function getProtocolAccountData() public view returns (uint256 stEthAmount_, uint256 debtEthAmount_) {
        uint256 rsEthAmount_;
        (bool success, bytes memory returnData) = A_RSETH_AAVEV3.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        if (!success || returnData.length == 0) rsEthAmount_ = 0;
        else rsEthAmount_ = abi.decode(returnData, (uint256));
        stEthAmount_ = getETHByRsETH(rsEthAmount_);
        uint256 debtWstEthAmount_ = IERC20(D_WSTETH_AAVEV3).balanceOf(address(this));
        debtEthAmount_ =
            IERC20(D_WETH_AAVEV3).balanceOf(address(this)) + IWstETH(WSTETH).getStETHByWstETH(debtWstEthAmount_);
    }

    /**
     * @dev Get the amount of net assets in the protocol.
     * @return net_ The amount of net assets.
     */
    function getProtocolNetAssets() public view returns (uint256 net_) {
        (uint256 stEthAmount_, uint256 debtEthAmount_) = getProtocolAccountData();
        net_ = stEthAmount_ - debtEthAmount_;
    }

    /**
     * @dev Get the amount of assets in all lending protocols involved in this contract for the strategy pool.
     * @return netAssets The total amount of net assets.
     */
    function getNetAssets() public view returns (uint256) {
        uint256 rsEthAmount_ = IERC20(RSETH).balanceOf(address(this));
        return getProtocolNetAssets() + getETHByRsETH(rsEthAmount_) + getTotalETHBalance();
    }

    /**
     * @dev Execute a self-leverage operation.
     * @param _loanAmount The amount to loan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function leverageSelf(address _borrowToken, uint256 _loanAmount, bytes calldata _swapData, uint256 _swapGetMin)
        internal
    {
        executeBorrow(_borrowToken, _loanAmount);
        IERC20(_borrowToken).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        uint256 return_;
        if (_swapData.length > 0) {
            (return_,) = executeSwap(_loanAmount, _borrowToken, SUPPLY_TOKEN, _swapData, _swapGetMin);
        } else {
            return_ = dummySwap(_loanAmount, _borrowToken);
        }
        executeDeposit(SUPPLY_TOKEN, return_);
    }

    /**
     * @dev Execute a self-deleverage operation.
     * @param _deleverageAmount The amount to deleverage.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function deleverageSelf(
        address _repayToken,
        uint256 _deleverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin
    ) internal {
        executeWithdraw(SUPPLY_TOKEN, _deleverageAmount);
        IERC20(SUPPLY_TOKEN).safeIncreaseAllowance(ONEINCH_ROUTER, _deleverageAmount);
        (uint256 return_,) = executeSwap(_deleverageAmount, SUPPLY_TOKEN, _repayToken, _swapData, _swapGetMin);
        executeRepay(_repayToken, return_);
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
        address _loanToken,
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
            IERC3156FlashBorrower(address(this)), _loanToken, _loanAmount, dataBytes_
        );
        executor = address(0);
    }

    /**
     * @dev Execute a deposit operation in the AAVE protocol.
     * @param _asset The address of the asset to deposit.
     * @param _amount The amount of the asset to deposit.
     */
    function executeDeposit(address _asset, uint256 _amount) internal {
        if (_asset != SUPPLY_TOKEN) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.supply(SUPPLY_TOKEN, _amount, address(this), 0);
    }

    /**
     * @dev Execute a withdrawal operation in the AAVE protocol.
     * @param _asset The address of the asset to withdraw.
     * @param _amount The amount of the asset to withdraw.
     */
    function executeWithdraw(address _asset, uint256 _amount) internal {
        if (_asset != SUPPLY_TOKEN) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.withdraw(SUPPLY_TOKEN, _amount, address(this));
    }

    /**
     * @dev Execute a borrow operation in the AAVE protocol.
     * @param _asset The address of the asset to borrow.
     * @param _amount The amount of the asset to borrow.
     */
    function executeBorrow(address _asset, uint256 _amount) internal {
        if (_asset != WETH && _asset != WSTETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.borrow(_asset, _amount, 2, 0, address(this));
    }

    /**
     * @dev Execute a repay operation in the AAVE protocol.
     * @param _asset The address of the asset to repay.
     * @param _amount The amount of the asset to repay.
     */
    function executeRepay(address _asset, uint256 _amount) internal {
        if (_asset != WETH && _asset != WSTETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.repay(_asset, _amount, 2, address(this));
    }

    /**
     * @dev Enter the AAVE protocol by approving tokens.
     */
    function enterProtocol() public onlyRebalancer {
        IERC20(STETH).safeIncreaseAllowance(RSETH, type(uint256).max);
        IERC20(WETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);
        IERC20(RSETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);
        IERC20(WSTETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);
        POOL_AAVEV3.setUserEMode(3);
    }

    /**
     * @dev Check the health status of a specific protocol after an operation
     * to prevent the strategy pool from being in a risky position.
     */
    function checkProtocolRatio() internal view {
        (, bool isOK_) = getCollateralRatio();
        if (!isOK_) revert Errors.RatioOutOfRange();
    }

    function getETHByRsETH(uint256 _rsethAmount) public view returns (uint256) {
        uint256 rate_ = kelpOracle.rsETHPrice();
        return _rsethAmount * rate_ / PRECISION;
    }

    function getRsETHByETH(uint256 _ethAmount) public view returns (uint256) {
        return kelpPool.getRsETHAmountToMint(ETH, _ethAmount);
    }

    /**
     * @dev Callback function for leverage flashloan.
     * @param _loanAmount The loan amount.
     * @param _fee The fee for the flashloan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function leverageCallback(
        address _loanToken,
        uint256 _loanAmount,
        uint256 _fee,
        bytes memory _swapData,
        uint256 _swapGetMin
    ) internal {
        IERC20(_loanToken).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount); uint256 return_;
        if (_swapData.length > 0) {
            (return_,) = executeSwap(_loanAmount, _loanToken, SUPPLY_TOKEN, _swapData, _swapGetMin);
        } else {
            return_ = dummySwap(_loanAmount, _loanToken);
        }
        executeDeposit(SUPPLY_TOKEN, return_);
        executeBorrow(_loanToken, _loanAmount + _fee);
    }

    /**
     * @dev Callback function for deleverage flashloan.
     * @param _loanAmount The loan amount.
     * @param _fee The fee for the flashloan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function deleverageCallback(
        address _loanToken,
        uint256 _loanAmount,
        uint256 _fee,
        bytes memory _swapData,
        uint256 _swapGetMin
    ) internal {
        executeRepay(_loanToken, _loanAmount);
        executeWithdraw(SUPPLY_TOKEN, _loanAmount);
        IERC20(SUPPLY_TOKEN).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, SUPPLY_TOKEN, _loanToken, _swapData, _swapGetMin);
        uint256 repayFlashloan_ = _loanAmount + _fee;
        if (repayFlashloan_ > return_) {
            uint256 borrowAgain_ = repayFlashloan_ - return_;
            executeBorrow(_loanToken, borrowAgain_);
        } else if (repayFlashloan_ < return_) {
            uint256 rapayAgain_ = return_ - repayFlashloan_;
            executeRepay(_loanToken, rapayAgain_);
        }
    }
}