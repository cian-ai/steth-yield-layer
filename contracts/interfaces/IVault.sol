// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IVault {
    event UpdateMarketCapacity(uint256 oldCapacityLimit, uint256 newCapacityLimit);
    event UpdateManagementFee(uint256 oldManagementFee, uint256 newManagementFee);
    event UpdateManagementFeeClaimPeriod(uint256 oldManagementFeeClaimPeriod, uint256 newManagementFeeClaimPeriod);
    event UpdateMaxPriceUpdatePeriod(uint256 oldMaxPriceUpdatePeriod, uint256 newMaxPriceUpdatePeriod);
    event UpdateRevenueRate(uint256 oldRevenueRate, uint256 newRevenueRate);
    event UpdateExitFeeRate(uint256 oldExitFeeRate, uint256 newExitFeeRate);
    event UpdateRebalancer(address oldRebalancer, address newRebalancer);
    event UpdateFeeReceiver(address oldFeeReceiver, address newFeeReceiver);
    event UpdateRedeemOperator(address oldRedeemOperator, address newRedeemOperator);
    event UpdateExchangePrice(uint256 newExchangePrice, uint256 newRevenue);
    event TransferToStrategy(address token, uint256 amount, uint256 strategyIndex);
    event OptionalDeposit(address caller, address token, uint256 assets, address receiver, address referral);
    event OptionalRedeem(address token, uint256 shares, address receiver, address owner);
    event RequestRedeem(address user, uint256 shares, address token);
    event CollectManagementFee(uint256 assets);
    event CollectRevenue(uint256 revenue);
    event Sweep(address token);
    event MigrateMint(address[] users, uint256[] assets);

    /**
     * @dev Parameters for initializing the vault contract.
     * @param underlyingToken The address of the underlying token for the vault.
     * @param name The name of the vault token.
     * @param symbol The symbol of the vault token.
     * @param marketCapacity The maximum market capacity of the vault.
     * @param managementFeeRate The rate of the management fee.
     * @param managementFeeClaimPeriod The period for claiming the management fee.
     * @param maxPriceUpdatePeriod The maximum allowed price update period.
     * @param revenueRate The rate of the revenue fee.
     * @param exitFeeRate The rate of the exit fee.
     * @param admin The address of the administrator.
     * @param rebalancer The address responsible for rebalancing the vault.
     * @param feeReceiver The address that will receive the fees.
     * @param redeemOperator The address of the operator responsible for redeeming shares
     */
    struct VaultParams {
        address underlyingToken;
        string name;
        string symbol;
        uint256 marketCapacity;
        uint256 managementFeeRate;
        uint256 managementFeeClaimPeriod;
        uint256 maxPriceUpdatePeriod;
        uint256 revenueRate;
        uint256 exitFeeRate;
        address admin;
        address rebalancer;
        address feeReceiver;
        address redeemOperator;
    }

    /**
     * @dev
     * @param exchangePrice The exchange rate used during user deposit and withdrawal operations.
     * @param revenueExchangePrice The exchange rate used when calculating performance fees,Performance fees will be recorded when the real exchange rate exceeds this rate.
     * @param revenue Collected revenue, stored in pegged ETH.
     * @param lastClaimMngFeeTime The last time the management fees were charged.
     * @param lastUpdatePriceTime The last time the exchange price was updated.
     */
    struct VaultState {
        uint256 exchangePrice;
        uint256 revenueExchangePrice;
        uint256 revenue;
        uint256 lastClaimMngFeeTime;
        uint256 lastUpdatePriceTime;
    }

    function optionalRedeem(address _token, uint256 _shares, uint256 _cutPercentage, address _receiver, address _owner)
        external
        returns (uint256 assetsAfterFee_);

    function getWithdrawFee(uint256 _amount) external view returns (uint256 amount_);

    function exchangePrice() external view returns (uint256);

    function revenueExchangePrice() external view returns (uint256);

    function revenue() external view returns (uint256);

    function lastExchangePrice() external view returns (uint256);
}
