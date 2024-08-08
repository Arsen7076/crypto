// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract RDCToken is ERC20, OwnerIsCreator {
    address payable public platformWallet;
    address payable public gasWallet;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 bnbSpent);

    constructor(
        string memory name,
        string memory symbol,
        address payable _platformWallet,
        address payable _gasWallet
    ) ERC20(name, symbol) {
        platformWallet = _platformWallet;
        gasWallet = _gasWallet;
        _mint(address(this), 1000000 * 10 ** decimals()); // Mint initial tokens to the contract
    }

    function buy() external payable {
        uint256 platformFee = ( msg.value * 2) / 100; // 2% platform fee
        uint256 gasFee = ( msg.value * 1) / 100; // 1% gas fee
        uint256 netAmount =  (msg.value - platformFee - gasFee) * 1000000000 ;

        // require(balanceOf(address(this)) >= netAmount, "Not enough tokens in the reserve");

        _mint( msg.sender, netAmount);
        (bool sent, ) = platformWallet.call{value: platformFee}("");
        require(sent, "Failed to transfer platform fee");
        (sent, ) = gasWallet.call{value: gasFee}("");
        require(sent, "Failed to transfer gas fee");

        emit TokensPurchased(msg.sender, netAmount, msg.value);
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool sent, ) = owner().call{value: amount}("");
        require(sent, "Failed to withdraw");
    }
}
