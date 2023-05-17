// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseTest.sol";
import "utils/CauldronDeployLib.sol";
import "periphery/CauldronOwner.sol";
import "/ArvinDegenNFT.sol";
import "/ARV.sol";
import "/VIN.sol";
import "/IN.sol";
import "periphery/MasterChef.sol";
import "/DegenBox.sol";
import "utils/BaseScript.sol";
import "utils/OracleLib.sol";
import "interfaces/IWETH.sol";

contract ArvinLogicTest is BaseTest {
    address treasury = address(0x999);
    ICauldronV4 ethCauldronV4;
    IWETH weth;
    DegenBox degenBox;
    ArvinDegenNFT nft;
    CauldronV4 cauldronV4MC;
    ARV arv;
    VIN vin;
    IN _in;
    MasterChef mc;

    function setupMainnet() public {
        if (address(ethCauldronV4) != address(0)) return;
        forkMainnet(17200806);
        super.setUp();
        pushPrank(deployer);
        weth = IWETH(constants.getAddress("mainnet.weth"));
        degenBox = new DegenBox(IERC20(weth));
        nft = new ArvinDegenNFT("", msg.sender);
        arv = new ARV();
        vin = new VIN();
        _in = new IN();
        mc = new MasterChef(address(arv), address(vin), address(_in), address(0), block.timestamp);
        cauldronV4MC = new CauldronV4(IBentoBoxV1(address(degenBox)), _in, address(mc), address(nft));
        cauldronV4MC.setFeeTo(deployer);
        ProxyOracle oracle = OracleLib.deploySimpleInvertedOracle("ETH/USD", IAggregator(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419));
        ethCauldronV4 = CauldronDeployLib.deployCauldronV4(
            IBentoBoxV1(address(degenBox)),
            address(cauldronV4MC),
            IERC20(weth),
            oracle,
            "",
            7500, // 75% ltv
            1800, // 18% interests
            0, // 0% opening
            1000 // 10% liquidation
        );

        vm.label(address(ethCauldronV4), "ethCauldronV4");
        _in.mint(deployer, 10000000 ether);
        _in.transfer(address(degenBox), 500000 ether);
        _in.approve(address(degenBox), type(uint256).max);
        mc.add((uint256(1096) * 1e17) / 1 days, address(ethCauldronV4), true);
        degenBox.deposit(_in, address(deployer), address(ethCauldronV4), 500000 ether, 0);
    }

    function testInterestRefund() public {
        setupMainnet();
        weth.deposit{value: 10 ether}();
        weth.approve(address(degenBox), type(uint256).max);
        (, uint256 share) = degenBox.deposit(weth, deployer, address(ethCauldronV4), 10 ether, 0);
        ethCauldronV4.addCollateral(deployer, true, share);
        (uint256 borrowPart1, ) = ethCauldronV4.borrow(deployer, 1000 ether);
        degenBox.deposit(_in, deployer, address(degenBox), 100000 ether, 0);
        vm.warp(block.timestamp + 100 seconds);
        ethCauldronV4.repay(deployer, true, borrowPart1 / 3);
        vm.warp(block.timestamp + 214 seconds);
        (uint256 borrowPart2, ) = ethCauldronV4.borrow(deployer, 2000 ether);
        ethCauldronV4.repay(deployer, true, borrowPart2 / 3);
        vm.warp(block.timestamp + 44 seconds);
        ethCauldronV4.repay(deployer, true, borrowPart1 / 3);
        vm.warp(block.timestamp + 60 seconds);
        ethCauldronV4.repay(deployer, true, borrowPart2 / 3);
        (uint256 borrowPart3, ) = ethCauldronV4.borrow(deployer, 2000 ether);
        vm.warp(block.timestamp + 80 seconds);
        ethCauldronV4.repay(deployer, true, borrowPart2 / 3);
        vm.warp(block.timestamp + 105 seconds);
        ethCauldronV4.repay(deployer, true, borrowPart1 / 3);
        vm.warp(block.timestamp + 98 seconds);
        ethCauldronV4.repay(deployer, true, borrowPart3);
        console.log(degenBox.toAmount(_in, degenBox.balanceOf(_in, deployer), true));
        console.log(degenBox.toAmount(_in, degenBox.balanceOf(_in, address(ethCauldronV4)), true));
    }

    function testInDistribution() public {
        setupMainnet();
        vin.approve(address(mc), type(uint256).max);
        arv.approve(address(mc), type(uint256).max);
        mc.deposit(1, 100 ether);
        mc.deposit(2, 100 ether);
        testInterestRefund();
        ethCauldronV4.withdrawFees();
        mc.claimPending(1);
        mc.claimPending(2);
        mc.withdraw(2, 100 ether);
        // vm.expectRevert();
        // mc.withdraw(1, 100 ether);
        vm.warp(block.timestamp + 21 days);
        mc.deposit(1, 200 ether);
        // vm.expectRevert();
        // mc.withdraw(1, 150 ether);
        vm.warp(block.timestamp + 21 days);
        mc.withdraw(1, 151 ether);
        console.log(_in.balanceOf(deployer));
    }

    function testVinDistribution() public {
        setupMainnet();
        vin.transfer(address(mc), 10000 ether);
        pushPrank(alice);
        weth.deposit{value: 10 ether}();
        weth.approve(address(degenBox), type(uint256).max);
        (, uint256 share) = degenBox.deposit(weth, alice, address(ethCauldronV4), 10 ether, 0);
        ethCauldronV4.addCollateral(alice, true, share);
        ethCauldronV4.borrow(alice, 1000 ether);

        pushPrank(bob);
        weth.deposit{value: 10 ether}();
        weth.approve(address(degenBox), type(uint256).max);
        (, share) = degenBox.deposit(weth, bob, address(ethCauldronV4), 10 ether, 0);
        ethCauldronV4.addCollateral(bob, true, share);
        ethCauldronV4.borrow(bob, 500 ether);

        //end of day
        vm.warp(block.timestamp + 1 days);
        mc.vestingPendingReward(true);
        popPrank();
        mc.vestingPendingReward(true);
        vm.warp(block.timestamp + 21 days);
        pushPrank(bob);
        mc.claimVestingReward();
        popPrank();
        mc.claimVestingReward();
        console.log(vin.balanceOf(alice));
        console.log(vin.balanceOf(bob));
        popPrank();
    }

    function testArvRelease() public {
        setupMainnet();
        arv.transfer(address(mc), 10000 ether);
        vin.transfer(alice, 10000 ether);
        pushPrank(alice);
        vin.approve(address(mc), type(uint256).max);
        mc.depositLock(1000 ether);
        uint256 today = block.timestamp - (block.timestamp % 1 days);
        for (uint i = 1; i <= 21; i++) {
            vm.warp(today + i * 1 days);
            vm.expectRevert();
            mc.withdrawLock(100 ether);
            mc.claimPending(0);
            console.log(arv.balanceOf(alice));
        }
        vm.warp(today + 40 * 1 days);
        mc.withdrawLock(100 ether);
        console.log(arv.balanceOf(alice));
        console.log(mc.getUnlockableAmount(alice));
    }

    mapping(address => uint256[]) testMap;

    fallback() external {}
}
