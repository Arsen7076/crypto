// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GrainStablecoin {
    string public name = "Grain Stablecoin";
    string public symbol = "GRN";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public admin; // Администратор контракта
    uint256 public wheatPrice; // Текущая цена пшеницы (в единицах базовой валюты)

    uint256 public discountBasisPoints; // Дисконт в базисных пунктах (10000 = 100%)

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event AdminUpdatedPrice(uint256 wheatPrice);
    event DiscountUpdated(uint256 discountBasisPoints);

    constructor() {
        admin = msg.sender;
        discountBasisPoints = 0; // По умолчанию нет скидки
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    // Администратор может обновлять цену пшеницы
    function updateWheatPrice(uint256 _wheatPrice) external onlyAdmin {
        require(_wheatPrice > 0, "Wheat price must be positive");
        wheatPrice = _wheatPrice;

        emit AdminUpdatedPrice(wheatPrice);
    }

    // Администратор может установить дисконт (до 30%)
    function setDiscount(uint256 _discountBasisPoints) external onlyAdmin {
        require(_discountBasisPoints <= 3000, "Max discount is 30%");
        discountBasisPoints = _discountBasisPoints;

        emit DiscountUpdated(discountBasisPoints);
    }

    // Расчёт цены 1 GRN на основе текущей цены пшеницы
    function getTokenPrice() public view returns (uint256) {
        return (wheatPrice * 10) / 100; // 10% от стоимости пшеницы
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
