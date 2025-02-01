// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./access.sol";

/**
 * @title AirdropVesting
 * @notice Manages an airdrop with:
 *         - 1-month cliff
 *         - 5% monthly unlock (non-accumulating)
 *         - Each month must be claimed only after the correct time has passed
 *
 * How it works:
 *  - Admin calls `assignAirdrop(user, amount, startTimestamp)`
 *  - User waits until (startTimestamp + 30 days) to claim monthIndex=0 (the first 5%)
 *  - Next month (monthIndex=1) can be claimed after an additional 30 days, and so on.
 *  - If a user skips claiming in one month, it does NOT accumulate or roll over.
 */
contract AirdropVesting is AccessControlBase {
    ERC20 public token;

    struct AirdropInfo {
        uint256 totalAlloc;      // total tokens allocated in this airdrop
        uint256 startTimestamp;  // when the cliff countdown begins
        bool isActive;           // if true, user can claim; if false, no airdrop
        // monthIndex => claimed or not
        mapping(uint256 => bool) claimedMonth;
    }

    // user => AirdropInfo
    mapping(address => AirdropInfo) public airdrops;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    event AirdropAssigned(address indexed user, uint256 amount, uint256 startTime);
    event AirdropClaimed(address indexed user, uint256 monthIndex, uint256 amount);
    event AirdropRevoked(address indexed user);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor(address _token) {
        require(_token != address(0), "Zero token address");
        token = ERC20(_token);
    }

    // ------------------------------------------------------------------------
    // Airdrop Management
    // ------------------------------------------------------------------------

    /**
     * @dev Assign an airdrop to a user. 
     *      `startTimestamp` is when the 1-month cliff countdown starts.
     */
    function assignAirdrop(
        address user, 
        uint256 amount, 
        uint256 startTimestamp
    ) external onlyAdminOrOwner {
        require(user != address(0), "Zero user address");
        require(amount > 0, "Zero allocation");

        AirdropInfo storage ad = airdrops[user];
        ad.totalAlloc = amount;
        ad.startTimestamp = startTimestamp;
        ad.isActive = true;

        emit AirdropAssigned(user, amount, startTimestamp);
    }

    /**
     * @dev Optionally revoke a user's airdrop if needed.
     *      This sets `isActive = false`. If you need to reclaim tokens, 
     *      you'd transfer them back from the user if not yet claimed, 
     *      or handle that off-chain.
     */
    function revokeAirdrop(address user) external onlyAdminOrOwner {
        AirdropInfo storage ad = airdrops[user];
        require(ad.isActive, "Already inactive");
        ad.isActive = false;
        emit AirdropRevoked(user);
    }

    // ------------------------------------------------------------------------
    // Claim Logic
    // ------------------------------------------------------------------------

    /**
     * @dev User claims the monthly 5% at `monthIndex`.
     *      - If they skip a month, it does NOT accumulate.
     *      - We also check that enough time (monthIndex * 30 days) has passed 
     *        beyond the 1-month cliff.
     */
    function claim(uint256 monthIndex) external notBlacklisted isEnabled {
        AirdropInfo storage ad = airdrops[msg.sender];
        require(ad.isActive, "No active airdrop for sender");

        // 1. The cliff ends at `ad.startTimestamp + 30 days`.
        uint256 cliffEnd = ad.startTimestamp + 30 days;
        require(block.timestamp >= cliffEnd, "Cliff not passed");

        // 2. Check that we haven't claimed this month
        require(!ad.claimedMonth[monthIndex], "Already claimed this month");

        // 3. Check that the correct time for this month has passed
        //    monthIndex=0 => can claim any time after cliffEnd
        //    monthIndex=1 => can claim after cliffEnd + 30 days
        //    monthIndex=2 => after cliffEnd + 60 days, etc.
        uint256 requiredTime = cliffEnd + (monthIndex * 30 days);
        require(block.timestamp >= requiredTime, "Too early for this month index");

        // 4. Calculate 5% of totalAlloc
        //    Non-accumulating means if you miss monthIndex=1, 
        //    you cannot claim 10% at monthIndex=2. It's still 5%.
        uint256 claimable = (ad.totalAlloc * 5) / 100;

        // 5. Mark claimed
        ad.claimedMonth[monthIndex] = true;

        // 6. Transfer tokens
        bool ok = token.transfer(msg.sender, claimable);
        require(ok, "Token transfer failed");

        emit AirdropClaimed(msg.sender, monthIndex, claimable);
    }

    // ------------------------------------------------------------------------
    // View Helpers
    // ------------------------------------------------------------------------

    /**
     * @dev Whether or not `user` has claimed for `monthIndex`.
     */
    function hasClaimed(address user, uint256 monthIndex) external view returns (bool) {
        return airdrops[user].claimedMonth[monthIndex];
    }

    /**
     * @dev Returns a user's total airdrop allocation (if any).
     */
    function getUserAllocation(address user) external view returns (uint256) {
        return airdrops[user].totalAlloc;
    }

    /**
     * @dev Check if the airdrop is still active for a user.
     */
    function isAirdropActive(address user) external view returns (bool) {
        return airdrops[user].isActive;
    }
}
