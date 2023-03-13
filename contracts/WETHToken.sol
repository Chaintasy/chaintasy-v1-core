// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETHToken is ERC20 {
    constructor() ERC20("Wrapped ETH", "WETH") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function mint() public {
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

}