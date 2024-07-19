// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title MultiSig
 * @author Naturelab
 * @dev This contract is designed for testing purposes only. In the production environment, a proper multisignature contract should be used.
 * The contract allows the owner to make multiple calls to different addresses in a single transaction.
 */
contract MultiSig is Ownable {
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Allows the owner to make multiple calls to different addresses.
     * This function is restricted to the contract owner.
     *
     * @param _addresses An array of addresses to call.
     * @param _callBytes An array of call data bytes, each corresponding to a call to be made to the addresses.
     */
    function multiCall(address[] calldata _addresses, bytes[] calldata _callBytes) external onlyOwner {
        // Ensure the lengths of the addresses and call bytes arrays are equal and non-zero
        require(_callBytes.length == _addresses.length && _addresses.length > 0, "Invalid lengths!");

        // Loop through each address and corresponding call data
        for (uint256 i = 0; i < _callBytes.length; ++i) {
            // Use Address library to safely call the function at each address
            Address.functionCall(_addresses[i], _callBytes[i]);
        }
    }
}
