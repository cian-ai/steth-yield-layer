// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../../interfaces/aave/v3/IPoolV3.sol";
import "../../../../interfaces/lending/ILendingAdapter.sol";
import "../../../libraries/Errors.sol";

abstract contract AaveLikeAdapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    bytes32 public immutable STORAGE_SLOT;

    struct AaveLendingAdapterStorage {
        IPoolV3 pool;
    }

    constructor(bytes memory _adapterId) {
        STORAGE_SLOT = keccak256(_adapterId);
    }

    function init(address _poolAddr) external {
        getStorage().pool = IPoolV3(_poolAddr);
    }

    function _getAToken(address token) internal view returns (address) {
        return getStorage().pool.getReserveData(token).aTokenAddress;
    }

    function _getDToken(address token) internal view returns (address) {
        return getStorage().pool.getReserveData(token).variableDebtTokenAddress;
    }

    function getStorage() internal view returns (AaveLendingAdapterStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    function depositOf(address token) external view override returns (uint256) {
        address _depositToken = _getAToken(token);
        if (_depositToken == address(0)) return 0;
        return IERC20(_depositToken).balanceOf(address(this));
    }

    function debtOf(address token) external view override returns (uint256) {
        address _debtToken = _getDToken(token);
        if (_debtToken == address(0)) return 0;
        return IERC20(_debtToken).balanceOf(address(this));
    }

    function deposit(address token, uint256 amount) external override {
        IERC20(token).safeIncreaseAllowance(address(getStorage().pool), amount);
        getStorage().pool.deposit(token, amount, address(this), 0);
        // Call enableCollateral to enable collateral
        getStorage().pool.setUserUseReserveAsCollateral(token, true);
    }

    function withdraw(address token, uint256 amount) external override {
        getStorage().pool.withdraw(token, amount, address(this));
    }

    function borrow(address token, uint256 amount) external override {
        getStorage().pool.borrow(token, amount, 2, 0, address(this));
    }

    function repay(address token, uint256 amount) external override {
        // Approve token to pool
        IERC20(token).safeIncreaseAllowance(address(getStorage().pool), amount);
        getStorage().pool.repay(token, amount, 2, address(this));
    }
}
