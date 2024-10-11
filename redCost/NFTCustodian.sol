// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract NFTCustodiann is OwnerIsCreator, ReentrancyGuard {
    // Event declarations
    event NFTDeposited(address indexed owner, address indexed nftAddress, uint256 indexed tokenId, uint256 index);
    event NFTWithdrawn(address indexed owner, address indexed nftAddress, uint256 indexed tokenId, uint256 index);
    event AuctionContractSet(address indexed auctionContract);

    address public auctionContract;

    // This struct stores information about each NFT held by the contract.
    struct NFTData {
        address owner;
        address nftAddress;
        uint256 tokenId;
        bool isAuctionActive;
        string tokenURI;
        uint256 tokenIndex;
    }

    // This mapping tracks all NFTs held by the contract.
    mapping(uint256 => NFTData) public nftRegistry;
    uint256 public nextNftIndex = 0;

    modifier onlyAuctionContract() {
        require(msg.sender == auctionContract, "Only auction contract can call");
        _;
    }

    /**
     * @dev Sets the auction contract address. Can only be set once.
     * @param _auctionContract The address of the auction contract.
     */
    function setAuctionContract(address _auctionContract) external onlyOwner {
        require(_auctionContract != address(0), "Invalid auction contract");
        require(auctionContract == address(0), "Auction contract already set");
        auctionContract = _auctionContract;
        emit AuctionContractSet(_auctionContract);
    }

    /**
     * @dev Deposits an NFT into the contract for auction.
     * @param nftAddress The contract address of the NFT.
     * @param tokenId The ID of the NFT being deposited.
     */
    function depositNFT(address nftAddress, uint256 tokenId) external nonReentrant {
        ERC721 nft = ERC721(nftAddress);
        require(nft.ownerOf(tokenId) == msg.sender, "You must own the NFT to deposit it.");
        nft.transferFrom(msg.sender, address(this), tokenId);
        string memory _tokenURI = ""; // Optionally fetch or store tokenURI if needed

        uint256 index = nextNftIndex;
        nextNftIndex += 1;
        nftRegistry[index] = NFTData({
            owner: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            isAuctionActive: true,
            tokenURI: _tokenURI,
            tokenIndex: index
        });

        emit NFTDeposited(msg.sender, nftAddress, tokenId, index);
    }

    /**
     * @dev Withdraws an NFT from the contract after an auction.
     * @param index The index of the NFT in the registry.
     */
    function withdrawNFT(uint256 index) internal nonReentrant {
        NFTData storage data = nftRegistry[index];
        require(!data.isAuctionActive, "Cannot withdraw while the auction is active.");

        ERC721(data.nftAddress).transferFrom(address(this), data.owner, data.tokenId);
        delete nftRegistry[index];

        emit NFTWithdrawn(data.owner, data.nftAddress, data.tokenId, index);
    }

    /**
     * @dev Transfers an NFT to a new owner after an auction is completed.
     * @param index The index of the NFT in the registry.
     * @param newOwner The address of the new owner.
     */
    function endAuction(uint256 index, address newOwner) external onlyAuctionContract {
        NFTData storage data = nftRegistry[index];
        require(data.isAuctionActive, "Auction not active");

        data.isAuctionActive = false;
        data.owner = newOwner;

        withdrawNFT(index);
    }
}
