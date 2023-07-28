// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "oracles/ProxyOracle.sol";
import "utils/BaseScript.sol";
import "utils/CauldronDeployLib.sol";
import "periphery/CauldronOwner.sol";
import "/ArvinDegenNFT.sol";
import "/ARV.sol";
import "/VIN.sol";
import "/DegenBox.sol";
import "/IN.sol";
import "utils/OracleLib.sol";
import "periphery/MasterChef.sol";
import "./MarketLens.s.sol";
import "interfaces/IWETH.sol";
import "forge-std/Test.sol";
import "oracles/Tricrypto2Oracle.sol";
import "oracles/GlpOracle.sol";
import "interfaces/IGmxRewardRouterV2.sol";
import "interfaces/IGmxVault.sol";
import "swappers/GlpLevSwapper.sol";
import "swappers/GlpSwapper.sol";
import "/cauldrons/CvxCauldron.sol";
import "interfaces/IUniswapV2Router01.sol";
import "interfaces/ICurvePool.sol";
import "oracles/WbtcOracle.sol";

contract ArvinDeployAllScript is BaseScript {
    ARV arv;
    VIN vin;
    IN _in;
    ArvinDegenNFT nft;
    CauldronV4 cauldronV4MC;
    CauldronV4 gmxCauldronMC;
    CauldronV4 cvxCauldronMC;
    IBentoBoxV1 degenBox;
    MasterChef mc;
    IWETH weth;
    uint256 rewardTimestamp = block.timestamp;
    address sGlp;
    IGmxRewardRouterV2 rewardRouterV2;
    address glpManager;
    string jsStr = "";
    mapping(string => address) addresses;

    function logAddr(address addr, string memory name) private {
        logAddrWithDesc(addr, name, "-");
    }

    function logAddrWithDesc(address addr, string memory name, string memory desc) private {
        console.log(string.concat("| ", name, " | ", vm.toString(addr), " |", desc, " |"));
        bytes memory bs = bytes(name);
        bytes memory newBs = new bytes(bs.length);
        for (uint i = 0; i < bs.length; i++) {
            if (bs[i] >= 0x20 && bs[i] <= 0x2F) {
                newBs[i] = 0x5F;
            } else {
                newBs[i] = (bs[i]);
            }
        }
        bytes memory lr = new bytes(1);
        lr[0] = 0x0A;
        jsStr = string.concat(jsStr, "export const ", string(newBs), "_ADDR=", "'", vm.toString(addr), "';", string(lr));
        vm.label(addr, name);
        addresses[name] = addr;
    }

    address cvx3crypto = 0xA9249f8667cb120F065D9dA1dCb37AD28E1E8FF0;

    function deploy() public {
        startBroadcast();
        sGlp = constants.getAddress("arbitrum.gmx.sGLP");
        rewardRouterV2 = IGmxRewardRouterV2(constants.getAddress("arbitrum.gmx.rewardRouterV2"));
        glpManager = constants.getAddress("arbitrum.gmx.glpManager");
        console.log("## Cores");
        console.log("| Contract Name  | Address   | Description   |");
        console.log("| -------------- | --------- | ------------- |");
        weth = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        degenBox = IBentoBoxV1(address(new DegenBox(IERC20(weth))));
        nft = new ArvinDegenNFT("", msg.sender);
        arv = new ARV();
        vin = new VIN();
        _in = new IN();
        logAddr(address(arv), "ARV");
        logAddr(address(vin), "VIN");
        logAddr(address(_in), "IN");
        logAddr(address(degenBox), "Degen Box");
        logAddr(address(nft), "Arvin Degen NFT");
        mc = new MasterChef(address(arv), address(vin), address(_in), address(0), rewardTimestamp);
        logAddr(address(mc), "Master Chef");

        cauldronV4MC = new CauldronV4(degenBox, _in, address(mc), address(nft));
        gmxCauldronMC = CauldronV4(
            address(new GmxCauldron(degenBox, _in, address(mc), address(nft), address(rewardRouterV2), address(cauldronV4MC)))
        );
        cvxCauldronMC = CauldronV4(
            address(new CvxCauldron(degenBox, _in, address(mc), address(nft), address(cvx3crypto), address(cauldronV4MC)))
        );
        logAddr(address(cauldronV4MC), "Cauldron Master Contract");
        logAddr(address(gmxCauldronMC), "GMX Cauldron Master Contract");
        logAddr(address(cvxCauldronMC), "Convex Cauldron Master Contract");
        cauldronV4MC.setFeeTo(msg.sender);
        gmxCauldronMC.setFeeTo(msg.sender);
        cvxCauldronMC.setFeeTo(msg.sender);

        _in.mint(msg.sender, 9500000 ether);

        // _in.transfer(address(degenBox), 9500000 ether);
        _in.approve(address(degenBox), type(uint256).max);

        console.log("## Cauldrons");
        console.log("| Contract Name  | Address   | Description   |");
        console.log("| -------------- | --------- | ------------- |");
        //Cauldron(ETH)
        ProxyOracle ethOracle = OracleLib.deploySimpleInvertedOracle("ETH/USD", IAggregator(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612));
        (
            deployCauldron(
                address(ethOracle),
                address(weth), //WETH
                8500, // 85% ltv
                350, // 3.5% interests
                50, // 0.5% opening
                750, // 7.5% liquidation
                1500000,
                80 * 1 ether,
                rewardTimestamp,
                "Cauldron(ETH)"
            )
        );

        //Cauldron(GLP)
        ProxyOracle aglpOracle = new ProxyOracle();
        aglpOracle.changeOracleImplementation(new GlpOracle(IGmxGlpManager(glpManager)));
        deployGmxCauldron(
            address(aglpOracle),
            address(sGlp),
            9000, // 90% ltv
            500, // 5% interests
            0, // 0% opening
            500, // 5% liquidation
            3000000,
            170 * 1 ether,
            rewardTimestamp,
            true,
            "Cauldron(sGLP)"
        );

        //Cauldron(ARB)
        ProxyOracle arbOracle = OracleLib.deploySimpleInvertedOracle("ARB/USD", IAggregator(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6));
        (
            deployCauldron(
                address(arbOracle),
                arb, //ARB
                8000, // 80% ltv
                500, // 5% interests
                50, // 0.5% opening
                750, // 7.5% liquidation
                2000000,
                150 * 1 ether,
                rewardTimestamp,
                "Cauldron(ARB)"
            )
        );

        //Cauldron(Tricrypto)
        ProxyOracle triOracle = OracleLib.deploySimpleProxyOracle(new Tricrypto2Oracle(0x960ea3e3C7FB317332d990873d354E18d7645590));

        address tricrypto = deployCauldronWithMasterContract(
            address(triOracle),
            cvx3crypto, //Tricrypto
            8500, // 85% ltv
            500, // 5% interests
            50, // 0.5% opening
            500, // 5% liquidation
            500000,
            20 * 1 ether,
            rewardTimestamp,
            address(cvxCauldronMC)
        );
        logAddr(tricrypto, "Cauldron(cvxcrv3crypto)");

        //Cauldron(MAGIC)
        ProxyOracle magicOracle = OracleLib.deploySimpleInvertedOracle(
            "MAGIC/USD",
            IAggregator(0x47E55cCec6582838E173f252D08Afd8116c2202d)
        );
        (
            deployCauldron(
                address(magicOracle),
                magic, //MAGIC
                7000, // 70% ltv
                500, // 5% interests
                50, // 0.5% opening
                1000, // 10% liquidation
                500000,
                40 * 1 ether,
                rewardTimestamp,
                "Cauldron(MAGIC)"
            )
        );

        //Cauldron(GMX)
        ProxyOracle gmxOracle = OracleLib.deploySimpleInvertedOracle("GMX/USD", IAggregator(0xDB98056FecFff59D032aB628337A4887110df3dB));
        (
            deployGmxCauldron(
                address(gmxOracle),
                address(gmx), //GMX
                8000, // 80% ltv
                500, // 5% interests
                50, // 0.5% opening
                750, // 7.5% liquidation
                1000000,
                70 * 1 ether,
                rewardTimestamp,
                false,
                "Cauldron(GMX)"
            )
        );

        //Cauldron(BTC)
        ProxyOracle btcOracle = OracleLib.deploySimpleProxyOracle(new WbtcOracle(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57));
        (
            deployCauldron(
                address(btcOracle),
                wbtc, //BTC
                8500, // 85% ltv
                350, // 3.5% interests
                50, // 0.5% opening
                750, // 7.5% liquidation
                1000000,
                60 * 1 ether,
                rewardTimestamp,
                "Cauldron(BTC)"
            )
        );

        console.log("## Oracles");
        console.log("| Contract Name  | Address   | Description   |");
        console.log("| -------------- | --------- | ------------- |");
        logAddr(address(ethOracle), "ETH/USD Oracle");
        logAddr(address(aglpOracle), "GLP Oracle");
        logAddr(address(arbOracle), "ARB/USD Oracle");
        logAddr(address(triOracle), "tricrypto/USD Oracle");
        logAddr(address(magicOracle), "MAGIC/USD Oracle");
        logAddr(address(gmxOracle), "GMX/USD Oracle");
        logAddr(address(btcOracle), "BTC/USD Oracle");
        // MarketLensScript script = new MarketLensScript();
        depolyPeripheries();
        // initToken();
        stopBroadcast();
    }

    IUniswapV2Router01 sushiRouter = IUniswapV2Router01(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    address usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address magic = 0x539bdE0d7Dbd336b79148AA742883198BBF60342;
    ICurvePool tricryptoPool = ICurvePool(0xF97c707024ef0DD3E77a0824555a46B622bfB500);
    address arb = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address gmx = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address booster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    function initToken() private {
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = usdt;
        address to = 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199;
        sushiRouter.swapExactETHForTokens{value: 1000 ether}(0, tokens, to, 9999999999999);
        tokens[1] = wbtc;
        sushiRouter.swapExactETHForTokens{value: 1000 ether}(0, tokens, to, 9999999999999);
        tokens[1] = magic;
        sushiRouter.swapExactETHForTokens{value: 1000 ether}(0, tokens, to, 9999999999999);
        tokens[1] = arb;
        sushiRouter.swapExactETHForTokens{value: 1000 ether}(0, tokens, to, 9999999999999);
        tokens[1] = gmx;
        sushiRouter.swapExactETHForTokens{value: 1000 ether}(0, tokens, to, 9999999999999);
        IGmxGlpRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5).mintAndStakeGlpETH{value: 1000 ether}(0, 0);
        IStrictERC20(sGlp).transfer(to, IERC20(sGlp).balanceOf(msg.sender));
        uint256[3] memory sss;
        sss[0] = 0;
        sss[1] = 0;
        sss[2] = 1000 ether;
        tricryptoPool.add_liquidity{value: 1000 ether}(sss, 0);
        IStrictERC20(0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2).approve(
            booster,
            IERC20(0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2).balanceOf(msg.sender)
        );
        bytes memory data = fromHex("c6f678bd0000000000000000000000000000000000000000000000000000000000000008");
        (bool succeed, bytes memory res) = address(booster).call(data);
        IStrictERC20(cvx3crypto).transfer(to, IERC20(cvx3crypto).balanceOf(msg.sender));
    }

    function depolyPeripheries() private {
        address swapper = constants.getAddress("arbitrum.aggregators.zeroXExchangeProxy");
        IGmxVault _gmxVault = IGmxVault(constants.getAddress("arbitrum.gmx.vault"));
        console.log("## Swappers");
        console.log("| Contract Name  | Address   | Description   |");
        console.log("| -------------- | --------- | ------------- |");
        GlpSwapper glpSwapper = new GlpSwapper(
            degenBox,
            _gmxVault,
            _in,
            IERC20(sGlp),
            IGmxGlpRewardRouter(address(rewardRouterV2)),
            swapper
        );
        GlpLevSwapper glpLevSwapper = new GlpLevSwapper(
            degenBox,
            _gmxVault,
            _in,
            IERC20(sGlp),
            glpManager,
            IGmxGlpRewardRouter(address(rewardRouterV2)),
            swapper
        );
        logAddrWithDesc(address(glpLevSwapper), "GLP Leverage Swapper", "IN -> Token");
        logAddrWithDesc(address(glpSwapper), "GLP Swapper", "Token -> IN");

        console.log("## Peripheries");
        console.log("| Contract Name  | Address   | Description   |");
        console.log("| -------------- | --------- | ------------- |");
        logAddr(address(new MarketLens()), "Market Lens");
        logAddr(address(new GmxLens(IGmxGlpManager(glpManager), _gmxVault)), "Gmx Lens");

        console.log(jsStr);
    }

    function deployGmxCauldron(
        address oracle,
        address token,
        uint256 ltv,
        uint256 interests,
        uint256 opening,
        uint256 liquidation,
        uint128 limit,
        uint256 rewardPerDay,
        uint256 startTimestamp,
        bool isGLP,
        string memory lable
    ) public returns (address cauldron) {
        bytes memory data = CauldronDeployLib.getCauldronParameters(
            IERC20(token),
            IOracle(oracle),
            "",
            ltv,
            interests,
            opening,
            liquidation
        );
        ICauldronV4 cauldronV4 = ICauldronV4(IBentoBoxV1(degenBox).deploy(address(gmxCauldronMC), abi.encode(data, isGLP), true));
        limit *= 1 ether;
        cauldronV4.changeBorrowLimit(limit, limit);
        logAddr(address(cauldronV4), lable);
        mc.add(rewardPerDay / 1 days / 4, address(cauldronV4), startTimestamp, true);
        degenBox.deposit(_in, address(msg.sender), address(cauldronV4), limit, 0);
        return address(cauldronV4);
    }

    function deployCauldron(
        address oracle,
        address token,
        uint256 ltv,
        uint256 interests,
        uint256 opening,
        uint256 liquidation,
        uint128 limit,
        uint256 rewardPerDay,
        uint256 startTimestamp,
        string memory lable
    ) public returns (address cauldron) {
        logAddr(
            address(
                deployCauldronWithMasterContract(
                    oracle,
                    token,
                    ltv,
                    interests,
                    opening,
                    liquidation,
                    limit,
                    rewardPerDay,
                    startTimestamp,
                    address(cauldronV4MC)
                )
            ),
            lable
        );
    }

    function deployCauldronWithMasterContract(
        address oracle,
        address token,
        uint256 ltv,
        uint256 interests,
        uint256 opening,
        uint256 liquidation,
        uint128 limit,
        uint256 rewardPerDay,
        uint256 startTimestamp,
        address masterContract
    ) public returns (address cauldron) {
        ICauldronV4 cauldronV4 = CauldronDeployLib.deployCauldronV4(
            degenBox,
            masterContract,
            IERC20(token),
            IOracle(oracle),
            "",
            ltv,
            interests,
            opening,
            liquidation
        );
        limit *= 1 ether;
        cauldronV4.changeBorrowLimit(limit, limit);
        mc.add(rewardPerDay / 1 days / 4, address(cauldronV4), startTimestamp, true);
        degenBox.deposit(_in, address(msg.sender), address(cauldronV4), limit, 0);
        return address(cauldronV4);
    }

    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }

    function fromHex(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);
        for (uint i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }
}
