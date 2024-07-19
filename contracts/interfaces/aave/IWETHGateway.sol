// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IWETHGateway {
    function borrowETH(address lendingPool, uint256 amount, uint256 interesRateMode, uint16 referralCode) external;

    function depositETH(address lendingPool, address onBehalfOf, uint16 referralCode) external payable;

    function repayETH(address lendingPool, uint256 amount, uint256 rateMode, address onBehalfOf) external payable;

    function withdrawETH(address lendingPool, uint256 amount, address to) external;
}
