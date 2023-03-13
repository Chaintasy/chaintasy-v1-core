// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Chaintasy is ERC20 {
    constructor() ERC20("Chaintasy", "CTY") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function mint() public {
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

}