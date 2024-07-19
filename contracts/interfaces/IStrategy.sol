// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IStrategy {
    function getNetAssets() external returns (uint256);

    function onTransferIn(address token, uint256 amount) external returns (bool);
}
