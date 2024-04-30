// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDEXRouter {
    function WETH() external pure returns (address);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
}

contract Burner is OwnerIsCreator, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public tokenInput;
    address public tokenToBurn;
    IDEXRouter public uniswapRouter;
    address public commissionReceiver;

    event BurnPerformed(address indexed tokenX, address indexed tokenY, uint256 amountX, uint256 amountY);
    event TokensWithdrawn(address token, address to, uint256 amount);
    event EtherWithdrawn(address to, uint256 amount);

    constructor(address _uniswapRouter, address _tokenToBurn, address _tokenInput, address _receiver) {
        uniswapRouter = IDEXRouter(_uniswapRouter);
        tokenToBurn = _tokenToBurn;
        tokenInput = ERC20(_tokenInput);
        commissionReceiver = _receiver;
    }

    receive() external payable {
        uint ethAmount = msg.value / 2;
        payable(commissionReceiver).transfer(ethAmount);
    }

    function swapAndBurn() external onlyOwner nonReentrant {
        uint256 amountX = tokenInput.balanceOf(address(this));
        require(amountX > 0, "Insufficient token balance");

        tokenInput.approve(address(uniswapRouter), 0);
        tokenInput.approve(address(uniswapRouter), amountX);

        address[] memory pathXtoETH = new address[](2);
        pathXtoETH[0] = address(tokenInput);
        pathXtoETH[1] = uniswapRouter.WETH();

        uniswapRouter.swapExactTokensForETH(
            amountX,
            0, // Accept any amount of ETH
            pathXtoETH,
            address(this),
            block.timestamp
        );

        address[] memory pathETHtoY = new address[](2);
        pathETHtoY[0] = uniswapRouter.WETH();
        pathETHtoY[1] = tokenToBurn;

        uint[] memory amountsY = uniswapRouter.swapExactETHForTokens{value: address(this).balance}(
            0, // Accept any amount of token Y
            pathETHtoY,
            address(this),
            block.timestamp
        );

        ERC20Burnable(tokenToBurn).burn(amountsY[1]);

        emit BurnPerformed(address(tokenInput), tokenToBurn, amountX, amountsY[1]);
    }

    function withdrawToken(address token, address to, uint256 amount) public onlyOwner {
        ERC20(token).safeTransfer(to, amount);
        emit TokensWithdrawn(token, to, amount);
    }

    function withdrawEther(address payable to) public onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No ether to withdraw");
        to.transfer(amount);
        emit EtherWithdrawn(to, amount);
    }

    function wild() external onlyOwner nonReentrant returns (bool) {
        uint256 amount = address(this).balance;
        require(amount > 0, "No ether to withdraw");

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");
        return sent;
    }
}
