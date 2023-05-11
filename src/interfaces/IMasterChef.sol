// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface IMasterChef {
    function addRewardToPool(uint256 poolId, uint256 amount) external;

    function withdraw(address to, uint256 _pid, uint256 _amount) external;

    function deposit(address to, uint256 _pid, uint256 _amount) external;

    function totalStake(uint256 _pid) external returns (uint256 stakeAmount);

    function userPendingReward(address user) external returns (uint256 pendingReward);
}
