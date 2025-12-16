// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./SilentSwapV2Gateway.sol";

/// @title Example contract that can be called from any chain to deposit to SilentSwapV2Gateway
/// The problem with allowing any token from any chain to be swapped, bridged and deposited into SilentSwap is that with pricy slippage you never know the exact amount you will get.
/// This contract will recieve the USDC and then deposit it into the gateway the exact amount of tokens recieved.
/// IF the intended amount to deposit is 100 USDC and 99.99 usdc is recieved after slippage, then the transfer will fail
/// IF the intended amount to deposit is 100 USDC and 100.01 usdc is recieved after slippage, then the deposit will succeed but .01 would be left in the contract lost.
/// Assume this contract is always zeroed out after a deposit. We have to have this seperate from the gateway to get the exact amount deposited.
/// Assumes that tokens to be deposited are already transferred to this contract and the depositProxy is called in the same transaction.
contract SilentSwapDepositor is Ownable {
    using SafeERC20 for IERC20;

    address public gatewayAddress;
    address public usdc;
    constructor(address _gatewayAddress, address _usdc) Ownable(msg.sender) {
        gatewayAddress = _gatewayAddress;
        usdc = _usdc;
    }

    event DepositProxy(
        address indexed signer,
        bytes32 indexed orderId,
        uint256 amount
    );

    event DepositProxy2(
        address indexed signer,
        bytes32 indexed orderId,
        uint256 amount
    );

    event Sweep(
        address indexed recipient,
        uint256 amount
    );

    /**
     * @notice Allows a user to commit funds to initiate an order from another blockchain where the bridge sends funds to the depositor contract
     * @param params The deposit parameters containing:
     *   - signer: Address of the order signer
     *   - orderId: Unique identifier for this order
     *   - notary: Address of the notary for this order
     *   - approver: Address of the authorized approver
     *   - orderApproval: Signature approving the order
     *   - approvalExpiration: Timestamp when approval expires
     *   - duration: Duration of the order lock period
     *   - domainSepHash: EIP-712 domain separator hash
     *   - payloadHash: Hash of the order payload
     *   - typedDataSignature: EIP-712 signature of the payload
     */
    function depositProxy(
        SilentSwapV2Gateway.DepositParams calldata params
    ) external {
        // Verify the deposit parameters and transfer tokens
        IERC20 token = IERC20(usdc);
        uint256 balance = token.balanceOf(address(this));

        require(balance > 0, "SilentSwapDepositor: balance must be greater than 0");

        token.forceApprove(gatewayAddress, 0);
        token.forceApprove(gatewayAddress, balance);

        SilentSwapV2Gateway(gatewayAddress).depositProxy(params, balance);

        emit DepositProxy(params.signer, params.orderId, balance);
    }

    /**
     * @notice Allows a user to commit funds to initiate an order from another blockchain where we need to manually call transferFrom in this contract
     */
   function depositProxy2(
        SilentSwapV2Gateway.DepositParams calldata params
    ) external {
        // Verify the deposit parameters and transfer tokens
        IERC20 token = IERC20(usdc);
        uint256 balance = token.balanceOf(msg.sender);

        require(balance > 0, "SilentSwapDepositor: balance must be greater than 0");

        token.safeTransferFrom(
            msg.sender,
            address(this),
            balance
        );
        balance = token.balanceOf(address(this));
        // Reset approval to zero, then set approval to the current balance
        token.forceApprove(gatewayAddress, 0);
        token.forceApprove(gatewayAddress, balance);

        SilentSwapV2Gateway(gatewayAddress).depositProxy(params, balance);

        emit DepositProxy2(params.signer, params.orderId, balance);
    }
      
    /**
     * @notice Allows the owner to sweep the USDC balance of the contract to a specified recipient incase funds get stuck
     */
    function sweep() external onlyOwner {
        IERC20 token = IERC20(usdc);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));

        emit Sweep(msg.sender, token.balanceOf(address(this)));
    }
}