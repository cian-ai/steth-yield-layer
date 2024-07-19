// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./AaveLikeAdapter.sol";

contract SparkLendingAdapter is AaveLikeAdapter {
    constructor() AaveLikeAdapter("cian.hedge.stable.lending.spark") {}
}
