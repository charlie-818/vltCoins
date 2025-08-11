import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", await deployer.getAddress());

  // Deploy Oracle (admin = deployer)
  console.log("Deploying ChainlinkOracle...");
  const OracleFactory = await ethers.getContractFactory("ChainlinkOracle");
  const oracle = await OracleFactory.deploy(await deployer.getAddress());
  await oracle.waitForDeployment();
  const oracleAddress = await oracle.getAddress();
  console.log("Oracle:", oracleAddress);

  // Deploy VltUSD (UUPS proxy)
  console.log("Deploying VltUSD (proxy)...");
  const VltUSDFactory = await ethers.getContractFactory("VltUSD");
  const vltUSD = await upgrades.deployProxy(
    VltUSDFactory,
    [
      "vltUSD",
      "vltUSD",
      await deployer.getAddress(),
      oracleAddress,
      14000,
    ],
    { kind: "uups" }
  );
  await vltUSD.waitForDeployment();
  const vltUSDAddress = await vltUSD.getAddress();
  console.log("VltUSD:", vltUSDAddress);

  // Example: grant roles to deployer (already admin, but explicit)
  console.log("Granting roles to deployer...");
  await (await vltUSD.grantRole(await vltUSD.MINTER_ROLE(), await deployer.getAddress())).wait();
  await (await vltUSD.grantRole(await vltUSD.BURNER_ROLE(), await deployer.getAddress())).wait();
  await (await vltUSD.grantRole(await vltUSD.KYC_OPERATOR_ROLE(), await deployer.getAddress())).wait();
  await (await vltUSD.grantRole(await vltUSD.COMPLIANCE_ROLE(), await deployer.getAddress())).wait();

  console.log("Done. Addresses:")
  console.log("- Oracle:", oracleAddress);
  console.log("- VltUSD:", vltUSDAddress);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});


