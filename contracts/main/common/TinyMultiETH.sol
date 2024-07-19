// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/weth/IWETH.sol";
import "../../interfaces/lido/IstETH.sol";
import "../../interfaces/etherfi/ILiquidityPool.sol";
import "./Constants.sol";
import "../libraries/Errors.sol";

contract TinyMultiETH is Constants {
    ILiquidityPool internal constant etherfiPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);

    function _stakeTo(address _toToken, uint256 _amount) internal {
        IWETH(WETH).withdraw(_amount);
        if (_toToken == STETH) {
            IstETH(STETH).submit{value: _amount}(address(0));
        } else if (_toToken == EETH) {
            etherfiPool.deposit{value: _amount}();
        } else {
            revert Errors.InvalidAsset();
        }
    }
}
