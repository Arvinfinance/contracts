// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseTest.sol";
import "script/CauldronFeeWithdrawer.s.sol";
import "interfaces/IAnyswapRouter.sol";
import "libraries/SafeApprove.sol";

contract CauldronFeeWithdrawerTest is BaseTest {
    using BoringERC20 for IERC20;
    using SafeApprove for IERC20;

    event LogOperatorChanged(address indexed operator, bool previous, bool current);
    event LogSwappingRecipientChanged(address indexed recipient, bool previous, bool current);
    event LogAllowedSwapTokenOutChanged(IERC20 indexed token, bool previous, bool current);
    event LogMimWithdrawn(IBentoBoxV1 indexed bentoBox, uint256 amount);
    event LogMimTotalWithdrawn(uint256 amount);
    event LogSwapMimTransfer(uint256 amounIn, uint256 amountOut, IERC20 tokenOut);
    event LogBentoBoxChanged(IBentoBoxV1 indexed bentoBox, bool previous, bool current);
    event LogCauldronChanged(address indexed cauldron, bool previous, bool current);
    event LogBridgeableTokenChanged(IERC20 indexed token, bool previous, bool current);
    event LogParametersChanged(address indexed swapper, address indexed mimProvider, ICauldronFeeBridger indexed bridger);

    CauldronFeeWithdrawer public withdrawer;
    address public mimWhale;

    uint256 constant MAINNET_BLOCK = 16471285;
    uint256 constant AVALANCHE_BLOCK = 25321519;

    function setUp() public override {}

    function setupMainnet() public {
        forkMainnet(MAINNET_BLOCK);
        mimWhale = 0xbbc4A8d076F4B1888fec42581B6fc58d242CF2D5;
        _setup("mainnet");
    }

    function setupAvalanche() public {
        forkAvalanche(AVALANCHE_BLOCK);
        mimWhale = 0xAE4D3a42E46399827bd094B4426e2f79Cca543CA;
        _setup("avalanche");
    }

    function _cauldronPredicate(
        address,
        bool,
        uint8,
        string memory,
        uint256 creationBlock
    ) external view returns (bool) {
        return creationBlock <= block.number;
    }

    function _setup(string memory chainName) private {
        super.setUp();

        CauldronFeeWithdrawerScript script = new CauldronFeeWithdrawerScript();
        script.setTesting(true);
        withdrawer = script.deploy();

        pushPrank(withdrawer.owner());
        CauldronInfo[] memory cauldronInfos = constants.getCauldrons(chainName, true, this._cauldronPredicate);
        address[] memory cauldrons = new address[](cauldronInfos.length);
        uint8[] memory versions = new uint8[](cauldronInfos.length);
        bool[] memory enabled = new bool[](cauldronInfos.length);

        for (uint256 i = 0; i < cauldronInfos.length; i++) {
            CauldronInfo memory cauldronInfo = cauldronInfos[i];
            cauldrons[i] = cauldronInfo.cauldron;
            versions[i] = cauldronInfo.version;
            enabled[i] = true;
        }
        withdrawer.setCauldrons(cauldrons, versions, enabled);
        popPrank();

        uint256 cauldronCount = withdrawer.cauldronInfosCount();
        IERC20 mim = withdrawer.mim();

        pushPrank(withdrawer.mimProvider());
        mim.safeApprove(address(withdrawer), type(uint256).max);
        popPrank();

        for (uint256 i = 0; i < cauldronCount; i++) {
            (, address masterContract, , ) = withdrawer.cauldronInfos(i);
            address owner = BoringOwnable(masterContract).owner();
            vm.prank(owner);
            ICauldronV1(masterContract).setFeeTo(address(withdrawer));
        }
    }

    function testWithdraw() public {
        setupMainnet();

        // deposit fund into each registered bentoboxes
        vm.startPrank(mimWhale);
        uint256 cauldronCount = withdrawer.cauldronInfosCount();
        uint256 totalFeeEarned;
        IERC20 mim = withdrawer.mim();
        uint256 mimBefore = mim.balanceOf(address(withdrawer));

        for (uint256 i = 0; i < cauldronCount; i++) {
            (address cauldron, , , uint8 version) = withdrawer.cauldronInfos(i);
            uint256 feeEarned;

            ICauldronV1(cauldron).accrue();

            if (version == 1) {
                (, feeEarned) = ICauldronV1(cauldron).accrueInfo();
            } else if (version >= 2) {
                (, feeEarned, ) = ICauldronV2(cauldron).accrueInfo();
            }

            totalFeeEarned += feeEarned;
        }

        uint256 approximatedTotalFeeEarned = 109534598403490120388539;
        vm.expectEmit(false, false, false, true);
        emit LogMimTotalWithdrawn(approximatedTotalFeeEarned);

        // some rounding error from share <-> amount conversions
        assertApproxEqAbs(totalFeeEarned, approximatedTotalFeeEarned, 50);
        withdrawer.withdraw();

        uint256 mimAfter = mim.balanceOf(address(withdrawer));
        assertGe(mimAfter, mimBefore);
    }

    function testSetBentoBox() public {
        setupMainnet();

        vm.startPrank(withdrawer.owner());

        IBentoBoxV1 box = IBentoBoxV1(constants.getAddress("mainnet.degenBox"));
        withdrawer.setBentoBox(box, true);

        uint256 count = withdrawer.bentoBoxesCount();
        withdrawer.setBentoBox(box, false);
        withdrawer.setBentoBox(box, true);
        withdrawer.setBentoBox(box, true);

        assertEq(count, withdrawer.bentoBoxesCount());
        withdrawer.setBentoBox(box, false);
        assertEq(count - 1, withdrawer.bentoBoxesCount());
        vm.stopPrank();
    }

    function testParameters() public {
        setupMainnet();

        vm.startPrank(withdrawer.owner());
        IERC20 mim = withdrawer.mim();

        address prevSwapper = withdrawer.swapper();
        uint256 prevSwapperAllowance = mim.allowance(address(withdrawer), prevSwapper);
        assertGt(prevSwapperAllowance, 0);

        withdrawer.setParameters(alice, bob, ICauldronFeeBridger(carol));
        assertEq(withdrawer.mimProvider(), bob);
        assertEq(address(withdrawer.bridger()), address(ICauldronFeeBridger(carol)));
        assertEq(mim.allowance(address(withdrawer), prevSwapper), 0);
        assertEq(mim.allowance(address(withdrawer), alice), type(uint256).max);
        vm.stopPrank();
    }

    function testSwappingRestrictions() public {
        setupMainnet();

        ERC20 spell = ERC20(constants.getAddress("mainnet.spell"));
        address sSpell = constants.getAddress("mainnet.sSpell");

        vm.startPrank(withdrawer.owner());
        withdrawer.setSwapTokenOut(spell, false);
        vm.expectRevert(abi.encodeWithSignature("ErrUnsupportedToken(address)", spell));
        withdrawer.swapMimAndTransfer(0, spell, sSpell, "");
        withdrawer.setSwapTokenOut(spell, true);
        withdrawer.setSwappingRecipient(sSpell, false);
        vm.expectRevert(abi.encodeWithSignature("ErrInvalidSwappingRecipient(address)", sSpell));
        withdrawer.swapMimAndTransfer(0, spell, sSpell, "");
        withdrawer.setSwappingRecipient(sSpell, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotAllowedOperator()"));
        withdrawer.swapMimAndTransfer(0, spell, sSpell, "");
        vm.stopPrank();

        vm.startPrank(withdrawer.owner());
        withdrawer.setOperator(alice, true);
        withdrawer.swapMimAndTransfer(0, spell, sSpell, "");
        vm.stopPrank();
    }

    function testMimToSpellSwapping() public {
        setupMainnet();

        vm.startPrank(withdrawer.owner());
        ERC20 spell = ERC20(constants.getAddress("mainnet.spell"));
        address sSpell = constants.getAddress("mainnet.sSpell");
        IERC20 mim = withdrawer.mim();
        withdrawer.withdraw();
        uint256 balanceSpellBefore = spell.balanceOf(sSpell);

        //console2.log("balanceSpellBefore", balanceSpellBefore);
        assertGt(mim.balanceOf(address(withdrawer)), 0);

        //console2.log("mim amount to swap", mim.balanceOf(address(withdrawer)));
        // https://api.0x.org/swap/v1/quote?buyToken=0x090185f2135308BaD17527004364eBcC2D37e5F6&sellToken=0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3&sellAmount=79274734755660500502507
        withdrawer.swapMimAndTransfer(
            0,
            spell,
            sSpell,
            hex"0f3b31b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000010c97df28cba393f07eb0000000000000000000000000000000000000000004f52ba953c6d8c71e63347000000000000000000000000000000000000000000000000000000000000000300000000000000000000000099d8a9c45b2eca8864373a26d1459e3dff1e17f3000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000090185f2135308bad17527004364ebcc2d37e5f600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000004299d8a9c45b2eca8864373a26d1459e3dff1e17f30001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000090185f2135308bad17527004364ebcc2d37e5f6869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000ff36add3c363ceec50"
        );

        uint256 balanceSpellBought = spell.balanceOf(sSpell) - balanceSpellBefore;
        assertApproxEqAbs(balanceSpellBought, 95985150732398456532864682, 100_000 ether);

        assertEq(mim.balanceOf(address(withdrawer)), 30259863647829619886032);
        vm.stopPrank();
    }

    function xtestBridging() public {
        setupAvalanche();

        IERC20 mim = withdrawer.mim();

        vm.startPrank(withdrawer.owner());
        withdrawer.setBridgeableToken(mim, false);
        vm.expectRevert(abi.encodeWithSignature("ErrUnsupportedToken(address)", mim));
        withdrawer.bridge(mim, 0);
        withdrawer.setBridgeableToken(mim, true);

        ICauldronFeeBridger prevBridger = withdrawer.bridger();
        assertTrue(prevBridger != ICauldronFeeBridger(address(0)));

        withdrawer.setParameters(withdrawer.swapper(), withdrawer.mimProvider(), ICauldronFeeBridger(address(0)));
        vm.expectRevert(abi.encodeWithSignature("ErrNoBridger()")); // no bridger
        withdrawer.bridge(mim, 100 ether);

        withdrawer.withdraw();
        assertGt(mim.balanceOf(address(withdrawer)), 100 ether);
        withdrawer.setParameters(withdrawer.swapper(), withdrawer.mimProvider(), prevBridger);
        withdrawer.bridge(mim, 100 ether);

        vm.stopPrank();
    }

    function testEnableDisableCauldrons() public {
        setupMainnet();
        uint256 count = withdrawer.cauldronInfosCount();
        assertGt(count, 0);

        address[] memory cauldrons = new address[](count);
        uint8[] memory versions = new uint8[](count);
        bool[] memory enabled = new bool[](count);

        (address cauldron1, , , ) = withdrawer.cauldronInfos(0);
        (address cauldron2, , , ) = withdrawer.cauldronInfos(1);
        for (uint256 i = 0; i < count; i++) {
            (address cauldron, , , uint8 version) = withdrawer.cauldronInfos(i);
            cauldrons[i] = cauldron;
            versions[i] = version;
            enabled[i] = false;
        }

        vm.startPrank(withdrawer.owner());
        withdrawer.setCauldrons(cauldrons, versions, enabled);

        count = withdrawer.cauldronInfosCount();
        assertEq(count, 0);

        withdrawer.withdraw();

        vm.expectRevert();
        withdrawer.setCauldron(alice, 2, true);

        withdrawer.setCauldron(cauldron1, 2, true);
        assertEq(withdrawer.cauldronInfosCount(), 1);
        withdrawer.setCauldron(cauldron1, 2, true);
        assertEq(withdrawer.cauldronInfosCount(), 1);
        withdrawer.setCauldron(cauldron1, 2, false);
        assertEq(withdrawer.cauldronInfosCount(), 0);

        withdrawer.setCauldron(cauldron1, 2, true);
        withdrawer.setCauldron(cauldron2, 2, true);
        assertEq(withdrawer.cauldronInfosCount(), 2);
        withdrawer.setCauldron(cauldron1, 2, false);
        withdrawer.setCauldron(cauldron2, 2, true);
        assertEq(withdrawer.cauldronInfosCount(), 1);
        withdrawer.setCauldron(cauldron2, 2, false);
        assertEq(withdrawer.cauldronInfosCount(), 0);
        vm.stopPrank();
    }
}
