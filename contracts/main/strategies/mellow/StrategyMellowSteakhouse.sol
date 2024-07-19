// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../interfaces/lido/IWstETH.sol";
import "../../../interfaces/IVault.sol";
import "../../../interfaces/steakhouse/ISteakhouseVault.sol";
import "../../../interfaces/steakhouse/IDepositWrapper.sol";
import "../../libraries/Errors.sol";
import "../../../interfaces/IStrategy.sol";
import "../../common/MultiETH.sol";

/**
 * @title StrategyMellowSteakhouse contract
 * @author Naturelab
 * @dev This contract is the actual address of the strategy pool, which
 * manages some assets in mellow steakhouse
 */
contract StrategyMellowSteakhouse is IStrategy, MultiETH, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // The version of the contract
    string public constant VERSION = "1.0";
    ISteakhouseVault internal constant steakhouse = ISteakhouseVault(0xBEEF69Ac7870777598A04B2bd4771c71212E6aBc);
    IDepositWrapper internal constant steakhouseWrapper = IDepositWrapper(0x24fee15BC11fF617c042283B58A3Bda6441Da145);

    // The underlying core assets.
    address public underlyingToken;
    // The token contract used to record the proportional equity of users.
    address public vault;
    // Position Adjustment Manager
    address public rebalancer;

    event UpdateRebalancer(address oldRebalancer, address newRebalancer);
    event Wrap(uint256 stEthAmount, uint256 wstEthAmount);
    event Unwrap(uint256 wstEthAmount, uint256 stEthAmount);

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

    function initialize(bytes calldata _initBytes) external initializer {
        (address _underlyingToken, address _admin, address _rebalancer) =
            abi.decode(_initBytes, (address, address, address));
        if (_underlyingToken == address(0)) revert Errors.InvalidUnderlyingToken();
        if (_admin == address(0)) revert Errors.InvalidAdmin();
        if (_rebalancer == address(0)) revert Errors.InvalidRebalancer();

        __Ownable_init(_admin);
        underlyingToken = _underlyingToken;
        rebalancer = _rebalancer;
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
        return true;
    }

    /**
     * @dev Transfer tokens to the Vault.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     */
    function transferToVault(address _token, uint256 _amount) external onlyRebalancer {
        IERC20(_token).safeTransfer(vault, _amount);
    }

    function enterProtocol(uint256 _deposit, uint256 _minLpAmount) external onlyRebalancer {
        IERC20(underlyingToken).safeIncreaseAllowance(address(steakhouseWrapper), _deposit);
        steakhouseWrapper.deposit(address(this), underlyingToken, _deposit, _minLpAmount, block.timestamp);
    }

    function exitProtocol(uint256 _lpAmount, uint256 _minAmount, uint256 _deadline, uint256 _requestDeadline)
        external
        onlyRebalancer
    {
        uint256[] memory minAmounts_ = new uint256[](1);
        minAmounts_[0] = _minAmount;
        steakhouse.registerWithdrawal(address(this), _lpAmount, minAmounts_, _deadline, _requestDeadline, true);
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

    function getProtocolPendingAmount() public view returns (uint256) {
        ISteakhouseVault.WithdrawalRequest memory request_ = steakhouse.withdrawalRequest(address(this));
        if (request_.to == address(0)) return 0;
        ISteakhouseVault.ProcessWithdrawalsStack memory s_ = steakhouse.calculateStack();
        uint256[] memory minAmounts_ = new uint256[](1);
        minAmounts_[0] = 0;
        address[] memory tokens = new address[](1);
        tokens[0] = WSTETH;
        (bool processingPossible_, bool withdrawalPossible_, uint256[] memory expectedAmounts) =
            steakhouse.analyzeRequest(s_, request_);
        if (!processingPossible_ || !withdrawalPossible_) revert Errors.IncorrectState();

        return expectedAmounts[0];
    }

    /**
     * @dev Get the amount of net assets in the protocol.
     * @return net_ The amount of net assets.
     */
    function getProtocolNetAssets() public view returns (uint256 net_) {
        uint256 lpAmount_ = steakhouse.balanceOf(address(this));
        uint256 totalLp_ = steakhouse.totalSupply();
        (address[] memory tokens_, uint256[] memory amounts_) = steakhouse.underlyingTvl();
        if (tokens_[0] != WSTETH) revert Errors.IncorrectState();
        uint256 personalAssets_ = lpAmount_ * amounts_[0] / totalLp_;
        net_ = IWstETH(WSTETH).getStETHByWstETH(personalAssets_ + getProtocolPendingAmount());
    }

    function getNetAssets() public view override returns (uint256) {
        uint256 wstETHAmount_ = IWstETH(WSTETH).balanceOf(address(this));
        return getProtocolNetAssets() + IWstETH(WSTETH).getStETHByWstETH(wstETHAmount_) + getTotalETHBalance();
    }
}
