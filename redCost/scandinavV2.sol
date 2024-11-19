// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INFTCustodian {
    function nftRegistry(uint256 index) external view returns (
        address owner,
        address nftAddress,
        uint256 tokenId,
        bool isAuctionActive,
        string memory tokenURI,
        uint256 tokenIndex
    );
    function endAuction(uint256 index, address newOwner) external;
}

interface INFTStaking {
    function allocate(uint256 amount) external;
}

contract Market is OwnerIsCreator, ReentrancyGuard {
    // State variables
    INFTCustodian public custodian;
    IERC20 public rdcToken;
    INFTStaking public nftStaking;

    struct Auction {
        uint256 index; // NFT index in the custodian
        uint256 currentPrice; // Current price in tokens
        uint256 decrementStep; // Step size in tokens
        bool isActive;
        address ownerOf;
        uint256 startTime;
        uint256 endTime;
    }

    struct User {
        uint256 referralCount;
        address referrer;
        uint256 tokensPurchased; // To track if user bought tokens worth $30
        bool hasClaimedAirDrop;
    }

    // Mappings
    mapping(uint256 => Auction) public auctions; // NFT index to Auction
    mapping(address => User) public users;

    // Wallets
    address payable public platformWallet;
    address payable public gasWallet;

    // Constants
    uint256 public constant MINIMUM_PRICE = 99 * 10 ** 18; // $99, assuming token has 18 decimals
    uint256 public constant MINIMUM_STEP = 2 * 10 ** 18; // $2
    uint256 public constant MULTIPLE_STEP = 125 * 10 ** 18; // $125
    uint256 public constant REGISTRATION_BONUS = 10 * 10 ** 18; // $10 in tokens
    uint256 public constant AIRDROP_AMOUNT = 5 * 10 ** 18; // Example amount, $5 in tokens

    // Events
    event PriceDecreased(uint256 indexed tokenId, uint256 newPrice, address whoDecreased);
    event AuctionConcluded(uint256 indexed tokenId, address buyer, uint256 price);
    event ReferralRegistered(address indexed user, address indexed referrer);
    event CommissionDistributed(uint256 tokenId, uint256 platformFee, uint256 gasFee, uint256 nftFee);
    event ReferralRewardDistributed(address referrer, uint256 reward);
    event UserRegistered(address indexed user, address indexed referrer, uint256 bonus);
    event TokensPurchased(address indexed user, uint256 amount, uint256 ethSpent);
    event TokensWithdrawn(address indexed user, uint256 amount);
    event AirDropClaimed(address indexed user, uint256 amount);

    // Modifiers
    modifier onlyActiveAuction(uint256 tokenId) {
        require(auctions[tokenId].isActive, "Auction not active");
        _;
    }

    // Constructor
    constructor(
        address _custodian,
        address _rdcTokenAddress,
        address payable _platformWallet,
        address payable _gasWallet
        // address _nftStaking
    ) {
        require(_custodian != address(0), "Invalid custodian address");
        require(_rdcTokenAddress != address(0), "Invalid RDC Token address");
        require(_platformWallet != address(0), "Invalid platform wallet");
        require(_gasWallet != address(0), "Invalid gas wallet");
        // require(_nftStaking != address(0), "Invalid NFT staking address");

        custodian = INFTCustodian(_custodian);
        rdcToken = IERC20(_rdcTokenAddress);
        platformWallet = _platformWallet;
        gasWallet = _gasWallet;
        // nftStaking = INFTStaking(_nftStaking);
    }

    // Function to register a new user with a referrer
    function register(address referrer) external nonReentrant {
        require(users[msg.sender].referrer == address(0), "Already registered");
        if (referrer == address(0) || referrer == msg.sender) {
            referrer = platformWallet; // Assign platform as referrer
        }
        require(
            users[referrer].referrer != address(0) || referrer == platformWallet,
            "Invalid referrer"
        );

        users[msg.sender].referrer = referrer;
        users[referrer].referralCount += 1;

        // Assign registration bonus
        require(rdcToken.transfer(msg.sender, REGISTRATION_BONUS), "Bonus transfer failed");

        emit UserRegistered(msg.sender, referrer, REGISTRATION_BONUS);
        emit ReferralRegistered(msg.sender, referrer);
    }

    // Function to set auction parameters
    function setAuctionParameters(
        uint256 tokenIndex,
        uint256 price,
        uint256 _step,
        uint8 _days
    ) external onlyOwner {
        require(price >= MINIMUM_PRICE, "Price must be at least $99");
        require(
            _step >= MINIMUM_STEP ,//&& (_step % MULTIPLE_STEP == 0),
            "Step must be at least $2 and a multiple of $125"
        );

        (
        address _owner,
        address nftAddress,
        uint256 tokenId,
        bool isAuctionActive,
        string memory tokenURI,
        uint256 tokenIdx
                        ) = custodian.nftRegistry(tokenIndex); 
        require(isAuctionActive, "Auction is not allowed");

        auctions[tokenIndex] = Auction({
            index: tokenIndex,
            currentPrice: price,
            decrementStep: _step,
            isActive: true,
            ownerOf: _owner,
            startTime: block.timestamp,
            endTime: block.timestamp + (_days * 1 days)
        });
    }

    // Function to decrease auction price
    function decreaseAuctionPrice(uint256 tokenIndex) external nonReentrant onlyActiveAuction(tokenIndex) {
        Auction storage auction = auctions[tokenIndex];

        // Transfer decrementStep tokens from sender to contract
        require(
            rdcToken.transferFrom(msg.sender, address(this), auction.decrementStep),
            "Failed to transfer tokens"
        );

        uint256 decreaseAmount = (auction.decrementStep * 75) / 100;
        uint256 commissionAmount = (auction.decrementStep * 20) / 100;
        uint256 referralReward = (auction.decrementStep * 5) / 100;

        auction.currentPrice -= decreaseAmount;

        // Distribute commission
        uint256 platformFee = (commissionAmount * 50) / 100; // 10% of step
        uint256 remainingCommission = commissionAmount - platformFee; // 10% of step
        // Split remaining commission equally between gasWallet and NFT staking
        uint256 gasFee = remainingCommission / 2;
        uint256 nftFee = remainingCommission - gasFee;

        // Transfer fees
        require(
            rdcToken.transfer(platformWallet, platformFee),
            "Platform fee transfer failed"
        );
        require(
            rdcToken.transfer(gasWallet, gasFee),
            "Gas fee transfer failed"
        );

        // Allocate NFT fee to staking contract
        // nftStaking.allocate(nftFee);

        emit CommissionDistributed(tokenIndex, platformFee, gasFee, nftFee);

        // Handle referral reward
        User storage user = users[msg.sender];
        if (user.referrer != address(0) && user.referralCount > 10) {
            uint256 rewardPercentage;
            if (user.referralCount > 30) {
                rewardPercentage = 5;
            } else if (user.referralCount > 20) {
                rewardPercentage = 4;
            } else {
                rewardPercentage = 2;
            }
            uint256 reward = (referralReward * rewardPercentage) / 100;
            require(rdcToken.transfer(user.referrer, reward), "Referral reward transfer failed");
            emit ReferralRewardDistributed(user.referrer, reward);

            // Allocate remaining referral reward to NFT staking
            // uint256 remainingReferral = referralReward - reward;
            // nftStaking.allocate(remainingReferral);
        } 
        // else {
        //     // Allocate entire referral reward to NFT staking
        //     nftStaking.allocate(referralReward);
        // }

        emit PriceDecreased(tokenIndex, auction.currentPrice, msg.sender);
    }

    // Function to buy the NFT
    function buy(uint256 tokenIndex) external nonReentrant onlyActiveAuction(tokenIndex) {
        Auction storage auction = auctions[tokenIndex];

        require(
            rdcToken.balanceOf(msg.sender) >= auction.currentPrice,
            "Insufficient balance"
        );
        require(
            rdcToken.allowance(msg.sender, address(this)) >= auction.currentPrice,
            "Insufficient allowance"
        );

        // Calculate platform fee (20% of step)
        uint256 platformFee = (auction.decrementStep * 20) / 100;
        require(
            rdcToken.transferFrom(msg.sender, platformWallet, platformFee),
            "Platform fee transfer failed"
        );

        uint256 netSellerAmount = auction.currentPrice - platformFee;
        require(
            rdcToken.transferFrom(msg.sender, auction.ownerOf, netSellerAmount),
            "Seller amount transfer failed"
        );

        // End the auction
        auction.isActive = false;
        custodian.endAuction(tokenIndex, msg.sender);

        emit AuctionConcluded(tokenIndex, msg.sender, auction.currentPrice);
    }

    // Function to end auction without a buyer
    function endAuction(uint256 tokenIndex) external onlyOwner onlyActiveAuction(tokenIndex) {
        Auction storage auction = auctions[tokenIndex];
        auction.isActive = false;
        custodian.endAuction(tokenIndex, auction.ownerOf);
    }

    // Function to purchase tokens (handled via RDCToken contract's buy())
    // Not needed here unless you implement additional token purchase mechanisms

    // Function to withdraw tokens with conditions
    function withdrawTokens(uint256 amount) external nonReentrant {
        require(amount >= 50 * 10 ** 18, "Minimum withdrawal is $50");
        require(
            users[msg.sender].tokensPurchased >= 30 * 10 ** 18,
            "Must purchase tokens worth at least $30"
        );
        require(
            rdcToken.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        // Transfer tokens to the user
        require(rdcToken.transfer(msg.sender, amount), "Withdrawal transfer failed");

        emit TokensWithdrawn(msg.sender, amount);
    }

    // Function to claim AirDrop
    function claimAirDrop() external nonReentrant {
        require(!users[msg.sender].hasClaimedAirDrop, "AirDrop already claimed");
        require(rdcToken.balanceOf(address(this)) >= AIRDROP_AMOUNT, "Not enough tokens for AirDrop");
        require(rdcToken.transfer(msg.sender, AIRDROP_AMOUNT), "AirDrop transfer failed");

        users[msg.sender].hasClaimedAirDrop = true;

        emit AirDropClaimed(msg.sender, AIRDROP_AMOUNT);
    }


    // Function to get auction details
    function getAuction(uint256 tokenIndex) external view returns (Auction memory) {
        return auctions[tokenIndex];
    }

 
    function setCustodianContract(address _custodianContract) external onlyOwner {
        require(_custodianContract != address(0), "Invalid custodian contract");
        custodian = INFTCustodian(_custodianContract);
    }

}
