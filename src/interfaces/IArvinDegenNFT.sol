// SPDX-License-Identifier: None
pragma solidity ^0.8.0;
import "OpenZeppelin/token/ERC1155/IERC1155.sol";

interface IArvinDegenNFT is IERC1155 {
    function getRefundRatio(address user) external view returns (uint256);
}
