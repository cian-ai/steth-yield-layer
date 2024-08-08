// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
