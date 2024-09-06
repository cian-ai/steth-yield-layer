// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title Compound's Comet Ext Interface
 * @notice An efficient monolithic money market protocol
 * @author Compound
 */
interface ICometExt {
    function allow(address manager, bool isAllowed) external;

    function allowBySig(
        address owner,
        address manager,
        bool isAllowed,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function collateralBalanceOf(address account, address asset) external view returns (uint128);

    function baseTrackingAccrued(address account) external view returns (uint64);

    function baseAccrualScale() external view returns (uint64);

    function baseIndexScale() external view returns (uint64);

    function factorScale() external view returns (uint64);

    function priceScale() external view returns (uint64);

    function maxAssets() external view returns (uint8);

    function version() external view returns (string memory);

    /**
     * ===== ERC20 interfaces =====
     * Does not include the following functions/events, which are defined in `CometMainInterface` instead:
     * - function decimals()  external view returns (uint8)
     * - function totalSupply()  external view returns (uint256)
     * - function transfer(address dst, uint amount)  external returns (bool)
     * - function transferFrom(address src, address dst, uint amount)  external returns (bool)
     * - function balanceOf(address owner)  external view returns (uint256)
     * - event Transfer(address indexed from, address indexed to, uint256 amount)
     */
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address owner, address spender) external view returns (uint256);

    event Approval(address indexed owner, address indexed spender, uint256 amount);
}
