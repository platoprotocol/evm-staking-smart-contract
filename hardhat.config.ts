import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "@typechain/hardhat";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "@openzeppelin/hardhat-upgrades";

dotenv.config();
const { PRIVATE_KEY = "", CHAIN_ID = "", RPC_URL = "" } = process.env;

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    monadDev: {
      chainId: Number(CHAIN_ID),
      url: RPC_URL,
      accounts: [PRIVATE_KEY],
    }
  },
};

export default config;
