// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./access.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface OldReferral {
    function _inviter(address user) external view returns (address referer);
}

contract ReferralContract is AccessControlBase {
    // ------------------------------------------------------------------------
    // Token & Basic Referral Settings
    // ------------------------------------------------------------------------
    ERC20 public token;           // The token used for referral payouts
    uint256 public refLevel1Percent = 3; // 3% (Level 1 referral commission)
    address public presaleAddress;

    // Track who referred whom (only one immediate referrer per user)
    mapping(address => address) public referrerOf;

    // Track the custom referral percentage set by the admin for each user
    mapping(address => uint256) public customReferralPercent;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    event ReferralSet(address indexed user, address indexed referrer);
    event ReferralPaid(address indexed referrer, uint256 amount);
    event ReferralPercentsUpdated(address indexed user, uint256 newPercent);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor(address _token) {
        require(_token != address(0), "Zero token address");

        token = ERC20(_token);
    }

    modifier checkPaying() {
        require(presaleAddress != address(0), "Presale address not set yet");
        require(msg.sender == presaleAddress || msg.sender == owner, "Unauthorized");
        _;
    }

    // ------------------------------------------------------------------------
    // Referral Setting
    // ------------------------------------------------------------------------
    function setReferrer(address user, address ref) external onlyAdminOrOwner {
        require(user != address(0), "User = zero");
        require(ref != address(0),  "Ref = zero");
        require(user != ref,        "Cannot self-refer");

        // Prevent referrer change if already set
        require(referrerOf[user] == address(0), "Referrer already set");
        referrerOf[user] = ref;
        emit ReferralSet(user, ref);
    }
    

    function updateReferrer(address user, address newReferrer) external onlyOwner {
        require(user != address(0), "User cannot be zero");
        require(newReferrer != address(0), "New referrer cannot be zero");
        require(user != newReferrer, "Cannot self-refer");

        // Allow admin to update referrer before any payout occurs
        referrerOf[user] = newReferrer;
        emit ReferralSet(user, newReferrer);
    }
    // ------------------------------------------------------------------------
    // Immediate Referral Payout
    // ------------------------------------------------------------------------
    function payReferral(address buyer, uint256 tokensBought) external checkPaying {
        require(buyer != address(0), "Buyer = zero");
        require(tokensBought > 0, "Nothing bought");

        address referrer = referrerOf[buyer];
        if (referrer != address(0) && referrer != buyer) {
            uint256 referralPercent = customReferralPercent[referrer] > 0
                ? customReferralPercent[referrer] 
                : refLevel1Percent;

            uint256 bonus = (tokensBought * referralPercent) / 100;

            require(token.balanceOf(presaleAddress) >= bonus, "Presale has insufficient tokens");
            require(token.transferFrom(presaleAddress, referrer, bonus), "Referral payout failed");
            emit ReferralPaid(referrer, bonus);
        }
    }

    // ------------------------------------------------------------------------
    // Admin: Adjust Referral Percentages
    // ------------------------------------------------------------------------
    function setCustomReferralPercent(address user, uint256 newPercent) external onlyOwner {
        require(user != address(0), "User cannot be zero");
        require(newPercent > 0 && newPercent <= 50, "Referral percent must be between 1 and 50");


        customReferralPercent[user] = newPercent;
        emit ReferralPercentsUpdated(user, newPercent);
    }

    function setPresaleAddress(address _presaleAddress) external onlyOwner {
        require(_presaleAddress != address(0), "Presale need to be real address");
        presaleAddress = _presaleAddress;
    }

    // ------------------------------------------------------------------------
    // Migration of Referrals from Old Contract
    // ------------------------------------------------------------------------
    function migrateReferrals(address oldReferralContract, address[] calldata users) external onlyOwner {
        require(oldReferralContract != address(0), "Old referral contract address is zero");

        OldReferral oldContract = OldReferral(oldReferralContract);
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            require(user != address(0), "User address cannot be zero");

            if (referrerOf[user] == address(0)) {
                address referrer = oldContract._inviter(user);
                if (referrer == address(0)) {
                    referrer = owner; // Default to owner if no referrer found
                }
                require(referrerOf[user] == address(0) || referrerOf[user] == referrer, "Cannot change referrer");

                referrerOf[user] = referrer;
                emit ReferralSet(user, referrer);
            }
        }
    }
    function getReferrer(address user) external view returns (address) {
        return referrerOf[user];
    }
}
