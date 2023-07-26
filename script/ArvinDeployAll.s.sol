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
import "/cauldrons/MuxCauldron.sol";

contract ArvinDeployAllScript is BaseScript {
    ARV arv;
    VIN vin;
    IN _in;
    ArvinDegenNFT nft;
    CauldronV4 cauldronV4MC;
    CauldronV4 gmxCauldronMC;
    CauldronV4 muxCauldronMC;
    IBentoBoxV1 degenBox;
    MasterChef mc;
    IWETH weth;
    uint256 rewardTimestamp = block.timestamp;
    address sGlp;
    IGmxRewardRouterV2 rewardRouterV2;
    address glpManager;
    string jsStr = "";

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
        jsStr = string.concat(jsStr, "const ", string(newBs), "_ADDR=", "'", vm.toString(addr), "';", string(lr));
    }

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
        address muxRewardRoute = 0xaf9C4F6A0ceB02d4217Ff73f3C95BbC8c7320ceE;
        muxCauldronMC = CauldronV4(
            address(new MuxCauldron(degenBox, _in, address(mc), address(nft), address(muxRewardRoute), address(cauldronV4MC)))
        );
        logAddr(address(cauldronV4MC), "Cauldron Master Contract");
        logAddr(address(gmxCauldronMC), "GMX Cauldron Master Contract");
        logAddr(address(muxCauldronMC), "MUX Cauldron Master Contract");
        cauldronV4MC.setFeeTo(msg.sender);
        gmxCauldronMC.setFeeTo(msg.sender);
        muxCauldronMC.setFeeTo(msg.sender);

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
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, //WETH
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
                0x912CE59144191C1204E64559FE8253a0e49E6548, //ARB
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

        ProxyOracle mlpOracle = new ProxyOracle();
        address sMlp = 0x0a9bbf8299FEd2441009a7Bb44874EE453de8e5D;
        // mlpOracle.changeOracleImplementation(new GlpOracle(IGmxGlpManager(glpManager)));
        deployGmxCauldron(
            address(mlpOracle),
            address(sMlp),
            9500, // 90% ltv
            500, // 5% interests
            0, // 0% opening
            500, // 5% liquidation
            3000000,
            170 * 1 ether,
            rewardTimestamp,
            true,
            "Cauldron(sMLP)"
        );
        // //Cauldron(Tricrypto)
        // ProxyOracle triOracle = OracleLib.deploySimpleProxyOracle(new Tricrypto2Oracle(0x960ea3e3C7FB317332d990873d354E18d7645590));
        // (
        //     deployCauldron(
        //         address(triOracle),
        //         0xA9249f8667cb120F065D9dA1dCb37AD28E1E8FF0, //Tricrypto
        //         8500, // 85% ltv
        //         500, // 5% interests
        //         50, // 0.5% opening
        //         500, // 5% liquidation
        //         500000,
        //         20 * 1 ether,
        //         rewardTimestamp,
        //         "Cauldron(cvxcrv3crypto)"
        //     )
        // );

        //Cauldron(MAGIC)
        ProxyOracle magicOracle = OracleLib.deploySimpleInvertedOracle(
            "MAGIC/USD",
            IAggregator(0x47E55cCec6582838E173f252D08Afd8116c2202d)
        );
        (
            deployCauldron(
                address(magicOracle),
                0x539bdE0d7Dbd336b79148AA742883198BBF60342, //MAGIC
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
        address gmx = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
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
        ProxyOracle btcOracle = OracleLib.deploySimpleInvertedOracle("BTC/USD", IAggregator(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57));
        (
            deployCauldron(
                address(btcOracle),
                0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, //BTC
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
        logAddr(address(magicOracle), "MAGIC/USD Oracle");
        logAddr(address(gmxOracle), "GMX/USD Oracle");
        logAddr(address(btcOracle), "BTC/USD Oracle");
        // MarketLensScript script = new MarketLensScript();
        depolyPeripheries();

        stopBroadcast();
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
        ICauldronV4 cauldronV4 = CauldronDeployLib.deployCauldronV4(
            degenBox,
            address(cauldronV4MC),
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
        logAddr(address(cauldronV4), lable);
        mc.add(rewardPerDay / 1 days / 4, address(cauldronV4), startTimestamp, true);
        degenBox.deposit(_in, address(msg.sender), address(cauldronV4), limit, 0);
        return address(cauldronV4);
    }
}
