// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IRedeemOperator.sol";
import "../interfaces/IVault.sol";
import "./libraries/Errors.sol";
import "./common/Constants.sol";

/**
 * @title RedeemOperator contract
 * @author Naturelab
 * @notice Manages temporary storage of share tokens and facilitates redemption operations.
 * @dev Implements the IRedeemOperator interface and uses OpenZeppelin libraries for safety and utility functions.
 */
contract RedeemOperator is IRedeemOperator, Constants, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_GAS_LIMIT = 300_000_000;

    // Address of the vault contract (immutable)
    address public immutable vault;

    // Address of the operator managing withdrawals
    address public operator;

    // Address to receive fees
    address public feeReceiver;

    // Mapping to track withdrawal requests
    mapping(address => uint256) private _withdrawalSTETHRequest;

    // Mapping to track withdrawal requests
    mapping(address => uint256) private _withdrawalEETHRequest;

    // Set to keep track of pending withdrawers
    EnumerableSet.AddressSet private _pendingSTETHWithdrawers;

    // Set to keep track of pending withdrawers
    EnumerableSet.AddressSet private _pendingEETHWithdrawers;

    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.CallerNotVault();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert Errors.CallerNotOperator();
        _;
    }

    /**
     * @dev Initializes the contract with the vault, operator, fee receiver, and gas parameters.
     * @param _vault Address of the vault contract.
     * @param _operator Address of the operator.
     * @param _feeReceiver Address to receive fees.
     */
    constructor(address _admin, address _vault, address _operator, address _feeReceiver) Ownable(_admin) {
        if (_vault == address(0)) revert Errors.InvalidVault();
        if (_operator == address(0)) revert Errors.InvalidNewOperator();
        if (_feeReceiver == address(0)) revert Errors.InvalidFeeReceiver();
        vault = _vault;
        operator = _operator;
        feeReceiver = _feeReceiver;
    }

    /**
     * @dev Updates the operator address.
     * @param _newOperator New operator address.
     */
    function updateOperator(address _newOperator) external onlyOwner {
        if (_newOperator == address(0)) revert Errors.InvalidNewOperator();
        emit UpdateOperator(operator, _newOperator);
        operator = _newOperator;
    }

    /**
     * @dev Update the address of the recipient for management fees.
     * @param _newFeeReceiver The new address of the recipient for management fees.
     */
    function updateFeeReceiver(address _newFeeReceiver) external onlyOwner {
        if (_newFeeReceiver == address(0)) revert Errors.InvalidFeeReceiver();
        emit UpdateFeeReceiver(feeReceiver, _newFeeReceiver);
        feeReceiver = _newFeeReceiver;
    }

    /**
     * @dev Registers a withdrawal request for a user.
     * @param _user Address of the user requesting withdrawal.
     * @param _shares Amount of shares to withdraw.
     * @param _token Address of the token to withdraw.
     */
    function registerWithdrawal(address _user, uint256 _shares, address _token) external onlyVault {
        if (_shares == 0) revert Errors.InvalidShares();
        if (_token == STETH) {
            // Handle existing pending withdrawal
            if (_pendingSTETHWithdrawers.contains(_user)) {
                revert Errors.IncorrectState();
            } else {
                // Register new withdrawal request
                _pendingSTETHWithdrawers.add(_user);
                _withdrawalSTETHRequest[_user] = _shares;
            }
        } else if (_token == EETH) {
            // Handle existing pending withdrawal
            if (_pendingEETHWithdrawers.contains(_user)) {
                revert Errors.IncorrectState();
            } else {
                // Register new withdrawal request
                _pendingEETHWithdrawers.add(_user);
                _withdrawalEETHRequest[_user] = _shares;
            }
        } else {
            revert Errors.UnsupportedToken();
        }

        emit RegisterWithdrawal(_user, _shares);
    }

    /**
     * @dev Returns the withdrawal request details for a user.
     * @param _user Address of the user.
     * @return WithdrawalRequest struct containing the token address and shares amount.
     */
    function withdrawalRequest(address _user) external view returns (uint256, uint256) {
        return (_withdrawalSTETHRequest[_user], _withdrawalEETHRequest[_user]);
    }

    /**
     * @dev Returns the withdrawal request details for multiple users.
     * @param _users Array of user addresses.
     * @return stETHshares_ Array of shares requested for stETH withdrawal.
     * @return eETHshares_ Array of shares requested for eETH withdrawal.
     */
    function withdrawalRequests(address[] calldata _users)
        external
        view
        returns (uint256[] memory stETHshares_, uint256[] memory eETHshares_)
    {
        uint256 count_ = _users.length;
        if (count_ == 0) revert Errors.InvalidLength();

        stETHshares_ = new uint256[](count_);
        eETHshares_ = new uint256[](count_);
        for (uint256 i = 0; i < count_; ++i) {
            stETHshares_[i] = _withdrawalSTETHRequest[_users[i]];
            eETHshares_[i] = _withdrawalEETHRequest[_users[i]];
        }
    }

    /**
     * @dev Returns the number of pending withdrawers.
     * @return Number of pending withdrawers.
     */
    function pendingWithdrawersCount() external view returns (uint256, uint256) {
        return (_pendingSTETHWithdrawers.length(), _pendingEETHWithdrawers.length());
    }

    /**
     * @dev Returns a paginated list of pending withdrawers.
     * @param _limit Maximum number of addresses to return.
     * @param _offset Offset for pagination.
     * @return result_ Array of addresses of pending withdrawers.
     */
    function pendingWithdrawers(uint256 _limit, uint256 _offset, address _token)
        external
        view
        returns (address[] memory result_)
    {
        EnumerableSet.AddressSet storage withdrawers_;
        if (_token == STETH) {
            withdrawers_ = _pendingSTETHWithdrawers;
        } else if (_token == EETH) {
            withdrawers_ = _pendingEETHWithdrawers;
        } else {
            revert Errors.UnsupportedToken();
        }
        uint256 count_ = withdrawers_.length();
        if (_offset >= count_ || _limit == 0) return result_;

        count_ -= _offset;
        if (count_ > _limit) count_ = _limit;

        result_ = new address[](count_);
        for (uint256 i = 0; i < count_; ++i) {
            result_[i] = withdrawers_.at(_offset + i);
        }
        return result_;
    }

    /**
     * @dev Returns the list of all pending withdrawers.
     * @return Array of addresses of all pending withdrawers.
     */
    function allPendingWithdrawers() external view returns (address[] memory, address[] memory) {
        return (_pendingSTETHWithdrawers.values(), _pendingEETHWithdrawers.values());
    }

    function confirmWithdrawal(address[] calldata _stEthUsers, address[] calldata _eEthUsers, uint256 _totalGasLimit)
        external
        onlyOperator
    {
        if (_totalGasLimit > MAX_GAS_LIMIT) revert Errors.InvalidGasLimit();
        uint256 getStEthShares_ = _getTotalShares(_stEthUsers, _pendingSTETHWithdrawers, _withdrawalSTETHRequest);
        uint256 getEEthShares_ = _getTotalShares(_eEthUsers, _pendingEETHWithdrawers, _withdrawalEETHRequest);
        uint256 totalShares_ = getStEthShares_ + getEEthShares_;
        uint256 exchangePrice_ = IVault(vault).exchangePrice();
        uint256 lastExchangePrice = IVault(vault).lastExchangePrice();
        if (lastExchangePrice == 0) revert Errors.UnSupportedOperation();
        uint256 cutPercentage_;
        if (exchangePrice_ < lastExchangePrice) {
            uint256 diff_ = (lastExchangePrice - exchangePrice_).mulDiv(
                (IERC20(vault).totalSupply() - totalShares_), PRECISION, Math.Rounding.Ceil
            );
            cutPercentage_ = diff_.mulDiv(PRECISION * PRECISION, totalShares_ * exchangePrice_, Math.Rounding.Ceil);
        }
        uint256 gasPerUser_ = _totalGasLimit * tx.gasprice / (_stEthUsers.length + _eEthUsers.length);
        if (getStEthShares_ != 0) {
            _confirmWithdrawal(
                _stEthUsers,
                STETH,
                getStEthShares_,
                gasPerUser_,
                cutPercentage_,
                _withdrawalSTETHRequest,
                _pendingSTETHWithdrawers
            );
            emit ConfirmWithdrawalSTETH(_stEthUsers);
        }
        if (getEEthShares_ != 0) {
            _confirmWithdrawal(
                _eEthUsers,
                EETH,
                getEEthShares_,
                gasPerUser_,
                cutPercentage_,
                _withdrawalEETHRequest,
                _pendingEETHWithdrawers
            );
            emit ConfirmWithdrawalEETH(_eEthUsers);
        }
    }

    function _getTotalShares(
        address[] calldata _users,
        EnumerableSet.AddressSet storage _pendingWithdrawers,
        mapping(address => uint256) storage _withdrawalRequest
    ) internal view returns (uint256 totalShares_) {
        if (_users.length == 0) return 0;
        for (uint256 i = 0; i < _users.length; ++i) {
            if (!_pendingWithdrawers.contains(_users[i])) revert Errors.InvalidWithdrawalUser();
            totalShares_ += _withdrawalRequest[_users[i]];
        }
    }

    /**
     * @dev Confirms withdrawals for a list of users.
     * @param _users Array of user addresses to confirm withdrawals for.
     */
    function _confirmWithdrawal(
        address[] calldata _users,
        address _token,
        uint256 _totalShares,
        uint256 _gasPerUser,
        uint256 _cutPercentage,
        mapping(address => uint256) storage _withdrawalRequest,
        EnumerableSet.AddressSet storage _pendingWithdrawers
    ) internal {
        uint256 tokenBalanceBefore_ = IERC20(_token).balanceOf(address(this));
        IVault(vault).optionalRedeem(_token, _totalShares, _cutPercentage, address(this), address(this));
        uint256 tokenBalanceGet_ = IERC20(_token).balanceOf(address(this)) - tokenBalanceBefore_;
        uint256 assetPerShare_ = tokenBalanceGet_.mulDiv(PRECISION, _totalShares, Math.Rounding.Floor);
        address thisUser_;
        uint256 thisUserGet_;
        for (uint256 i = 0; i < _users.length; ++i) {
            thisUser_ = _users[i];
            thisUserGet_ = _withdrawalRequest[thisUser_].mulDiv(assetPerShare_, PRECISION, Math.Rounding.Floor);
            // If the user's share is not enough to cover the gas, it will fail.
            IERC20(_token).safeTransfer(thisUser_, thisUserGet_ - _gasPerUser);
            _pendingWithdrawers.remove(thisUser_);
            delete _withdrawalRequest[thisUser_];
        }
        uint256 totalGas_ = _gasPerUser * _users.length;
        IERC20(_token).safeTransfer(feeReceiver, totalGas_);
    }

    /**
     * @dev Handles accidental transfers of tokens or ETH to this contract.
     * @param _token Address of the token to sweep.
     */
    function sweep(address _token) external onlyOwner {
        uint256 amount_ = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount_);

        uint256 ethbalance_ = address(this).balance;
        if (ethbalance_ > 0) {
            Address.sendValue(payable(msg.sender), ethbalance_);
        }

        emit Sweep(_token);
    }
}
