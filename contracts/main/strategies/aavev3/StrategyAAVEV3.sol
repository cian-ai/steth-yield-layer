// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../interfaces/flashloanHelper/IFlashloanHelper.sol";
import "../../../interfaces/lido/IWstETH.sol";
import "../../../interfaces/IVault.sol";
import "../../../interfaces/aave/v3/IPoolV3.sol";
import "../../../interfaces/aave/IAaveOracle.sol";
import "../../../interfaces/IStrategy.sol";
import "../../libraries/Errors.sol";
import "../../swap/OneInchCallerV6.sol";
import "../../common/MultiETH.sol";

/**
 * @title StrategyAAVEV3 contract
 * @author Naturelab
 * @dev This contract is the actual address of the strategy pool, which
 * manages some assets in aaveV3.
 */
contract StrategyAAVEV3 is IStrategy, MultiETH, OneInchCallerV6, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // The version of the contract
    string public constant VERSION = "1.0";

    // The maximum allowable ratio for the protocol, set to 85%
    uint256 public constant MAX_PROTOCOL_RATIO = 0.85e18;

    // The address of the AAVE v3 aToken for wstETH
    address internal constant A_WSTETH_AAVEV3 = 0x0B925eD163218f6662a35e0f0371Ac234f9E9371;

    // The address of the AAVE v3 variable debt token for WETH
    address internal constant D_WETH_AAVEV3 = 0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE;

    // The address of the AAVE v3 Oracle contract
    IAaveOracle internal constant ORACLE_AAVEV3 = IAaveOracle(0x54586bE62E3c3580375aE3723C145253060Ca0C2);

    // The address of the AAVE v3 Pool contract
    IPoolV3 internal constant POOL_AAVEV3 = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

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
    event Wrap(uint256 stEthAmount, uint256 wstEthAmount);
    event Unwrap(uint256 wstEthAmount, uint256 stEthAmount);
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
        enterProtocol();
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

    function convertToken(address _srcToken, address _toToken, uint256 _amount) external onlyRebalancer {
        _convertToken(_srcToken, _toToken, _amount);
    }

    function claimUnstake(address _srcToken) external onlyRebalancer {
        _claimUnstake(_srcToken);
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
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
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

    /**
     * @dev Wrap STETH to WSTETH.
     */
    function wrap() external onlyRebalancer {
        uint256 stEthAmount_ = IERC20(STETH).balanceOf(address(this));
        IERC20(STETH).safeIncreaseAllowance(WSTETH, stEthAmount_);
        uint256 wstETHAmount_ = IWstETH(WSTETH).wrap(stEthAmount_);

        emit Wrap(stEthAmount_, wstETHAmount_);
    }

    /**
     * @dev Unwrap WSTETH to STETH.
     */
    function unwrap() external onlyRebalancer {
        uint256 wstETHAmount_ = IERC20(WSTETH).balanceOf(address(this));
        uint256 stEthAmount_ = IWstETH(WSTETH).unwrap(wstETHAmount_);

        emit Unwrap(wstETHAmount_, stEthAmount_);
    }

    function repay(uint256 _amount) external onlyRebalancer {
        executeRepay(WETH, _amount);

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
        uint256 _leverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external onlyRebalancer {
        executeDeposit(STETH, _deposit);
        checkProtocolRatio();
        if (_leverageAmount == 0) return;
        uint256 availableBorrowsETH_ = getAvailableBorrowsETH();
        if (_leverageAmount < availableBorrowsETH_) {
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
            uint256 availableWithdrawWeETH = getAvailableWithdrawsStETH();
            if (_deleverageAmount < availableWithdrawWeETH) deleverageSelf(_deleverageAmount, _swapData, _swapGetMin);
            else executeFlashLoan(false, _deleverageAmount, _swapData, _swapGetMin, _flashloanSelector);
        }
        executeWithdraw(STETH, _withdraw);
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
     * @return availableBorrowsETH_ The amount of available borrows in ETH.
     */
    function getAvailableBorrowsETH() public view returns (uint256 availableBorrowsETH_) {
        (,, uint256 availableBorrowsInUsd_,,,) = POOL_AAVEV3.getUserAccountData(address(this));
        if (availableBorrowsInUsd_ > 0) {
            uint256 WEthPrice_ = ORACLE_AAVEV3.getAssetPrice(WETH);
            availableBorrowsETH_ = availableBorrowsInUsd_ * PRECISION / WEthPrice_;
        }
    }

    /**
     * @dev Get the available withdrawable amount in stETH.
     * @return maxWithdrawsStETH_ The maximum amount of stETH that can be withdrawn.
     */
    function getAvailableWithdrawsStETH() public view returns (uint256 maxWithdrawsStETH_) {
        (uint256 colInUsd_, uint256 debtInUsd_,,, uint256 ltv_,) = POOL_AAVEV3.getUserAccountData(address(this));
        if (colInUsd_ > 0) {
            uint256 colMin_ = debtInUsd_ * 1e4 / ltv_;
            uint256 maxWithdrawsInUsd_ = colInUsd_ > colMin_ ? colInUsd_ - colMin_ : 0;
            uint256 WstEthPrice_ = ORACLE_AAVEV3.getAssetPrice(WSTETH);
            uint256 maxWithdrawsWstETH_ = maxWithdrawsInUsd_ * PRECISION / WstEthPrice_;
            maxWithdrawsStETH_ = IWstETH(WSTETH).getStETHByWstETH(maxWithdrawsWstETH_);
        }
    }

    function getRatio() public view returns (uint256 ratio_) {
        (uint256 stEthAmount_, uint256 debtEthAmount_) = getProtocolAccountData();
        ratio_ = stEthAmount_ == 0 ? 0 : debtEthAmount_ * PRECISION / stEthAmount_;
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
     * @param _depositOrWithdraw The amount to deposit or withdraw.
     * @return isLeverage_ Boolean indicating whether the operation is leverage.
     * @return loanAmount_ The loan amount.
     */
    function getLeverageAmount(bool _isDepositOrWithdraw, uint256 _depositOrWithdraw)
        public
        view
        returns (bool isLeverage_, uint256 loanAmount_)
    {
        uint256 wstPrice_ = ORACLE_AAVEV3.getAssetPrice(WSTETH);
        uint256 ethPrice_ = ORACLE_AAVEV3.getAssetPrice(WETH);
        uint256 totalCollateralETH_ = IERC20(A_WSTETH_AAVEV3).balanceOf(address(this)) * wstPrice_ / ethPrice_;
        uint256 totalDebtETH_ = IERC20(D_WETH_AAVEV3).balanceOf(address(this));
        uint256 depositOrWithdrawInETH_ = IWstETH(WSTETH).getWstETHByStETH(_depositOrWithdraw) * wstPrice_ / ethPrice_;

        totalCollateralETH_ = _isDepositOrWithdraw
            ? (totalCollateralETH_ + depositOrWithdrawInETH_)
            : (totalCollateralETH_ - depositOrWithdrawInETH_);
        if (totalCollateralETH_ != 0) {
            uint256 ratio = totalCollateralETH_ == 0 ? 0 : totalDebtETH_ * PRECISION / totalCollateralETH_;
            isLeverage_ = ratio < safeProtocolRatio ? true : false;
            if (isLeverage_) {
                loanAmount_ = (safeProtocolRatio * totalCollateralETH_ - totalDebtETH_ * PRECISION)
                    / (PRECISION - safeProtocolRatio);
            } else {
                loanAmount_ = (totalDebtETH_ * PRECISION - safeProtocolRatio * totalCollateralETH_)
                    / (PRECISION - safeProtocolRatio);
            }
        }
    }

    /**
     * @dev Get the protocol account data.
     * @return stEthAmount_ The amount of supplied wstETH in stETH.
     * @return debtEthAmount_ The amount of debt in ETH.
     */
    function getProtocolAccountData() public view returns (uint256 stEthAmount_, uint256 debtEthAmount_) {
        uint256 wstEthAmount_ = IERC20(A_WSTETH_AAVEV3).balanceOf(address(this));
        stEthAmount_ = IWstETH(WSTETH).getStETHByWstETH(wstEthAmount_);
        debtEthAmount_ = IERC20(D_WETH_AAVEV3).balanceOf(address(this));
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
        uint256 wstETHAmount_ = IWstETH(WSTETH).balanceOf(address(this));
        return getProtocolNetAssets() + IWstETH(WSTETH).getStETHByWstETH(wstETHAmount_) + getTotalETHBalance();
    }

    /**
     * @dev Execute a self-leverage operation.
     * @param _loanAmount The amount to loan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function leverageSelf(uint256 _loanAmount, bytes calldata _swapData, uint256 _swapGetMin) internal {
        executeBorrow(WETH, _loanAmount);
        IERC20(WETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, WETH, STETH, _swapData, _swapGetMin);
        executeDeposit(STETH, return_);
    }

    /**
     * @dev Execute a self-deleverage operation.
     * @param _deleverageAmount The amount to deleverage.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function deleverageSelf(uint256 _deleverageAmount, bytes calldata _swapData, uint256 _swapGetMin) internal {
        executeWithdraw(STETH, _deleverageAmount);
        IERC20(STETH).safeIncreaseAllowance(ONEINCH_ROUTER, _deleverageAmount);
        (uint256 return_,) = executeSwap(_deleverageAmount, STETH, WETH, _swapData, _swapGetMin);
        executeRepay(WETH, return_);
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
        IFlashloanHelper(flashloanHelper).flashLoan(IERC3156FlashBorrower(address(this)), WETH, _loanAmount, dataBytes_);
        executor = address(0);
    }

    /**
     * @dev Execute a deposit operation in the AAVE protocol.
     * @param _asset The address of the asset to deposit.
     * @param _amount The amount of the asset to deposit.
     */
    function executeDeposit(address _asset, uint256 _amount) internal {
        if (_asset != STETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        uint256 wst_ = IWstETH(WSTETH).wrap(_amount);
        POOL_AAVEV3.supply(WSTETH, wst_, address(this), 0);
    }

    /**
     * @dev Execute a withdrawal operation in the AAVE protocol.
     * @param _asset The address of the asset to withdraw.
     * @param _amount The amount of the asset to withdraw.
     */
    function executeWithdraw(address _asset, uint256 _amount) internal {
        if (_asset != STETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        /// @dev If you don't add 1wei, it will return 1wei less steth than expected.
        uint256 withdraw_ = IWstETH(WSTETH).getWstETHByStETH(_amount + 1);
        POOL_AAVEV3.withdraw(WSTETH, withdraw_, address(this));
        IWstETH(WSTETH).unwrap(withdraw_);
    }

    /**
     * @dev Execute a borrow operation in the AAVE protocol.
     * @param _asset The address of the asset to borrow.
     * @param _amount The amount of the asset to borrow.
     */
    function executeBorrow(address _asset, uint256 _amount) internal {
        if (_asset != WETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.borrow(_asset, _amount, 2, 0, address(this));
    }

    /**
     * @dev Execute a repay operation in the AAVE protocol.
     * @param _asset The address of the asset to repay.
     * @param _amount The amount of the asset to repay.
     */
    function executeRepay(address _asset, uint256 _amount) internal {
        if (_asset != WETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        POOL_AAVEV3.repay(_asset, _amount, 2, address(this));
    }

    /**
     * @dev Enter the AAVE protocol by approving tokens.
     */
    function enterProtocol() internal {
        IERC20(WETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);
        IERC20(WSTETH).safeIncreaseAllowance(address(POOL_AAVEV3), type(uint256).max);
        IERC20(STETH).safeIncreaseAllowance(WSTETH, type(uint256).max);
        POOL_AAVEV3.setUserEMode(1);
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
        IERC20(WETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, WETH, STETH, _swapData, _swapGetMin);
        executeDeposit(STETH, return_);
        executeBorrow(WETH, _loanAmount + _fee);
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
        executeRepay(WETH, _loanAmount);
        executeWithdraw(STETH, _loanAmount);
        IERC20(STETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, STETH, WETH, _swapData, _swapGetMin);
        uint256 repayFlashloan_ = _loanAmount + _fee;
        uint256 borrowAgain_ = repayFlashloan_ - return_;
        executeBorrow(WETH, borrowAgain_);
    }
}
