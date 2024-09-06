// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICometRewards {
    struct RewardOwed {
        address token;
        uint256 owed;
    }

    function claim(address comet, address src, bool shouldAccrue) external;

    function claimTo(address comet, address src, address to, bool shouldAccrue) external;

    function getRewardOwed(address comet, address account) external returns (RewardOwed memory);

    function governor() external view returns (address);

    function rewardConfig(address) external view returns (address token, uint64 rescaleFactor, bool shouldUpscale);

    function rewardsClaimed(address, address) external view returns (uint256);

    function setRewardConfig(address comet, address token) external;

    function transferGovernor(address newGovernor) external;

    function withdrawToken(address token, address to, uint256 amount) external;
}
