// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

library Errors {
    // Revert Errors:
    error CallerNotOperator(); // 0xa5523ee5
    error CallerNotRebalancer(); // 0xbd72e291
    error CallerNotVault(); // 0xedd7338f
    error ExitFeeRateTooHigh(); // 0xf4d1caab
    error FlashloanInProgress(); // 0x772ac4e8
    error IncorrectState(); // 0x508c9390
    error InfoExpired(); // 0x4ddf4a65
    error InvalidAccount(); // 0x6d187b28
    error InvalidAdapter(); // 0xfbf66df1
    error InvalidAdmin(); // 0xb5eba9f0
    error InvalidAsset(); // 0xc891add2
    error InvalidCaller(); // 0x48f5c3ed
    error InvalidClaimTime(); // 0x1221b97b
    error InvalidFeeReceiver(); // 0xd200485c
    error InvalidFlashloanCall(); // 0xd2208d52
    error InvalidFlashloanHelper(); // 0x8690f016
    error InvalidFlashloanProvider(); // 0xb6b48551
    error InvalidGasLimit(); // 0x98bdb2e0
    error InvalidInitiator(); // 0xbfda1f28
    error InvalidLength(); // 0x947d5a84
    error InvalidLimit(); // 0xe55fb509
    error InvalidManagementFeeClaimPeriod(); // 0x4022e4f6
    error InvalidManagementFeeRate(); // 0x09aa66eb
    error InvalidMarketCapacity(); // 0xc9034604
    error InvalidNetAssets(); // 0x6da79d69
    error InvalidNewOperator(); // 0xba0cdec5
    error InvalidOperator(); // 0xccea9e6f
    error InvalidRebalancer(); // 0xff288a8e
    error InvalidRedeemOperator(); // 0xd214a597
    error InvalidSafeProtocolRatio(); // 0x7c6b23d6
    error InvalidShares(); // 0x6edcc523
    error InvalidTarget(); // 0x82d5d76a
    error InvalidToken(); // 0xc1ab6dc1
    error InvalidTokenId(); // 0x3f6cc768
    error InvalidUnderlyingToken(); // 0x2fb86f96
    error InvalidVault(); // 0xd03a6320
    error InvalidWithdrawalUser(); // 0x36c17319
    error ManagementFeeRateTooHigh(); // 0x09aa66eb
    error ManagementFeeClaimPeriodTooShort(); // 0x4022e4f6
    error MarketCapacityTooLow(); // 0xc9034604
    error NotSupportedYet(); // 0xfb89ba2a
    error PriceNotUpdated(); // 0x1f4bcb2b
    error PriceUpdatePeriodTooLong(); // 0xe88d3ecb
    error RatioOutOfRange(); // 0x9179cbfa
    error RevenueFeeRateTooHigh(); // 0x0674143f
    error UnSupportedOperation(); // 0xe9ec8129
    error UnsupportedToken(); // 0x6a172882
    error WithdrawZero(); // 0x7ea773a9

    // for 1inch swap
    error OneInchInvalidReceiver(); // 0xd540519e
    error OneInchInvalidToken(); // 0x8e7ad912
    error OneInchInvalidInputAmount(); // 0x672b500f
    error OneInchInvalidFunctionSignature(); // 0x247f51aa
    error OneInchUnexpectedSpentAmount(); // 0x295ada05
    error OneInchUnexpectedReturnAmount(); // 0x05e64ca8
    error OneInchNotSupported(); // 0x04b2de78
}
