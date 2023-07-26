// SPDX-License-Identifier: UNLICENSED

// Cauldron

//    (                (   (
//    )\      )    (   )\  )\ )  (
//  (((_)  ( /(   ))\ ((_)(()/(  )(    (    (
//  )\___  )(_)) /((_) _   ((_))(()\   )\   )\ )
// ((/ __|((_)_ (_))( | |  _| |  ((_) ((_) _(_/(
//  | (__ / _` || || || |/ _` | | '_|/ _ \| ' \))
//   \___|\__,_| \_,_||_|\__,_| |_|  \___/|_||_|

pragma solidity >=0.8.0;
import "./CauldronV4.sol";
import "libraries/MuxLib.sol";

// solhint-disable avoid-low-level-calls
// solhint-disable no-inline-assembly

/// @title Cauldron
/// @dev This contract allows contract calls to any contract (except BentoBox)
/// from arbitrary callers thus, don't trust calls from this contract in any circumstances.
contract MuxCauldron is CauldronV4 {
    address public immutable rewardRouter;
    address public immutable baseContract;
    uint256 public rewardPershare;
    mapping(address => uint256) public userRwardDebt;

    error InsufficientStakeBalance();

    constructor(
        IBentoBoxV1 bentoBox_,
        IERC20 magicInternetMoney_,
        address distributeTo_,
        address _arvinDegenNftAddress,
        address _rewardRouter,
        address _baseContract
    ) CauldronV4(bentoBox_, magicInternetMoney_, distributeTo_, _arvinDegenNftAddress) {
        baseContract = _baseContract;
        rewardRouter = _rewardRouter;
        blacklistedCallees[_rewardRouter] = true;
        blacklistedCallees[address(collateral)] = true;
    }

    function init(bytes memory data) public payable virtual override {
        address(baseContract).delegatecall(abi.encodeWithSelector(IMasterContract.init.selector, data));
        blacklistedCallees[address(rewardRouter)] = true;
        collateral.approve(address(bentoBox), type(uint256).max);
        blacklistedCallees[address(collateral)] = true;
    }

    function _beforeAddCollateral(address user, uint256) internal virtual override {
        _harvest(user);
    }

    function _beforeRemoveCollateral(address from, address, uint256 collateralShare) internal virtual override {
        _harvest(from);
        _unstake(collateralShare);
    }

    function _afterAddCollateral(address user, uint256 collateralShare) internal virtual override {
        _stake(user, collateralShare);
        _updateUserDebt(user);
    }

    function _afterRemoveCollateral(address from, address, uint256 collateralShare) internal virtual override {
        _updateUserDebt(from);
    }

    function _beforeUserLiquidated(address user, uint256, uint256, uint256 collateralShare) internal virtual override {
        _harvest(user);
        _unstake(collateralShare);
    }

    function _afterUserLiquidated(address user, uint256 collateralShare) internal virtual override {
        _updateUserDebt(user);
    }

    function withdrawToken(address token) external {
        if (msg.sender != owner) revert CallerIsNotTheOwner();
        if (token == address(collateral)) return;
        IStrictERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function pendingReward(address user) external view returns (uint256) {
        return (userCollateralShare[user] * rewardPershare) / 1e20 - userRwardDebt[user];
    }

    function claim() external {
        address user = msg.sender;
        uint256 ucs = userCollateralShare[user];
        if (ucs == 0) return;
        _harvest(user);
        _updateUserDebt(user);
    }

    function _updateUserDebt(address user) private {
        userRwardDebt[user] = (userCollateralShare[user] * rewardPershare) / 1e20;
    }

    function _stake(address user, uint256 collateralShare) private {
        MuxLib.stake(bentoBox, collateral, rewardRouter, collateralShare);
    }

    function _unstake(uint256 collateralShare) private {
        MuxLib.unstake(bentoBox, collateral, rewardRouter, collateralShare);
    }

    function _harvest(address user) private {
        rewardPershare = MuxLib.harvest(
            rewardRouter,
            user,
            userCollateralShare[user],
            userRwardDebt[user],
            rewardPershare,
            totalCollateralShare
        );
    }

    receive() external payable {}
}
