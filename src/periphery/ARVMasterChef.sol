// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "OpenZeppelin/access/Ownable.sol";
import "OpenZeppelin/utils/math/SafeMath.sol";
import "OpenZeppelin/utils/math/Math.sol";
import "../interfaces/ICauldronV4.sol";

// MasterChef is the master of Cake. He can make Cake and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CAKE is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract ARVMasterChef is Ownable {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
    struct LockDetail {
        uint256 lockAmount;
        uint256 unlockAmount;
        uint256 unlockTimestamp;
    }

    uint256 public lastRewardTimestamp;
    uint256 public lastRelease;
    uint256 rewardPerSecond = uint256(100 ether) / 1 days;
    uint256 rewardPerShare = 0;

    IStrictERC20 public arv;
    IStrictERC20 public vin;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    mapping(address => LockDetail[]) public userLock;
    mapping(address => uint256) public userUnlockIndex;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _arv, address _vin) {
        arv = IStrictERC20(_arv);
        vin = IStrictERC20(_vin);
        lastRewardTimestamp = block.timestamp - (block.timestamp % 1 days) + 1 days;
        lastRelease = block.timestamp - (block.timestamp % 1 days) + 1 days;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending CAKEs on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 lpSupply = vin.balanceOf(address(this));
        uint256 rps = rewardPerShare;
        if (block.timestamp > lastRewardTimestamp && lpSupply != 0) {
            uint256 lrt = lastRewardTimestamp;
            for (uint i = lastRelease; i < block.timestamp; ) {
                i += 1 days;
                uint256 timestamp = Math.min(block.timestamp, i);
                if (timestamp < block.timestamp) {
                    rps = (rewardPerSecond * 999) / 1000;
                }
                uint256 multiplier = getMultiplier(lrt, timestamp);
                uint256 reward = multiplier.mul(rewardPerSecond);
                rps = rps.add(reward.mul(1e20).div(lpSupply));
                lrt = timestamp;
            }
        }
        return user.amount.mul(rps).div(1e20).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function update() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = vin.balanceOf(address(this));
        if (lpSupply == 0) {
            return;
        }
        for (uint i = lastRelease; i <= block.timestamp; ) {
            i += 1 days;
            uint256 timestamp = Math.min(block.timestamp, i);
            if (i < block.timestamp) {
                lastRelease = i;
                rewardPerSecond = (rewardPerSecond * 999) / 1000;
            }
            uint256 multiplier = getMultiplier(lastRewardTimestamp, timestamp);
            uint256 reward = multiplier.mul(rewardPerSecond);
            rewardPerShare = rewardPerShare.add(reward.mul(1e20).div(lpSupply));
            lastRewardTimestamp = timestamp;
        }
    }

    function deposit(uint256 _amount) public {
        address to = msg.sender;
        UserInfo storage user = userInfo[to];
        update();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(rewardPerShare).div(1e20).sub(user.rewardDebt);
            if (pending > 0) {
                arv.transfer(to, pending);
            }
        }
        if (_amount > 0) {
            userLock[to].push(LockDetail({lockAmount: _amount, unlockAmount: 0, unlockTimestamp: block.timestamp + 21 days}));
            vin.transferFrom(address(to), address(this), _amount);
            user.amount = user.amount.add(_amount);
            emit Deposit(msg.sender, _amount);
        }
        user.rewardDebt = user.amount.mul(rewardPerShare).div(1e20);
    }

    function withdraw(uint256 _amount) public {
        address to = msg.sender;
        UserInfo storage user = userInfo[to];
        require(user.amount >= _amount, "withdraw: not good");
        update();
        uint256 pending = user.amount.mul(rewardPerShare).div(1e20).sub(user.rewardDebt);
        if (pending > 0) {
            arv.transfer(to, pending);
        }
        if (_amount > 0) {
            uint256 epoch = block.timestamp;
            require(getUnlockableAmount(to, epoch) >= _amount, "no enough unlockable");
            uint256 unlockAmountLeft = _amount;
            uint256 i = 0;
            uint256 unlockIndex = userUnlockIndex[to];
            LockDetail[] storage details = userLock[to];
            for (i = unlockIndex; i < details.length && unlockAmountLeft > 0; i++) {
                LockDetail storage detail = userLock[to][i];
                if (detail.unlockTimestamp <= epoch) {
                    uint256 unlockableAmount = detail.lockAmount - detail.unlockAmount;
                    if (unlockableAmount <= unlockAmountLeft) {
                        unlockAmountLeft -= unlockableAmount;
                        detail.unlockAmount = detail.lockAmount;
                    } else {
                        detail.unlockAmount += unlockAmountLeft;
                        unlockAmountLeft = 0;
                        break;
                    }
                }
            }
            userUnlockIndex[to] = i;
            user.amount = user.amount.sub(_amount);
            vin.transfer(to, _amount);
            emit Withdraw(to, _amount);
        }
        user.rewardDebt = user.amount.mul(rewardPerShare).div(1e20);
    }

    function claimPending() public {
        address to = msg.sender;
        UserInfo storage user = userInfo[to];
        update();
        uint256 pending = user.amount.mul(rewardPerShare).div(1e20).sub(user.rewardDebt);
        user.rewardDebt = user.amount.mul(rewardPerShare).div(1e20);
        if (pending > 0) {
            arv.transfer(to, pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        vin.transfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function getLockInfo(address user) external view returns (LockDetail[] memory locks) {
        uint256 unlockCount = userLock[user].length - userUnlockIndex[user];
        locks = new LockDetail[](unlockCount);
        for (uint256 i = 0; i < unlockCount; i++) {
            locks[i] = (userLock[user][i + userUnlockIndex[user]]);
        }
    }

    function getUnlockableAmount(address user, uint256 epoch) public view returns (uint256 amount) {
        LockDetail[] memory details = userLock[user];
        uint256 unlockIndex = userUnlockIndex[user];
        for (uint256 i = unlockIndex; i < details.length; i++) {
            if (details[i].unlockTimestamp <= epoch) {
                amount += details[i].lockAmount - details[i].unlockAmount;
            } else {
                break;
            }
        }
    }
}
