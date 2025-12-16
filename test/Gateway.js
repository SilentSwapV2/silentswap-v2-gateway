const {
  time,
  loadFixture,
  mine,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, network, utils, AbiCoder } = require("hardhat");

const abiCoder = ethers.AbiCoder.defaultAbiCoder();

// Address of the USDC token contract on Avalanche C-Chain
// This is the official USDC contract address that we'll interact with
const USDC_ADDRESS = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";

describe("SilentSwapV2Gateway", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployGatewayFixture() {
    //avoid hardhat network to fork from the current block
    await mine();

    // Get signers for testing
    const [owner, otherAccount, notary, approver, refundee, signer] =
      await ethers.getSigners();

    const USDC = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20",
      USDC_ADDRESS
    );
    console.log("USDC decimals:", await USDC.decimals());

    // Define config parameters
    const config = {
      minDuration: 3600, // 1 hour in seconds
      maxDuration: 86400, // 24 hours in seconds
      minDepositAmount: ethers.parseUnits("1", 6), // 1 USDC (6 decimals)
    };

    // Deploy the SilentSwapV2Gateway contract
    const Gateway = await ethers.getContractFactory("SilentSwapV2Gateway");
    const gateway = await Gateway.deploy(USDC_ADDRESS, config);

    return {
      gateway,
      USDC,
      owner,
      notary,
      signer,
      approver,
      refundee,
      config,
      otherAccount,
    };
  }

  describe("Deployment", function () {
    it("Should deploy successfully", async function () {
      const { gateway } = await loadFixture(deployGatewayFixture);
      expect(await gateway.getAddress()).to.be.properAddress;
    });

    it("Should set the correct USDC address", async function () {
      const { gateway } = await loadFixture(deployGatewayFixture);
      expect(await gateway.usdc()).to.equal(USDC_ADDRESS);
    });

    it("Should be a valid USDC contract", async function () {
      const { USDC } = await loadFixture(deployGatewayFixture);
      const decimals = await USDC.decimals();
      const symbol = await USDC.symbol();
      const name = await USDC.name();
      expect(decimals).to.equal(6); // USDC uses 6 decimals
      expect(symbol).to.equal("USDC");
      expect(name).to.equal("USD Coin");
    });

    it("Should set the correct initial config", async function () {
      const { gateway, config } = await loadFixture(deployGatewayFixture);
      const deployedConfig = await gateway.config();
      expect(deployedConfig.minDuration).to.equal(config.minDuration);
      expect(deployedConfig.maxDuration).to.equal(config.maxDuration);
      expect(deployedConfig.minDepositAmount).to.equal(config.minDepositAmount);
    });
  });

  describe("Deposit", function () {
    it("should deposit successfully with valid parameters", async function () {
      const { gateway, usdcMock, owner, signer, notary, approver, refundee } =
        await loadFixture(deployGatewayFixture);

      const orderId = ethers.encodeBytes32String("1");

      const domainSeparatorHash = ethers.keccak256(
        ethers.toUtf8Bytes("Domain Separator")
      );
      const payloadHash = ethers.keccak256(ethers.toUtf8Bytes("Payload Hash"));

      const approvalExpiration =
        (await ethers.provider.getBlock("latest")).timestamp + 3600; // 1 hour
      const duration = 3600; // 1 hour duration
      const depositAmount = ethers.parseUnits("500", 6); // 500 USDC

      // Simulate approval signature (ECDSA)
      const approvalMessageHash = ethers.keccak256(
        abiCoder.encode(
          ["bytes32", "address", "uint256"],
          [orderId, notary.address, approvalExpiration]
        )
      );
      const orderApprovalSignature = await approver.signMessage(
        ethers.toUtf8Bytes(approvalMessageHash)
      );

      // Simulate EIP712 typed data signature
      // Define EIP712 types
      const types = {
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
            { "name": "facilitatorPublicKeys", "type": "Facilitator" },
            { "name": "recipient", "type": "string" },
            { "name": "value", "type": "uint256" },
            { "name": "extra", "type": "string" }
        ],
        "Facilitator": [
            { "name": "coinType", "type": "uint256" },
            { "name": "keyType", "type": "string" },
            { "name": "publicKeyBytes", "type": "string" },
        ],
        "Metadata": [
            { "name": "notaryContract", "type": "NotaryContract" }
        ],
        "NotaryContract": [
            { "name": "chainId", "type": "string" },
            { "name": "contractAddress", "type": "string" },
            { "name": "signerAddress", "type": "address" }
        ]
      };

      // Define domain data
      const domain = {
        name: "SilentSwap",
        version: "1",
        chainId: 43114,
      };

      // Define message data
      const message = {
        quoteId: "",
        quote: {
          signer: "0xc434375761034eFC80850eF0b32e1882336ec439",
          nonce: "...",
          orderId: "5acfe611cf",
          privacy: "CHEAPEST",
          allocations: "WEIGHTED",
          deposit: "1000000000",
          fee: "1000000",
          outputs: [
            {
              method: "CCTP",
              chain: "eip155:1",
              token: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
              facilitatorPublicKeys: [
                {
                  coinType: "*",
                  keyType: "SECP256K1",
                  publicKeyBytes: "0x3f3d3e3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100ff",
                },
                {
                  coinType: "1",
                  keyType: "SECP256K1",
                  publicKeyBytes: "0x3f3d3e3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100ff",
                },
                {
                  coinType: "118",
                  keyType: "SECP256K1",
                  publicKeyBytes: "0x3f3d3e3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100ff",
                },
                {
                  coinType: "529",
                  keyType: "SECP256K1",
                  publicKeyBytes: "0x3f3d3e3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100ff",
                },
              ],
              recipient: "0xc434375761034eFC80850eF0b32e1882336ec439",
              value: "500000000000000000",
              extra: "",
            },
          ],
          metadata: {
            notaryContract: {
              chainId: "secret-4",
              contractAddres: "secret1...",
              signerAddress: "0x...."
            }
          },
        },
      };

      const typedDataSignature = await signer.signTypedData(
        domain,
        {
          Order: types.Order,
          Output: types.Output,
          Metadata: types.Metadata,
          CctpAttestors: types.CctpAttestors,
          AxelarValidators: types.AxelarValidators,
        },
        message
      );

      // Encode EIP3009 receiveAuthorization
      const receiveAuthorization = abiCoder.encode(
        ["address", "uint256"],
        [refundee.address, depositAmount]
      );

      // Approve the smart contract to spend USDC
      await usdcMock.connect(refundee).approve(gateway.address, depositAmount);

      const params = {
        signer: signer.address,
        orderId: orderId,
        notary: notary.address,
        approver: approver.address,
        orderApproval: orderApprovalSignature,
        approvalExpiration: approvalExpiration,
        duration: duration,
        domainSepHash: domainSeparatorHash,
        payloadHash: payloadHash,
        typedDataSignature: typedDataSignature,
        receiveAuthorization: receiveAuthorization,
      };

      // Expect successful deposit
      await expect(gateway.connect(refundee).deposit(params))
        .to.emit(gateway, "Deposit")
        .withArgs(signer.address, orderId, depositAmount, duration);

      // Check USDC balance
      const contractBalance = await usdcMock.balanceOf(gateway.address);
      expect(contractBalance).to.equal(depositAmount);

      // Verify order details
      const orderDetails = await gateway.orders(orderId);
      expect(orderDetails.amount).to.equal(depositAmount);
      expect(orderDetails.notary).to.equal(notary.address);
    });
  });

  describe("Owner", function () {
    it("Should return the correct owner", async function () {
      const { gateway, owner } = await loadFixture(deployGatewayFixture);
      expect(await gateway.owner()).to.equal(owner.address);
    });

    it("Should revert when non-owner tries to call onlyOwner functions", async function () {
      const { gateway, otherAccount } = await loadFixture(deployGatewayFixture);

      // Try to update config as non-owner
      await expect(
        gateway.connect(otherAccount).setConfig(
          7200, // minDuration
          172800, // maxDuration
          ethers.parseUnits("2", 6) // minDepositAmount
        )
      )
        .to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount")
        .withArgs(otherAccount.address);
    });
  });

  describe("Approver Management", function () {
    it("Should allow owner to add an approver", async function () {
      const { gateway, otherAccount } = await loadFixture(deployGatewayFixture);

      await expect(gateway.addApprover(otherAccount.address))
        .to.emit(gateway, "ApproverAdded")
        .withArgs(otherAccount.address);

      expect(await gateway.authorizedApprovers(otherAccount.address)).to.be
        .true;
    });

    it("Should revert when non-owner tries to add an approver", async function () {
      const { gateway, otherAccount } = await loadFixture(deployGatewayFixture);

      await expect(
        gateway.connect(otherAccount).addApprover(otherAccount.address)
      )
        .to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount")
        .withArgs(otherAccount.address);
    });

    it("Should allow owner to remove an approver", async function () {
      const { gateway, otherAccount } = await loadFixture(deployGatewayFixture);

      // First add an approver
      await gateway.addApprover(otherAccount.address);

      expect(await gateway.authorizedApprovers(otherAccount.address)).to.be
        .true;

      // Then remove them
      await expect(gateway.removeApprover(otherAccount.address))
        .to.emit(gateway, "ApproverRemoved")
        .withArgs(otherAccount.address);

      expect(await gateway.authorizedApprovers(otherAccount.address)).to.be
        .false;
    });

    it("Should revert when non-owner tries to remove an approver", async function () {
      const { gateway, otherAccount, owner } = await loadFixture(
        deployGatewayFixture
      );

      // First add an approver as owner
      await gateway.addApprover(otherAccount.address);

      // Try to remove as non-owner
      await expect(
        gateway.connect(otherAccount).removeApprover(otherAccount.address)
      )
        .to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount")
        .withArgs(otherAccount.address);
    });
  });
});
