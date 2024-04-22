// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";


contract NFTMarketplace is ERC721, ReentrancyGuard, OwnerIsCreator {
    struct Auction {
        uint256 minPrice;
        uint256 startTime;
        uint256 endTime;
        bool active;
        uint256 highestBid;
        address highestBidder;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => bool) public lockedNFTs;

    constructor() ERC721("NFTMarketplace", "NFTMKT") {}

    function createAuction(uint256 _tokenId, uint256 _minPrice, uint256 _startTime, uint256 _endTime) public onlyOwner {
        require(_startTime < _endTime, "Invalid time range");
        auctions[_tokenId] = Auction({
            minPrice: _minPrice,
            startTime: _startTime,
            endTime: _endTime,
            active: true,
            highestBid: 0,
            highestBidder: address(0)
        });
        lockedNFTs[_tokenId] = true;
    }

    function bid(uint256 _tokenId) public payable nonReentrant {
        Auction storage auction = auctions[_tokenId];
        require(auction.active, "Auction is not active");
        require(block.timestamp >= auction.startTime && block.timestamp <= auction.endTime, "Auction not in session");
        require(msg.value >= auction.minPrice, "Bid below minimum price");
        require(msg.value > auction.highestBid, "Bid not high enough");

        // Refund the previous highest bidder
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
    }

    function endAuction(uint256 _tokenId) public onlyOwner {
        Auction storage auction = auctions[_tokenId];
        require(auction.active, "Auction is not active");
        require(block.timestamp > auction.endTime, "Auction not ended yet");

        auction.active = false;
        lockedNFTs[_tokenId] = false;
        _transfer(address(this), auction.highestBidder, _tokenId);

        // Transfer funds to the owner
        payable(owner()).transfer(auction.highestBid);
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
