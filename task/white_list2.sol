// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IDEXFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IPancakePair {
    function sync() external;
}

interface IDEXRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable
        returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
}

contract MyToken is ERC20 {
    address  public owner ;
    address public  constant ROUTER = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;   //Change with your chain swap router address
    IDEXRouter public  router ;
    address public pair;
    uint public  tokenPrice;
    uint8 public  feePercentage;
    modifier  onlyOwner{
        require(msg.sender == owner, "You aren't owner");
        _;
    } 


    // Define events
    event FeeTransfered(address indexed from, address indexed to, uint256 value);
    event TokensBurned(address indexed burner, uint256 amount);
    event TokensBought(address indexed buyer, uint256 amountSpent, uint256 tokensReceived);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 amountReceived);


    constructor(string memory _name, string memory _symbol, address _mintAddress, uint _amountMint, uint8 _fee, uint _tokenPrice) 
    ERC20(_name, _symbol) {
        owner = msg.sender;
        tokenPrice = _tokenPrice;  //Can be 1
        _mint(_mintAddress, _amountMint);
        // require(_fee <=49, "Fee can't be high than 49%");
        feePercentage = _fee;
    }
    function setPrice(uint _price)external  onlyOwner{
        tokenPrice = _price;
    }

     // Override the transfer function
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountAfterFee = amount - fee;
        if (msg.sender == owner){
                    return super.transfer(recipient, amount);
        }
        // Transfer the fee to a specific address (e.g., the contract owner)
        super.transfer(owner, fee);
        emit  FeeTransfered(recipient, owner, fee);
        
    
        return super.transfer(recipient, amountAfterFee);
    }

    // Override the transferFrom function
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountAfterFee = amount - fee;

        // Transfer the fee to a specific address (e.g., the contract owner)
        if (sender == owner){
            return super.transferFrom(sender, recipient, amount);
        }
        super.transferFrom(sender, owner, fee);
        emit  FeeTransfered(recipient, owner, fee);
        
    
        return super.transferFrom(sender, recipient, amountAfterFee);
    }
    // Buy tokens by sending Ether
    function buyTokens() external payable  {
        require(msg.value > 0, "Value can't be 0");
        uint256 tokenAmount = msg.value/tokenPrice; // 1 ETH = 1 token for simplicity
        _mint(msg.sender, tokenAmount);
        emit TokensBought(msg.sender, msg.value, tokenAmount);

    }
    
    function sellTokens(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        uint256 ethAmount = amount * tokenPrice; // Assuming 1 token = 1 ETH for simplicity
        require(address(this).balance > ethAmount, "In the contract not enough Balance");
        _burn(msg.sender, amount);
        emit TokensSold(msg.sender, amount, ethAmount);
        payable(msg.sender).transfer(ethAmount);
    }

    // Create PancakeSwap pair with Ether
    function createPairWithEther() external onlyOwner returns (address) {
        router = IDEXRouter(ROUTER);
        pair = IDEXFactory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        _approve(address (this), address(router), type(uint256).max);
        return  pair;
    }
  

    function getTimestamp()public  view returns(uint){
        return block.timestamp;
    }   

    // Withdraw Ether from the contract
    function withdrawEther(uint256 amount) external onlyOwner {
        payable(owner).transfer(amount);
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(this), "Cannot withdraw the token of this contract");
        IERC20(token).transfer(owner, amount);
    }

    function burn(uint value)external {
        require(value <= balanceOf(msg.sender), "You Don't have enough tokens");
        _burn(msg.sender, value);
        emit TokensBurned(msg.sender, value);
    }
}