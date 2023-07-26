pragma solidity >=0.8.0;
import "interfaces/IMuxRewardRouter.sol";
import "interfaces/IBentoBoxV1.sol";

library MuxLib {
    function unstake(IBentoBoxV1 bentoBox, IERC20 collateral, address rewardRouter, uint256 collateralShare) external {
        uint256 amount = bentoBox.toAmount(collateral, collateralShare, false);
        bentoBox.deposit(collateral, address(this), address(this), 0, collateralShare);
    }

    function stake(IBentoBoxV1 bentoBox, IERC20 collateral, address rewardRouter, uint256 collateralShare) external {
        (uint256 amount, ) = bentoBox.withdraw(collateral, address(this), address(this), 0, collateralShare);
    }

    function harvest(
        address rewardRouter,
        address user,
        uint256 userCollateralShare,
        uint256 userRwardDebt,
        uint256 rewardPershare,
        uint256 totalCollateralShare
    ) external returns (uint256) {
        uint256 lastBalance = address(this).balance;
        IMuxRewardRouter(rewardRouter).claimAllUnwrap();
        uint256 tcs = totalCollateralShare;
        if (tcs > 0) {
            rewardPershare += ((address(this).balance - lastBalance) * 1e20) / tcs;
        }
        uint256 last = userRwardDebt;
        uint256 curr = (userCollateralShare * rewardPershare) / 1e20;

        if (curr > last) {
            payable(user).call{value: curr - last, gas: 21000}("");
        }
        return rewardPershare;
    }
}
