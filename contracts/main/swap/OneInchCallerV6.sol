// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/Address.sol";
import "../../interfaces/1inch/AddressLib.sol";
import "../../interfaces/1inch/IAggregationRouterV6.sol";
import "../libraries/Errors.sol";
import "../common/Constants.sol";

/**
 * @title OneInchCallerV6 contract
 * @author Naturelab
 * @notice The focal point of interacting with the 1inch protocol.
 * @dev This contract will be inherited by the strategy contract and the wrapper contract,
 * used for the necessary exchange between different tokens when necessary.
 * @dev When using this contract, it is necessary to first obtain the calldata through 1inch API.
 * The contract will then extract and verify the calldata before proceeding with the exchange.
 */
contract OneInchCallerV6 is Constants {
    // 1inch v6 protocol is currently in use.
    address public constant ONEINCH_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65;

    using AddressLib for UAddress;

    /**
     * @dev Separate the function signature and detailed parameters in the calldata.
     * This approach is used because memory variables in Solidity do not support slicing
     * operations directly. By using inline assembly, we can manually handle memory operations
     * to extract and copy the necessary parts of the data efficiently.
     * @param _swapData Calldata of 1inch.
     * @return functionSignature_ Function signature of the swap method.
     * @return remainingBytes_ The remaining bytes after the function signature.
     */
    function parseSwapCalldata(bytes memory _swapData)
        internal
        pure
        returns (bytes4 functionSignature_, bytes memory remainingBytes_)
    {
        assembly {
            // Extract function signature (first 4 bytes)
            functionSignature_ := mload(add(_swapData, 32))

            // Calculate remaining data length
            let remainingLength := sub(mload(_swapData), 4)

            // Allocate memory and copy remaining data
            remainingBytes_ := mload(0x40)
            mstore(remainingBytes_, remainingLength)
            let dst := add(remainingBytes_, 32)
            let src := add(_swapData, 36)

            for { let end := add(dst, remainingLength) } lt(dst, end) {
                dst := add(dst, 32)
                src := add(src, 32)
            } { mstore(dst, mload(src)) }

            // Update free memory pointer
            mstore(0x40, add(remainingBytes_, add(remainingLength, 32)))
        }
    }

    /**
     * @dev Executes the swap operation and verify the validity of the parameters and results.
     * @param _amount The maximum amount of currency spent.
     * @param _srcToken The token to be spent.
     * @param _dstToken The token to be received.
     * @param _swapData Calldata of 1inch.
     * @param _swapGetMin Minimum amount of the token to be received.
     * @return returnAmount_ Actual amount of the token spent.
     * @return spentAmount_ Actual amount of the token received.
     */
    function executeSwap(
        uint256 _amount,
        address _srcToken,
        address _dstToken,
        bytes memory _swapData,
        uint256 _swapGetMin
    ) internal returns (uint256 returnAmount_, uint256 spentAmount_) {
        (bytes4 functionSignature_, bytes memory remainingBytes_) = parseSwapCalldata(_swapData);
        bytes memory returnData_;
        if (functionSignature_ == IAggregationRouterV6.swap.selector) {
            (, IAggregationRouterV6.SwapDescription memory desc_,) =
                abi.decode(remainingBytes_, (IAggregationExecutor, IAggregationRouterV6.SwapDescription, bytes));
            if (address(this) != desc_.dstReceiver) revert Errors.OneInchInvalidReceiver();
            if (IERC20(_srcToken) != desc_.srcToken || IERC20(_dstToken) != desc_.dstToken) {
                revert Errors.OneInchInvalidToken();
            }
            if (_amount < desc_.amount) revert Errors.OneInchInvalidInputAmount();

            if (_srcToken == ETH) {
                returnData_ = Address.functionCallWithValue(ONEINCH_ROUTER, _swapData, _amount);
            } else {
                returnData_ = Address.functionCall(ONEINCH_ROUTER, _swapData);
            }
            (returnAmount_, spentAmount_) = abi.decode(returnData_, (uint256, uint256));
            if (spentAmount_ > desc_.amount) revert Errors.OneInchUnexpectedSpentAmount();
            if (returnAmount_ < _swapGetMin) revert Errors.OneInchUnexpectedReturnAmount();
            return (returnAmount_, spentAmount_);
        }

        if (
            functionSignature_ == IAggregationRouterV6.ethUnoswap.selector
                || functionSignature_ == IAggregationRouterV6.ethUnoswap2.selector
                || functionSignature_ == IAggregationRouterV6.ethUnoswap3.selector
        ) {
            if (_srcToken != ETH || _dstToken == ETH) revert Errors.OneInchNotSupported();
            uint256 tokenBefore_ = IERC20(_dstToken).balanceOf(address(this));
            uint256 ethBal_ = address(this).balance;
            returnData_ = Address.functionCallWithValue(ONEINCH_ROUTER, _swapData, _amount);
            spentAmount_ = ethBal_ - address(this).balance;
            returnAmount_ = IERC20(_dstToken).balanceOf(address(this)) - tokenBefore_;
            if (spentAmount_ != _amount) revert Errors.OneInchUnexpectedSpentAmount();
            if (returnAmount_ < _swapGetMin) revert Errors.OneInchUnexpectedReturnAmount();
            return (returnAmount_, spentAmount_);
        }

        UAddress srcTokenFromCalldata_;
        if (
            functionSignature_ == IAggregationRouterV6.unoswap.selector
                || functionSignature_ == IAggregationRouterV6.unoswap2.selector
                || functionSignature_ == IAggregationRouterV6.unoswap3.selector
        ) {
            (srcTokenFromCalldata_, spentAmount_) = abi.decode(remainingBytes_, (UAddress, uint256));
        } else {
            revert Errors.OneInchInvalidFunctionSignature();
        }
        if (srcTokenFromCalldata_.get() != _srcToken || _srcToken == ETH) revert Errors.OneInchNotSupported();
        if (_amount < spentAmount_) revert Errors.OneInchInvalidInputAmount();
        uint256 unoswapTokenBefore_ = IERC20(_dstToken).balanceOf(address(this));
        returnData_ = Address.functionCall(ONEINCH_ROUTER, _swapData);
        returnAmount_ = IERC20(_dstToken).balanceOf(address(this)) - unoswapTokenBefore_;
        if (returnAmount_ < _swapGetMin) revert Errors.OneInchUnexpectedReturnAmount();
    }

    receive() external payable {}
}
