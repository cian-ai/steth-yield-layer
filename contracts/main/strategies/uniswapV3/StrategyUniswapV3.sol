// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../interfaces/uniswapV3/INonfungiblePositionManager.sol";
import "../../../interfaces/uniswapV3/IUniswapV3PoolState.sol";
import "../../../interfaces/uniswapV3/libraries/TickMath.sol";
import "../../../interfaces/uniswapV3/libraries/SqrtPriceMath.sol";
import "../../../interfaces/lido/IWstETH.sol";
import "../../../interfaces/IVault.sol";
import "../../../interfaces/IStrategy.sol";
import "../../libraries/Errors.sol";
import "../../common/MultiETH.sol";

/**
 * @title StrategyUniswapV3 contract
 * @author Naturelab
 * @dev This contract is the actual address of the strategy pool, which
 * manages some assets in uniswapV3.
 */
contract StrategyUniswapV3 is IStrategy, MultiETH, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // The version of the contract
    string public constant VERSION = "1.0";

    address internal constant UNI_V3_POS_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address internal constant UNI_V3_POOL = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;

    uint256 public tokenId;

    // The address of the Vault contract that manages user shares
    address public vault;

    // The address of the position adjustment manager
    address public rebalancer;

    event UpdateRebalancer(address oldRebalancer, address newRebalancer);
    event OnTransferIn(address token, uint256 amount);
    event TransferToVault(address token, uint256 amount);
    event Wrap(uint256 stEthAmount, uint256 wstEthAmount);
    event Unwrap(uint256 wstEthAmount, uint256 stEthAmount);
    event Mint(uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event IncreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);
    event Collect(uint256 amount0, uint256 amount1);
    event Burn(uint256 tokenId);

    /**
     * @dev Ensure that this method is only called by the Vault contract.
     */
    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.CallerNotVault();
        _;
    }

    /**
     * @dev  Ensure that this method is only called by authorized portfolio managers.
     */
    modifier onlyRebalancer() {
        if (msg.sender != rebalancer) revert Errors.CallerNotRebalancer();
        _;
    }

    /**
     * @dev Initialize the strategy with given parameters.
     * @param _initBytes Initialization data
     */
    function initialize(bytes calldata _initBytes) external initializer {
        (address admin_, address rebalancer_) = abi.decode(_initBytes, (address, address));
        if (admin_ == address(0)) revert Errors.InvalidAdmin();
        if (rebalancer_ == address(0)) revert Errors.InvalidRebalancer();
        __Ownable_init(admin_);

        rebalancer = rebalancer_;
        vault = msg.sender;
    }

    /**
     * @dev Add a new address to the position adjustment whitelist.
     * @param _newRebalancer The new address to be added.
     */
    function updateRebalancer(address _newRebalancer) external onlyOwner {
        if (_newRebalancer == address(0)) revert Errors.InvalidRebalancer();
        emit UpdateRebalancer(rebalancer, _newRebalancer);
        rebalancer = _newRebalancer;
    }

    function convertToken(address _srcToken, address _toToken, uint256 _amount) external onlyRebalancer {
        _convertToken(_srcToken, _toToken, _amount);
    }

    function claimUnstake(address _srcToken) external onlyRebalancer {
        _claimUnstake(_srcToken);
    }

    /**
     * @dev Transfers funds from the vault contract to this contract.
     * This function is called by the vault to move tokens into this contract.
     * It uses the `safeTransferFrom` function from the SafeERC20 library to ensure the transfer is successful.
     * @param _token The address of the token to be transferred.
     * @param _amount The amount of tokens to be transferred.
     * @return A boolean indicating whether the transfer was successful.
     */
    function onTransferIn(address _token, uint256 _amount) external onlyVault returns (bool) {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        if (_token == STETH) {
            IERC20(STETH).safeIncreaseAllowance(WSTETH, _amount);
            IWstETH(WSTETH).wrap(_amount);
        }
        emit OnTransferIn(_token, _amount);
        return true;
    }

    /**
     * @dev Transfer tokens to the Vault.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     */
    function transferToVault(address _token, uint256 _amount) external onlyRebalancer {
        IERC20(_token).safeTransfer(vault, _amount);
        emit TransferToVault(_token, _amount);
    }

    /**
     * @dev Wrap STETH to WSTETH.
     */
    function wrap() external onlyRebalancer {
        uint256 stEthAmount_ = IERC20(STETH).balanceOf(address(this));
        IERC20(STETH).safeIncreaseAllowance(WSTETH, stEthAmount_);
        uint256 wstETHAmount_ = IWstETH(WSTETH).wrap(stEthAmount_);

        emit Wrap(stEthAmount_, wstETHAmount_);
    }

    /**
     * @dev Unwrap WSTETH to STETH.
     */
    function unwrap() external onlyRebalancer {
        uint256 wstETHAmount_ = IERC20(WSTETH).balanceOf(address(this));
        uint256 stEthAmount_ = IWstETH(WSTETH).unwrap(wstETHAmount_);

        emit Unwrap(wstETHAmount_, stEthAmount_);
    }

    function mint(INonfungiblePositionManager.MintParams calldata _params)
        external
        onlyRebalancer
        returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_)
    {
        if (tokenId != 0 || _params.recipient != address(this)) revert Errors.UnSupportedOperation();
        if (_params.token0 != WSTETH || _params.token1 != WETH) revert Errors.InvalidToken();
        IERC20(WSTETH).safeIncreaseAllowance(UNI_V3_POS_MANAGER, _params.amount0Desired);
        IERC20(WETH).safeIncreaseAllowance(UNI_V3_POS_MANAGER, _params.amount1Desired);
        (tokenId_, liquidity_, amount0_, amount1_) = INonfungiblePositionManager(UNI_V3_POS_MANAGER).mint(_params);
        tokenId = tokenId_;

        emit Mint(tokenId_, liquidity_, amount0_, amount1_);
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata _params)
        external
        onlyRebalancer
        returns (uint128 liquidity_, uint256 amount0_, uint256 amount1_)
    {
        if (_params.tokenId != tokenId) revert Errors.InvalidTokenId();
        IERC20(WSTETH).safeIncreaseAllowance(UNI_V3_POS_MANAGER, _params.amount0Desired);
        IERC20(WETH).safeIncreaseAllowance(UNI_V3_POS_MANAGER, _params.amount1Desired);
        (liquidity_, amount0_, amount1_) = INonfungiblePositionManager(UNI_V3_POS_MANAGER).increaseLiquidity(_params);

        emit IncreaseLiquidity(liquidity_, amount0_, amount1_);
    }

    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata _params)
        external
        onlyRebalancer
        returns (uint256 amount0_, uint256 amount1_)
    {
        if (_params.tokenId != tokenId) revert Errors.InvalidTokenId();
        (amount0_, amount1_) = INonfungiblePositionManager(UNI_V3_POS_MANAGER).decreaseLiquidity(_params);

        INonfungiblePositionManager(UNI_V3_POS_MANAGER).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: uint128(amount0_),
                amount1Max: uint128(amount1_)
            })
        );

        emit DecreaseLiquidity(_params.liquidity, amount0_, amount1_);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata _params)
        external
        onlyRebalancer
        returns (uint256 amount0_, uint256 amount1_)
    {
        if (_params.tokenId != tokenId) revert Errors.InvalidTokenId();
        (amount0_, amount1_) = INonfungiblePositionManager(UNI_V3_POS_MANAGER).collect(_params);

        emit Collect(amount0_, amount1_);
    }

    function burn() external onlyRebalancer {
        if (tokenId == 0) revert Errors.UnSupportedOperation();
        (,,,,,,, uint128 liquidity_,,,,) = INonfungiblePositionManager(UNI_V3_POS_MANAGER).positions(tokenId);
        if (liquidity_ != 0) revert Errors.IncorrectState();
        INonfungiblePositionManager(UNI_V3_POS_MANAGER).burn(tokenId);
        tokenId = 0;

        emit Burn(tokenId);
    }

    function getPosition()
        public
        view
        returns (
            uint96 nonce_,
            address operator_,
            address token0_,
            address token1_,
            uint24 fee_,
            int24 tickLower_,
            int24 tickUpper_,
            uint128 liquidity_,
            uint256 feeGrowthInside0LastX128_,
            uint256 feeGrowthInside1LastX128_,
            uint128 tokensOwed0_,
            uint128 tokensOwed1_
        )
    {
        if (tokenId != 0) {
            return INonfungiblePositionManager(UNI_V3_POS_MANAGER).positions(tokenId);
        }
    }

    function getPositionAmounts() public view returns (uint256 amount0_, uint256 amount1_) {
        if (tokenId == 0) {
            return (0, 0);
        }
        int256 amount0Int_;
        int256 amount1Int_;
        (,,,,, int24 tickLower_, int24 tickUpper_, uint128 liquidity_,,,,) =
            INonfungiblePositionManager(UNI_V3_POS_MANAGER).positions(tokenId);
        (uint160 sqrtPriceX96_, int24 currentTick_,,,,,) = IUniswapV3PoolState(UNI_V3_POOL).slot0();

        int128 liquidityDelta = -int128(liquidity_);
        if (currentTick_ < tickLower_) {
            amount0Int_ = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(tickLower_), TickMath.getSqrtRatioAtTick(tickUpper_), liquidityDelta
            );
        } else if (currentTick_ < tickUpper_) {
            amount0Int_ =
                SqrtPriceMath.getAmount0Delta(sqrtPriceX96_, TickMath.getSqrtRatioAtTick(tickUpper_), liquidityDelta);
            amount1Int_ =
                SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(tickLower_), sqrtPriceX96_, liquidityDelta);
        } else {
            amount1Int_ = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower_), TickMath.getSqrtRatioAtTick(tickUpper_), liquidityDelta
            );
        }
        if (amount0Int_ > 0 || amount1Int_ > 0) revert Errors.IncorrectState();
        assembly {
            amount0_ := sub(0, amount0Int_)
            amount1_ := sub(0, amount1Int_)
        }
    }

    /**
     * @dev Get the amount of net assets in the protocol.
     * @return net_ The amount of net assets.
     */
    function getProtocolNetAssets() public returns (uint256 net_) {
        if (tokenId != 0) {
            INonfungiblePositionManager(UNI_V3_POS_MANAGER).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }
        (uint256 amount0_, uint256 amount1_) = getPositionAmounts();
        net_ = IWstETH(WSTETH).getStETHByWstETH(amount0_) + amount1_;
    }

    /**
     * @dev Get the amount of assets in all lending protocols involved in this contract for the strategy pool.
     * @return netAssets The total amount of net assets.
     */
    function getNetAssets() public returns (uint256) {
        uint256 wstETHAmount_ = IWstETH(WSTETH).balanceOf(address(this));
        return getProtocolNetAssets() + IWstETH(WSTETH).getStETHByWstETH(wstETHAmount_) + getTotalETHBalance();
    }

    function getLastNetAssets() public view returns (uint256) {
        (uint256 amount0_, uint256 amount1_) = getPositionAmounts();
        uint256 netWstEth_ = amount0_ + IWstETH(WSTETH).balanceOf(address(this));
        return IWstETH(WSTETH).getStETHByWstETH(netWstEth_) + amount1_ + getTotalETHBalance();
    }

    receive() external payable {}
}
