// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWeETH is IERC20 {
    function wrap(uint256 _eETHAmount) external returns (uint256);

    function unwrap(uint256 _weETHAmount) external returns (uint256);

    function getWeETHByeETH(uint256 _eETHAmount) external view returns (uint256);

    function getEETHByWeETH(uint256 _weETHAmount) external view returns (uint256);

    function getRate() external view returns (uint256);
}
