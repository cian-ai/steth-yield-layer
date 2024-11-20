// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IStrategyAaveV3 {
    function getLeverageAmount(bool _isDepositOrWithdraw, uint256 _depositOrWithdraw) external view returns (bool, uint256);
    function getAvailableBorrowsWSTETH() external view returns (uint256);
    function safeProtocolRatio() external view returns (uint256);
    function leverage(
        uint256 _deposit,
        uint256 _leverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external;
    function enterProtocol() external;
}
