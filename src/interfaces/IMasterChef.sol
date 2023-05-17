// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface IMasterChef {
    struct LockDetail {
        uint256 lockAmount;
        uint256 unlockAmount;
        uint256 unlockTimestamp;
    }

    // Info of each user.
    struct VestingInfo {
        uint256 vestingReward;
        uint256 claimTime;
        bool isClaimed;
    }

    function addRewardToPool(uint256 poolId, uint256 amount) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function deposit(address to) external;

    function depositLock(uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function withdraw(address to) external;

    function withdrawLock(uint256 _amount) external;

    function totalStake(uint256 _pid) external returns (uint256 stakeAmount);

    function userPendingReward(address user) external returns (uint256 pendingReward);

    function getLockAmount(address user) external view returns (uint256 amount);

    function getLockInfo(address user) external view returns (LockDetail[] memory locks);

    function getUnlockableAmount(address user) external view returns (uint256 amount);
}
