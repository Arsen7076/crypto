// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol"; // For Address.sendValue, if needed
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // If we want reentrancy guard
import "./access.sol"; // Your AccessControlBase
import "./referral.sol"; // Referral Contract Interface
import "./earlyinvestors.sol";  // Vesting Contract
interface  LiquidityManager {
    function checkBalance()external returns(bool);
}
contract Presale is AccessControlBase, ReentrancyGuard {
    using Address for address payable;

    ERC20 public token;           // Token being sold
    ERC20 public usdt;            // USDT (BEP-20)
    ReferralContract public referralContract;
    EarlyInvestors public vestingContract; // Team vesting contract
    address liquidityManager; 
    
    bool public presaleActive = false;

    uint256 public softCap;       // Soft cap for raised funds
    uint256 public hardCap;       // Hard cap for raised funds
    uint256 public totalRaisedBNB; // Total BNB raised
    uint256 public totalRaisedUSDT; // Total USDT raised
    uint256 public minPurchase;   // Min purchase amount
    uint256 public maxPurchase;   // Max purchase amount
    uint256 public tokenPriceInUSDT; // Token price in USDT
    uint256 public tokenPriceInBNB;  // Token price in BNB
    uint256 public discountPrice = 95;
    uint256 public totalTokensSold;

    event PresaleStarted(uint256 start, uint256 end);
    event PresaleStopped();
    event BoughtWithBNB(address indexed buyer, uint256 bnbAmount, uint256 tokens);
    event BoughtWithUSDT(address indexed buyer, uint256 usdtAmount, uint256 tokens);
    event BuyBackExecuted(address indexed buyer, uint256 tokensReturned, uint256 paymentAmount, string paymentType);
    event ReferralContractUpdated(address oldRef, address newRef);
    event VestingContractUpdated(address oldVesting, address newVesting);
    event LiquidityPoolCreated();

    constructor(
        address _token,
        address _usdt,
        address _referral,
        address _vesting,

        uint256 _softCap,
        uint256 _hardCap,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _tokenPriceInUSDT,
        uint256 _tokenPriceInBNB
    ) {
        require(_token != address(0), "Zero token");
        require(_usdt  != address(0), "Zero usdt");
        require(_referral != address(0), "Zero referral");
        require(_vesting  != address(0), "Zero vesting");

        token = ERC20(_token);
        usdt  = ERC20(_usdt);
        referralContract = ReferralContract(_referral);
        vestingContract  = EarlyInvestors(_vesting);


        softCap   = _softCap;
        hardCap   = _hardCap;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        tokenPriceInUSDT = _tokenPriceInUSDT;
        tokenPriceInBNB  = _tokenPriceInBNB;
    }
    modifier hardCapCheck(){
        require(totalTokensSold <= hardCap, "Hard cap limit has been reached");
        _;
    }

    function setDiscount(uint8 _percent) external onlyAdminOrOwner{
        require(_percent < 100, "Discount need be low than 100");
        discountPrice = _percent;
    }
    
    function buyBack(uint256 tokenAmount) external notBlacklisted isEnabled nonReentrant {
        require(presaleActive, "Presale not active");
        require(tokenAmount > 0, "Token amount must be greater than zero");

        // Ensure the contract has enough tokens
        require(token.balanceOf(address(this)) >= tokenAmount, "Not enough tokens in contract");

        // Calculate the current token price (either in BNB or USDT)
        uint256 currentPriceInBNB = tokenPriceInBNB;
        uint256 currentPriceInUSDT = tokenPriceInUSDT;

        // Calculate the 90% discounted price for buying back tokens
        uint256 discountedPriceInBNB = (currentPriceInBNB * discountPrice) / 100; 
        uint256 discountedPriceInUSDT = (currentPriceInUSDT * discountPrice) / 100; 

        // Calculate the total payment the user will receive (either BNB or USDT)
        uint256 totalPaymentBNB = discountedPriceInBNB * tokenAmount;
        uint256 totalPaymentUSDT = discountedPriceInUSDT * tokenAmount;

        // Transfer the tokens back to the contract
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");

        // Decrease the total raised amount and total tokens sold
        totalTokensSold -= tokenAmount;

        // Pay the user in BNB or USDT
        if (currentPriceInBNB > 0) {
            // Transfer BNB to the user
            payable(msg.sender).sendValue(totalPaymentBNB);
            emit BuyBackExecuted(msg.sender, tokenAmount, totalPaymentBNB, "BNB");
        } else {
            // Transfer USDT to the user
            require(usdt.transfer(msg.sender, totalPaymentUSDT), "USDT transfer failed");
            emit BuyBackExecuted(msg.sender, tokenAmount, totalPaymentUSDT, "USDT");
        }
    }

    // Function to buy tokens with BNB
    function buyWithBNB() external payable notBlacklisted isEnabled nonReentrant hardCapCheck {

        require(presaleActive, "Presale not active");
        uint256 bnbAmount = msg.value;
        require(bnbAmount > 0, "Zero BNB sent");

        totalRaisedBNB += bnbAmount;

        uint256 tokens = (bnbAmount * 1e18) / tokenPriceInBNB;
        require(tokens >= minPurchase, "Token count to buy is not enough");
        require(tokens <= maxPurchase, "Token count to buy is higher");

        // Referral logic
      
        uint referralPercent = referralContract.customReferralPercent(referralContract.referrerOf(msg.sender));
        referralPercent == 0 ? 3 : referralPercent;
        token.approve(address(referralContract), (tokens *referralPercent +1)/100);
        referralContract.payReferral(msg.sender, tokens);
        tokens = (tokens * (100 - referralPercent ))/100;
        token.approve(address(vestingContract), tokens);

        // Assign tokens in the vesting contract
        vestingContract.addVestingSchedule(msg.sender, tokens);
        totalTokensSold += tokens;
        emit BoughtWithBNB(msg.sender, bnbAmount, tokens);
    }

    // Function to buy tokens with USDT
    function buyWithUSDT(uint256 usdtAmount) external notBlacklisted isEnabled nonReentrant hardCapCheck{
        require(presaleActive, "Presale not active");
        require(usdtAmount > 0, "Zero USDT amount");

        // Transfer USDT in
        bool ok = usdt.transferFrom(msg.sender, address(this), usdtAmount);
        require(ok, "USDT transferFrom failed");

        totalRaisedUSDT += usdtAmount;

        uint256 tokens = (usdtAmount * 1e18) / tokenPriceInUSDT;
        require(tokens >= minPurchase, "Token count to buy is not enough");
        require(tokens <= maxPurchase, "Token count to buy is higher");
        totalTokensSold += tokens;

        
        referralContract.payReferral(msg.sender, tokens);
        uint referralPercent = referralContract.customReferralPercent(referralContract.referrerOf(msg.sender));

        tokens = (tokens * (100 - referralContract.customReferralPercent(referralContract.referrerOf(msg.sender))))/100;
        token.approve(address(referralContract), (tokens *referralPercent )/100);
        referralContract.payReferral(msg.sender, tokens);
        tokens = (tokens * (100 - referralPercent ))/100;
        token.approve(address(vestingContract), tokens);

        // Assign tokens in the vesting contract
        vestingContract.addVestingSchedule(msg.sender, tokens);

        emit BoughtWithUSDT(msg.sender, usdtAmount, tokens);

            // Check liquidity pool creation
        bool liquidityCreated = LiquidityManager(liquidityManager).checkBalance();
        if (liquidityCreated) {
            presaleActive = false; // Turn off presale
            emit PresaleStopped();

            // Transfer remaining tokens and funds to the owner
            uint256 remainingTokens = token.balanceOf(address(this));
            uint256 remainingUSDT = usdt.balanceOf(address(this));

            if (remainingTokens > 0) {
                token.transfer(owner, remainingTokens);
            }
            if (remainingUSDT > 0) {
                usdt.transfer(owner, remainingUSDT);
            }

            emit LiquidityPoolCreated();
        }
    }

    function updatePresaleParameters(
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _tokenPriceInUSDT,
        uint256 _tokenPriceInBNB,
        bool _presaleActive
    ) external onlyOwner {
        softCap = _softCap;
        hardCap = _hardCap;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        tokenPriceInUSDT = _tokenPriceInUSDT;
        tokenPriceInBNB = _tokenPriceInBNB;
        presaleActive = _presaleActive;
    }

    function setTokenAddress(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        token = ERC20(_token);
    }

    // Setter for USDT address
    function setUsdtAddress(address _usdt) external onlyOwner {
        require(_usdt != address(0), "Invalid USDT address");
        usdt = ERC20(_usdt);
    }

    // Setter for referral contract address
    function setReferralContract(address _referral) external onlyOwner {
        require(_referral != address(0), "Invalid referral contract address");
        referralContract = ReferralContract(_referral);
    }

    // Setter for vesting contract address
    function setVestingContract(address _vesting) external onlyOwner {
        require(_vesting != address(0), "Invalid vesting contract address");
        vestingContract = EarlyInvestors(_vesting);
    }

    function activatePresale() external onlyOwner {
        presaleActive = true;
    }

        // Setter for Liquidity Manager
    function setLiquidityManager(address _liquidityManager) external onlyOwner {
        require(_liquidityManager != address(0), "Invalid liquidity manager address");
        liquidityManager = _liquidityManager;
    }


}
