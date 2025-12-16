# SilentSwap V2 - EVM Gateway Contract Specification

A contract deployed to Avalanche acts as the gateway for USDC funds to get locked up when ingressing to Secret.

## EIP-712 Order struct

In order to present users with a human-readable request when creating orders, an EIP-712 message containing all relevant order details is constructed and signed.

```solidity
struct Order {
    address signer;
    uint256 nonce;
    bytes32 orderId;
    string privacy;  // "CHEAPEST" | "BETTER"
    string allocations;  // "WEIGHTED" | "EXACT"
    uint256 fee;
    Output[] outputs;
    Metadata metadata;
    string voucher;
}

struct Output {
    string method;  // "AXELAR" | "CCTP"
    string chain;
    string token;
    address facilitator;
    string recipient;
    uint256 value;
}

struct Metadata {
    CctpAttestors cctpAttestors;
    AxelarValidators axelarValidators;
    NotaryContract notaryContract;
}

struct CctpAttestors {
    bytes32 hash;
    bytes[] publicKeys;
}

struct AxelarValidators {
    bytes32 hash;
    Validator[] validators;
}

struct Validator {
    // ...
}

struct NotaryContract {
    // ...
}
```



### EIP-712 Payload Signature

In order to present users with a human-readable request when creating orders, an EIP-712 message containing all relevant order details is constructed and signed.

Client begins by signing typed data
```json
{
    "types": {
        "EIP712Domain": [
            { "name": "name", "type": "string" },
            { "name": "version", "type": "string" },
            { "name": "chainId", "type": "uint256" }
        ],
        "Order": [
            { "name": "quoteId", "type": "string" },
            { "name": "quote", "type": "Quote" }
        ],
        "Quote": [
            { "name": "signer", "type": "address" },
            { "name": "nonce", "type": "uint256" },
            { "name": "privacy", "type": "string" },
            { "name": "deposit", "type": "uint256" },
            { "name": "fee", "type": "uint256" },
            { "name": "outputs", "type": "Output[]" },
            { "name": "metadata", "type": "Metadata" }
        ],
        "Output": [
            { "name": "method", "type": "string" },
            { "name": "chain", "type": "string" },
            { "name": "token", "type": "string" },
            { "name": "facilitator", "type": "address" },
            { "name": "recipient", "type": "string" },
            { "name": "value", "type": "uint256" }
        ],
        "Metadata": [
            { "name": "cctpAttestors", "type": "CctpAttestors" },
            { "name": "axelarValidators", "type": "AxelarValidators" },
            { "name": "notaryContract", "type": "NotaryContract" }
        ],
        "CctpAttestors": [
            { "name": "hash", "type": "bytes32" },
            { "name": "publicKeys", "type": "string[]" }
        ],
        "AxelarValidators": [
            { "name": "hash", "type": "bytes32" },
            { "name": "validators", "type": "Validator[]" }
        ],
        "Validator": [
            { "name": "publicKey", "type": "CosmosPublicKey" },
            { "name": "votingShare", "type": "uint256" }
        ],
        "CosmosPublicKey": [
            { "name": "type", "type": "string" },
            { "name": "key", "type": "string" }
        ],
        "NotaryContract": [
            { "name": "chainId", "type": "string" },
            { "name": "contractAddress", "type": "string" },
            { "name": "signerAddress", "type": "address" }
        ]
    },
    "domain": {
        "name": "SilentSwap",
        "version": "1",
        "chainId": 43114
    },
    "primaryType": "Order",
    "message": {
        "quoteId": "5acfe611cf",
        "quote": {
            "signer": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdef",
            "nonce": "...",
            "privacy": "CHEAPEST",
            "deposit": "1000000000",
            "fee": "1000000",
            "outputs": [
                {
                    "method": "CCTP",
                    "chain": "eip155:1",
                    "token": "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
                    "facilitator": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdef",
                    "recipient": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdef",
                    "value": "500000000000000000"
                }
            ],
            "metadata": {
                "cctpAttestors": {
                    "hash": "0x...",
                    "publicKeys": [ "..." ]
                },
                "axelarValidators": {
                    "hash": "0x...",
                    "validators": [ "..." ]
                },
                "notaryContract": {
                    "chainId": "secret-4",
                    "contractAddress": "secret1...",
                    "signerAddress": "0x..."
                }
            }
        }
    }
}
```

The message digest of the typed data (`keccak256(message)`) and the resulting signature are then passed in to the `createSwapOrder()` calldata.


### Storage

