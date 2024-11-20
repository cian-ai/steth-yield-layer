// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IStrategyAaveV3MultiLend {
    function safeProtocolRatio() external view returns (uint256);
    function enterProtocol() external;
    function leverage(
        uint256 _deposit,
        address _borrowToken,
        uint256 _leverageAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external;
}
