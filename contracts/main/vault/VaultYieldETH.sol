// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "../../interfaces/lido/IWstETH.sol";
import "../../interfaces/etherfi/IWeETH.sol";
import "../../interfaces/weth/IWETH.sol";
import "../../interfaces/IRedeemOperator.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IVault.sol";
import "../libraries/StorageSlot.sol";
import "../libraries/Errors.sol";
import "../common/TinyMultiETH.sol";
import "./StrategyFactory.sol";

/**
 * @title VaultYieldETH contract
 * @author Naturelab
 * @dev This contract is the logical implementation of the vault,
 * and its main purpose is to provide users with a gateway for depositing
 * and withdrawing funds and to manage user shares.
 */
contract VaultYieldETH is
    IVault,
    TinyMultiETH,
    StrategyFactory,
    ERC4626Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using StorageSlot for *;

    // The version of the contract
    string public constant VERSION = "1.0";

    // Use EIP-1153 to temporarily store prices for calculation.
    bytes32 internal constant EXCHANGE_PRICE_CACHE = keccak256("EXCHANGE_PRICE_CACHE");

    // Define a constant variable representing the fee denominator, 10000 (used for percentage calculations)
    uint256 internal constant FEE_DENOMINATOR = 1e4;

    // The minimum market capacity is 100 units (scaled by 1e18)
    uint256 internal constant MIN_MARKET_CAPACITY = 100e18;

    // Up to 0.04% can be charged as a management fee in each cycle (4 / 10000)
    uint256 internal constant MAX_MANAGEMENT_FEE_RATE = 4;

    // The shortest cycle for charging the management fee is 7 days
    uint256 internal constant MIN_MANAGEMENT_FEE_CLAIM_PERIOD = 7 days;

    // The maximum interval for price updates. If prices are not updated for a long time,
    // deposits will be temporarily unavailable.
    uint256 internal constant MAX_PRICE_UPDATED_PERIOD = 3 days;

    // The maximum fee for withdrawing from the idle treasury is 1.2% (120 / 10000)
    uint256 internal constant MAX_EXIT_FEE_RATE = 120;

    // The maximum revenue fee rate is 15% (1500 / 10000)
    uint256 internal constant MAX_REVENUE_FEE_RATE = 1500;

    // Initial exchange price set to 1e18 (used as a scaling factor)
    uint256 internal constant INIT_EXCHANGE_PRICE = 1e18;

    // Vault parameters, encapsulating the configuration of the vault
    VaultParams internal vaultParams;

    // Vault state, encapsulating the state of the vault
    VaultState internal vaultState;

    /**
     * @dev  Ensure that this method is only called by authorized portfolio managers.
     */
    modifier onlyRebalancer() {
        if (msg.sender != vaultParams.rebalancer) revert Errors.CallerNotRebalancer();
        _;
    }

    /**
     * @dev Initialize various parameters of the Vault contract.
     * @param _initBytes The encoded initialization parameters.
     */
    function initialize(bytes calldata _initBytes) external initializer {
        VaultParams memory params_ = abi.decode(_initBytes, (IVault.VaultParams));

        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init(params_.name, params_.symbol);

        if (params_.underlyingToken == address(0)) revert Errors.InvalidUnderlyingToken();
        if (params_.rebalancer == address(0)) revert Errors.InvalidRebalancer();
        if (params_.admin == address(0)) revert Errors.InvalidAdmin();
        if (params_.feeReceiver == address(0)) revert Errors.InvalidFeeReceiver();
        if (params_.marketCapacity < MIN_MARKET_CAPACITY) revert Errors.MarketCapacityTooLow();
        if (params_.managementFeeRate > MAX_MANAGEMENT_FEE_RATE) revert Errors.ManagementFeeRateTooHigh();
        if (params_.managementFeeClaimPeriod < MIN_MANAGEMENT_FEE_CLAIM_PERIOD) {
            revert Errors.ManagementFeeClaimPeriodTooShort();
        }
        if (params_.maxPriceUpdatePeriod > MAX_PRICE_UPDATED_PERIOD) revert Errors.PriceUpdatePeriodTooLong();
        if (params_.revenueRate > MAX_REVENUE_FEE_RATE) revert Errors.RevenueFeeRateTooHigh();
        if (params_.exitFeeRate > MAX_EXIT_FEE_RATE) revert Errors.ExitFeeRateTooHigh();
        __Ownable_init(params_.admin);
        __ERC4626_init(IERC20(params_.underlyingToken));
        vaultState.lastClaimMngFeeTime = block.timestamp;
        vaultState.lastUpdatePriceTime = block.timestamp;
        vaultState.exchangePrice = INIT_EXCHANGE_PRICE;
        vaultParams = params_;
    }

    /**
     * @dev Returns the vault parameters.
     * @return A struct containing the vault parameters.
     */
    function getVaultParams() public view returns (VaultParams memory) {
        return vaultParams;
    }

    /**
     * @dev Returns the vault state.
     * @return A struct containing the vault state.
     */
    function getVaultState() public view returns (VaultState memory) {
        return vaultState;
    }

    /**
     * @dev Update the size of the pool's capacity.
     * @param _newCapacityLimit The new size of the capacity.
     */
    function updateMarketCapacity(uint256 _newCapacityLimit) external onlyOwner {
        if (_newCapacityLimit <= vaultParams.marketCapacity) revert Errors.UnSupportedOperation();
        emit UpdateMarketCapacity(vaultParams.marketCapacity, _newCapacityLimit);
        vaultParams.marketCapacity = _newCapacityLimit;
    }

    /**
     * @dev Update the management fee rate.
     * @param _newManagementFeeRate The new rate.
     */
    function updateManagementFee(uint256 _newManagementFeeRate) external onlyOwner {
        if (_newManagementFeeRate > MAX_MANAGEMENT_FEE_RATE) revert Errors.ManagementFeeRateTooHigh();
        emit UpdateManagementFee(vaultParams.managementFeeRate, _newManagementFeeRate);
        vaultParams.managementFeeRate = _newManagementFeeRate;
    }

    /**
     * @dev Update the collection cycle of management fees.
     * @param _newmanagementFeeClaimPeriod The new management fee claim period.
     */
    function updateManagementFeeClaimPeriod(uint256 _newmanagementFeeClaimPeriod) external onlyOwner {
        if (_newmanagementFeeClaimPeriod < MIN_MANAGEMENT_FEE_CLAIM_PERIOD) {
            revert Errors.ManagementFeeClaimPeriodTooShort();
        }
        emit UpdateManagementFeeClaimPeriod(vaultParams.managementFeeClaimPeriod, _newmanagementFeeClaimPeriod);
        vaultParams.managementFeeClaimPeriod = _newmanagementFeeClaimPeriod;
    }

    /**
     * @dev Update the maximum allowed price update period.
     * @param _newMaxPriceUpdatePeriod The new period.
     */
    function updateMaxPriceUpdatePeriod(uint256 _newMaxPriceUpdatePeriod) external onlyOwner {
        if (_newMaxPriceUpdatePeriod > MAX_PRICE_UPDATED_PERIOD) revert Errors.PriceUpdatePeriodTooLong();
        emit UpdateMaxPriceUpdatePeriod(vaultParams.maxPriceUpdatePeriod, _newMaxPriceUpdatePeriod);
        vaultParams.maxPriceUpdatePeriod = _newMaxPriceUpdatePeriod;
    }

    /**
     * @dev Update the revenue fee rate.
     * @param _newRevenueRate The new rate.
     */
    function updateRevenueRate(uint256 _newRevenueRate) external onlyOwner {
        if (_newRevenueRate > MAX_REVENUE_FEE_RATE) revert Errors.RevenueFeeRateTooHigh();
        emit UpdateRevenueRate(vaultParams.revenueRate, _newRevenueRate);
        vaultParams.revenueRate = _newRevenueRate;
    }

    /**
     * @dev Update the exit fee rate.
     * @param _newExitFeeRate The new rate.
     */
    function updateExitFeeRate(uint256 _newExitFeeRate) external onlyOwner {
        if (_newExitFeeRate > MAX_EXIT_FEE_RATE) revert Errors.ExitFeeRateTooHigh();
        emit UpdateExitFeeRate(vaultParams.exitFeeRate, _newExitFeeRate);
        vaultParams.exitFeeRate = _newExitFeeRate;
    }

    /**
     * @dev Add a new address to the position adjustment whitelist.
     * @param _newRebalancer The new address to be added.
     */
    function updateRebalancer(address _newRebalancer) external onlyOwner {
        if (_newRebalancer == address(0)) revert Errors.InvalidRebalancer();
        emit UpdateRebalancer(vaultParams.rebalancer, _newRebalancer);
        vaultParams.rebalancer = _newRebalancer;
    }

    /**
     * @dev Update the address of the recipient for management fees.
     * @param _newFeeReceiver The new address of the recipient for management fees.
     */
    function updateFeeReceiver(address _newFeeReceiver) external onlyOwner {
        if (_newFeeReceiver == address(0)) revert Errors.InvalidFeeReceiver();
        emit UpdateFeeReceiver(vaultParams.feeReceiver, _newFeeReceiver);
        vaultParams.feeReceiver = _newFeeReceiver;
    }

    /**
     * @dev Update the temporary address of shares when users redeem.
     * @param _newRedeemOperator The new redeem operator address.
     */
    function updateRedeemOperator(address _newRedeemOperator) external onlyOwner {
        if (_newRedeemOperator == address(0)) revert Errors.InvalidRedeemOperator();
        emit UpdateRedeemOperator(vaultParams.redeemOperator, _newRedeemOperator);
        vaultParams.redeemOperator = _newRedeemOperator;
    }

    /*
     * @return newExchangePrice The new exercise price
     * @return newRevenue The new realized profit.
     */
    function updateExchangePrice() external onlyRebalancer returns (uint256 newExchangePrice, uint256 newRevenue) {
        EXCHANGE_PRICE_CACHE.asUint256().tstore(vaultState.exchangePrice);
        vaultState.lastUpdatePriceTime = block.timestamp;
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            return (vaultState.exchangePrice, vaultState.revenue);
        }
        uint256 currentNetAssets_ = underlyingTvl();
        newExchangePrice = currentNetAssets_ * PRECISION / totalSupply_;
        if (newExchangePrice > vaultState.revenueExchangePrice) {
            if (vaultState.revenueExchangePrice == 0) {
                vaultState.revenueExchangePrice = newExchangePrice;
                vaultState.exchangePrice = newExchangePrice;
                return (vaultState.exchangePrice, vaultState.revenue);
            }
            uint256 newProfit_ = currentNetAssets_ - ((vaultState.revenueExchangePrice * totalSupply_) / PRECISION);
            newRevenue = (newProfit_ * vaultParams.revenueRate) / FEE_DENOMINATOR;
            vaultState.revenue += newRevenue;
            vaultState.exchangePrice = ((currentNetAssets_ - newRevenue) * PRECISION) / totalSupply_;
            vaultState.revenueExchangePrice = vaultState.exchangePrice;
        } else {
            vaultState.exchangePrice = newExchangePrice;
        }

        emit UpdateExchangePrice(newExchangePrice, newRevenue);
    }

    /**
     * @dev Transfer tokens to a strategy.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     * @param _strategyIndex The index of the strategy to transfer to.
     */
    function transferToStrategy(address _token, uint256 _amount, uint256 _strategyIndex) external {
        // Strategy 0 is a special strategy that is used exclusively for the conversion of various ETH tokens.
        address caller_ = msg.sender;
        if (_strategyIndex == 0) {
            if (caller_ != owner() && caller_ != vaultParams.rebalancer) revert Errors.InvalidOperator();
        } else {
            if (caller_ != owner()) revert Errors.InvalidOperator();
        }
        address strategyAddress_ = strategyAddress(_strategyIndex);
        uint256 positionLimit_ = positionLimit[strategyAddress_];
        uint256 nowAssets_ = IStrategy(strategyAddress_).getNetAssets();
        if ((nowAssets_ + _amount) > (totalAssets() * positionLimit_ / 1e4)) revert Errors.InvalidLimit();
        IERC20(_token).safeIncreaseAllowance(strategyAddress_, _amount);
        if (!IStrategy(strategyAddress_).onTransferIn(_token, _amount)) revert Errors.IncorrectState();

        emit TransferToStrategy(_token, _amount, _strategyIndex);
    }

    /**
     * @dev Function to quickly convert ETH to other tokens.
     * @param _toToken The type of token to be obtained.
     * @param _amount The amount of token to be obtained.
     */
    function stakeTo(address _toToken, uint256 _amount) public onlyRebalancer {
        _stakeTo(_toToken, _amount);
    }

    /**
     * @dev Retrieve the amount of the exit fee.
     * @param _assetAmount The amount of asset to be withdrawn.
     * @return withdrawFee_ The exit fee to be deducted.
     */
    function getWithdrawFee(uint256 _assetAmount) public view returns (uint256 withdrawFee_) {
        withdrawFee_ = _assetAmount * vaultParams.exitFeeRate / FEE_DENOMINATOR;
    }

    /**
     * @dev Retrieve the total value locked (TVL) in underlying assets.
     * @return The total value locked in underlying assets.
     */
    function underlyingTvl() public returns (uint256) {
        uint256 wethBal_ = IERC20(WETH).balanceOf(address(this));
        uint256 stethBal_ = IERC20(STETH).balanceOf(address(this));
        uint256 eethBal_ = IERC20(EETH).balanceOf(address(this));
        uint256 totalStrategy_ = totalStrategiesAssets();
        return totalStrategy_ + wethBal_ + stethBal_ + eethBal_ - vaultState.revenue;
    }

    /**
     * @dev Retrieve the amount of assets in the strategy pool.
     * @return The total assets in the strategy pool.
     */
    function totalAssets() public view override returns (uint256) {
        if (block.timestamp - vaultState.lastUpdatePriceTime > vaultParams.maxPriceUpdatePeriod) {
            revert Errors.PriceNotUpdated();
        }
        return vaultState.exchangePrice * totalSupply() / PRECISION;
    }

    /**
     * @return Actual LP price during the user's deposit phase.
     */
    function exchangePrice() public view override returns (uint256) {
        return vaultState.exchangePrice;
    }

    /**
     * @dev When the actual LP price exceeds this price, performance fee settlement can be conducted.
     * @return LP price for settling performance fees.
     */
    function revenueExchangePrice() public view override returns (uint256) {
        return vaultState.revenueExchangePrice;
    }

    /**
     * @return Currently accumulated performance fees.
     */
    function revenue() public view override returns (uint256) {
        return vaultState.revenue;
    }

    /**
     * @return The remaining time. If it is 0, deposits and withdrawals are currently not allowed.
     * @dev If it is not 0, the admin needs to update the price within this period.
     */
    function remainingUpdateTime() public view returns (uint256) {
        uint256 timeDiff_ = block.timestamp - vaultState.lastUpdatePriceTime;
        return vaultParams.maxPriceUpdatePeriod > timeDiff_ ? (vaultParams.maxPriceUpdatePeriod - timeDiff_) : 0;
    }

    /**
     * @dev Retrieve the maximum amount that can be deposited by an address.
     * @return maxAssets_ The maximum deposit amount.
     */
    function maxDeposit(address) public view override returns (uint256 maxAssets_) {
        maxAssets_ = vaultParams.marketCapacity - totalAssets();
    }

    /**
     * @return The actual LP price before the last update.
     * @dev If it is lower than current price, there might be a withdrawal rebalancing loss,
     * which the user needs to bear. This usually does not happen.
     */
    function lastExchangePrice() public view override returns (uint256) {
        return EXCHANGE_PRICE_CACHE.asUint256().tload();
    }

    /**
     * @dev Optional deposit function allowing deposits in different token types.
     * @param _token The address of the token to deposit.
     * @param _assets The amount of assets to deposit.
     * @param _receiver The address of the receiver of the shares.
     * @param _referral  Address of the referrer.
     * @return shares_ The amount of shares issued.
     */
    function optionalDeposit(address _token, uint256 _assets, address _receiver, address _referral)
        public
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 shares_)
    {
        if (vaultParams.maxPriceUpdatePeriod < block.timestamp - vaultState.lastUpdatePriceTime) {
            revert Errors.PriceNotUpdated();
        }
        if (_token == address(0) || _token == ETH) {
            if (_assets != 0) revert Errors.UnSupportedOperation();
            uint256 depositAssets_ = msg.value;
            shares_ = optionalDepositDeal(depositAssets_, _receiver);
            IWETH(WETH).deposit{value: depositAssets_}();
        } else if (_token == WETH || _token == STETH || _token == EETH) {
            shares_ = optionalDepositDeal(_assets, _receiver);
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _assets);
        } else if (_token == WSTETH) {
            IERC20(WSTETH).safeTransferFrom(msg.sender, address(this), _assets);
            uint256 depositAssets_ = IWstETH(WSTETH).getStETHByWstETH(_assets);
            shares_ = optionalDepositDeal(depositAssets_, _receiver);
            if (depositAssets_ != IWstETH(WSTETH).unwrap(_assets)) revert Errors.IncorrectState();
        } else if (_token == WEETH) {
            IERC20(WEETH).safeTransferFrom(msg.sender, address(this), _assets);
            uint256 depositAssets_ = IWeETH(WEETH).getEETHByWeETH(_assets);
            shares_ = optionalDepositDeal(depositAssets_, _receiver);
            if (depositAssets_ != IWeETH(WEETH).unwrap(_assets)) revert Errors.IncorrectState();
        } else {
            revert Errors.UnsupportedToken();
        }

        _mint(_receiver, shares_);

        emit OptionalDeposit(msg.sender, _token, _assets, _receiver, _referral);
    }

    /**
     * @dev Internal function to calculate the shares issued for a deposit.
     * @param _assets The amount of assets to deposit.
     * @param _receiver The address of the receiver of the shares.
     * @return shares_ The amount of shares issued.
     */
    function optionalDepositDeal(uint256 _assets, address _receiver) internal returns (uint256 shares_) {
        uint256 maxAssets = maxDeposit(_receiver);
        if (_assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(_receiver, _assets, maxAssets);
        }
        shares_ = previewDeposit(_assets);

        emit Deposit(msg.sender, _receiver, _assets, shares_);
    }

    /**
     * @dev Redemption operation executed by the redeemOperator. Currently, only STETH and EETH redemptions are supported.
     * @param _token The address of the token to deposit.
     * @param _shares The amount of share tokens to be redeemed.
     * @param _cutPercentage The percentage of the rebalancing loss incurred.
     * @param _receiver The address of the receiver of the assets.
     * @param _owner The owner address of the shares.
     * @return assetsAfterFee_ The amount of assets obtained.
     */
    function optionalRedeem(address _token, uint256 _shares, uint256 _cutPercentage, address _receiver, address _owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assetsAfterFee_)
    {
        if (msg.sender != vaultParams.redeemOperator) revert Errors.UnSupportedOperation();
        if (vaultState.lastUpdatePriceTime != block.timestamp) revert Errors.PriceNotUpdated();

        if (_shares == type(uint256).max) {
            _shares = maxRedeem(_owner);
        } else {
            require(_shares <= maxRedeem(_owner), "ERC4626: redeem more than max");
        }

        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }

        uint256 assets_ = previewRedeem(_shares * (PRECISION - _cutPercentage) / PRECISION);
        _burn(_owner, _shares);
        assetsAfterFee_ = assets_ - getWithdrawFee(assets_);
        if (_token == STETH) {
            IERC20(STETH).safeTransfer(_receiver, assetsAfterFee_);
        } else if (_token == EETH) {
            IERC20(EETH).safeTransfer(_receiver, assetsAfterFee_);
        } else {
            revert Errors.UnsupportedToken();
        }

        emit OptionalRedeem(_token, _shares, _receiver, _owner);
    }

    /**
     * @dev The deposit method of ERC4626, with the parameter being the amount of assets.
     * @param _assets The amount of asset being deposited.
     * @param _receiver The recipient of the share tokens.
     * @return shares_ The amount of share tokens obtained.
     */
    function deposit(uint256 _assets, address _receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares_)
    {
        if (_assets == type(uint256).max) {
            _assets = IERC20(asset()).balanceOf(msg.sender);
        }
        shares_ = super.deposit(_assets, _receiver);
    }

    /**
     * @dev The deposit method of ERC4626, with the parameter being the amount of share tokens.
     * @param _shares The amount of share tokens to be minted.
     * @param _receiver The recipient of the share tokens.
     * @return assets_ The amount of assets consumed.
     */
    function mint(uint256 _shares, address _receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets_)
    {
        assets_ = super.mint(_shares, _receiver);
    }

    function withdraw(uint256, address, address) public override returns (uint256) {
        // Only delayed withdrawals are supported
        revert Errors.NotSupportedYet();
    }

    function redeem(uint256, address, address) public override returns (uint256) {
        // Only delayed withdrawals are supported
        revert Errors.NotSupportedYet();
    }

    /**
     * @dev When a user applies for redemption, his share will be
     * transferred to the RedeemOperator address.
     * @param _shares The amount of share tokens to be redeemed.
     * @param _token The address of the token to redeem.
     */
    function requestRedeem(uint256 _shares, address _token) external nonReentrant whenNotPaused {
        if (_shares == 0) revert Errors.WithdrawZero();
        _transfer(msg.sender, vaultParams.redeemOperator, _shares);
        IRedeemOperator(vaultParams.redeemOperator).registerWithdrawal(msg.sender, _shares, _token);

        emit RequestRedeem(msg.sender, _shares, _token);
    }

    /**
     * @dev Used when some users migrating from other vaults.
     * @param _users The amount of share tokens to be redeemed.
     * @param _assets The address of the token to redeem.
     */
    function migrateMint(address[] calldata _users, uint256[] calldata _assets) external onlyOwner {
        if (_users.length != _assets.length) revert Errors.InvalidLength();
        uint256 shares_;
        for (uint256 i = 0; i < _users.length; ++i) {
            shares_ = previewDeposit(_assets[i]);
            _mint(_users[i], shares_);
        }

        emit MigrateMint(_users, _assets);
    }

    /**
     * @dev Collect management fee.
     */
    function collectManagementFee() external {
        if (msg.sender != vaultParams.feeReceiver) revert Errors.InvalidFeeReceiver();
        uint256 nowTime_ = block.timestamp;
        if (nowTime_ - vaultState.lastClaimMngFeeTime < vaultParams.managementFeeClaimPeriod) {
            revert Errors.InvalidClaimTime();
        }
        vaultState.lastClaimMngFeeTime = nowTime_;
        uint256 assets_ = totalAssets() * vaultParams.managementFeeRate / FEE_DENOMINATOR;
        IERC20(asset()).safeTransfer(vaultParams.feeReceiver, assets_);

        emit CollectManagementFee(assets_);
    }

    /**
     * @dev Collect performance fees to the recipient address.
     */
    function collectRevenue() external {
        if (msg.sender != vaultParams.feeReceiver) revert Errors.InvalidFeeReceiver();
        IERC20(asset()).safeTransfer(vaultParams.feeReceiver, vaultState.revenue);
        emit CollectRevenue(vaultState.revenue);
        vaultState.revenue = 0;
    }

    /**
     * @dev Handle when someone else accidentally transfers assets to this contract.
     * @param _token The address of the token to transfer out.
     */
    function sweep(address _token) external onlyOwner {
        if (_token == asset() || _token == EETH || _token == STETH) revert Errors.UnsupportedToken();
        uint256 amount_ = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount_);
        uint256 ethBalance_ = address(this).balance;
        if (ethBalance_ > 0) {
            Address.sendValue(payable(msg.sender), ethBalance_);
        }

        emit Sweep(_token);
    }

    function pause() external {
        if (msg.sender != owner() && msg.sender != vaultParams.rebalancer) revert Errors.UnSupportedOperation();
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
