// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWstETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    function unwrap(uint256 _stETHAmount) external returns (uint256);

    function tokensPerStEth() external view returns (uint256);

    function stEthPerToken() external view returns (uint256);

    function getStETHByWstETH(uint256 _stETHAmount) external view returns (uint256);

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}
