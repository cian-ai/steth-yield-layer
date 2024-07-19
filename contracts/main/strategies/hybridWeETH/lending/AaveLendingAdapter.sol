// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./AaveLikeAdapter.sol";

contract AaveLendingAdapter is AaveLikeAdapter {
    constructor() AaveLikeAdapter("cian.hedge.stable.lending.aave") {}
}
