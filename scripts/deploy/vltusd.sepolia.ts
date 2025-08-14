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

  // Basic sanity test: set up mock collateral and mint/burn
  console.log("\nRunning basic on-chain sanity test for VltUSD...");
  const MockTokenFactory = await ethers.getContractFactory("MockERC20");
  const collateral = await MockTokenFactory.deploy("Mock Collateral", "MCOLL");
  await collateral.waitForDeployment();
  const collateralAddress = await collateral.getAddress();
  console.log("Collateral:", collateralAddress);

  const MockAggFactory = await ethers.getContractFactory("MockAggregatorV3");
  const feed = await MockAggFactory.deploy(8, 2000_00000000); // $2000
  await feed.waitForDeployment();
  const feedAddress = await feed.getAddress();
  console.log("PriceFeed:", feedAddress);

  // Wire oracle and collateral support
  await (await oracle.setPriceFeed(collateralAddress, feedAddress)).wait();
  await (await vltUSD.setCollateralSupport(collateralAddress, true)).wait();

  // Mint some collateral to deployer and approve
  await (await collateral.mint(await deployer.getAddress(), ethers.parseEther("100"))).wait();
  await (await collateral.approve(vltUSDAddress, ethers.parseEther("100"))).wait();

  // KYC deployer
  await (await vltUSD.setKYCStatus(await deployer.getAddress(), true)).wait();

  // Mint and burn
  const mintAmount = ethers.parseEther("10");
  const collateralDeposit = ethers.parseEther("1");
  await (await vltUSD.mint(await deployer.getAddress(), mintAmount, collateralAddress, collateralDeposit)).wait();
  console.log("Minted", mintAmount.toString(), "vltUSD to", await deployer.getAddress());

  await (await vltUSD.burn(await deployer.getAddress(), ethers.parseEther("1"), collateralAddress)).wait();
  console.log("Burned 1 vltUSD");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});


