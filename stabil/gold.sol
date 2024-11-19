// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GoldStablecoin {
    string public name = "Gold Stablecoin";
    string public symbol = "GOLD";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public admin; // Администратор контракта
    uint256 public goldPrice; // Текущая цена золота (в единицах базовой валюты)

    uint256 public discountBasisPoints; // Дисконт в базисных пунктах (10000 = 100%)

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event AdminUpdatedPrice(uint256 goldPrice);
    event DiscountUpdated(uint256 discountBasisPoints);

    constructor() {
        admin = msg.sender;
        discountBasisPoints = 0; // По умолчанию нет скидки
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    // Администратор может обновлять цену золота
    function updateGoldPrice(uint256 _goldPrice) external onlyAdmin {
        require(_goldPrice > 0, "Gold price must be positive");
        goldPrice = _goldPrice;

        emit AdminUpdatedPrice(goldPrice);
    }

    // Администратор может установить дисконт (до 30%)
    function setDiscount(uint256 _discountBasisPoints) external onlyAdmin {
        require(_discountBasisPoints <= 3000, "Max discount is 30%");
        discountBasisPoints = _discountBasisPoints;

        emit DiscountUpdated(discountBasisPoints);
    }

    // Расчёт цены 1 GOLD на основе текущей цены золота
    function getTokenPrice() public view returns (uint256) {
        return (goldPrice * 5) / 100; // 5% от стоимости золота
    }

    // Создание новых токенов (только для администратора)
    function mint(address to, uint256 amount) external onlyAdmin {
        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    // Перевод токенов с учётом ценового ограничения
    function transfer(address to, uint256 amount) external {
        uint256 tokenPrice = getTokenPrice();
        uint256 minPrice = (tokenPrice * (10000 - discountBasisPoints)) / 10000;

        // Убедиться, что у отправителя достаточно токенов
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        // Проверка соответствия цены
        require(
            tx.origin.balance >= amount * minPrice,
            "Transaction below valid price range"
        );

        // Обработка перевода
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
    }
}