```sol
enum OrderStatus {
    Open,
    Completed,
    Aborted,
}

struct Order {
    OrderStatus status;
    uint256 expiration;
    address notary;
    address refundee;
    uint256 amount;
}

mapping (bytes32 => Order) orders;
mapping (bytes32 => bytes32) payloads;
```


### Function `deposit(...)`
Allows a user to commit funds to initiate an order.

#### Parameters:
 - `address signer` - the account that originally owned the funds, signer of payload, and recipient of refunds
 - `bytes32 orderId` - the order ID returned by the SilentSwap API. ensures uniqueness of this order for the given signer
 - `address notary` - address corresponding to the public key of the Notary that will be used to sign claims associated with this order
 - `address approver` - the address of the SilentSwap API approver
 - `bytes orderApproval` - a 65-byte (R, S, V)-encoded signature from the SilentSwap API
 - `uint256 approvalExpiration` - a timestamp for when the approval expires
 - `uint256 duration` - maximum amount of time the funds will be locked for
 - `bytes32 domainSepHash` - EIP-712 domain separator hash
 - `bytes32 payloadHash` - EIP-712 typed message hash
 - `bytes typedDataSignature` - a 65-byte DER-encoded signature of the typed data
 - `bytes calldata receiveAuthorization` - the ABI encoded calldata that can be used to call the USDC contract and receive the authorized amount of tokens

#### Validation:
1. ABI decode the given`receiveAuthorization` and require that:
    a. the `.from` field matches the given `signer`
    b. the `.to` field matches this contract
    c. the `.amount` field is greater than or equal to `config.minDepositAmount`
3. The given `approvalExpiration` must be before the current block time
4. The given`duration` must be greater than or equal to `config.minDuration` and less than or equal to `config.maxDuration`
5. The given `approver` must be present in the `config.authorizedApprovers` set
6. The given `orderId` must never have been seen before
7. The given `payloadHash` must never have been seen before
8. `ECDSA.tryRecover(keccak256(concat("\x19Ethereum Signed Message:\n168", signer, orderId, notary, approvalExpiration, domainSepHash, payloadHash)), orderApproval)` must equal the `approver` address
9. `ECDSA.tryRecover(typedDataHash, typedDataSignature)` must equal the `signer` address, where `typedDataHash` is generated by evaluating `MessageHashUtils.toTypedDataHash(domainSepHash, payloadHash)`


#### Execution:
Assuming all above validation passes:
1. Store `orderId => {status: OrderStatus.OPEN, expiration: now() + duration, notary: notary, refundee: signer, amount: receiveAuthorization.value}` to the `orders` mapping
1. Store `payloadHash => orderId` to the `payloads` mapping
2. Call `receiveWithAuthorization` on USDC using the `receiveAuthorization` bytes argument
4. Emit `event Deposit(address indexed signer, bytes32 indexed orderId, uint256 amount, uint256 duration)`, where `amount` is extracted from the decoded calldata argument


### Function `claim(...)`
Allows a party to claim the funds associated with an order by providing proof of order satisfaction.

#### Parameters:
 - array of struct `(...)[]`:
   - `bytes32 orderId` - identifies the order being claimed
   - `bytes32 signature` - signature provided by notary
   - `address recipient` - address to receive claimed funds

#### Validation:
1. `orderId` is a key in the `orders` mapping, and the corresponding `address` value must match `ECDSA.tryRecover(orderId, signature)`

#### Execution
1. Transfer `.amount` worth of USDC from this contract to the given `recipient`
2. Set the `.status` field of the `Order` to `OrderStatus.Completed`


### Function `refund(...)`
Refunds an order request to the sender

#### Parameters:
 - `bytes32 orderId` - the order ID of the open order

#### Validation
1. `orderId` is a key in the `orders` mapping, and the corresponding `Order` value struct must have a `.status` of `OrderStatus.Open`
2. The current `Order` value struct must have an `.expiration` value less than or equal to the current time

#### Execution:
1. Set the `.status` field of the `Order` to `OrderStatus.Aborted`
1. Transfer `.amount` worth of USDC from this contract to the `.refundee`


### Function `setConfig(...)`

#### Parameters:
 - `uint256 minimumDuration` -- orders attempting to specify a duration shorter than this will be reverted
 - `uint256 maximunDuration` -- orders attempting to specify a duration longer than this will be reverted
 - `uint256 minimumDepositAmount` -- orders  attempting to deposit less USDC than this will be reverted


### Function `addApprover(...)`

#### Parameters: 
 - `address approver` - address of the approver to add


### Function `removeApprover(...)`

#### Parameters: 
 - `address approver` - address of the approver to remove


### Query `openDeposits(...)`
# silentswap-v2-gateway
