// SPDX-License-Identifier: None
pragma solidity ^0.8.0;
import "OpenZeppelin/token/ERC1155/ERC1155.sol";
import "OpenZeppelin/utils/math/Math.sol";
import "interfaces/IArvinDegenNFT.sol";

contract ArvinDegenNFT is ERC1155, IArvinDegenNFT {
    string public name;
    string public symbol;

    uint256 constant DIAMOND = 0;
    uint256 constant GOLDEN = 1;
    uint256 constant SILVER = 2;
    uint256 constant BRONZE = 3;

    constructor(string memory _uri, address _treasury) ERC1155(_uri) {
        name = "Arvin Degen NFT";
        symbol = "AD";
        _mint(_treasury, DIAMOND, 111, "");
        _mint(_treasury, GOLDEN, 333, "");
        _mint(_treasury, SILVER, 666, "");
        _mint(_treasury, BRONZE, 2223, "");
    }

    function getRefundRatio(address user) public view returns (uint256) {
        uint256 diamondBalance = balanceOf(user, DIAMOND);
        uint256 goldenBalance = balanceOf(user, GOLDEN);
        uint256 silverBalance = balanceOf(user, SILVER);
        uint256 bronzeBalance = balanceOf(user, BRONZE);
        return Math.min(diamondBalance * 20 + goldenBalance * 10 + silverBalance * 5 + bronzeBalance * 2, 20);
    }
}
