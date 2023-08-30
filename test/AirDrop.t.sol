pragma solidity ^0.8.13;
import "utils/BaseTest.sol";
import "../src/periphery/AirDrop.sol";
import "OpenZeppelin/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract AirDropTest is BaseTest {
    function testAirDrop() public {
        ERC20PresetFixedSupply vin = new ERC20PresetFixedSupply("test", "test", 100000 ether, address(this));
        AirDrop ad = new AirDrop(0x88f5734e205cb6f4c68a76c6fc1a3cd4813935c6efec3ead602df262fea4671c, 200 ether, address(vin));
        vin.transfer(address(ad), 10000 ether);
        vm.prank(0x8A473EFb809B1C9eA7A4DD5cDD498e1fAC54Da14);
        bytes32[] memory proofs = new bytes32[](11);
        proofs[0] = 0xc3cfb1583f4ce81b354c8df7edf0869ea20a93a7565b518e281f7d08fa54ebaf;
        proofs[1] = 0x41b99615c6ae19e1e61fd2e2eefe6dc2b35bee74bdcfe4395f1b649899175f97;
        proofs[2] = 0x9ee3d18366a923957cd781b9983edfa772ad9982ea92b09e67d697c0d2f5fcad;
        proofs[3] = 0x83a4602e553bf1b380d0322a4b85b8baa1be83935aea904997dd39fcaa7f2a96;
        proofs[4] = 0x8739de4936e4e3be00cc5b2c7c66c16bc70b3aafc2067b0f71a6ed3137683c0d;
        proofs[5] = 0xb03c40a6bdda76b2789c4ab30458f380f7ca14c73ca9081a0a8061f5499717dc;
        proofs[6] = 0x570b22c62646444103288449421b0516a78ea8330a76ec0030085dc26eb829c2;
        proofs[7] = 0x689e0582418a885623ca49a45f50415e81d48b948faa953515b928d332400958;
        proofs[8] = 0x43119f9e6ac8b899237b777f1da571124712f3970644d7640b984fc3fcf926d2;
        proofs[9] = 0x10ee3f36e0d4c3c937b3e5e283bd2667af7f517f40689b9bc3a1198817651b99;
        proofs[10] = 0xa594043c6c1bc671e1f4b6cd56abea85f8a5a5830fbf74f087535bad843f51b6;
        ad.claim(proofs);
    }
}
