// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

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
    using SafeERC20 for IERC20;

    address private  UNISWAP_V2_ROUTER = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; // Address of the Uniswap V2 Router 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
    address public tokenToBurn; // Address of the token Y that will be burned
    IDEXRouter public uniswapRouter;
    IERC20 public tokenInput ;
    constructor(address _uniswapRouter, address _tokenToBurn, address _tokenInput) {
        uniswapRouter = IDEXRouter(_uniswapRouter);
        tokenToBurn = _tokenToBurn;
        tokenInput = IERC20(_tokenInput);
    }

    // Function to receive Ether
    receive() external payable {}

    function swapAndBurn() external onlyOwner {
        // IERC20 tokenXInstance = IERC20(tokenX);

        // Ensure the contract has enough token X for the swap
        uint amountX = tokenInput.balanceOf(address(this)) ;

        // Approve Uniswap router to spend token X
        tokenInput.safeApprove(address(uniswapRouter), amountX);

        // Path from token X to WETH
        address[] memory pathXtoETH = new address[](2);
        pathXtoETH[0] = address(tokenInput);
        pathXtoETH[1] = uniswapRouter.WETH();

        // Swap token X to Ether
        uint[] memory amountsETH = uniswapRouter.swapExactTokensForETH(
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
        uint[] memory amountsY = uniswapRouter.swapExactETHForTokens{value: amountsETH[1]}(
            0, // Accept any amount of token Y
            pathETHtoY,
            address(this),
            block.timestamp
        );

        // Burn the token Y
        IERC20(tokenToBurn).safeTransfer(address(0), amountsY[1]);

        emit BurnPerformed(address(tokenInput), tokenToBurn, amountX, amountsY[1]);
    }

    event BurnPerformed(address indexed tokenX, address indexed tokenY, uint256 amountX, uint256 amountY);
    
    function wild()external  onlyOwner returns (bool){
          // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        // if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = msg.sender.call{value: amount}("");
        return  sent;
    }
}
