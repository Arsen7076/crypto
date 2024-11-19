// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ENERGYCoin {
    string public name = "ENERGY Coin";
    string public symbol = "NRG";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public admin; // Admin address
    uint256 public electricityPrice; // Price of 1 kWh of electricity
    uint256 public oilPrice; // Price of 1 barrel of Brent oil
    uint256 public gasPrice; // Price of 1 cubic meter of gas

    uint256 public discountBasisPoints; // Discount (in basis points, 10000 = 100%)

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event AdminUpdatedPrices(uint256 electricityPrice, uint256 oilPrice, uint256 gasPrice);
    event DiscountUpdated(uint256 discountBasisPoints);

    constructor() {
        admin = msg.sender;
        discountBasisPoints = 0; // Default no discount
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    // Admin can update the commodity prices manually
    function updatePrices(
        uint256 _electricityPrice,
        uint256 _oilPrice,
        uint256 _gasPrice
    ) external onlyAdmin {
        require(_electricityPrice > 0, "Electricity price must be positive");
        require(_oilPrice > 0, "Oil price must be positive");
        require(_gasPrice > 0, "Gas price must be positive");

        electricityPrice = _electricityPrice;
        oilPrice = _oilPrice;
        gasPrice = _gasPrice;

        emit AdminUpdatedPrices(electricityPrice, oilPrice, gasPrice);
    }

    // Admin can set a discount (up to 30%)
    function setDiscount(uint256 _discountBasisPoints) external onlyAdmin {
        require(_discountBasisPoints <= 3000, "Max discount is 30%");
        discountBasisPoints = _discountBasisPoints;

        emit DiscountUpdated(discountBasisPoints);
    }

    // Calculate the price of 1 NRG based on the formula
    function getTokenPrice() public view returns (uint256) {
        uint256 electricityCost = electricityPrice * 5; // Cost of 5 kWh
        uint256 oilCost = (oilPrice * 20) / 100; // 20% of oil price
        uint256 gasCost = gasPrice / 100; // 1% of gas price

        return electricityCost + oilCost + gasCost;
    }

    // Mint new tokens (admin only)
    function mint(address to, uint256 amount) external onlyAdmin {
        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    // Transfer tokens with pricing enforcement
    function transfer(address to, uint256 amount) external {
        uint256 tokenPrice = getTokenPrice();
        uint256 minPrice = (tokenPrice * (10000 - discountBasisPoints)) / 10000;

        // Ensure the sender has enough balance
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        // Check if transaction meets the price requirements
        require(
            tx.origin.balance >= amount * minPrice,
            "Transaction below valid price range"
        );

        // Process the transfer
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
    }
}
