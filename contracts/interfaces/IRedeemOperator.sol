// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IRedeemOperator {
    // Events for logging actions
    event RegisterWithdrawal(address indexed user, uint256 shares);
    event ConfirmWithdrawalSTETH(address[] users);
    event ConfirmWithdrawalEETH(address[] users);
    event UpdateOperator(address oldOperator, address newOperator);
    event UpdateFeeReceiver(address oldFeeReceiver, address newFeeReceiver);
    event Sweep(address token);

    function registerWithdrawal(address _user, uint256 _shares, address _token) external;

    function pendingWithdrawersCount() external view returns (uint256, uint256);

    function pendingWithdrawers(uint256 _limit, uint256 _offset, address _token)
        external
        view
        returns (address[] memory result_);

    function allPendingWithdrawers() external view returns (address[] memory, address[] memory);

    function confirmWithdrawal(address[] calldata _stEthUsers, address[] calldata _eEthUsers, uint256 _totalGasLimit)
        external;
}
