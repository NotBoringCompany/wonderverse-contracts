import { vars, type HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import * as dotenv from "dotenv";

dotenv.config();

const deployerWallet: string = process.env.DEPLOYER_PRIVATE_KEY ?? '';
const ETHERSCAN_API_KEY = vars.get("ETHERSCAN_API_KEY");

const config: HardhatUserConfig = {
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  networks: {
    blastSepolia: {
      url: "https://sepolia.blast.io",
      accounts: [`0x${deployerWallet}`],
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_KEY}`,
      chainId: 11155111,
      accounts: [`0x${deployerWallet}`],
      gasPrice: "auto",
    },
    baseSepolia: {
      url: `https://sepolia.base.org`,
      chainId: 84532,
      accounts: [`0x${deployerWallet}`],
    }
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true,
    }
  }
};

export default config;
