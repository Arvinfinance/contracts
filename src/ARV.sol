// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "BoringSolidity/ERC20.sol";

contract ARV is ERC20WithSupply {
    string public constant symbol = "ARV";
    string public constant name = "ARV";

    constructor() {
        _mint(msg.sender, 1e5 ether);
    }

    //TODO：burn logic
}
