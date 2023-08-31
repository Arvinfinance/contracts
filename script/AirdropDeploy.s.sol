pragma solidity ^0.8.13;
import "utils/BaseScript.sol";

contract AirDropDeployScript is BaseScript {
    function deploy() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(deployerKey);
        AirDrop ad = new AirDrop(
            0x88f5734e205cb6f4c68a76c6fc1a3cd4813935c6efec3ead602df262fea4671c,
            200 ether,
            address(0xB544EA96CB338894e27f28ddAf5478ADDe5Db2Da),
            1696118400
        );
        vm.stopBroadcast();
    }
}
