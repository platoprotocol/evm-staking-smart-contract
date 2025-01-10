import { ethers } from "hardhat";

const { FAT_TOKEN_ADDRESS = "" } = process.env;

const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  // Hardcoded token address
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const tokenAddress = FAT_TOKEN_ADDRESS;
  const apyPercentage = 50;
  const apyDuration = 10; // seconds
  const exitPenaltyPercentage = 5;
  const withdrawFee = 1;

  console.log({
    deployerAddress,
    tokenAddress,
    apyPercentage,
    apyDuration,
    exitPenaltyPercentage,
    withdrawFee,
  });

  // Get the contract factory
  const StakingVault = await ethers.getContractFactory("StakingVault");

  // Deploy the contract with the token address
  console.log("deploying StakingVault");
  const stakingVault = await StakingVault.deploy(
    tokenAddress,
    apyPercentage,
    apyDuration,
    exitPenaltyPercentage,
    withdrawFee
  );

  // Wait for the deployment to be mined
  console.log("waiting for deployment");
  await stakingVault.waitForDeployment();
  const stakingVaultAddress = await stakingVault.getAddress();

  console.log("StakingVault deployed to:", stakingVaultAddress);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
