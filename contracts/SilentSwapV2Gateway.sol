// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Importing required OpenZeppelin contracts and libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IEIP3009.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SilentSwap V2 - EVM Gateway Contract
 * @dev This contract facilitates the locking of USDC on Avalanche and acts as a gateway for cross-chain swaps with Secret.
 */
contract SilentSwapV2Gateway is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // keccak256("receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)")[0:4]
    bytes4 private constant _RECEIVE_WITH_AUTHORIZATION_SELECTOR = 0xef55bec6;

    // Enumerations
    enum OrderStatus {
        None,
        Open,
        Completed,
        Aborted
    }

    // Structures
    struct Order {
        OrderStatus status;
        uint256 expiration;
        address notary;
        address refundee;
        uint256 amount;
    }

    // Configuration struct for flexible adjustments
    struct Config {
        uint256 minDuration;
        uint256 maxDuration;
        uint256 minDepositAmount;
    }

    // Storage
    mapping(bytes32 => Order) public orders;
    mapping(bytes32 => bytes32) public payloads;
    mapping(address => bool) public authorizedApprovers;
    mapping(address => bool) public authorizedClaimers;

    // tracks the number of times a given signer has deposited
    mapping(address => uint256) public signerCounts;

    Config public config;

    // Token address
    IERC20 public immutable usdc;

    // Events
    event Deposit(
        address indexed signer,
        bytes32 indexed orderId,
        uint256 amount,
        uint256 duration
    );
    event ProxyDeposit(
        address indexed signer,
        bytes32 indexed orderId,
        uint256 amount,
        uint256 duration
    );
    event Claim(
        bytes32 indexed orderId,
        address indexed recipient,
        uint256 amount
    );
    event Refund(
        bytes32 indexed orderId,
        address indexed refundee,
        uint256 amount
    );
    event ConfigUpdated(
        uint256 minDuration,
        uint256 maxDuration,
        uint256 minDepositAmount
    );
    event ApproverAdded(address indexed approver);
    event ApproverRemoved(address indexed approver);
    event ClaimerAdded(address indexed claimer);
    event ClaimerRemoved(address indexed claimer);

    /**
     * @dev Claim was rejected because the sender is unauthorized
     */
    error ClaimRejectedUnauthorized();

    /**
     * @dev Claim was rejected because of too many attempted claims
     */
    error ClaimRejectedExcessiveClaimAttempts();

    /**
     * @dev Claim was rejected because order is not in Open state
     */
    error ClaimRejectedOrderNotOpen(uint256 index, OrderStatus status);

    /**
     * @dev Claim was rejected because the signature is invalid
     */
    error ClaimRejectedInvalidSignature();

    /**
     * @dev Constructor sets the USDC token contract address and initializes configuration.
     * @param _usdc The address of the USDC token contract.
     * @param _config Initial configuration values.
     */
    constructor(IERC20 _usdc, Config memory _config, address _claimer) Ownable(msg.sender) {
        require(_config.minDuration <= _config.maxDuration, "Gateway: minimumDuration must be <= maximumDuration");
        usdc = _usdc;
        config = _config;
        authorizedClaimers[_claimer] = true;
        emit ClaimerAdded(_claimer);
    }

    /**
     * @notice Verifies an EIP-712 typed data signature.
     * @param domainSepHash The domain separator hash.
     * @param payloadHash The hash of the structured data payload.
     * @param typedDataSignature The EIP-712 signature to verify.
     * @param signer The address expected to have signed the data.
     * @return isValid True if the signature is valid, false otherwise.
     */
    function verifyTypedDataSignature(
        bytes32 domainSepHash,
        bytes32 payloadHash,
        bytes memory typedDataSignature,
        address signer
    ) public pure returns (bool isValid) {
        // Compute the EIP-712 typed data hash
        bytes32 typedDataHash = keccak256(
            abi.encodePacked("\x19\x01", domainSepHash, payloadHash)
        );

        // Recover the address from the signature
        address recoveredAddress = ECDSA.recover(
            typedDataHash,
            typedDataSignature
        );

        // Check if the recovered address matches the expected signer
        return recoveredAddress == signer;
    }

    // Functions

    struct DepositParams {
        address signer;
        bytes32 orderId;
        address notary;
        address approver;
        bytes orderApproval;
        uint256 approvalExpiration;
        uint256 duration;
        bytes32 domainSepHash;
        bytes32 payloadHash;
        bytes typedDataSignature;
        bytes receiveAuthorization;
    }

    /**
     * @notice Returns the number of times a given signer has deposited.
     * @param signer The address of the signer.
     * @return count The number of deposits made by the signer.
     */
    function getSignerCount(address signer) external view returns (uint256 count) {
        return signerCounts[signer];
    }

    /**
     * @notice Allows a user to commit funds to initiate an order.
     */
    function deposit(DepositParams calldata params) external nonReentrant {
        // V1. ABI decode the`receiveAuthorization` argument and require that...
        (address funder, address recipient, uint256 amount) = abi.decode(
            params.receiveAuthorization[0:96],
            (address, address, uint256)
        );

        // V1. ...(a) the `.from` field matches the given `signer`...
        require(funder == params.signer, "Gateway: receive authorization not from signer");

        // V1. ...(b) the `.to` field matches this contract...
        require(recipient == address(this), "Gateway: receive authorization not to contract");

        // V1. ...(c) the amount is greater than or equal to `config.minDepositAmount`
        require(amount != 0 && amount >= config.minDepositAmount, string(abi.encodePacked("Gateway: receive authorization amount too low; minimum is ", Strings.toString(config.minDepositAmount))));

        // V2. The given `approvalExpiration` must be after the current block time
        require(block.timestamp < params.approvalExpiration, "Gateway: approval expired");

        // V3. The`duration` argument must be greater than or equal to `config.minDuration` and less than or equal to `config.maxDuration`
        require(
            params.duration >= config.minDuration && params.duration <= config.maxDuration,
            string(abi.encodePacked(
                "Gateway: invalid duration ", Strings.toString(params.duration),"; must be between ", Strings.toString(config.minDuration), " and ", Strings.toString(config.maxDuration)
            ))
        );

        // V4. The given `approver` must be present in the `config.authorizedApprovers` set
        require(authorizedApprovers[params.approver], "Gateway: approver not authorized");

        // V5. The given `orderId` must never have been seen before
        require(orders[params.orderId].amount == 0 && orders[params.orderId].notary == address(0), "Gateway: order already exists");

        // V6. The given `payloadHash` must never have been seen before
        require(payloads[params.payloadHash] == bytes32(0), "Gateway: payload already used");

        // V7. `ECDSA.tryRecover(keccak256(concat("\x19Ethereum Signed Message:\n168", orderId, signer, notary, approvalExpiration, domainSepHash, payloadHash)), orderApproval)`...
        address recoveredAddress = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n168",
                    params.orderId,
                    params.signer,
                    params.notary,
                    params.approvalExpiration,
                    params.domainSepHash,
                    params.payloadHash
                )
            ),
            params.orderApproval
        );

        // V7. ...must equal the `approver` address
        require(recoveredAddress == params.approver, "Gateway: invalid order approval signature");

        // V8. `ECDSA.tryRecover(typedDataHash, typedDataSignature)` must equal the `signer` address, where `typedDataHash` is generated by evaluating `MessageHashUtils.toTypedDataHash(domainSepHash, payloadHash)`
        bool isValid = verifyTypedDataSignature(
            params.domainSepHash,
            params.payloadHash,
            params.typedDataSignature,
            params.signer
        );
        require(isValid, "Gateway: invalid typed data signature");

        // E1. Store to `orders` mapping
        orders[params.orderId] = Order({
            status: OrderStatus.Open,
            expiration: block.timestamp + params.duration,
            notary: params.notary,
            refundee: params.signer,
            amount: amount
        });

        // E2. Store to `payloads` mapping
        payloads[params.payloadHash] = params.orderId;

        // E3. Call `receiveWithAuthorization` on USDC
        (bool usdcReceived, ) = address(usdc).call(
            abi.encodePacked(
                _RECEIVE_WITH_AUTHORIZATION_SELECTOR,
                params.receiveAuthorization
            )
        );

        require(usdcReceived, "Gateway: receive authorization failed()");

        // increment deposit count
        signerCounts[params.signer]++;

        // E4. Emit deposit event
        emit Deposit(params.signer, params.orderId, amount, params.duration);
    }


    event Error(string reason);
    /**
     * @notice Allows a user to commit funds to initiate an order.
     */
    function depositProxy(DepositParams calldata params, uint256 amount) external nonReentrant {
        // V1. ...(c) the amount is greater than or equal to `config.minDepositAmount`
        require(amount != 0 && amount >= config.minDepositAmount, string(abi.encodePacked("Gateway: receive authorization amount too low; minimum is ", Strings.toString(config.minDepositAmount))));

        // V2. The given `approvalExpiration` must be before the current block time
        require(block.timestamp < params.approvalExpiration, "Gateway: approval expired");
     

        // V3. The`duration` argument must be greater than or equal to `config.minDuration` and less than or equal to `config.maxDuration`
        require(
            params.duration >= config.minDuration && params.duration <= config.maxDuration,
            string(abi.encodePacked(
                "Gateway: invalid duration ", Strings.toString(params.duration),"; must be between ", Strings.toString(config.minDuration), " and ", Strings.toString(config.maxDuration)
            ))
        );
       

        // V4. The given `approver` must be present in the `config.authorizedApprovers` set
        require(authorizedApprovers[params.approver], "Gateway: approver not authorized");
      

        // V5. The given `orderId` must never have been seen before
        require(orders[params.orderId].amount == 0 && orders[params.orderId].notary == address(0), "Gateway: order already exists");
      

        // V6. The given `payloadHash` must never have been seen before
        require(payloads[params.payloadHash] == bytes32(0), "Gateway: payload already used");
     

        // V7. `ECDSA.tryRecover(keccak256(concat("\x19Ethereum Signed Message:\n168", orderId, signer, notary, approvalExpiration, domainSepHash, payloadHash)), orderApproval)`...
        address recoveredAddress = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n168",
                    params.orderId,
                    params.signer,
                    params.notary,
                    params.approvalExpiration,
                    params.domainSepHash,
                    params.payloadHash
                )
            ),
            params.orderApproval
        );

        // V7. ...must equal the `approver` address
        require(recoveredAddress == params.approver, "Gateway: invalid order approval signature");
      

        // V8. `ECDSA.tryRecover(typedDataHash, typedDataSignature)` must equal the `signer` address, where `typedDataHash` is generated by evaluating `MessageHashUtils.toTypedDataHash(domainSepHash, payloadHash)`
        bool isValid = verifyTypedDataSignature(
            params.domainSepHash,
            params.payloadHash,
            params.typedDataSignature,
            params.signer
        );
        
        // require validity of the typed data signature
        require(isValid, "Gateway: invalid typed data signature");
      

        // E1. Store to `orders` mapping
        orders[params.orderId] = Order({
            status: OrderStatus.Open,
            expiration: block.timestamp + params.duration,
            notary: params.notary,
            refundee: params.signer,
            amount: amount
        });

        // E2. Store to `payloads` mapping
        payloads[params.payloadHash] = params.orderId;

        // E3. Call transferFrom on USDC after processing all params
        usdc.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // increment deposit count
        signerCounts[params.signer]++;

        // E4. Emit deposit event
        emit ProxyDeposit(params.signer, params.orderId, amount, params.duration);
    }

    struct ClaimSpec {
        bytes32 orderId;
        bytes signature;
    }

    struct BulkClaimParams {
        ClaimSpec[] claims;
        address recipient;
    }

    uint256 public claimsCap = 50;

    /**
     * @notice Sets the maximum number of claims allowed in a bulk claim.
     * @param newCap The new maximum number of claims.
     */
    function setClaimsCap(uint256 newCap) external onlyOwner {
        claimsCap = newCap;
    }

    /**
     * @notice Allows a party to claim the funds associated with an order by providing proof of order satisfaction.
     */
    function claim(BulkClaimParams calldata params) external nonReentrant returns (uint256) {
        // sender is not authorized
        if(!authorizedClaimers[params.recipient]) revert ClaimRejectedUnauthorized();

        // cumulative claim amount
        uint256 amount = 0;

        // cache number of claims
        uint256 claimsLen = params.claims.length;

        // number of claims exceeds the cap
        if(claimsLen > claimsCap) revert ClaimRejectedExcessiveClaimAttempts();

        // cache claims' recipient
        address recipient = params.recipient;

        // each claim
        for (uint i = 0; i < claimsLen; i++) {
            // cache claim
            ClaimSpec memory claim = params.claims[i];

            // look up order
            Order storage order = orders[claim.orderId];

            // order must have status "Open"
            if(order.status != OrderStatus.Open) revert ClaimRejectedOrderNotOpen(i, order.status);

            // verify the claim's signature against the order's approved notary address
            if(
                ECDSA.recover(
                    keccak256(
                        abi.encodePacked(
                            "\x19Ethereum Signed Message:\n32",
                            keccak256(abi.encodePacked(claim.orderId))
                        )
                    ),
                    claim.signature
                ) != order.notary
            ) revert ClaimRejectedInvalidSignature();

            // update order status
            order.status = OrderStatus.Completed;

            // accumulate claim amount
            amount += order.amount;

            // emit claim event
            emit Claim(claim.orderId, recipient, order.amount);
        }

        // transfer total claimed funds
        usdc.safeTransfer(recipient, amount);

        return amount;
    }

    /**
     * @notice Refunds an order request to the sender if the order is expired.
     */
    function refund(bytes32 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, string(abi.encodePacked("Gateway: order not open; status: ", order.status)));
        require(block.timestamp >= order.expiration, string(abi.encodePacked("Gateway: order not expired; expires: ", order.expiration)));

        // update order status
        order.status = OrderStatus.Aborted;

        // transfer funds
        usdc.safeTransfer(order.refundee, order.amount);

        emit Refund(orderId, order.refundee, order.amount);
    }

    /**
     * @notice Updates configuration parameters.
     */
    function setConfig(
        uint256 minimumDuration,
        uint256 maximumDuration,
        uint256 minimumDepositAmount
    ) external onlyOwner {
        require(minimumDuration <= maximumDuration, "Gateway: minimumDuration must be <= maximumDuration");
        
        config = Config({
            minDuration: minimumDuration,
            maxDuration: maximumDuration,
            minDepositAmount: minimumDepositAmount
        });

        emit ConfigUpdated(
            minimumDuration,
            maximumDuration,
            minimumDepositAmount
        );
    }

    /**
     * @notice Returns the current configuration parameters.
     */
    function getConfig() external view returns (Config memory) {
        return config;
    }

    /**
     * @notice Adds an approver to the authorized list.
     */
    function addApprover(address approver) external onlyOwner {
        authorizedApprovers[approver] = true;
        emit ApproverAdded(approver);
    }

    /**
     * @notice Removes an approver from the authorized list.
     */
    function removeApprover(address approver) external onlyOwner {
        authorizedApprovers[approver] = false;
        emit ApproverRemoved(approver);
    }


    /**
     * @notice Adds a claimer to the authorized list.
     */
    function addClaimer(address claimer) external onlyOwner {
        authorizedClaimers[claimer] = true;
        emit ClaimerAdded(claimer);
    }

    /**
     * @notice Removes a claimer from the authorized list.
     */
    function removeClaimer(address claimer) external onlyOwner {
        authorizedClaimers[claimer] = false;
        emit ClaimerRemoved(claimer);
    }


    /**
     * @notice Checks if an address is an authorized approver.
     * @param approver The address to check.
     * @return isAuthorized True if the address is an authorized approver, false otherwise.
     */
    function isAuthorizedApprover(address approver) external view returns (bool isAuthorized) {
        return authorizedApprovers[approver];
    }


    /**
     * @notice Checks if an address is an authorized claimer.
     * @param claimer The address to check.
     * @return isAuthorized True if the address is an authorized claimer, false otherwise.
     */
    function isAuthorizedClaimer(address claimer) external view returns (bool isAuthorized) {
        return authorizedClaimers[claimer];
    }
    /**
     * @notice Returns the current status of an order.
     */
    function queryOrderStatus(
        bytes32 orderId
    ) external view returns (OrderStatus) {
        return orders[orderId].status;
    }
}
