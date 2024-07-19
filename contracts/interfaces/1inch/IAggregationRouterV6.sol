// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for making arbitrary calls during swap
interface IAggregationExecutor {
    /// @notice propagates information about original msg.sender and executes arbitrary data
    function execute(address msgSender) external payable returns (uint256); // 0x4b64e492
}

interface IAggregationRouterV6 {
    type Address is uint256;

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(IAggregationExecutor executor, SwapDescription calldata desc, bytes calldata data)
        external
        returns (uint256 returnAmount, uint256 spentAmount);

    // uno

    /**
     * @notice Swaps `amount` of the specified `token` for another token using an Unoswap-compatible exchange's pool,
     *         with a minimum return specified by `minReturn`.
     * @param token The address of the token to be swapped.
     * @param amount The amount of tokens to be swapped.
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap.
     */
    function unoswap(Address token, uint256 amount, uint256 minReturn, Address dex)
        external
        returns (uint256 returnAmount);

    /**
     * @notice Swaps ETH for another token using an Unoswap-compatible exchange's pool, with a minimum return specified by `minReturn`.
     *         The function is payable and requires the sender to attach ETH.
     *         It is necessary to check if it's cheaper to use _WETH_NOT_WRAP_FLAG in `dex` Address (for example: for Curve pools).
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap.
     */
    function ethUnoswap(uint256 minReturn, Address dex) external payable returns (uint256 returnAmount);

    /**
     * @notice Swaps `amount` of the specified `token` for another token using two Unoswap-compatible exchange pools (`dex` and `dex2`) sequentially,
     *         with a minimum return specified by `minReturn`.
     * @param token The address of the token to be swapped.
     * @param amount The amount of tokens to be swapped.
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the first Unoswap-compatible exchange's pool.
     * @param dex2 The address of the second Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap through both pools.
     */
    function unoswap2(Address token, uint256 amount, uint256 minReturn, Address dex, Address dex2)
        external
        returns (uint256 returnAmount);

    /**
     * @notice Swaps ETH for another token using two Unoswap-compatible exchange pools (`dex` and `dex2`) sequentially,
     *         with a minimum return specified by `minReturn`. The function is payable and requires the sender to attach ETH.
     *         It is necessary to check if it's cheaper to use _WETH_NOT_WRAP_FLAG in `dex` Address (for example: for Curve pools).
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the first Unoswap-compatible exchange's pool.
     * @param dex2 The address of the second Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap through both pools.
     */
    function ethUnoswap2(uint256 minReturn, Address dex, Address dex2)
        external
        payable
        returns (uint256 returnAmount);

    /**
     * @notice Swaps `amount` of the specified `token` for another token using three Unoswap-compatible exchange pools
     *         (`dex`, `dex2`, and `dex3`) sequentially, with a minimum return specified by `minReturn`.
     * @param token The address of the token to be swapped.
     * @param amount The amount of tokens to be swapped.
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the first Unoswap-compatible exchange's pool.
     * @param dex2 The address of the second Unoswap-compatible exchange's pool.
     * @param dex3 The address of the third Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap through all three pools.
     */
    function unoswap3(Address token, uint256 amount, uint256 minReturn, Address dex, Address dex2, Address dex3)
        external
        returns (uint256 returnAmount);

    /**
     * @notice Swaps ETH for another token using three Unoswap-compatible exchange pools (`dex`, `dex2`, and `dex3`) sequentially,
     *         with a minimum return specified by `minReturn`. The function is payable and requires the sender to attach ETH.
     *         It is necessary to check if it's cheaper to use _WETH_NOT_WRAP_FLAG in `dex` Address (for example: for Curve pools).
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the first Unoswap-compatible exchange's pool.
     * @param dex2 The address of the second Unoswap-compatible exchange's pool.
     * @param dex3 The address of the third Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap through all three pools.
     */
    function ethUnoswap3(uint256 minReturn, Address dex, Address dex2, Address dex3)
        external
        payable
        returns (uint256 returnAmount);
}
