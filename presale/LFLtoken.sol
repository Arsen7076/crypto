// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    /**
     * @notice Add liquidity between an ERC20 token and WETH,
     *         sending ETH along with the tx to wrap as WETH.
     * @param token The address of the ERC20 token.
     * @param amountTokenDesired The amount of tokens you want to add as liquidity.
     * @param amountTokenMin The minimum amount of tokens you’ll actually accept (slippage).
     * @param amountETHMin The minimum amount of ETH you’ll accept (slippage).
     * @param to The address that will receive the LP tokens.
     * @param deadline Unix timestamp after which the tx will revert if not executed.
     * @return amountToken The actual amount of tokens used.
     * @return amountETH The actual amount of ETH used.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable 
      returns (uint amountToken, uint amountETH, uint liquidity);

    /**
     * @notice Add liquidity between two ERC20 tokens (e.g. your token + USDT).
     * @return amountA The actual amount of tokenA used.
     * @return amountB The actual amount of tokenB used.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external 
      returns (uint amountA, uint amountB, uint liquidity);
}

/**
 * @title LFLToken
 * @dev ERC20 Token with 4 decimals, burn function, and predefined supply.
 *      Uses Chainlink's `OwnerIsCreator` to set owner = deployer.
 */
contract LFLToken is ERC20, OwnerIsCreator {
    uint256 private constant TOTAL_SUPPLY = 1111111000 * (10 ** 4); // Adjusted to correct scale

    // Addresses for distribution
    address public liquidityManager;
    address public presale;
    address public airdrop;
    address public linearVesting;

    bool public distributionCompleted;

    constructor() ERC20("LFL Token", "LFL") {
        _mint(address(this), TOTAL_SUPPLY); // Mint all tokens to the contract itself
    }

    /**
     * @notice Set the addresses for distribution contracts.
     * @param _liquidityManager Address of the liquidity manager contract (6% allocation).
     * @param _presale Address of the presale contract (12% allocation).
     * @param _airdrop Address of the airdrop contract (3% allocation).
     * @param _linearVesting Address of the linear vesting contract (26% allocation).
     */
    function setDistributionAddresses(
        address _liquidityManager,
        address _presale,
        address _airdrop,
        address _linearVesting
    ) external onlyOwner {
        require(_liquidityManager != address(0), "Invalid liquidity manager address");
        require(_presale != address(0), "Invalid presale address");
        require(_airdrop != address(0), "Invalid airdrop address");
        require(_linearVesting != address(0), "Invalid linear vesting address");

        liquidityManager = _liquidityManager;
        presale = _presale;
        airdrop = _airdrop;
        linearVesting = _linearVesting;
    }

    /**
     * @notice Distribute tokens to the predefined addresses.
     *         This function can only be called once.
     */
    function distributeTokens() external onlyOwner {
        require(!distributionCompleted, "Distribution already completed");
        require(
            liquidityManager != address(0) &&
            presale != address(0) &&
            airdrop != address(0) &&
            linearVesting != address(0),
            "Distribution addresses not set"
        );

        uint256 totalTokens = balanceOf(address(this));

        // Calculate allocations
        uint256 liquidityAllocation = (totalTokens * 6) / 100;   // 6%
        uint256 presaleAllocation = (totalTokens * 12) / 100;    // 12%
        uint256 airdropAllocation = (totalTokens * 3) / 100;     // 3%
        uint256 vestingAllocation = (totalTokens * 26) / 100;    // 26%

        // Perform transfers
        _transfer(address(this), liquidityManager, liquidityAllocation);
        _transfer(address(this), presale, presaleAllocation);
        _transfer(address(this), airdrop, airdropAllocation);
        _transfer(address(this), linearVesting, vestingAllocation);

        // Mark distribution as completed
        distributionCompleted = true;
    }

    /**
     * @notice Override decimals() to return 4.
     */
    function decimals() public view virtual override returns (uint8) {
        return 4;
    }

    /**
     * @notice Burn tokens from the sender’s balance.
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}


/**
 * @title LiquidityManager
 * @notice This sample contract demonstrates how to add liquidity 
 *         to a DEX (Uniswap/PancakeSwap style) using either 
 *         the chain coin (via WETH/WBNB) or a stablecoin (like USDT).
 *
 *         In a real system, you'd combine this with your token contract 
 *         or use it from an “owner” or “admin” account that holds tokens.
 *         This is purely a demonstration.
 */
contract LiquidityManager {
    address public owner;
    uint requiredUSDTBalanceForLiquidity;
    // The Uniswap/PancakeSwap V2 router address 
    // (on Ethereum mainnet or BSC mainnet, etc.).
    // For example, UniswapV2 on Ethereum mainnet is typically 0x...
    // On BSC, PancakeSwap router is typically 0x10ED43C718714eb63d5aA57B78B54704E256024E (v2).
    address public routerAddress;
    address public usdt;
    address public token;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event LiquidityAddedETH(
        address token, 
        uint amountToken, 
        uint amountETH, 
        uint liquidity
    );
    event LiquidityAddedTokens(
        address tokenA, 
        address tokenB, 
        uint amountA, 
        uint amountB, 
        uint liquidity
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _routerAddress) {
        owner = msg.sender;
        routerAddress = _routerAddress;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Set the router address, in case you need to change (e.g. to a different DEX).
     */
    function setRouterAddress(address _router) external onlyOwner {
        routerAddress = _router;
    }

    /**
     * @notice Add liquidity pairing your token with the chain’s coin (ETH/BNB).
     *         1) The contract must hold or have approval for `tokenAmount`.
     *         2) This function must be called with a payable value = amount of chain coin.
     *         3) If your token is not already in this contract, you must “transferFrom” it in 
     *            or hold it here beforehand, and `approve` the router to use it.
     *
     * @param tokenToCreate The address of your ERC20 token.
     * @param tokenAmount The amount of your token to add as liquidity.
     * @param amountTokenMin The minimum of your token you’ll accept (slippage protection).
     * @param amountETHMin The minimum ETH you’ll accept (slippage protection).
     * @param to The address that receives the LP tokens.
     * @param deadline The timestamp after which this tx fails if not executed.
     */
    function addLiquidityWithChainCoin(
        address tokenToCreate,
        uint256 tokenAmount,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable onlyOwner {
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

        // *** IMPORTANT *** 
        // Typically, your contract or this function must have already:
        //   1) Received `tokenAmount` of `token` 
        //      (e.g. via `transferFrom(owner, address(this), tokenAmount)`).
        //   2) Called `IERC20(token).approve(routerAddress, tokenAmount)` 
        //      so the router can pull tokens from this contract.
        // In a minimal demonstration, we do that here:
        
        bool ok = IERC20(tokenToCreate).transferFrom(msg.sender, address(this), tokenAmount);
        require(ok, "Token transferFrom failed");
        ok = IERC20(tokenToCreate).approve(routerAddress, tokenAmount);
        require(ok, "Approve failed");

        // Then call addLiquidityETH 
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = 
            router.addLiquidityETH{value: msg.value}(
                tokenToCreate,
                tokenAmount,
                amountTokenMin,
                amountETHMin,
                to,
                deadline
            );

        emit LiquidityAddedETH(tokenToCreate, amountToken, amountETH, liquidity);

        // If any leftover tokens are not used by the router (due to slippage constraints),
        // you might want to send them back to the owner.
        // If (tokenAmount - amountToken) > 0 => leftover. For demonstration:
        uint256 leftoverToken = IERC20(tokenToCreate).balanceOf(address(this));
        if (leftoverToken > 0) {
            IERC20(tokenToCreate).transfer(owner, leftoverToken);
        }
        
        // If any leftover ETH wasn't used, it's typically left in the contract. 
        // We could also send that back to the owner if you wish:
        uint256 leftoverETH = address(this).balance;
        if (leftoverETH > 0) {
            (bool success, ) = payable(owner).call{value: leftoverETH}("");
            require(success, "Refund leftover ETH failed");
        }
    }

    /**
     * @notice Add liquidity between two ERC20 tokens (e.g. your token and USDT).
     *         1) The contract must have or get `amountTokenA` of tokenA 
     *            and `amountTokenB` of tokenB.
     *         2) The contract must have approved the router to spend those tokens.
     *
     * @param tokenA The first token (e.g. your token).
     * @param tokenB The second token (e.g. USDT).
     * @param amountADesired The amount of tokenA to add.
     * @param amountBDesired The amount of tokenB to add.
     * @param amountAMin Minimal accepted tokenA (slippage).
     * @param amountBMin Minimal accepted tokenB (slippage).
     * @param to The address to receive the LP tokens.
     * @param deadline Unix timestamp after which this tx reverts if not done.
     */
    function addLiquidityTwoTokens(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external onlyOwner {
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

        // Transfer tokens from owner (or somewhere) to this contract
        bool okA = IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        bool okB = IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
        require(okA && okB, "transferFrom tokens failed");

        // Approve the router
        okA = IERC20(tokenA).approve(routerAddress, amountADesired);
        okB = IERC20(tokenB).approve(routerAddress, amountBDesired);
        require(okA && okB, "Approve tokens failed");

        // Add liquidity
        (uint256 amountA, uint256 amountB, uint256 liquidity) = 
            router.addLiquidity(
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                to,
                deadline
            );

        emit LiquidityAddedTokens(tokenA, tokenB, amountA, amountB, liquidity);

        // Handle leftover tokens (not used due to slippage).
        uint256 leftoverA = IERC20(tokenA).balanceOf(address(this));
        if (leftoverA > 0) {
            IERC20(tokenA).transfer(owner, leftoverA);
        }
        uint256 leftoverB = IERC20(tokenB).balanceOf(address(this));
        if (leftoverB > 0) {
            IERC20(tokenB).transfer(owner, leftoverB);
        }
    }
    // Setter for required USDT balance for liquidity
    function setRequiredUSDTBalance(uint256 _requiredUSDTBalance) external onlyOwner {
        requiredUSDTBalanceForLiquidity = _requiredUSDTBalance;
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) internal {
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

        // Transfer tokens from contract to itself
        bool okA = IERC20(tokenA).transferFrom(owner, address(this), amountADesired);
        bool okB = IERC20(tokenB).transferFrom(owner, address(this), amountBDesired);
        require(okA && okB, "Token transfer failed");

        // Approve the router for token transfers
        IERC20(tokenA).approve(routerAddress, amountADesired);
        IERC20(tokenB).approve(routerAddress, amountBDesired);

        // Add liquidity to the pool
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );

        emit LiquidityAddedTokens(tokenA, tokenB, amountA, amountB, liquidity);

        // Handle leftover tokens
        uint256 leftoverA = IERC20(tokenA).balanceOf(address(this));
        if (leftoverA > 0) {
            IERC20(tokenA).transfer(owner, leftoverA);
        }
        uint256 leftoverB = IERC20(tokenB).balanceOf(address(this));
        if (leftoverB > 0) {
            IERC20(tokenB).transfer(owner, leftoverB);
        }
    }



    /// @notice Checks the balance and adds liquidity if conditions are met
    function checkBalance() external returns (bool) {
        uint256 balanceUSDT = IERC20(usdt).balanceOf(address(this));
        if (balanceUSDT < requiredUSDTBalanceForLiquidity) {
            return false; // Insufficient USDT balance
        }

        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken > 0, "Insufficient token balance");

        // Add liquidity using the available balances
        _addLiquidity(
            token,
            usdt,
            balanceToken,
            balanceUSDT,
            100,         // Minimal token amount
            10,          // Minimal USDT amount
            owner,       // Liquidity recipient
            block.timestamp + 15 minutes // Deadline
        );

        return true; // Liquidity successfully added
    }
    /**
     * @dev Fallback to receive ETH if needed (e.g. router might send some back).
     */
    receive() external payable {}
}
