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
import "/IN.sol";
import "periphery/MasterChef.sol";

contract CauldronV4Script is BaseScript {
    function deploy() public {
        IBentoBoxV1 degenBox;
        address safe;
        ERC20 mim;

        if (block.chainid == ChainId.Mainnet) {
            degenBox = IBentoBoxV1(constants.getAddress("mainnet.degenBox"));
            safe = constants.getAddress("mainnet.safe.ops");
            mim = ERC20(constants.getAddress("mainnet.mim"));
        } else if (block.chainid == ChainId.Avalanche) {
            degenBox = IBentoBoxV1(constants.getAddress("avalanche.degenBox"));
            safe = constants.getAddress("avalanche.safe.ops");
            mim = ERC20(constants.getAddress("avalanche.mim"));
        }
        startBroadcast();
        ArvinDegenNFT nft = new ArvinDegenNFT("", msg.sender);
        ARV arv = new ARV();
        VIN vin = new VIN();
        IN _in = new IN();

        MasterChef mc = new MasterChef(address(arv), address(vin), address(_in), address(0), block.timestamp);
        CauldronOwner owner = new CauldronOwner(safe, mim);
        CauldronV4 cauldronV4MC = new CauldronV4(degenBox, mim, address(mc), address(nft));

        if (!testing) {
            owner.setOperator(safe, true);
            owner.transferOwnership(safe, true, false);
            cauldronV4MC.setFeeTo(safe);
            cauldronV4MC.transferOwnership(address(safe), true, false);
        }

        stopBroadcast();
    }
}
