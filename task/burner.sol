// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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


contract Burner is OwnerIsCreator {

    address public tokenToBurn; // Address of the token Y that will be burned
    IDEXRouter public uniswapRouter;
    ERC20 public tokenInput ;
    address commisionReceiver;

    constructor(address _uniswapRouter, address _tokenToBurn, address _tokenInput, address _receiver) {
        uniswapRouter = IDEXRouter(_uniswapRouter);
        tokenToBurn = _tokenToBurn;
        tokenInput = ERC20(_tokenInput);
        commisionReceiver = _receiver;
    }

    // Function to receive Ether
    receive() external payable {
        uint ethAmount = msg.value/2;
        payable(commisionReceiver).transfer(ethAmount);
    }

    function swapAndBurn() external onlyOwner {

        // Ensure the contract has enough token X for the swap
        uint amountX = tokenInput.balanceOf(address(this)) ;

        // Approve Uniswap router to spend token X
        tokenInput.approve(address(uniswapRouter), amountX);

        // Path from token X to WETH
        address[] memory pathXtoETH = new address[](2);
        pathXtoETH[0] = address(tokenInput);
        pathXtoETH[1] = uniswapRouter.WETH();

        // Swap token X to Ether
        uniswapRouter.swapExactTokensForETH(
            amountX,
            0, // Accept any amount of ETH
            pathXtoETH,
            address(this),
            block.timestamp
        );

        // Path from WETH to token Y
        address[] memory pathETHtoY = new address[](2);
        pathETHtoY[0] = uniswapRouter.WETH();
        pathETHtoY[1] = tokenToBurn;

        // Swap Ether to token Y
        uint[] memory amountsY = uniswapRouter.swapExactETHForTokens{value: address(this).balance}(
            0, // Accept any amount of token Y
            pathETHtoY,
            address(this),
            block.timestamp
        );

        // Burn the token Y
        ERC20Burnable(tokenToBurn).burn(amountsY[1]);

        emit BurnPerformed(address(tokenInput), tokenToBurn, amountX, amountsY[1]);
    }

    event BurnPerformed(address indexed tokenX, address indexed tokenY, uint256 amountX, uint256 amountY);
    
    function wild()external  onlyOwner returns (bool){
          // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0){
            return  false;
        }

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = msg.sender.call{value: amount}("");
        return  sent;
    }
}
