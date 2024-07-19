// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

contract RedCostNFT is ERC721URIStorage, OwnerIsCreator {
    uint256 private _tokenIds;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    /**
     * @dev Mint a new NFT.
     * @param to The address of the recipient who will receive the NFT.
     * @param tokenURI The URI for the token metadata.
     * @return tokenId The ID of the minted token.
     */
    function mint(address to, string memory tokenURI) public onlyOwner returns (uint256) {
        _tokenIds++;
        uint256 newTokenId = _tokenIds;
        _mint(to, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        return newTokenId;
    }
}


// User approve nft for custodian contract
// after that deposit nft
// Creator set auction parameters and start auction
// Buyer who hes our tokens
// now buyer balance hes 999 ether(token)
// Also owner need set step for decreasing 20 ether
// User will give approve for tokens before decreasing
// Now for buy user will approve price count and call buy function
// In the end buyer can wildrow his nft