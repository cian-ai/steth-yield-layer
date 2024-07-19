// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/IRedeemOperator.sol";
import "../../interfaces/IStrategy.sol";
import "../libraries/Errors.sol";

/**
 * @title StrategyFactory contract
 * @author Naturelab
 * @dev This contract is responsible for managing strategies in a vault.
 * It allows the owner to create, remove, and interact with different strategies.
 */
abstract contract StrategyFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_POSITION_LIMIT = 10000; // 10000/10000 = 100%

    // Set to keep track of the addresses of strategies
    EnumerableSet.AddressSet private _strategies;
    // This mapping is used to set position limits for various strategies.
    // The key is the strategy ID, and the value is the maximum percentage of the entire position
    // that the strategy is allowed to occupy. 1000 = 10%
    mapping(address => uint256) public positionLimit;

    // Events for logging actions
    event CreateStrategy(address strategy, address impl);
    event RemoveStrategy(address strategy);
    event UpdateOperator(address oldOperator, address newOperator);
    event UpdateStrategyLimit(uint256 oldLimit, uint256 newLimit);

    /**
     * @dev Returns the number of strategies in the set.
     * @return The number of strategies.
     */
    function strategiesCount() public view returns (uint256) {
        return _strategies.length();
    }

    /**
     * @dev Returns an array of all strategy addresses.
     * @return An array of strategy addresses.
     */
    function strategies() public view returns (address[] memory) {
        return _strategies.values();
    }

    /**
     * @dev Returns the address of a strategy at a specific index.
     * @param _offset The index of the strategy.
     * @return The address of the strategy.
     */
    function strategyAddress(uint256 _offset) public view returns (address) {
        return _strategies.at(_offset);
    }

    /**
     * @dev Returns the total assets managed by a specific strategy.
     * @param _offset The index of the strategy.
     * @return totalAssets_ The total assets managed by the strategy.
     */
    function strategyAssets(uint256 _offset) public returns (uint256 totalAssets_) {
        totalAssets_ = IStrategy(_strategies.at(_offset)).getNetAssets();
    }

    /**
     * @dev Returns the total assets managed by all strategies combined.
     * @return totalAssets_ The total assets managed by all strategies.
     */
    function totalStrategiesAssets() public returns (uint256 totalAssets_) {
        uint256 length_ = strategiesCount();
        address[] memory strategies_ = strategies();
        for (uint256 i = 0; i < length_; ++i) {
            totalAssets_ += IStrategy(strategies_[i]).getNetAssets();
        }
    }

    /**
     * @dev Allows the owner to create a new strategy.
     * @param _impl The implementation address of the strategy.
     * @param _initBytes The initialization parameters for the strategy.
     */
    function createStrategy(address _impl, bytes calldata _initBytes, uint256 _positionLimit) external onlyOwner {
        if (_positionLimit == 0 || _positionLimit > MAX_POSITION_LIMIT) revert Errors.InvalidLimit();
        address newStrategy_ = address(new TransparentUpgradeableProxy(_impl, msg.sender, _initBytes));
        positionLimit[newStrategy_] = _positionLimit;
        _strategies.add(newStrategy_);

        emit CreateStrategy(newStrategy_, _impl);
    }

    /**
     * @dev Allows the owner to remove a strategy from the set.
     * @param _strategy The address of the strategy to be removed.
     */
    function removeStrategy(address _strategy) external onlyOwner {
        if (IStrategy(_strategy).getNetAssets() > 0) revert Errors.UnSupportedOperation();
        _strategies.remove(_strategy);
        positionLimit[_strategy] = 0;

        emit RemoveStrategy(_strategy);
    }

    /**
     * @dev Update the temporary address of shares when users redeem.
     * @param _newPositionLimit The new redeem operator address.
     */
    function updateStrategyLimit(uint256 _offset, uint256 _newPositionLimit) external onlyOwner {
        if (_newPositionLimit == 0 || _newPositionLimit > MAX_POSITION_LIMIT) revert Errors.InvalidLimit();
        address strategyAddress_ = _strategies.at(_offset);
        emit UpdateStrategyLimit(positionLimit[strategyAddress_], _newPositionLimit);
        positionLimit[strategyAddress_] = _newPositionLimit;
    }
}
