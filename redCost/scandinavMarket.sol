// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

interface INFTCustodian {
      struct NFTData {
        address owner;
        address nftAddress;
        uint256 tokenId;
        bool isAuctionActive;
    }

    // This mapping tracks all NFTs held by the contract.
    function nftRegistry (uint256 tokenId) external view returns(NFTData memory) ;
    function endAuction(uint256 index, address newOwner) external;
}

contract Market is OwnerIsCreator {
    INFTCustodian public custodian;
    IERC20 public rdcToken;

    struct Auction {
        uint256 index;
        uint256 currentPrice;
        uint256 decrementStep;
        bool isActive;
        address lastBider;
    }

    struct User {
        uint256 referralCount;
        address referrer;
    }

    mapping(uint256 => Auction) public auctions; // Index to Auction
    mapping(address => User) public users;

    address payable public platformWallet;
    address payable public gasWallet;

    uint256 public constant MINIMUM_PRICE = 99 ether;
    uint256 public constant MINIMUM_STEP = 2 ether;

    event PriceDecreased(uint256 indexed tokenId, uint256 newPrice);

    constructor(
        address _custodian,
        address _rdcTokenAddress,
        address payable _platformWallet,
        address payable _gasWallet
    ) {
        custodian = INFTCustodian(_custodian);
        rdcToken = IERC20(_rdcTokenAddress);
        platformWallet = _platformWallet;
        gasWallet = _gasWallet;
    }

    function setAuctionParameters(uint256 tokenId, uint256 price, uint256 step) external onlyOwner {
        require(price >= MINIMUM_PRICE, "Price must be at least $99");
        require(step >= MINIMUM_STEP, "Step must be at least $2");
        require(custodian.nftRegistry(tokenId).isAuctionActive, "Auctoin is not allowed ");
        // custodian.registerNFT(tokenId, msg.sender);
        uint256 index = tokenId; // Assuming tokenId is used as index
        auctions[index] = Auction({
            index: index,
            currentPrice: price,
            decrementStep: step,
            isActive: true,
            lastBider : address (custodian.nftRegistry(tokenId).owner)
        });
    }

    function decreaseAuctionPrice(uint256 tokenId) external {
        Auction storage auction = auctions[tokenId];
        require(auction.isActive, "Auction not active");
        require(rdcToken.transferFrom(msg.sender, address(this), auction.decrementStep), "Failed to transfer tokens");

        uint256 decreaseAmount = (auction.decrementStep * 75) / 100;
        uint256 platformFee = (auction.decrementStep * 20) / 100;
        uint256 referralReward = (auction.decrementStep * 5) / 100;

        auction.currentPrice -= decreaseAmount;
        auction.lastBider = msg.sender;
        rdcToken.transfer(platformWallet, platformFee * 50 / 100);
        rdcToken.transfer(gasWallet, platformFee * 50 / 100);

        User memory user = users[msg.sender];
        if (user.referralCount > 10) {
            uint256 rewardPercentage = user.referralCount < 20 ? 2 : user.referralCount < 30 ? 4 : 5;
            uint256 reward = (referralReward * rewardPercentage) / 100;
            rdcToken.transfer(user.referrer, reward);
        } 

        emit PriceDecreased(tokenId, auction.currentPrice);
    }

    function endAuction(uint256 tokenId) external onlyOwner {
        Auction storage auction = auctions[tokenId];
        require(auction.isActive, "Auction not active");
        auction.isActive = false;
        custodian.endAuction(tokenId, auction.lastBider);
    }

    function registerReferral(address referrer) external {
        require(users[msg.sender].referrer == address(0), "Referrer already set");
        users[msg.sender].referrer = referrer;
        users[referrer].referralCount++;
    }
}
