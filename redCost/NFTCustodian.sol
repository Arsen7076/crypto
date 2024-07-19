// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";


contract NFTCustodian is OwnerIsCreator, ReentrancyGuard {
    // Event declarations
    event NFTDeposited(address indexed owner, address indexed nftAddress, uint256 indexed tokenId);
    event NFTWithdrawn(address indexed owner, address indexed nftAddress, uint256 indexed tokenId);
    address auctionContract;
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

    /**
     * @dev Deposits an NFT into the contract for auction.
     * @param nftAddress The contract address of the NFT.
     * @param tokenId The ID of the NFT being deposited.
     */
    function depositNFT(address nftAddress, uint256 tokenId) external nonReentrant {
        ERC721 nft = ERC721(nftAddress);
        require(nft.ownerOf(tokenId) == msg.sender, "You must own the NFT to deposit it.");
        nft.transferFrom(msg.sender, address(this), tokenId);
        string memory _tokenURI = nft.tokenURI(tokenId);
        uint256 index = nextNftIndex;
        nextNftIndex+=1;
        nftRegistry[index] = NFTData({
            owner: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            isAuctionActive: true,
            tokenURI: _tokenURI,
            tokenIndex: index
        });

        emit NFTDeposited(msg.sender, nftAddress, tokenId);
    }

    /**
     * @dev Withdraws an NFT from the contract after an auction.
     * @param index The index of the NFT in the registry.
     */
    function withdrawNFT(uint256 index) external nonReentrant {
        NFTData storage data = nftRegistry[index];
        require(data.owner == msg.sender, "Only the owner can withdraw the NFT.");
        require(!data.isAuctionActive, "Cannot withdraw while the auction is active.");

        ERC721(data.nftAddress).transferFrom(address(this), msg.sender, data.tokenId);
        delete nftRegistry[index];

        emit NFTWithdrawn(msg.sender, data.nftAddress, data.tokenId);
    }

    /**
     * @dev Transfers an NFT to a new owner after an auction is completed.
     * @param newIndex The index of the new owner's record in the NFT registry.
     * @param oldIndex The index of the previous owner's record.
     */
    function transferNFT(uint256 newIndex, uint256 oldIndex) external onlyOwner nonReentrant {
        NFTData storage newData = nftRegistry[newIndex];
        NFTData storage oldData = nftRegistry[oldIndex];

        require(newData.isAuctionActive, "Auction must be active to transfer NFT.");
        require(oldData.isAuctionActive, "Auction must be active to transfer NFT.");

        ERC721(oldData.nftAddress).transferFrom(address(this), newData.owner, oldData.tokenId);
        newData.isAuctionActive = false;
        oldData.isAuctionActive = false;

        emit NFTWithdrawn(newData.owner, oldData.nftAddress, oldData.tokenId);
    }

    /**
     * @dev Marks the auction as complete for a specific NFT.
     * @param index The index of the NFT in the registry.
     */
    function endAuction(uint256 index, address newOwner) external  {
        require(msg.sender == auctionContract, "Only auction contract can end");
        nftRegistry[index].isAuctionActive = false;
        nftRegistry[index].owner = newOwner;
    }

    function setAuctionContract(address _auctionContract)external onlyOwner{
        require(_auctionContract !=address(0), "Can't be address 0");
        auctionContract = _auctionContract;
    }
}
