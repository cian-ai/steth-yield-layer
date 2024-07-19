// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

interface IFlashloanHelper {
    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _params)
        external
        returns (bool);

    function addToWhitelist(address _account) external;
}
