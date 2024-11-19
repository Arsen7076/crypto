// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";


// import "@openzeppelin/contracts/access/Ownable.sol";

contract RDCToken is ERC20, OwnerIsCreator {
    address payable public platformWallet;
    address payable public gasWallet;
    address public marketContract; // Address of the Market contract

    uint256 public constant EXCHANGE_RATE = 100000000; // 1 ETH = 100000000 Tokens

    // Mapping to track allowed transfer recipients
    mapping(address => bool) public allowedTransfers;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 ethSpent);
    event TransferAllowed(address indexed addr, bool status);
    event MarketContractSet(address indexed market);

    constructor(
        string memory name,
        string memory symbol,
        address payable _platformWallet,
        address payable _gasWallet
    ) ERC20(name, symbol) {
        require(_platformWallet != address(0), "Invalid platform wallet");
        require(_gasWallet != address(0), "Invalid gas wallet");
        platformWallet = _platformWallet;
        gasWallet = _gasWallet;
        _mint(address(this), 1000000 * 10 ** decimals()); // Mint initial tokens to the contract
        _mint(address(msg.sender), 1000 * 1e18 * 10 ** decimals()); // Mint initial tokens to the contract
    }

    // Function to set the Market contract address
    function setMarketContract(address _marketContract) external onlyOwner {
        require(_marketContract != address(0), "Invalid market contract");
        marketContract = _marketContract;
        allowedTransfers[_marketContract] = true;
        emit MarketContractSet(_marketContract);
    }

    // Function to allow or disallow transfers to specific addresses
    function setAllowedTransfer(address _addr, bool _status) external onlyOwner {
        allowedTransfers[_addr] = _status;
        emit TransferAllowed(_addr, _status);
    }

    // Function to buy tokens by sending ETH
    function buy() external payable {
        require(marketContract != address(0), "Market contract not set");
        require(msg.value > 0, "Must send ETH to buy tokens");

        uint256 platformFee = (msg.value * 2) / 100; // 2% platform fee
        uint256 gasFee = (msg.value * 1) / 100; // 1% gas fee
        uint256 netEth = msg.value - platformFee - gasFee;

        uint256 tokensToMint = netEth * EXCHANGE_RATE;

        require(balanceOf(address(this)) >= tokensToMint, "Not enough tokens in reserve");

        _transfer(address(this), msg.sender, tokensToMint);

        // Transfer fees
        (bool platformSent, ) = platformWallet.call{value: platformFee}("");
        require(platformSent, "Failed to send platform fee");

        (bool gasSent, ) = gasWallet.call{value: gasFee}("");
        require(gasSent, "Failed to send gas fee");

        emit TokensPurchased(msg.sender, tokensToMint, msg.value);
    }

    // Function to withdraw ETH from the contract (onlyOwner)
    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient ETH balance");
        (bool sent, ) = owner().call{value: amount}("");
        require(sent, "Failed to withdraw ETH");
    }
}
