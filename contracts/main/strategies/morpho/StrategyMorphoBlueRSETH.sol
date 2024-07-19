// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import "@morpho-org/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import "@morpho-org/morpho-blue/src/libraries/periphery/MorphoStorageLib.sol";
import "@morpho-org/morpho-blue/src/libraries/MarketParamsLib.sol";
import "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";
import "../../../interfaces/flashloanHelper/IFlashloanHelper.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/kelp/ILRTDepositPool.sol";
import "../../../interfaces/kelp/ILRTOracle.sol";
import "../../../interfaces/kelp/ILRTWithdrawalManager.sol";
import "../../../interfaces/lido/IWstETH.sol";
import "../../libraries/Errors.sol";
import "../../swap/OneInchCallerV6.sol";
import "../../common/MultiETH.sol";

/**
 * @title StrategyMorphoBlueRSETH contract
 * @author Naturelab
 * @dev This contract is the actual address of the strategy pool.
 */
contract StrategyMorphoBlueRSETH is IStrategy, MultiETH, OneInchCallerV6, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using MorphoBalancesLib for IMorpho;

    // The version of the contract
    string public constant VERSION = "1.0";

    ILRTDepositPool internal constant kelpPool = ILRTDepositPool(0x036676389e48133B63a802f8635AD39E752D375D);

    ILRTOracle internal constant kelpOracle = ILRTOracle(0x349A73444b1a310BAe67ef67973022020d70020d);

    ILRTWithdrawalManager internal constant kelpWithdrawal =
        ILRTWithdrawalManager(0x62De59c08eB5dAE4b7E6F7a8cAd3006d6965ec16);

    address public constant RSETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;

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

    // Permissible deviation from the safe collateral rate, allowing a small buffer
    uint256 public permissibleLimit;

    // Limit the proportion of total position (currently not in use)
    uint256 public percentageLimit;

    bytes32 public requestId;

    //Morpho
    address internal constant MORPHO_POOL = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_Oracle = 0x423671566dE77E9Cb50E9bE4383BA78fFC808a4e;
    address internal constant MORPHO_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 internal constant MORPHO_LLTV = 860000000000000000;

    event UpdateFlashloanHelper(address oldFlashloanHelper, address newFlashloanHelper);
    event UpdateRebalancer(address oldRebalancer, address newRebalancer);
    event UpdateSafeProtocolRatio(uint256 oldSafeProtocolRatio, uint256 newSafeProtocolRatio);
    event OnTransferIn(address token, uint256 amount);
    event TransferToVault(address token, uint256 amount);
    event Stake(uint256 amount);
    event Unstake(uint256 amount);
    event ConfirmUnstake();
    event Leverage(uint256 deposit, uint256 debtAmount, bytes swapData, uint256 flashloanSelector);
    event Deleverage(uint256 deleverageAmount, uint256 withdrawAmount, bytes swapData, uint256 flashloanSelector);

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
        (uint256 _safeProtocolRatio, address _admin, address _flashloanHelper, address _rebalancer) =
            abi.decode(_initBytes, (uint256, address, address, address));
        __Ownable_init(_admin);
        if (_admin == address(0)) revert Errors.InvalidAdmin();
        if (_flashloanHelper == address(0)) revert Errors.InvalidFlashloanHelper();
        if (_safeProtocolRatio > MORPHO_LLTV) revert Errors.InvalidSafeProtocolRatio();
        if (_rebalancer == address(0)) revert Errors.InvalidRebalancer();
        flashloanHelper = _flashloanHelper;
        safeProtocolRatio = _safeProtocolRatio;
        rebalancer = _rebalancer;
        vault = msg.sender;
        enterProtocol();
        IERC20(STETH).safeIncreaseAllowance(WSTETH, type(uint256).max);
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

    /**
     * @dev stake STETH to RSETH.
     */
    function stake(uint256 _amount) external onlyRebalancer {
        IERC20(STETH).safeIncreaseAllowance(address(kelpPool), _amount);
        kelpPool.depositAsset(STETH, _amount, 0, "");

        emit Stake(_amount);
    }

    /**
     * @dev unstake RSETH to STETH.
     */
    function unstake(uint256 _rsAmount) external onlyRebalancer {
        if (requestId != bytes32(0)) revert Errors.UnSupportedOperation();
        uint256 nextUnusedNonce_ = kelpWithdrawal.nextUnusedNonce(STETH);
        bytes32 newRequestId_ = kelpWithdrawal.getRequestId(STETH, nextUnusedNonce_);
        IERC20(RSETH).safeIncreaseAllowance(address(kelpWithdrawal), _rsAmount);

        kelpWithdrawal.initiateWithdrawal(STETH, _rsAmount);
        (uint256 rsETHUnstaked_,, uint256 withdrawalStartBlock_, uint256 userNonce_) =
            kelpWithdrawal.getUserWithdrawalRequest(STETH, address(this), 0);
        if (rsETHUnstaked_ != _rsAmount || withdrawalStartBlock_ != block.number || nextUnusedNonce_ != userNonce_) {
            revert Errors.IncorrectState();
        }
        requestId = newRequestId_;

        emit Unstake(_rsAmount);
    }

    function confirmUnstake() external onlyRebalancer {
        if (requestId == bytes32(0)) revert Errors.UnSupportedOperation();
        kelpWithdrawal.completeWithdrawal(STETH);

        emit ConfirmUnstake();
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
        executeDeposit(RSETH, _deposit);
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
            uint256 availableWithdrawRSETH = getAvailableWithdrawsRSETH();
            if (_deleverageAmount < availableWithdrawRSETH) deleverageSelf(_deleverageAmount, _swapData, _swapGetMin);
            else executeFlashLoan(false, _deleverageAmount, _swapData, _swapGetMin, _flashloanSelector);
        }
        executeWithdraw(RSETH, _withdraw);
        checkProtocolRatio();
        emit Deleverage(_deleverageAmount, _withdraw, _swapData, _flashloanSelector);
    }

    function getKelpUnstakingAmount() public view returns (uint256) {
        if (requestId == bytes32(0)) return 0;
        (, uint256 expectedAssetAmount_,) = kelpWithdrawal.withdrawalRequests(requestId);
        return expectedAssetAmount_;
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

    function getStETHByRsETH(uint256 _rsethAmount) public view returns (uint256) {
        uint256 rate_ = kelpOracle.rsETHPrice();
        return _rsethAmount * rate_ / PRECISION;
    }

    function getRsETHByStETH(uint256 _ethAmount) public view returns (uint256) {
        return kelpPool.getRsETHAmountToMint(ETH, _ethAmount);
    }

    function getMarketParams() public pure returns (MarketParams memory) {
        return MarketParams({
            loanToken: WETH,
            collateralToken: RSETH,
            oracle: MORPHO_Oracle,
            irm: MORPHO_IRM,
            lltv: MORPHO_LLTV
        });
    }

    function supplyAssetsUser() public view returns (uint256 totalSupplyAssets) {
        totalSupplyAssets = IMorpho(MORPHO_POOL).expectedSupplyAssets(getMarketParams(), address(this));
    }

    function collateralAssetsUser() public view returns (uint256 totalCollateralAssets) {
        bytes32[] memory slots = new bytes32[](1);
        slots[0] =
            MorphoStorageLib.positionBorrowSharesAndCollateralSlot(MarketParamsLib.id(getMarketParams()), address(this));
        bytes32[] memory values = IMorpho(MORPHO_POOL).extSloads(slots);
        totalCollateralAssets = uint256(values[0] >> 128);
    }

    function borrowAssetsUser() public view returns (uint256 totalBorrowAssets) {
        totalBorrowAssets = IMorpho(MORPHO_POOL).expectedBorrowAssets(getMarketParams(), address(this));
    }

    /**
     * @dev Get the available borrows in ETH.
     * @return availableBorrowsETH_ The amount of available borrows in ETH.
     */
    function getAvailableBorrowsETH() public view returns (uint256 availableBorrowsETH_) {
        uint256 rsETHAmount_ = collateralAssetsUser();
        uint256 maxBorrowsETH_ = rsETHAmount_ * IOracle(MORPHO_Oracle).price() * MORPHO_LLTV / 1e54; //1e36*1e18
        uint256 debtWEthAmount_ = borrowAssetsUser();
        availableBorrowsETH_ = maxBorrowsETH_ > debtWEthAmount_ ? (maxBorrowsETH_ - debtWEthAmount_) : 0;
    }

    /**
     * @dev Get the available withdrawable amount in rsETH.
     * @return maxWithdrawsRSETH_ The maximum amount of rsETH that can be withdrawn.
     */
    function getAvailableWithdrawsRSETH() public view returns (uint256 maxWithdrawsRSETH_) {
        uint256 rsETHPrice_ = IOracle(MORPHO_Oracle).price();
        uint256 colInEthScale_ = collateralAssetsUser() * rsETHPrice_;
        uint256 debtInEthScale_ = borrowAssetsUser() * 1e36;
        if (colInEthScale_ > 0) {
            uint256 colMin_ = debtInEthScale_ * PRECISION / MORPHO_LLTV;
            uint256 maxWithdrawsInEthScale_ = colInEthScale_ > colMin_ ? colInEthScale_ - colMin_ : 0;
            maxWithdrawsRSETH_ = maxWithdrawsInEthScale_ / rsETHPrice_;
        }
    }

    function getRatio() public view returns (uint256 ratio_) {
        uint256 rsETHAmount_ = collateralAssetsUser();
        uint256 debtWETHAmount_ = borrowAssetsUser();
        uint256 debtRSETHAmount_ = getRsETHByStETH(debtWETHAmount_);
        ratio_ = rsETHAmount_ > 0 ? (debtRSETHAmount_ * PRECISION / rsETHAmount_) : 0;
    }

    /**
     * @dev Get the collateral ratio and its status.
     * @return collateralRatio_ The collateral ratio.
     * @return isOK_ Boolean indicating whether the ratio is within safe limits.
     */
    function getCollateralRatio() public view returns (uint256 collateralRatio_, bool isOK_) {
        uint256 rsETHAmount_ = collateralAssetsUser();
        uint256 debtWETHAmount_ = borrowAssetsUser();
        uint256 rsETHPrice_ = IOracle(MORPHO_Oracle).price() / PRECISION;
        collateralRatio_ = rsETHAmount_ > 0 ? (debtWETHAmount_ * PRECISION / (rsETHAmount_ * rsETHPrice_)) : 0;
        isOK_ = safeProtocolRatio + permissibleLimit > collateralRatio_;
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
        uint256 rsEthPrice_ = IOracle(MORPHO_Oracle).price() / PRECISION;
        uint256 ethPrice_ = PRECISION;
        uint256 totalCollateralETH_ = collateralAssetsUser() * rsEthPrice_ / ethPrice_;
        uint256 totalDebtETH_ = borrowAssetsUser();
        uint256 depositOrWithdrawInETH_ = IWstETH(WSTETH).getWstETHByStETH(_depositOrWithdraw) * rsEthPrice_ / ethPrice_;

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
     * @return stEthAmount_ The amount of supplied rsETH in stETH.
     * @return debtWEthAmount_ The amount of debt in WETH.
     */
    function getProtocolAccountData() public view returns (uint256 stEthAmount_, uint256 debtWEthAmount_) {
        uint256 rsETHAmount_ = collateralAssetsUser();
        debtWEthAmount_ = borrowAssetsUser();
        stEthAmount_ = getStETHByRsETH(rsETHAmount_);
    }

    /**
     * @dev Get the amount of assets in all lending protocols involved in this contract for the strategy pool.
     * @return netAssets The total amount of net assets.
     */
    function getNetAssets() public view override returns (uint256) {
        uint256 rsETHAmount_ = collateralAssetsUser() + IERC20(RSETH).balanceOf(address(this));
        uint256 unstaking_ = getKelpUnstakingAmount();
        uint256 debtETHAmount_ = borrowAssetsUser();

        return getStETHByRsETH(rsETHAmount_) + getTotalETHBalance() + unstaking_ - debtETHAmount_;
    }

    /**
     * @dev Execute a deposit operation in the Morpho Blue protocol.
     * @param _asset The address of the asset to deposit.
     * @param _amount The amount of the asset to deposit.
     */
    function executeDeposit(address _asset, uint256 _amount) internal {
        if (_asset != RSETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        IMorpho(MORPHO_POOL).supplyCollateral(getMarketParams(), _amount, address(this), "");
    }

    /**
     * @dev Execute a withdrawal operation in the Morpho Blue protocol.
     * @param _asset The address of the asset to withdraw.
     * @param _amount The amount of the asset to withdraw.
     */
    function executeWithdraw(address _asset, uint256 _amount) internal {
        if (_asset != RSETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        IMorpho(MORPHO_POOL).withdrawCollateral(getMarketParams(), _amount, address(this), address(this));
    }

    /**
     * @dev Execute a borrow operation in the Morpho Blue protocol.
     * @param _asset The address of the asset to borrow.
     * @param _amount The amount of the asset to borrow.
     */
    function executeBorrow(address _asset, uint256 _amount) internal {
        if (_asset != WETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        IMorpho(MORPHO_POOL).borrow(getMarketParams(), _amount, 0, address(this), address(this));
    }

    /**
     * @dev Execute a repay operation in the Morpho Blue protocol.
     * @param _asset The address of the asset to repay.
     * @param _amount The amount of the asset to repay.
     */
    function executeRepay(address _asset, uint256 _amount) internal {
        if (_asset != WETH) revert Errors.InvalidAsset();
        if (_amount == 0) return;
        IMorpho(MORPHO_POOL).repay(getMarketParams(), _amount, 0, address(this), "");
    }

    /**
     * @dev Enter the Morpho Blue protocol.
     */
    function enterProtocol() internal {
        IERC20(RSETH).forceApprove(MORPHO_POOL, type(uint256).max);
        IERC20(WETH).forceApprove(MORPHO_POOL, type(uint256).max);
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
     * @dev Execute a self-leverage operation.
     * @param _loanAmount The amount to loan.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function leverageSelf(uint256 _loanAmount, bytes calldata _swapData, uint256 _swapGetMin) internal {
        executeBorrow(WETH, _loanAmount);
        IERC20(WETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, WETH, RSETH, _swapData, _swapGetMin);
        executeDeposit(RSETH, return_);
    }

    /**
     * @dev Execute a self-deleverage operation.
     * @param _deleverageAmount The amount to deleverage.
     * @param _swapData The swap data.
     * @param _swapGetMin The minimum amount to get from the swap.
     */
    function deleverageSelf(uint256 _deleverageAmount, bytes calldata _swapData, uint256 _swapGetMin) internal {
        executeWithdraw(RSETH, _deleverageAmount);
        IERC20(RSETH).safeIncreaseAllowance(ONEINCH_ROUTER, _deleverageAmount);
        (uint256 return_,) = executeSwap(_deleverageAmount, RSETH, WETH, _swapData, _swapGetMin);
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
        (uint256 return_,) = executeSwap(_loanAmount, WETH, RSETH, _swapData, _swapGetMin);
        executeDeposit(RSETH, return_);
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
        executeWithdraw(RSETH, _loanAmount);
        IERC20(RSETH).safeIncreaseAllowance(ONEINCH_ROUTER, _loanAmount);
        (uint256 return_,) = executeSwap(_loanAmount, RSETH, WETH, _swapData, _swapGetMin);
        uint256 repayFlashloan_ = _loanAmount + _fee;
        uint256 borrowAgain_ = repayFlashloan_ - return_;
        executeBorrow(WETH, borrowAgain_);
    }
}
