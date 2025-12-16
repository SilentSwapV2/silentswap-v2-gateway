import '@nomicfoundation/hardhat-toolbox';
import 'dotenv/config';
import 'hardhat-contract-sizer';
import { HardhatUserConfig } from 'hardhat/types';

const P_RPC_AVALANCHE_MAINNET = process.env.RPC_AVALANCHE_MAINNET || '';
const P_RPC_AVALANCHE_TESTNET = process.env.RPC_AVALANCHE_TESTNET || '';

const P_API_SNOWTRACE_TESTNET = 'https://api.routescan.io/v2/network/testnet/evm/43113/etherscan';


const S0X_DEPLOYER_SECRET_KEY = process.env.S0X_DEPLOYER_SECRET_KEY || '';

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || '';

const GC_HARDHAT: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  solidity: {
    compilers: [
      {
        version: '0.8.20',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY, // V2 requires a single Etherscan key (works across supported explorers)
    customChains: [
      {
        network: 'snowtrace',
        chainId: 43114,
        urls: {
          apiURL: 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan',
          browserURL: 'https://snowtrace.io',
        },
      },
      {
        network: 'fuji',
        chainId: 43113,
        urls: {
          apiURL: 'https://api.routescan.io/v2/network/testnet/evm/43113/etherscan',
          browserURL: 'https://testnet.snowtrace.io',
        },
      },
      {
        network: 'bsc',
        chainId: 56,
        urls: {
          apiURL: 'https://api.bscscan.com/api',
          browserURL: 'https://bscscan.com',
        },
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 43113,
      forking: {
        url: P_RPC_AVALANCHE_MAINNET, // Avalanche C-Chain RPC
        //blockNumber: 55292094, // Specify the block number to fork from
        enabled: true,
      },
    },
    bsc: {
      chainId: 56,
      url: 'https://bsc-dataseed.binance.org/',
      accounts: [
        S0X_DEPLOYER_SECRET_KEY,
      ],
    },
    fuji: {
      chainId: 43113,
      url: P_RPC_AVALANCHE_TESTNET,
      accounts: [
        S0X_DEPLOYER_SECRET_KEY,
        // {
        //   privateKey: S0X_DEPLOYER_SECRET_KEY,
        //   balance: ((2n ** 256n) - 1n)+'',
        // },
      ],
    },
    snowtrace: {
      chainId: 43114,
      url: 'https://api.avax.network/ext/bc/C/rpc',
      accounts: [
        S0X_DEPLOYER_SECRET_KEY,
      ],
    },
  
  },
  // dodoc: {
  //   runOnCompile: false,
  //   debugMode: true,
  //   include: ["contracts/UmeeToken.sol"],
  //   // More options...
  // },
  // gasReporter: {
  //   enabled: true,
  //   currency: "USD",
  // },
  // etherscan: {
  //   apiKey: {
  //     ryoshi: "abc",
  //   },
  //   customChains: [
  //     {
  //       network: "ryoshi",
  //       chainId: 117722,
  //       urls: {
  //         apiURL: "https://explorer.ryoshiresearch.com/api/v2",
  //         browserURL: "https://explorer.ryoshiresearch.com/",
  //       },
  //     },
  //   ],
  // },
  // contractSizer: {
  //   alphaSort: true,
  //   disambiguatePaths: false,
  //   runOnCompile: true,
  //   strict: true,
  // },
};

export default GC_HARDHAT;
