// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./libraries/Errors.sol";

/**
 * @title Manager
 * @author Naturelab
 * @dev This contract is used to manage KMS addresses for batch operations.
 */
contract Manager is Ownable {
    mapping(address => bool) public operators;

    /**
     * @dev Initializes the contract by setting the admin and adding the initial operator to the whitelist.
     * @param _admin The address of the contract owner, it will be a multisignature address.
     * @param _initialOperator The address of the initial operator.
     */
    constructor(address _admin, address _initialOperator) Ownable(_admin) {
        operators[_initialOperator] = true;
    }

    // Event emitted when an operator is added to the whitelist
    event OperatorAdded(address operator);

    // Event emitted when an operator is removed from the whitelist
    event OperatorRemoved(address operator);

    // Modifier to restrict function access to the operators in the whitelist
    modifier onlyOperator() {
        if (!operators[msg.sender]) revert Errors.CallerNotOperator();
        _;
    }

    /**
     * @dev Allows the owner to add a new operator to the whitelist.
     * Emits an OperatorAdded event.
     * @param _operator The address of the operator to add.
     */
    function addOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert Errors.InvalidOperator();
        operators[_operator] = true;
        emit OperatorAdded(_operator);
    }

    /**
     * @dev Allows the owner to remove an operator from the whitelist.
     * Emits an OperatorRemoved event.
     * @param _operator The address of the operator to remove.
     */
    function removeOperator(address _operator) external onlyOwner {
        if (!operators[_operator]) revert Errors.InvalidOperator();
        operators[_operator] = false;
        emit OperatorRemoved(_operator);
    }

    /**
     * @dev Allows operators to make multiple calls to different addresses in a single transaction.
     * @param _addresses An array of addresses to call.
     * @param _callBytes An array of call data bytes, each corresponding to a call to be made to the addresses.
     */
    function multiCall(address[] calldata _addresses, bytes[] calldata _callBytes) external onlyOperator {
        if (_callBytes.length != _addresses.length || _addresses.length == 0) revert Errors.InvalidLength();

        for (uint256 i = 0; i < _callBytes.length; ++i) {
            Address.functionCall(_addresses[i], _callBytes[i]);
        }
    }
}
