// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract NFTCustodian is OwnerIsCreator, ReentrancyGuard {
    // Event declarations
    event NFTDeposited(address indexed owner, address indexed nftAddress, uint256 indexed tokenId, uint256 index);
    event NFTWithdrawn(address indexed owner, address indexed nftAddress, uint256 indexed tokenId, uint256 index);
    event AuctionContractSet(address indexed auctionContract);
    event NFTReturnedToOwner(address indexed owner, address indexed nftAddress, uint256 indexed tokenId, uint256 index);

    address public auctionContract;

    struct NFTData {
        address owner;
        address nftAddress;
        uint256 tokenId;
        bool isAuctionActive;
        string tokenURI;
        uint256 tokenIndex;
    }

    mapping(uint256 => NFTData) public nftRegistry;
    uint256 public nextNftIndex = 0;

    modifier onlyAuctionContract() {
        require(msg.sender == auctionContract, "Only auction contract can call");
        _;
    }

 
    function setAuctionContract(address _auctionContract) external onlyOwner {
        require(_auctionContract != address(0), "Invalid auction contract");
        auctionContract = _auctionContract;
        emit AuctionContractSet(_auctionContract);
    }

    function depositNFT(address nftAddress, uint256 tokenId) external nonReentrant returns (uint256){
        ERC721 nft = ERC721(nftAddress);
        require(nft.ownerOf(tokenId) == msg.sender, "You must own the NFT to deposit it.");
        nft.transferFrom(msg.sender, address(this), tokenId);
        string memory _tokenURI = nft.tokenURI(tokenId);

        uint index = nextNftIndex;
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
        return  index;
    }

    function withdrawNFT(uint256 index) internal nonReentrant {
        NFTData storage data = nftRegistry[index];
        require(!data.isAuctionActive, "Cannot withdraw while the auction is active.");

        ERC721(data.nftAddress).transferFrom(address(this), data.owner, data.tokenId);
        delete nftRegistry[index];

        emit NFTWithdrawn(data.owner, data.nftAddress, data.tokenId, index);
    }

    function endAuction(uint256 index, address newOwner) external onlyAuctionContract {
        NFTData storage data = nftRegistry[index];
        require(data.isAuctionActive, "Auction not active");

        data.isAuctionActive = false;
        data.owner = newOwner;

        withdrawNFT(index);
    }

    /**
     * @dev Allows moderators to return an NFT to the original owner if it fails verification.
     * @param index The index of the NFT in the registry.
     */
    function returnNFTToOwner(uint256 index) external onlyOwner nonReentrant {
        NFTData storage data = nftRegistry[index];

        data.isAuctionActive = false; // Mark auction as inactive for this NFT
        ERC721(data.nftAddress).transferFrom(address(this), data.owner, data.tokenId);

        delete nftRegistry[index];

        emit NFTReturnedToOwner(data.owner, data.nftAddress, data.tokenId, index);
    }
}
