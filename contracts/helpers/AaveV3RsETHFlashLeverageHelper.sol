// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/aave/v3/IPoolV3.sol";
import "../interfaces/strategy/aave/IStrategyAaveV3MultiLend.sol";
import "../interfaces/aave/IAaveOracle.sol";
import "../interfaces/kelp/ILRTDepositPool.sol";
import "../interfaces/kelp/ILRTOracle.sol";
import "../interfaces/kelp/ILRTWithdrawalManager.sol";
import "../interfaces/lido/IWstETH.sol";
import "../main/common/Constants.sol";
// import "hardhat/console.sol";

/**
 * @title AaveV3RsETHFlashLeverageHelpers
 * @author Naturelab
 * @dev This contract is used to allow leverage on aaveV3 without simulation.
 */
contract AaveV3RsETHFlashLeverageHelper is Ownable, Constants {
    // The address of the strategy contract
    address public strategy;

    address public multiCall;

    bool internal enterProtocol = false;

    address public constant RSETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;

    // The address of the AAVE v3 variable debt token for wstETH
    address internal constant D_WSTETH_AAVEV3 = 0xC96113eED8cAB59cD8A66813bCB0cEb29F06D2e4;

    // The address of the AAVE v3 Oracle contract
    IAaveOracle internal constant ORACLE_AAVEV3 = IAaveOracle(0x54586bE62E3c3580375aE3723C145253060Ca0C2);

    // The address of the AAVE v3 Pool contract
    IPoolV3 internal constant POOL_AAVEV3 = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    ILRTWithdrawalManager internal constant kelpWithdrawal =
        ILRTWithdrawalManager(0x62De59c08eB5dAE4b7E6F7a8cAd3006d6965ec16);

    ILRTOracle internal constant kelpOracle = ILRTOracle(0x349A73444b1a310BAe67ef67973022020d70020d);

    ILRTDepositPool internal constant kelpPool = ILRTDepositPool(0x036676389e48133B63a802f8635AD39E752D375D);
    

    constructor(address _admin, address _multiCall, address _strategy) Ownable(_admin) {
        // leverage by stake
        strategy = _strategy;
        multiCall = _multiCall;
    }

    function updateMultiCall(address _multiCall) external onlyOwner {
        multiCall = _multiCall;
    }

    function aTokenRsETH() public view returns (address) {
        DataTypes.ReserveData memory reserveData = POOL_AAVEV3.getReserveData(RSETH);
        return reserveData.aTokenAddress;
    }

    function getETHByRsETH(uint256 _rsethAmount) public view returns (uint256) {
        uint256 rate_ = kelpOracle.rsETHPrice();
        return _rsethAmount * rate_ / 1e18;
    }

    function getRsETHByETH(uint256 _ethAmount) public view returns (uint256) {
        return kelpPool.getRsETHAmountToMint(ETH, _ethAmount);
    }

    function getETHByWstETH(uint256 _wstethAmount) public view returns (uint256) {
        return IWstETH(WSTETH).getStETHByWstETH(_wstethAmount);
    }

    function getWstETHByETH(uint256 _ethAmount) public view returns (uint256) {
        return IWstETH(WSTETH).getWstETHByStETH(_ethAmount);
    }

    // rsETH - > ETH -> rsETH
    function getWstETHByRsETH(uint256 _rsethAmount) public view returns (uint256) {
        if (_rsethAmount == 0) return 0;
        return getWstETHByETH(getETHByRsETH(_rsethAmount));
    }

    // wstETH - > ETH -> rsETH
    function getRsETHByWstETH(uint256 _wstethAmount) public view returns (uint256) {
        if (_wstethAmount == 0) return 0;
        return getRsETHByETH(getETHByWstETH(_wstethAmount));
    }

    function getCaps() public view returns (uint256, uint256) {
        return (getSupplyCap(), getBorrowCap());
    }

    function getSupplyCap() internal view returns (uint256) {
        uint256 totalSupplied_ = IERC20(aTokenRsETH()).totalSupply();
        uint256 configMap_ = POOL_AAVEV3.getReserveData(RSETH).configuration.data;
        // Cut out bit 116-151 to get supply cap
        return ((configMap_ >> 116) & 0x7FFFF) * 1e18 - totalSupplied_;
    }

    function getBorrowCap() internal view returns (uint256) {
        uint256 totalBorrowed_ = IERC20(D_WSTETH_AAVEV3).totalSupply();
        uint256 configMap_ = POOL_AAVEV3.getReserveData(WSTETH).configuration.data;
        // Cut out bit 80-151 to get borrow cap
        return ((configMap_ >> 80) & 0x7FFFF) * 1e18 - totalBorrowed_;
    }

    function calculateBorrowable(uint256 _depositAmount) public view returns (uint256) {
        uint256 totalBorrowed_ = IERC20(D_WSTETH_AAVEV3).balanceOf(strategy);
        uint256 totalSupplied_ = IERC20(aTokenRsETH()).balanceOf(strategy);
        totalSupplied_ += _depositAmount;
        // Log amounts
        // console.log("Total supplied: %s", totalSupplied_);
        // console.log("Total borrowed: %s", totalBorrowed_);
        uint256 wstPrice_ = ORACLE_AAVEV3.getAssetPrice(WSTETH);
        uint256 ezPrice_ = ORACLE_AAVEV3.getAssetPrice(RSETH);
        // Log price
        // console.log("Wst price: %s", wstPrice_);
        // console.log("Ez price: %s", ezPrice_);
        uint256 wstToEzRate_ = getRsETHByWstETH(1e18);
        // Log rate
        // console.log("Wst to ez rate: %s", wstToEzRate_);
        uint256 collRate_ = IStrategyAaveV3MultiLend(strategy).safeProtocolRatio();
        uint256 priceInvolvedCollRate_ = collRate_ * ezPrice_ / wstPrice_;
        uint256 amount = (priceInvolvedCollRate_ * totalSupplied_ - totalBorrowed_ * 1e18) / (1e18 - (priceInvolvedCollRate_ * wstToEzRate_ / 1e18));
        // Log result
        // console.log("Borrowable leverage amount: %s", amount);
        return amount;
    }

    /**
     * @dev Allows the owner to leverage by stake, to the allowed maximum for contract.
     */
    function leverageMaxium() external onlyOwner {
        if (!enterProtocol) {
            IStrategyAaveV3MultiLend(strategy).enterProtocol();
            enterProtocol = true;
        }
        // First, get current total supply of rsETH
        (uint256 supplyCap_, uint256 borrowCap_) = getCaps();
        // Get the current balance of the strategy
        uint256 balance_ = IERC20(RSETH).balanceOf(strategy);
        // If the remaining supply is less than the balance, set balance to remaining supply
        if (supplyCap_ < balance_) {
            balance_ = supplyCap_;
        }
        uint256 leverageAmount_ = calculateBorrowable(balance_); // Hold 5% for success rate
        leverageAmount_ = leverageAmount_ * 98 / 100;
        if (leverageAmount_ > supplyCap_ - balance_) {
            leverageAmount_ = supplyCap_ - balance_;
        }
        if (leverageAmount_ > borrowCap_) {
            leverageAmount_ = borrowCap_;
        }
        if (leverageAmount_ > getWstETHByRsETH(supplyCap_ - balance_)) {
            leverageAmount_ = getWstETHByRsETH(supplyCap_ - balance_);
        }
        if (leverageAmount_ < 1e18) { 
            IStrategyAaveV3MultiLend(strategy).leverage(balance_, WSTETH, 0, "", 0, 0);
            return;
        }
        IStrategyAaveV3MultiLend(strategy).leverage(balance_, WSTETH, leverageAmount_ - 1e10, "", 0, 0);
    }

    fallback() external payable {
        // Require msg.sender is owner
        require(msg.sender == owner() || msg.sender == multiCall, "AaveV3FlashLeverageHelper: fallback caller is not owner");
        // Delegate to the strategy contract
        (bool success, ) = strategy.call(msg.data);
        require(success, "AaveV3FlashLeverageHelper: fallback call failed");
    }

    receive() external payable {}
}
