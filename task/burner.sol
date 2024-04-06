// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Burner is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private constant UNISWAP_V2_ROUTER = 0x...; // Адрес Uniswap V2 Router
    address public tokenToBurn; // Адрес токена, который будет сжигаться

    constructor(address _tokenToBurn) {
        tokenToBurn = _tokenToBurn;
    }

    // Функция для получения Ether
    receive() external payable {}

    function buyAndBurnToken() external nonReentrant {
        require(address(this).balance > 0, "Contract has no Ether");

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenToBurn;

        // Обменять все Ether на токены
        uint[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER)
            .swapExactETHForTokens{ value: address(this).balance }(
                0, // Принимаем любое количество токенов (ноль для упрощения)
                path,
                address(this),
                block.timestamp
            );

        // Сжигание токенов
        IERC20(tokenToBurn).safeTransfer(address(0), amounts[1]);
    }


     function swapAndBurn() external onlyOwner {
        // Swap BNB for STD tokens
        address[] memory path = new address[](2);
        path[0] = UNISWAP_V2_ROUTER.WETH();
        // path[1] = stdTokenAddress; // STD token address
        path[1] = address(tokenToBurn);
        // First swap BNB for STD tokens
        uint[] memory amounts;
        amounts = UNISWAP_V2_ROUTER.swapExactETHForTokens{value: address(this).balance }(
            0,
            path,
            address(this), // Tokens need to be received by this contract first
            block.timestamp
        );
}
