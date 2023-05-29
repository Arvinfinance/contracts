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

contract ArvinScript is BaseScript {
    function deploy() public {
        startBroadcast();

        IWETH weth = IWETH(0x7F5bc2250ea57d8ca932898297b1FF9aE1a04999);
        DegenBox degenBox = new DegenBox(IERC20(weth));
        ArvinDegenNFT nft = new ArvinDegenNFT("", msg.sender);
        ARV arv = new ARV();
        VIN vin = new VIN();
        IN _in = new IN();
        MasterChef mc = new MasterChef(address(arv), address(vin), address(_in), address(0), block.timestamp);
        CauldronV4 cauldronV4MC = new CauldronV4(IBentoBoxV1(address(degenBox)), _in, address(mc), address(nft));
        cauldronV4MC.setFeeTo(msg.sender);
        ProxyOracle oracle = OracleLib.deploySimpleInvertedOracle("ETH/USD", IAggregator(0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08));
        ICauldronV4 ethCauldronV4 = CauldronDeployLib.deployCauldronV4(
            IBentoBoxV1(address(degenBox)),
            address(cauldronV4MC),
            IERC20(weth),
            oracle,
            "",
            85000, // 85% ltv
            3500, // 3.5% interests
            500, // 0.5% opening
            110000 // 10% liquidation
        );

        vm.label(address(ethCauldronV4), "ethCauldronV4");
        _in.mint(msg.sender, 10000000 ether);
        _in.transfer(address(degenBox), 500000 ether);
        _in.approve(address(degenBox), type(uint256).max);
        mc.add((uint256(1096) * 1e17) / 1 days, address(ethCauldronV4), block.timestamp, true);
        degenBox.deposit(_in, address(msg.sender), address(ethCauldronV4), 500000 ether, 0);
        stopBroadcast();
    }
}
