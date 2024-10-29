// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface IWithdrawQueue {
    struct WithdrawRequest {
        address collateralToken;
        uint256 withdrawRequestID;
        uint256 amountToRedeem;
        uint256 ezETHLocked;
        uint256 createdAt;
    }

    function withdrawRequests(address _address, uint256 _id) external view returns (WithdrawRequest memory);
    /// @dev To get available value to withdraw from buffer
    /// @param _asset address of token
    function getAvailableToWithdraw(address _asset) external view returns (uint256);

    /// @dev To get the withdraw buffer target of given asset
    /// @param _asset address of token
    function withdrawalBufferTarget(address _asset) external view returns (uint256);

    /// @dev To get the current Target Buffer Deficit
    /// @param _asset address of token
    function getWithdrawDeficit(address _asset) external view returns (uint256);

    /// @dev Fill ERC20 Withdraw Buffer
    /// @param _asset the token address to fill the respective buffer
    /// @param _amount  amount of token to fill with
    function fillERC20WithdrawBuffer(address _asset, uint256 _amount) external;

    /// @dev Fill ETH Withdraw buffer
    function fillEthWithdrawBuffer() external payable;

    /**
     * @notice  Creates a withdraw request for user
     * @param   _amount  amount of ezETH to withdraw
     * @param   _assetOut  output token to receive on claim
     */
    function withdraw(uint256 _amount, address _assetOut) external;

    /**
     * @notice  Returns the number of outstanding withdrawal requests of the specified user
     * @param   user  address of the user
     * @return  uint256  number of outstanding withdrawal requests
     */
    function getOutstandingWithdrawRequests(address user) external view returns (uint256);

    /**
     * @notice  Claim user withdraw request
     * @dev     revert on claim before cooldown period
     * @param   withdrawRequestIndex  Index of the Withdraw Request user wants to claim
     * @param   user address of the user to claim withdrawRequest for
     */
    function claim(uint256 withdrawRequestIndex, address user) external;
}