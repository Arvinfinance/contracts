// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "BoringSolidity/ERC20.sol";
import "utils/BaseTest.sol";
import "script/VelodromeVolatileOpUsdc.s.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ICauldronV3.sol";
import "interfaces/ISwapperV2.sol";
import "interfaces/ILevSwapperV2.sol";
import "interfaces/IVelodromePairFactory.sol";
import "interfaces/ISolidlyLpWrapper.sol";

contract VelodromeVolatileOpUsdcTest is BaseTest {
    address constant mimWhale = 0x4217AA01360846A849d2A89809d450D10248B513;
    address constant opWhale = 0x2A82Ae142b2e62Cb7D10b55E323ACB1Cab663a26;
    address constant usdcWhale = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;
    address constant rewardDistributor = 0x5d5Bea9f0Fc13d967511668a60a3369fD53F784F;

    event NotifyReward(address indexed from, address indexed reward, uint256 amount);
    event ClaimRewards(address indexed from, address indexed reward, uint256 amount);
    event LpMinted(uint256 total, uint256 strategyAmount, uint256 feeAmount);
    event LogStrategyProfit(address indexed token, uint256 amount);
    event LogStrategyDivest(address indexed token, uint256 amount);
    event LogStrategyQueued(address indexed token, address indexed strategy);

    ICauldronV3 cauldron;
    IBentoBoxV1 degenBox;
    ISwapperV2 swapper;
    ILevSwapperV2 levSwapper;
    SolidlyGaugeVolatileLPStrategy strategy;
    ERC20 veloToken;
    ERC20 opToken;
    ERC20 usdcToken;
    ERC20 mim;
    ISolidlyPair underlyingLp;
    ISolidlyLpWrapper lp;
    ISolidlyGauge gauge;
    IVelodromePairFactory pairFactory;
    ISolidlyRouter router;
    IOracle oracle;
    UniswapLikeLPOracle underlyingLpOracle;
    uint256 fee;

    function setUp() public override {}

    function _setupCommon() public {
        degenBox = IBentoBoxV1(constants.getAddress("optimism.degenBox"));
        gauge = ISolidlyGauge(constants.getAddress("optimism.velodrome.vOpUsdcGauge"));
        pairFactory = IVelodromePairFactory(constants.getAddress("optimism.velodrome.factory"));
        router = ISolidlyRouter(constants.getAddress("optimism.velodrome.router"));
        veloToken = ERC20(constants.getAddress("optimism.velodrome.velo"));

        opToken = ERC20(constants.getAddress("optimism.op"));
        usdcToken = ERC20(constants.getAddress("optimism.usdc"));
        mim = ERC20(constants.getAddress("optimism.mim"));
        fee = pairFactory.volatileFee();

        opToken.approve(address(router), type(uint256).max);
        usdcToken.approve(address(router), type(uint256).max);
    }

    function _setupV1() public {
        forkOptimism(18243290);
        super.setUp();

        VelodromeVolatileOpUsdcScript script = new VelodromeVolatileOpUsdcScript();
        script.setTesting(true);
        (cauldron, swapper, levSwapper, strategy) = script.deploy();

        _setupCommon();
        lp = ISolidlyLpWrapper(address(cauldron.collateral()));
        underlyingLp = ISolidlyPair(address(lp.underlying()));
        underlyingLp.approve(address(lp), type(uint256).max);

        oracle = cauldron.oracle();
        underlyingLpOracle = UniswapLikeLPOracle(
            address(
                ERC20VaultAggregator(address(InverseOracle(address(ProxyOracle(address(oracle)).oracleImplementation())).oracle()))
                    .underlyingOracle()
            )
        );
        _mintLpToDegenBox();
        _activateStrategy();
    }

    function _setupV2() public {
        forkOptimism(73744718);
        super.setUp();

        VelodromeVolatileOpUsdcScript script = new VelodromeVolatileOpUsdcScript();
        script.setTesting(true);
        script.setDeployment(VelodromeVolatileOpUsdcScript_Deployment.VELODROME_SWAPPERS);
        (, swapper, levSwapper, ) = script.deploy();

        lp = ISolidlyLpWrapper(constants.getAddress("optimism.abraWrappedVOpUsdc"));

        _setupCommon();
    }

    function testFarmRewards() public {
        _setupV1();
        uint256 previousAmount = veloToken.balanceOf(address(strategy));
        _distributeRewards();

        vm.startPrank(deployer);
        strategy.safeHarvest(type(uint256).max, false, 0, false);
        vm.stopPrank();

        assertGt(veloToken.balanceOf(address(strategy)), previousAmount, "no velo harvested");
    }

    function testFeeParameters() public {
        _setupV1();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        strategy.setFeeParameters(alice, 15);

        vm.prank(strategy.owner());
        strategy.setFeeParameters(alice, 15);
        assertEq(strategy.feeCollector(), alice);
        assertEq(strategy.feePercent(), 15);
    }

    function testMintLpFromRewardsTakeFees() public {
        _setupV1();
        vm.prank(strategy.owner());
        strategy.setFeeParameters(deployer, 10);

        _distributeRewards();

        vm.startPrank(deployer);
        strategy.safeHarvest(0, false, 0, false);

        uint256 balanceFeeCollector = lp.balanceOf(deployer);
        uint256 balanceStrategy = lp.balanceOf(address(strategy));
        vm.stopPrank();

        _transferRewardsToStrategy(4_000_000 * 1e18);

        vm.expectEmit(false, false, false, false);
        emit LpMinted(0, 0, 0);

        vm.startPrank(deployer);
        strategy.swapToLP(0, fee);

        // Strategy and FeeCollector should now have more LP
        assertGt(lp.balanceOf(deployer), balanceFeeCollector);
        assertGt(lp.balanceOf(address(strategy)), balanceStrategy);
    }

    function testStrategyProfit() public {
        _setupV1();
        uint256 degenBoxBalance = degenBox.totals(lp).elastic;

        vm.prank(deployer);
        strategy.safeHarvest(0, false, 0, false);

        _transferRewardsToStrategy(4_000_000 * 1e18);
        vm.startPrank(deployer);
        strategy.swapToLP(0, fee);

        vm.expectEmit(true, false, false, false);
        emit LogStrategyProfit(address(lp), 0);
        strategy.safeHarvest(0, false, 0, false);

        assertGt(degenBox.totals(lp).elastic, degenBoxBalance);
    }

    function testStrategyDivest() public {
        _setupV1();
        uint256 degenBoxBalance = lp.balanceOf(address(degenBox));

        vm.prank(degenBox.owner());
        degenBox.setStrategyTargetPercentage(lp, 50);

        vm.expectEmit(true, false, false, false);
        emit LogStrategyDivest(address(lp), 0);
        vm.prank(deployer);
        strategy.safeHarvest(0, true, 0, false);

        assertGt(lp.balanceOf(address(degenBox)), degenBoxBalance);
    }

    function testStrategyExit() public {
        _setupV1();
        uint256 degenBoxBalance = lp.balanceOf(address(degenBox));

        _distributeRewards();

        vm.prank(deployer);
        strategy.safeHarvest(0, true, 0, false);
        _transferRewardsToStrategy(4_000_000 * 1e18);

        vm.prank(deployer);
        strategy.swapToLP(0, fee);

        vm.expectEmit(true, true, false, false);
        emit LogStrategyQueued(address(lp), address(strategy));

        vm.startPrank(degenBox.owner());
        degenBox.setStrategy(lp, strategy);
        advanceTime(1210000);

        vm.expectEmit(true, false, false, false);
        emit LogStrategyDivest(address(lp), 0);
        degenBox.setStrategy(lp, strategy);
        vm.stopPrank();

        assertGt(lp.balanceOf(address(degenBox)), degenBoxBalance);
        assertEq(lp.balanceOf(address(strategy)), 0);
    }

    function testSwappersV2() public {
        _setupV2();

        // transfer mim to lev swapper
        pushPrank(mimWhale);
        mim.transfer(address(degenBox), 1000 ether);
        console2.log("mim in", 1000 ether);
        popPrank();

        degenBox.deposit(mim, address(degenBox), address(levSwapper), 1000 ether, 0);
        uint256 shareFrom = degenBox.balanceOf(mim, address(levSwapper));
        (, uint256 shareReturned) = levSwapper.swap(address(swapper), 0, shareFrom, "");
        console2.log("shareReturned", shareReturned);

        uint256 wrapperShares = degenBox.toAmount(IERC20(constants.getAddress("optimism.abraWrappedVOpUsdc")), shareReturned, false);
        console2.log("wrapperShares", wrapperShares);
        uint256 lpAmount = lp.toAmount(wrapperShares);

        console2.log("lpAmount", lpAmount);

        (, shareReturned) = swapper.swap(address(0), address(0), alice, 0, shareReturned, "");
        uint256 mimOut = degenBox.toAmount(mim, shareReturned, false);
        console2.log("mim out", mimOut);
    }

    function _mintLp(
        address to,
        uint256 amountToken0,
        uint256 amountToken1
    ) private returns (uint256 shares, uint256 liquidity) {
        vm.prank(opWhale);
        opToken.transfer(address(this), amountToken0);
        vm.prank(usdcWhale);
        usdcToken.transfer(address(this), amountToken1);

        uint256 underlyingLpBefore = underlyingLp.balanceOf(address(this));
        uint256 lpBefore = lp.balanceOf(address(this));

        (, , liquidity) = router.addLiquidity(
            address(opToken),
            address(usdcToken),
            false,
            amountToken0,
            amountToken1,
            0,
            0,
            address(this),
            type(uint256).max
        );

        uint256 underlyingLpAfter = underlyingLp.balanceOf(address(this)) - underlyingLpBefore;
        uint256 lpBeforeEnter = lp.balanceOf(address(this));
        assertEq(underlyingLpAfter, liquidity);
        assertEq(lpBefore, lpBeforeEnter);

        shares = lp.enterFor(liquidity, to);

        assertEq(underlyingLp.balanceOf(address(this)) + liquidity, underlyingLpAfter);
        assertEq(lpBeforeEnter, lp.balanceOf(address(this)));
    }

    function _mintLpToDegenBox() private {
        (uint256 lpAmount, ) = _mintLp(alice, 1000 * 1e18, 5000 * 1e6);

        vm.startPrank(alice);
        lp.approve(address(degenBox), type(uint256).max);
        degenBox.deposit(lp, alice, alice, lpAmount, 0);
        vm.stopPrank();
    }

    function _activateStrategy() private {
        vm.startPrank(degenBox.owner());
        degenBox.setStrategy(lp, strategy);
        advanceTime(1210000);
        degenBox.setStrategy(lp, strategy);
        degenBox.setStrategyTargetPercentage(lp, 70);
        vm.stopPrank();

        // Initial Rebalance, calling skim to deposit to the gauge
        vm.startPrank(deployer);
        strategy.safeHarvest(type(uint256).max, true, 0, false);
        assertEq(lp.balanceOf(address(strategy)), 0);
        assertEq(veloToken.balanceOf(address(strategy)), 0);
        vm.stopPrank();
    }

    function _distributeRewards() private {
        advanceTime(1210000);
        uint256 amount = 50000 * 1e18;

        vm.prank(rewardDistributor);
        veloToken.transfer(address(gauge), amount);

        vm.startPrank(address(gauge));
        veloToken.approve(address(gauge), 0);
        veloToken.approve(address(gauge), amount);

        vm.expectEmit(true, true, false, true);
        emit NotifyReward(address(gauge), address(veloToken), amount);
        gauge.notifyRewardAmount(address(veloToken), amount);
        advanceTime(5);
        vm.stopPrank();
    }

    function _transferRewardsToStrategy(uint256 amount) private {
        vm.prank(rewardDistributor);
        veloToken.transfer(address(strategy), amount);
    }
}
