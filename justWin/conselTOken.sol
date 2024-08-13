// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract CounselToken is ERC20, OwnerIsCreator, AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public constant TOTAL_SUPPLY = 30000000 * 10**8;  // 30 million tokens with 8 decimals
    uint256 public salePriceETH;  // Price of one token in terms of Ethereum

    mapping(address => bool) public whitelist;

    // Events
    event TokensPurchased(address indexed buyer, uint256 amountETH, uint256 amountTokens);
    event WhitelistUpdated(address indexed user, bool status);

    constructor(uint256 _initialSalePriceETH) ERC20("Counsel Token", "CT") {
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, msg.sender);
        salePriceETH = _initialSalePriceETH;
        _mint(address(this), TOTAL_SUPPLY);
    }

    function setSalePriceETH(uint256 _newPriceETH) external onlyRole(ADMIN_ROLE) {
        salePriceETH = _newPriceETH;
    }

    function buyTokens() external payable nonReentrant {
        require(whitelist[msg.sender], "Address not whitelisted");
        uint256 tokensToBuy = msg.value / salePriceETH;
        require(tokensToBuy <= balanceOf(address(this)), "Not enough tokens available");

        _transfer(address(this), msg.sender, tokensToBuy);
        emit TokensPurchased(msg.sender, msg.value, tokensToBuy);
    }

    function addToWhitelist(address _user) external onlyRole(ADMIN_ROLE) {
        whitelist[_user] = true;
        emit WhitelistUpdated(_user, true);
    }

    function removeFromWhitelist(address _user) external onlyRole(ADMIN_ROLE) {
        whitelist[_user] = false;
        emit WhitelistUpdated(_user, false);
    }

    function withdrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function manualTokenTransfer(address _to, uint256 _amount) external onlyRole(ADMIN_ROLE) {
        _transfer(address(this), _to, _amount);
    }
}
