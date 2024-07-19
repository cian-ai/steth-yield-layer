// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface ILendingAdapter {
    // View only adapter functions
    function depositOf(address token) external view returns (uint256);
    function debtOf(address token) external view returns (uint256);
    // Operations
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
}
