// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract RedCostToken is ERC20, OwnerIsCreator, ERC20Burnable {
    constructor() ERC20("RedCostToken", "RDC") {
        // Initial mint can be done here if needed
        _mint(msg.sender, 1000000 * 10 ** decimals()); // Minting 1,000,000 RDC for example
        // _mint(address(0x9DE3672f6E3Cf438B3f54B85848343cd0003182A), 1000000 * 10 ** decimals()); // Minting 1,000,000 RDC for example
        // _mint(msg.sender, 1000000 * 10 ** decimals()); // Minting 1,000,000 RDC for example

    }

    /**
     * @dev Allows the owner to mint more tokens.
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
