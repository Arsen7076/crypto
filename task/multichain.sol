// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

// import "@chainlink/contracts/src/v0.8/libraries/Client.sol";
import "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

interface IDEXRouter {
    function WETH() external pure returns (address);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external payable returns (uint[] memory amounts);
}

/// @title TokenTransferor - Contract for cross-chain token transfers using Chainlink.
contract TokenTransferor is OwnerIsCreator, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IRouterClient private s_router;
    IDEXRouter public uniswap;
    IERC20 public stdToken;
    address public ethereumContractAddress;
    address public commissionReceiver;
    uint64 public destinationChainSelector;

    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    event EthereumContractAddressChanged(address indexed newAddress);
    event StdTokenAddressChanged(address indexed newAddress);
    event SRouterAddressChanged(address indexed newAddress);
    event TokenSwapped(uint indexed amount);

    constructor(
        address _routerChain,
        address _uniswapRouter,
        address _ethereumContractAddress,
        address _stdToken,
        uint64 _destinationChainSelector,
        address _receiver
    ) {
        s_router = IRouterClient(_routerChain);
        uniswap = IDEXRouter(_uniswapRouter);
        ethereumContractAddress = _ethereumContractAddress;
        stdToken = IERC20(_stdToken);
        destinationChainSelector = _destinationChainSelector;
        commissionReceiver = _receiver;
    }

    /// @notice Transfer tokens with payment in native currency (e.g., ETH).
    function transferTokensPayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) internal nonReentrant returns (bytes32 messageId) {
        uint256 fees = calculateFee(_destinationChainSelector, _receiver, _token, _amount);
        require(address(this).balance >= fees, "Not enough ETH to cover fees");

        stdToken.approve(address(s_router), _amount);

        Client.EVM2AnyMessage memory evm2AnyMessage = buildCCIPMessage(_receiver, _token, _amount, address(0));
        messageId = s_router.ccipSend{value: fees}(_destinationChainSelector, evm2AnyMessage);

        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(0),
            fees
        );

        return messageId;
    }

    /// @notice Helper to build a CCIP message.
    function buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: _feeTokenAddress
        });
    }

    /// @notice Calculates fees required for a CCIP message.
    function calculateFee(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount) public view returns (uint256 fees) {
        Client.EVM2AnyMessage memory message = buildCCIPMessage(_receiver, _token, _amount, address(0));
        fees = s_router.getFee(_destinationChainSelector, message);
        return fees;
    }

    receive() external payable {
        uint amount = msg.value / 2;
        payable (commissionReceiver).transfer(amount);
        transferTokensPayNative(destinationChainSelector,
                                ethereumContractAddress,
                                address(stdToken),
                                msg.value-amount);
    }

    /// @notice Withdraw ETH from the contract.
    function withdrawEther(address payable _to) public onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "No ether to withdraw");
        _to.transfer(amount);
    }

    /// @notice Allows updating the address for the Ethereum side contract.
    function setEthereumContractAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        ethereumContractAddress = _newAddress;
        emit EthereumContractAddressChanged(_newAddress);
    }

    /// @notice Allows updating the STD token address.
    function setStdTokenAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        stdToken = IERC20(_newAddress);
        emit StdTokenAddressChanged(_newAddress);
    }

    /// @notice Allows updating the chainlink Router  address.
    function setSrouterAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        s_router = IRouterClient(_newAddress);
        emit StdTokenAddressChanged(_newAddress);
    }
}
