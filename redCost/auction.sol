// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ScandinavianAuction is OwnerIsCreator, ReentrancyGuard {
    IERC721 public immutable nft;
    IERC20 public immutable token;

    struct Auction {
        uint256 tokenId;
        uint256 startPrice;
        uint256 currentPrice;
        uint256 startTime;
        uint256 endTime;
        uint256 minBid;
        uint256 minBuyers;
        address highestBidder;
        bool isActive;
    }

    uint256 public auctionCount;
    mapping(uint256 => Auction) public auctions;

    event AuctionCreated(uint256 indexed auctionId, uint256 indexed tokenId, uint256 startPrice, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 newPrice);
    event AuctionFinalized(uint256 indexed auctionId, address winner, uint256 finalPrice);
    event AuctionCancelled(uint256 indexed auctionId);

    constructor(IERC721 _nft, IERC20 _token) {
        nft = _nft;
        token = _token;
    }

    function createAuction(uint256 tokenId, uint256 startPrice, uint256 duration, uint256 minBid, uint256 minBuyers) external onlyOwner {
        require(duration >= 72 hours && duration <= 28 days, "Invalid auction duration");
        
        uint256 endTime = block.timestamp + duration;
        auctions[auctionCount] = Auction({
            tokenId: tokenId,
            startPrice: startPrice,
            currentPrice: startPrice,
            startTime: block.timestamp,
            endTime: endTime,
            minBid: minBid,
            minBuyers: minBuyers,
            highestBidder: address(0),
            isActive: true
        });

        emit AuctionCreated(auctionCount, tokenId, startPrice, endTime);
        auctionCount++;
    }

    function placeBid(uint256 auctionId, uint256 bidAmount) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.isActive, "Auction is not active");
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(bidAmount >= auction.minBid, "Bid is below the minimum bid");
        require(bidAmount < auction.currentPrice, "Bid must be lower than current price");
        
        uint256 decrement = auction.currentPrice - bidAmount;
        token.transferFrom(msg.sender, address(this), decrement);
        auction.currentPrice = bidAmount;
        auction.highestBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, bidAmount);
    }

    function finalizeAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.isActive, "Auction is not active");
        require(block.timestamp >= auction.endTime, "Auction is not yet finished");
        
        auction.isActive = false;
        if (auction.highestBidder != address(0)) {
            nft.transferFrom(address(this), auction.highestBidder, auction.tokenId);
            emit AuctionFinalized(auctionId, auction.highestBidder, auction.currentPrice);
        } else {
            emit AuctionCancelled(auctionId);
        }
    }

    function cancelAuction(uint256 auctionId) external onlyOwner {
        Auction storage auction = auctions[auctionId];
        require(auction.isActive, "Auction is not active or already ended");
        
        auction.isActive = false;
        emit AuctionCancelled(auctionId);
    }
}
