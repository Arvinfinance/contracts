// SPDX-License-Identifier: None
pragma solidity ^0.8.0;
import "OpenZeppelin/token/ERC721/extensions/ERC721Enumerable.sol";
import "OpenZeppelin/utils/math/Math.sol";
import "interfaces/IArvinDegenNFT.sol";
import "forge-std/console.sol";

contract ArvinDegenNFT is ERC721Enumerable, IArvinDegenNFT {
    uint256 constant Common = 650; //2%
    uint256 constant Uncommon = 200; //5%
    uint256 constant Rare = 100; //10%
    uint256 constant Legendary = 50; //20%

    constructor(string memory _uri, address _treasury) ERC721("Arvin Degen NFT", "ADNFT") {
        // for (uint256 i = 0; i < 1000; i++) {
        //     _mint(_treasury, i);
        // }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "ipfs://abc/";
    }

    function getRefundRatio(address user) public view returns (uint256) {
        uint256 balance = balanceOf(user);
        uint256 rate = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint tokenId = tokenOfOwnerByIndex(user, i);
            if (tokenId < 650) {
                rate += 2;
            } else if (tokenId < 850) {
                rate += 2;
            } else if (tokenId < 950) {
                rate += 10;
            } else if (tokenId < 1000) {
                rate += 20;
            }
            if (rate >= 20) {
                break;
            }
        }
        return Math.min(rate, 20);
    }
}
