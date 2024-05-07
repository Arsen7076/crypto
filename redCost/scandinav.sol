// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import "@openzeppelin/contracts/access/Ownable.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ScandinavianAuction is OwnerIsCreator {
    // Minimum constants
    uint256 public constant MINIMUM_PRICE = 99 ether; // Assuming using a stablecoin with 18 decimals
    uint256 public constant MINIMUM_STEP = 2 ether;

    struct NFT {
        uint256 currentPrice;
        uint256 decrementStep;
        bool approved;
    }

    // RDC token for transactions
    IERC20 public rdcToken;

    // Platform wallet for receiving commissions
    address payable public platformWallet;
    address payable public gasWallet; // Separate wallet for gas management

    // NFT details mapped by user
    mapping(address => NFT) public nfts;

    // Referral system
    mapping(address => address) public referrer;
    mapping(address => uint256) public referralsCount;

    event AuctionPriceDecreased(address indexed user, uint256 newPrice);

    constructor(address _rdcTokenAddress, address payable _platformWallet, address payable _gasWallet) {
        rdcToken = IERC20(_rdcTokenAddress);
        platformWallet = _platformWallet;
        gasWallet = _gasWallet;
    }

    function setNFTPriceAndStep(address user, uint256 price, uint256 step) external onlyOwner {
        require(price >= MINIMUM_PRICE, "Price must be at least $99");
        require(step >= MINIMUM_STEP, "Step must be at least $2");

        NFT storage nft = nfts[user];
        nft.currentPrice = price;
        nft.decrementStep = step;
        nft.approved = true;
    }

    function decreaseAuctionPrice(address user) external {
        NFT storage nft = nfts[user];
        require(nft.approved, "NFT settings not approved");
        require(rdcToken.transferFrom(msg.sender, address(this), nft.decrementStep), "Payment failed");

        uint256 decreaseAmount = (nft.decrementStep * 75) / 100;
        uint256 platformFee = (nft.decrementStep * 10) / 100;
        uint256 gasFee = (nft.decrementStep * 10) / 100 / 2;
        uint256 stakingFee = (nft.decrementStep * 10) / 100 / 2;

        nft.currentPrice -= decreaseAmount;
        rdcToken.transfer(platformWallet, platformFee);
        rdcToken.transfer(gasWallet, gasFee);
        // Distribution to staking not implemented here, needs further details

        address ref = referrer[msg.sender];
        if (referralsCount[ref] >= 10) {
            uint256 referralReward = (referralsCount[ref] < 20) ? (nft.decrementStep * 2) / 100 :
                                     (referralsCount[ref] < 30) ? (nft.decrementStep * 4) / 100 :
                                                                  (nft.decrementStep * 5) / 100;
            rdcToken.transfer(ref, referralReward);
        } else {
            rdcToken.transfer(gasWallet, stakingFee); // Assuming extra staking distribution
        }

        emit AuctionPriceDecreased(user, nft.currentPrice);
    }

    function registerReferral(address _referrer) external {
        require(referrer[msg.sender] == address(0), "Referrer already set");
        referrer[msg.sender] = _referrer;
        referralsCount[_referrer]++;
    }
}
