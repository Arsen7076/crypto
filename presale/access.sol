// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/**
 * @title AccessControlBase
 * @notice Simple contract for ownership and admin/blacklist checks
 *         that other contracts can inherit from.
 */
contract AccessControlBase {
    address public owner;
    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isBlacklisted;
    bool public contractEnabled = true;

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event AdminUpdated(address indexed admin, bool enabled);
    event BlacklistedSet(address indexed user, bool blacklisted);
    event ContractEnabled(bool enabled);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == owner || isAdmin[msg.sender], "Not admin/owner");
        _;
    }

    modifier notBlacklisted() {
        require(!isBlacklisted[msg.sender], "Sender blacklisted");
        _;
    }

    modifier isEnabled() {
        require(contractEnabled, "Contract disabled");
        _;
    }

    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setAdmin(address admin, bool enabled) external onlyOwner {
        isAdmin[admin] = enabled;
        emit AdminUpdated(admin, enabled);
    }

    function setBlacklisted(address user, bool flag) external onlyAdminOrOwner {
        isBlacklisted[user] = flag;
        emit BlacklistedSet(user, flag);
    }

    function setContractEnabled(bool enabled) external onlyOwner {
        contractEnabled = enabled;
        emit ContractEnabled(enabled);
    }
}
