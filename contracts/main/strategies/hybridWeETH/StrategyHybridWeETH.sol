// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../../../interfaces/lending/ILendingAdapter.sol";
import "../../../interfaces/aave/IAaveOracle.sol";
import "../../../interfaces/etherfi/IWeETH.sol";
import "../../../interfaces/IStrategy.sol";
import "../../libraries/Errors.sol";
import "../../swap/OneInchCallerV6.sol";
import "../../common/MultiETH.sol";

/**
 * @title StrategyHybridWeETH contract
 * @author Naturelab
 * @dev This contract is the actual address of the strategy pool, which
 * manages assets on-chain and in CEX.
 */
contract StrategyHybridWeETH is IStrategy, IERC3156FlashBorrower, MultiETH, OneInchCallerV6, OwnableUpgradeable {
    using Address for address;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // The version of the contract
    string public constant VERSION = "1.0";
    // USE_MAX is used to indicate that the maximum amount should be used.
    uint256 internal constant USE_MAX = type(uint256).max;
    // USE_PREVIOUS_OUT is used to indicate that the previous output should be used as input.
    uint256 internal constant USE_PREVIOUS_OUT = type(uint256).max - 1;
    // Storage
    bytes32 internal constant STORAGE_SLOT = keccak256("cian.hedge.weeth");
    // Max Daily NetValue Change
    uint256 internal constant MAX_DAILY_NET_ASSET_CHANGE = 1e16; // 100bps per day

    struct HedgeStorage {
        address rebalancer;
        address vault;
        uint256 originalAssetAmount;
        uint256 totalValue;
        uint256 lastUpdateTimestamp;
        EnumerableSet.AddressSet lendingAdapters;
        EnumerableSet.AddressSet flashloanAdapters;
        EnumerableSet.AddressSet allowedDepositAddresses;
    }

    enum ActionSelectors {
        Deposit,
        Withdraw,
        Borrow,
        Repay,
        RepayWithRemain,
        Swap,
        TransferTo
    }

    event RebalancerUpdated(address indexed oldRebalancer, address indexed newRebalancer);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    event LendingAdaptersUpdated(address indexed adapter, bool enabled);
    event FlashloanAdaptersUpdated(address indexed adapter, bool enabled);
    event AllowedDepositAddressUpdated(address indexed depositAddress, bool enabled);
    event LendingAdapterDataUpdated(address indexed adapter);

    // Operation events
    event DepositToAdapter(address indexed adapter, address indexed token, uint256 amount);
    event WithdrawFromAdapter(address indexed adapter, address indexed token, uint256 amount);
    event BorrowFromAdapter(address indexed adapter, address indexed token, uint256 amount);
    event RepayToAdapter(address indexed adapter, address indexed token, uint256 amount);
    event Swapped(address indexed from, address indexed to, uint256 inAmount, uint256 outAmount);
    event TransferToCustody(address indexed token, address indexed to, uint256 amount);
    event NetAssetsUpdated(uint256 oldNetAssets, uint256 newNetAssets);

    /**
     * @dev Ensure that this method is only called by the Vault contract.
     */
    modifier onlyVault() {
        if (msg.sender != getStorage().vault) revert Errors.CallerNotVault();
        _;
    }

    /**
     * @dev  Ensure that this method is only called by authorized portfolio managers.
     */
    modifier onlyRebalancer() {
        if (msg.sender != getStorage().rebalancer) revert Errors.CallerNotRebalancer();
        _;
    }

    modifier onlyFlashloanProvider() {
        if (!getStorage().flashloanAdapters.contains(msg.sender)) revert Errors.InvalidFlashloanProvider();
        _;
    }

    function initialize(bytes calldata _initBytes) external initializer {
        (
            address admin_,
            address rebalancer_,
            address[] memory depositAccounts_,
            address[] memory flashloanProviders_,
            address[] memory lendingAdapters_,
            bytes[] memory adapterInitializeDatas_
        ) = abi.decode(_initBytes, (address, address, address[], address[], address[], bytes[]));
        if (admin_ == address(0)) revert Errors.InvalidAdmin();
        if (rebalancer_ == address(0)) revert Errors.InvalidRebalancer();
        if (lendingAdapters_.length != adapterInitializeDatas_.length) revert Errors.InvalidLength();
        __Ownable_init(admin_);
        HedgeStorage storage s = getStorage();
        s.rebalancer = rebalancer_;
        s.vault = msg.sender;
        for (uint256 i = 0; i < depositAccounts_.length; ++i) {
            if (depositAccounts_[i] == address(0)) revert Errors.InvalidAccount();
            updateAllowedDepositAddresses(depositAccounts_[i], true);
        }
        for (uint256 i = 0; i < flashloanProviders_.length; ++i) {
            if (flashloanProviders_[i] == address(0)) revert Errors.InvalidFlashloanProvider();
            updateFlashloanAdapters(flashloanProviders_[i], true);
        }
        for (uint256 i = 0; i < lendingAdapters_.length; ++i) {
            if (lendingAdapters_[i] == address(0)) revert Errors.InvalidAdapter();
            updateLendingAdapters(lendingAdapters_[i], true);
            if (adapterInitializeDatas_[i].length > 0) {
                lendingAdapters_[i].functionDelegateCall(adapterInitializeDatas_[i]);
            }
        }
    }

    function updateRebalancer(address _rebalancer) external onlyOwner {
        if (_rebalancer == address(0)) revert Errors.InvalidRebalancer();
        HedgeStorage storage s = getStorage();
        address oldRebalacer_ = s.rebalancer;
        s.rebalancer = _rebalancer;
        emit RebalancerUpdated(oldRebalacer_, _rebalancer);
    }

    function installAdapter(address _adapter, bytes calldata _payload) external onlyOwner {
        if (_adapter == address(0)) revert Errors.InvalidAdapter();
        // First, install the adapter using updateAllowedLendingProviders
        updateLendingAdapters(_adapter, true);
        // Then, delegate call using _payload
        if (_payload.length > 0) {
            _adapter.functionDelegateCall(_payload);
        }
    }

    function uninstallAdapter(address _adapter) external onlyOwner {
        // First, uninstall the adapter using updateAllowedLendingProviders
        updateLendingAdapters(_adapter, false);
    }

    function installFlashloanProvider(address _provider) external onlyOwner {
        if (_provider == address(0)) revert Errors.InvalidFlashloanProvider();
        updateFlashloanAdapters(_provider, true);
    }

    function uninstallFlashloanProvider(address _provider) external onlyOwner {
        updateFlashloanAdapters(_provider, false);
    }

    function addAllowedDepositAddress(address _depositAccount) external onlyOwner {
        if (_depositAccount == address(0)) revert Errors.InvalidAccount();
        updateAllowedDepositAddresses(_depositAccount, true);
    }

    function removeAllowedDepositAddress(address _address) external onlyOwner {
        updateAllowedDepositAddresses(_address, false);
    }

    function deposit(address _adapter, address _token, uint256 _amount) external onlyRebalancer {
        // Handle max amount
        if (_amount == USE_MAX) {
            _amount = IERC20Metadata(_token).balanceOf(address(this));
        }
        _deposit(ILendingAdapter(_adapter), _token, _amount);
    }

    function withdraw(address _adapter, address _token, uint256 _amount) external onlyRebalancer {
        _withdraw(ILendingAdapter(_adapter), _token, _amount);
    }

    function borrow(address _adapter, address _token, uint256 _amount) external onlyRebalancer {
        _borrow(ILendingAdapter(_adapter), _token, _amount);
    }

    function repay(address _adapter, address _token, uint256 _amount) external onlyRebalancer {
        // Handle max amount
        if (_amount == USE_MAX) {
            _amount = IERC20Metadata(_token).balanceOf(address(this));
        }
        _tryRepay(ILendingAdapter(_adapter), _token, _amount);
    }

    function swap(address _srcToken, address _toToken, uint256 _amount, uint256 _minOut, bytes calldata _swapData)
        external
        onlyRebalancer
        returns (uint256)
    {
        return _swap(_srcToken, _toToken, _amount, _minOut, _swapData);
    }

    function moveDeposit(address _srcAdapter, address _dstAdapter, address _depositToken, uint256 _amount)
        external
        onlyRebalancer
    {
        // Withdraw from srcAdapter
        _withdraw(ILendingAdapter(_srcAdapter), _depositToken, _amount);
        // Deposit to dstAdapter
        _deposit(ILendingAdapter(_dstAdapter), _depositToken, _amount);
    }

    function moveDebt(
        address _srcAdapter,
        address _dstAdapter,
        address _debtToken,
        address _repayToken,
        uint256 _amount,
        uint256 _minOut,
        bytes calldata _swapData
    ) external onlyRebalancer {
        _borrow(ILendingAdapter(_srcAdapter), _debtToken, _amount);
        uint256 repayAmount_ = _amount;
        if (_repayToken != _debtToken) {
            repayAmount_ = _swap(_debtToken, _repayToken, _amount, _minOut, _swapData);
        }
        _tryRepay(ILendingAdapter(_dstAdapter), _repayToken, repayAmount_);
    }

    function convertToken(address _srcToken, address _toToken, uint256 _amount) external onlyRebalancer {
        _convertToken(_srcToken, _toToken, _amount);
    }

    function claimUnstake(address _srcToken) external onlyRebalancer {
        _claimUnstake(_srcToken);
    }

    function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata _data)
        external
        override
        onlyFlashloanProvider
        returns (bytes32)
    {
        if (_initiator != address(this)) revert Errors.InvalidInitiator();
        // Decode calldata & run composed call
        (uint8[] memory _actionId, bytes[] memory _actionData) = abi.decode(_data, (uint8[], bytes[]));
        // Assert call data length
        if (_actionId.length != _actionData.length || _actionId.length <= 1) revert Errors.InvalidLength();
        // Special Handling for the first action
        uint256 previousOut_ = _amount;
        for (uint256 i = 0; i < _actionId.length - 1; ++i) {
            previousOut_ = _dispatchCall(_actionId[i], previousOut_, _actionData[i]);
        }
        previousOut_ = _amount + _fee;
        // For the last call, previousOut_ is the amount + fee
        _dispatchCall(_actionId[_actionId.length - 1], previousOut_, _actionData[_actionId.length - 1]);
        // Approve _amount + _fee _token to msg.sender
        IERC20(_token).safeIncreaseAllowance(msg.sender, _amount + _fee);
        // Check msg.sender and initator
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
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
        if (_token != EETH) revert Errors.InvalidToken();
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 beforeBalance_ = IERC20(WEETH).balanceOf(address(this));
        // Convert to WEETH
        IERC20(EETH).safeIncreaseAllowance(address(WEETH), _amount);
        IWeETH(address(WEETH)).wrap(_amount);
        uint256 afterBalance_ = IERC20(WEETH).balanceOf(address(this));
        // Update originalAssetAmount
        getStorage().originalAssetAmount += afterBalance_ - beforeBalance_;
        getStorage().totalValue += _amount;
        return true;
    }

    function convertToIncome(
        address _adapter,
        address _borrowingToken,
        uint256 _amount,
        uint256 _minOut,
        bytes calldata _swapData
    ) external onlyRebalancer {
        _borrow(ILendingAdapter(_adapter), _borrowingToken, _amount);
        uint256 swapOut_ = _swap(_borrowingToken, address(WEETH), _amount, _minOut, _swapData);
        _deposit(ILendingAdapter(_adapter), address(WEETH), swapOut_);
        getStorage().originalAssetAmount += swapOut_;
    }

    function convertToLoss(
        address _adapter,
        address _repayingToken,
        uint256 _amount,
        uint256 _minOut,
        bytes calldata _swapData
    ) external onlyRebalancer {
        _withdraw(ILendingAdapter(_adapter), address(WEETH), _amount);
        uint256 swapOut_ = _swap(address(WEETH), _repayingToken, _amount, _minOut, _swapData);
        _tryRepay(ILendingAdapter(_adapter), _repayingToken, swapOut_);
        getStorage().originalAssetAmount -= swapOut_;
    }

    function doFlashLoan(address _adapter, address _token, uint256 _amount, bytes calldata _data)
        external
        onlyRebalancer
    {
        _callFlashloan(_adapter, _token, _amount, _data);
    }

    function transferToVault(address _token, uint256 _amount) external onlyRebalancer {
        if (_token != EETH) revert Errors.InvalidAsset();
        uint256 beforeBalance_ = IERC20(EETH).balanceOf(address(this));
        IWeETH(address(WEETH)).unwrap(_amount);
        uint256 afterBalance_ = IERC20(EETH).balanceOf(address(this));
        IERC20(EETH).safeTransfer(getStorage().vault, afterBalance_ - beforeBalance_);

        uint256 currentDeposit_ = getStorage().originalAssetAmount;
        if (_amount > currentDeposit_) {
            _amount = currentDeposit_;
        }
        getStorage().originalAssetAmount -= _amount;
    }

    function updateNetAssets(uint256 _newNetAsset) external onlyRebalancer {
        uint256 oldNetAsset_ = getStorage().totalValue;
        if (oldNetAsset_ != 0) {
            // Check difference with latest exchangePrice
            uint256 allowedDiff_ =
                (((block.timestamp - getStorage().lastUpdateTimestamp) / 86400) + 1) * MAX_DAILY_NET_ASSET_CHANGE;
            uint256 diff_ = _newNetAsset > oldNetAsset_
                ? (_newNetAsset - oldNetAsset_) * 1e18 / oldNetAsset_
                : (oldNetAsset_ - _newNetAsset) * 1e18 / oldNetAsset_;
            if (diff_ > allowedDiff_) revert Errors.InvalidNetAssets();
        }
        getStorage().totalValue = _newNetAsset;
        getStorage().lastUpdateTimestamp = block.timestamp;
        emit NetAssetsUpdated(oldNetAsset_, _newNetAsset);
    }

    function updateAssetAmount(uint256 _amount) external onlyRebalancer {
        getStorage().originalAssetAmount = _amount;
    }

    function composedCall(uint8[] calldata _actionId, bytes[] calldata _data) external onlyRebalancer {
        if (_actionId.length != _data.length) revert Errors.InvalidLength();
        uint256 previousOut_ = 0;
        for (uint256 i = 0; i < _actionId.length; ++i) {
            previousOut_ = _dispatchCall(_actionId[i], previousOut_, _data[i]);
        }
    }

    function transferTo(address _token, address _to, uint256 _amount) public onlyRebalancer {
        if (!getStorage().allowedDepositAddresses.contains(_to)) revert Errors.InvalidTarget();
        IERC20(_token).safeTransfer(_to, _amount);
        emit TransferToCustody(_token, _to, _amount);
    }

    function originalAssetAmount() public view returns (uint256) {
        return getStorage().originalAssetAmount;
    }

    function rebalancer() public view returns (address) {
        return getStorage().rebalancer;
    }

    function vault() public view returns (address) {
        return getStorage().vault;
    }

    // Convential functions
    function snapshotProtocol(address _lendingProtocol, address[] calldata _tokens)
        public
        returns (uint256[] memory deposits_, uint256[] memory debts_)
    {
        deposits_ = new uint256[](_tokens.length);
        debts_ = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            ILendingAdapter adapter = ILendingAdapter(_lendingProtocol);
            deposits_[i] = _depositOf(adapter, _tokens[i]);
            debts_[i] = _debtOf(adapter, _tokens[i]);
        }
    }

    function snapshotBalance(address[] calldata tokens) public view returns (uint256[] memory balances_) {
        balances_ = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            balances_[i] = IERC20Metadata(tokens[i]).balanceOf(address(this));
        }
    }

    function getCollateralRatio(address _adapter, address _oracle, address[] calldata _tokens)
        public
        returns (uint256)
    {
        uint256 totalCollateralValue_ = 0;
        uint256 totalDebtValue_ = 0;
        IAaveOracle oracle_ = IAaveOracle(_oracle);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20Metadata token_ = IERC20Metadata(_tokens[i]);
            uint256 price_ = oracle_.getAssetPrice(_tokens[i]);
            uint256 deposit_ = _depositOf(ILendingAdapter(_adapter), _tokens[i]);
            uint256 debt_ = _debtOf(ILendingAdapter(_adapter), _tokens[i]);
            uint256 decimal_ = 10 ** token_.decimals();
            totalCollateralValue_ += deposit_ * price_ / decimal_;
            totalDebtValue_ += debt_ * price_ / decimal_;
        }
        return totalDebtValue_ * 1e18 / totalCollateralValue_;
    }

    function getNetAssets() public view returns (uint256) {
        // Commenting out is for debugging.
        // if (block.timestamp != getStorage().totalValueLastUpdated) revert Errors.InfoExpired();
        return getStorage().totalValue;
    }

    function getLastNetAssets() public view returns (uint256) {
        return getStorage().totalValue;
    }

    function getStorage() internal pure returns (HedgeStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    function updateLendingAdapters(address _adapters, bool _add) internal {
        HedgeStorage storage s = getStorage();
        if (_add) {
            s.lendingAdapters.add(_adapters);
        } else {
            s.lendingAdapters.remove(_adapters);
        }
        emit LendingAdaptersUpdated(_adapters, _add);
    }

    function updateFlashloanAdapters(address _adapters, bool _add) internal {
        HedgeStorage storage s = getStorage();
        if (_add) {
            s.flashloanAdapters.add(_adapters);
        } else {
            s.flashloanAdapters.remove(_adapters);
        }
        emit FlashloanAdaptersUpdated(_adapters, _add);
    }

    function updateAllowedDepositAddresses(address _address, bool _add) internal {
        HedgeStorage storage s = getStorage();
        if (_add) {
            s.allowedDepositAddresses.add(_address);
        } else {
            s.allowedDepositAddresses.remove(_address);
        }
        emit AllowedDepositAddressUpdated(_address, _add);
    }

    function _debtOf(ILendingAdapter _adapter, address _token) internal returns (uint256) {
        bytes memory calldata_ = abi.encodeWithSelector(_adapter.debtOf.selector, _token);
        bytes memory resp_ = address(_adapter).functionDelegateCall(calldata_);
        return abi.decode(resp_, (uint256));
    }

    function _depositOf(ILendingAdapter _adapter, address _token) internal returns (uint256) {
        bytes memory calldata_ = abi.encodeWithSelector(_adapter.depositOf.selector, _token);
        bytes memory resp_ = address(_adapter).functionDelegateCall(calldata_);
        return abi.decode(resp_, (uint256));
    }

    function _deposit(ILendingAdapter _adapter, address _token, uint256 _amount) internal {
        // Handle full amount
        if (_amount == USE_MAX) {
            _amount = IERC20Metadata(_token).balanceOf(address(this));
        }
        bytes memory calldata_ = abi.encodeWithSelector(_adapter.deposit.selector, _token, _amount);
        address(_adapter).functionDelegateCall(calldata_);
        emit DepositToAdapter(address(_adapter), _token, _amount);
    }

    function _withdraw(ILendingAdapter _adapter, address _token, uint256 _amount) internal {
        bytes memory calldata_ = abi.encodeWithSelector(_adapter.withdraw.selector, _token, _amount);
        address(_adapter).functionDelegateCall(calldata_);
        emit WithdrawFromAdapter(address(_adapter), _token, _amount);
    }

    function _borrow(ILendingAdapter _adapter, address _token, uint256 _amount) internal {
        // Get balance, and borrow amount to _amount
        uint256 currentBalance_ = IERC20Metadata(_token).balanceOf(address(this));
        if (currentBalance_ < _amount) {
            _amount = _amount - currentBalance_;
        } else {
            _amount = 0;
        }
        if (_amount > 0) {
            bytes memory calldata_ = abi.encodeWithSelector(_adapter.borrow.selector, _token, _amount);
            address(_adapter).functionDelegateCall(calldata_);
            emit BorrowFromAdapter(address(_adapter), _token, _amount);
        }
    }

    function _repay(ILendingAdapter _adapter, address _token, uint256 _amount) internal {
        bytes memory calldata_ = abi.encodeWithSelector(_adapter.repay.selector, _token, _amount);
        address(_adapter).functionDelegateCall(calldata_);
        emit RepayToAdapter(address(_adapter), _token, _amount);
    }

    function _repayWithRemain(ILendingAdapter _adapter, address _token, uint256 _remainAmount) internal {
        uint256 balance_ = IERC20Metadata(_token).balanceOf(address(this));
        if (balance_ < _remainAmount) {
            return;
        }
        balance_ -= _remainAmount;
        _tryRepay(_adapter, _token, balance_);
    }

    function _swap(address _srcToken, address _toToken, uint256 _amount, uint256 _minOut, bytes memory _swapData)
        internal
        returns (uint256)
    {
        // Approve _amount of _srcToken to 1inch
        IERC20(_srcToken).safeIncreaseAllowance(address(ONEINCH_ROUTER), _amount);
        (uint256 out_,) = executeSwap(_amount, _srcToken, _toToken, _swapData, _minOut);
        emit Swapped(_srcToken, _toToken, _amount, out_);
        return out_;
    }

    function _tryRepay(ILendingAdapter _adapter, address _token, uint256 _amount) internal {
        // Handle full amount
        if (_amount == USE_MAX) {
            _amount = IERC20Metadata(_token).balanceOf(address(this));
        }
        // First try to get the debt from the lending provider
        uint256 debt_ = _debtOf(_adapter, _token);
        // If the debt is less than the amount, repay the debt
        if (debt_ < _amount) {
            if (debt_ > 0) {
                _repay(_adapter, _token, debt_);
            }
        } else if (_amount > 0) {
            _repay(_adapter, _token, _amount);
        }
    }

    function _tryWithdraw(ILendingAdapter _adapter, address _token, uint256 _amount) internal {
        // Handle full amount
        if (_amount == USE_MAX) {
            // Directly call withdraw and return
            _withdraw(_adapter, _token, _amount);
            return;
        }
        // First try to get the deposit from the lending provider
        uint256 balance_ = IERC20Metadata(_token).balanceOf(address(this));
        // Deduce balance from _amount
        uint256 withdrawAmount = 0;
        if (balance_ < _amount) {
            withdrawAmount = _amount - balance_;
        }
        if (withdrawAmount > 0) {
            _withdraw(_adapter, _token, withdrawAmount);
        }
    }

    function _callFlashloan(address _adapter, address _token, uint256 _amount, bytes calldata _data) internal {
        IERC3156FlashLender flashLender_ = IERC3156FlashLender(_adapter);
        flashLender_.flashLoan(this, _token, _amount, _data);
    }

    function _dispatchCall(uint8 _actionId, uint256 _prevousOut, bytes memory _data) internal returns (uint256) {
        // Match the action selector, and if it's not swap, try mangle the calldata
        if (_actionId == uint8(ActionSelectors.Deposit)) {
            // Decode input
            (address adapter_, address token_, uint256 amount_) = abi.decode(_data, (address, address, uint256));
            if (amount_ == USE_PREVIOUS_OUT) {
                amount_ = _prevousOut;
            }
            _deposit(ILendingAdapter(adapter_), token_, amount_);
            return 0;
        } else if (_actionId == uint8(ActionSelectors.Withdraw)) {
            (address adapter_, address token_, uint256 amount_) = abi.decode(_data, (address, address, uint256));
            if (amount_ == USE_PREVIOUS_OUT) {
                amount_ = _prevousOut;
            }
            _withdraw(ILendingAdapter(adapter_), token_, amount_);
            return 0;
        } else if (_actionId == uint8(ActionSelectors.Borrow)) {
            (address adapter_, address token_, uint256 amount_) = abi.decode(_data, (address, address, uint256));
            if (amount_ == USE_PREVIOUS_OUT) {
                amount_ = _prevousOut;
            }
            _borrow(ILendingAdapter(adapter_), token_, amount_);
            return 0;
        } else if (_actionId == uint8(ActionSelectors.Repay)) {
            (address adapter_, address token_, uint256 amount_) = abi.decode(_data, (address, address, uint256));
            if (amount_ == USE_PREVIOUS_OUT) {
                amount_ = _prevousOut;
            }
            _tryRepay(ILendingAdapter(adapter_), token_, amount_);
            return 0;
        } else if (_actionId == uint8(ActionSelectors.RepayWithRemain)) {
            (address adapter_, address token_, uint256 remainAmount_) = abi.decode(_data, (address, address, uint256));
            if (remainAmount_ == USE_PREVIOUS_OUT) {
                remainAmount_ = _prevousOut;
            }
            _repayWithRemain(ILendingAdapter(adapter_), token_, remainAmount_);
            return 0;
        } else if (_actionId == uint8(ActionSelectors.Swap)) {
            (address fromToken_, address toToken_, uint256 amount_, uint256 minOut_, bytes memory swapData_) =
                abi.decode(_data, (address, address, uint256, uint256, bytes));
            return _swap(fromToken_, toToken_, amount_, minOut_, swapData_);
        } else if (_actionId == uint8(ActionSelectors.TransferTo)) {
            (address token_, address to_, uint256 amount_) = abi.decode(_data, (address, address, uint256));
            if (amount_ == USE_PREVIOUS_OUT) {
                amount_ = _prevousOut;
            }
            transferTo(token_, to_, amount_);
            return 0;
        }
        return 0;
    }
}
