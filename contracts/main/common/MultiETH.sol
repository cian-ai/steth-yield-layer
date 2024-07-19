// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../interfaces/weth/IWETH.sol";
import "../../interfaces/lido/IstETH.sol";
import "../../interfaces/lido/IWithdrawalNft.sol";
import "../../interfaces/etherfi/ILiquidityPool.sol";
import "../../interfaces/etherfi/ILiquifier.sol";
import "../../interfaces/etherfi/IWithdrawRequestNFT.sol";
import "./Constants.sol";
import "../libraries/Errors.sol";

abstract contract MultiETH is IERC721Receiver, Constants {
    using SafeERC20 for IERC20;

    ILiquifier internal constant etherfiLiquifier = ILiquifier(0x9FFDF407cDe9a93c47611799DA23924Af3EF764F);
    ILiquidityPool internal constant etherfiPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
    IWithdrawRequestNFT internal constant etherfiQueue = IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);
    IWithdrawalNft internal constant lidoQueue = IWithdrawalNft(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
    uint256 public lidoUnstakeId;
    uint256 public etherfiUnstakeId;

    event ConvertToken(address srcToken, address toToken, uint256 amount);
    event ClaimUnstake(address srcToken);

    function _convertToken(address _srcToken, address _toToken, uint256 _amount) internal {
        if (_srcToken == ETH) {
            if (_toToken == WETH) {
                IWETH(WETH).deposit{value: _amount}();
            } else if (_toToken == STETH) {
                IstETH(STETH).submit{value: _amount}(address(0));
            } else if (_toToken == EETH) {
                etherfiPool.deposit{value: _amount}();
            } else {
                revert Errors.InvalidAsset();
            }
        } else if (_srcToken == WETH) {
            IWETH(WETH).withdraw(_amount);
            if (_toToken == ETH) {
                // do nothing
            } else if (_toToken == STETH) {
                IstETH(STETH).submit{value: _amount}(address(0));
            } else if (_toToken == EETH) {
                etherfiPool.deposit{value: _amount}();
            } else {
                revert Errors.InvalidAsset();
            }
        } else if (_srcToken == STETH) {
            if (_toToken == ETH) {
                if (lidoUnstakeId != 0) revert Errors.IncorrectState();
                uint256[] memory amounts_ = new uint256[](1);
                amounts_[0] = _amount;
                IERC20(STETH).safeIncreaseAllowance(address(lidoQueue), _amount);
                uint256[] memory newLidoUnstakeIds_ = lidoQueue.requestWithdrawals(amounts_, address(this));
                lidoUnstakeId = newLidoUnstakeIds_[0];
            } else if (_toToken == EETH) {
                IERC20(STETH).safeIncreaseAllowance(address(etherfiLiquifier), _amount);
                uint256 return_ = etherfiLiquifier.depositWithERC20(STETH, _amount, address(this));
                if (return_ != _amount) revert Errors.IncorrectState();
            } else {
                revert Errors.InvalidAsset();
            }
        } else if (_srcToken == EETH) {
            if (_toToken == ETH) {
                if (etherfiUnstakeId != 0) revert Errors.IncorrectState();
                IERC20(EETH).safeIncreaseAllowance(address(etherfiPool), _amount);
                etherfiUnstakeId = etherfiPool.requestWithdraw(address(this), _amount);
            } else {
                revert Errors.InvalidAsset();
            }
        } else {
            revert Errors.InvalidAsset();
        }

        emit ConvertToken(_srcToken, _toToken, _amount);
    }

    function _claimUnstake(address _srcToken) internal {
        if (_srcToken == STETH) {
            if (lidoUnstakeId == 0) revert Errors.IncorrectState();
            lidoQueue.claimWithdrawal(lidoUnstakeId);
            lidoUnstakeId = 0;
        } else if (_srcToken == EETH) {
            if (etherfiUnstakeId == 0) revert Errors.IncorrectState();
            etherfiQueue.claimWithdraw(etherfiUnstakeId);
            etherfiUnstakeId = 0;
        } else {
            revert Errors.IncorrectState();
        }

        emit ClaimUnstake(_srcToken);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // to = ETH
    function getUnstakingAmount(address _srcToken) public view returns (uint256) {
        if (_srcToken == STETH) {
            if (lidoUnstakeId == 0) return 0;
            uint256[] memory requestIds_ = new uint256[](1);
            requestIds_[0] = lidoUnstakeId;
            IWithdrawalNft.WithdrawalRequestStatus[] memory statuses_ = lidoQueue.getWithdrawalStatus(requestIds_);
            return statuses_[0].amountOfStETH;
        } else if (_srcToken == EETH) {
            if (etherfiUnstakeId == 0) return 0;
            IWithdrawRequestNFT.WithdrawRequest memory request_ = etherfiQueue.getRequest(etherfiUnstakeId);
            return request_.amountOfEEth;
        } else {
            revert Errors.InvalidAsset();
        }
    }

    function getTotalETHBalance() public view returns (uint256) {
        uint256 ethBalance_ = address(this).balance;
        uint256 wethBalance_ = IERC20(WETH).balanceOf(address(this));
        uint256 stethBalance_ = IERC20(STETH).balanceOf(address(this));
        uint256 eethBalance_ = IERC20(EETH).balanceOf(address(this));
        uint256 unstaking_ = getUnstakingAmount(STETH) + getUnstakingAmount(EETH);

        // Assuming 1:1 conversion rate for simplicity
        return ethBalance_ + wethBalance_ + stethBalance_ + eethBalance_ + unstaking_;
    }
}
