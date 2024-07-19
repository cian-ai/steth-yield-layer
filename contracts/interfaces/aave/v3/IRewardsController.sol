// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRewardsController {
    function getAllUserRewards(address[] calldata assets, address user)
        external
        view
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);

    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimAllRewardsToSelf(address[] calldata assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        returns (uint256);
}
