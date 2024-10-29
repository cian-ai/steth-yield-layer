// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IRestakeManager {
    function calculateTVLs() external view returns (uint256[][] memory, uint256[] memory, uint256);

    function depositETH() external payable;

    function deposit(address _collateralToken, uint256 _amount) external;
}
