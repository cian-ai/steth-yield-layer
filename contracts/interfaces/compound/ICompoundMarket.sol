// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICompoundMarket {
    struct UserCollateral {
        uint128 balance;
        uint128 _reserved;
    }

    function borrowBalanceOf(address account) external view returns (uint256);

    function userCollateral(address, address) external view returns (UserCollateral memory);
}
