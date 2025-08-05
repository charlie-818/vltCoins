import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", await deployer.getAddress());

    // Deploy Oracle
    console.log("Deploying ChainlinkOracle...");
    const OracleFactory = await ethers.getContractFactory("ChainlinkOracle");
    const oracle = await OracleFactory.deploy(await deployer.getAddress());
    await oracle.deployed();
    console.log("ChainlinkOracle deployed to:", oracle.address);

    // Deploy VltUSD
    console.log("Deploying VltUSD...");
    const VltUSDFactory = await ethers.getContractFactory("VltUSD");
    const vltUSD = await upgrades.deployProxy(VltUSDFactory, [
        "vltUSD",
        "vltUSD",
        await deployer.getAddress(),
        oracle.address,
        14000 // 140% minimum collateral ratio
    ]);
    await vltUSD.deployed();
    console.log("VltUSD deployed to:", vltUSD.address);

    // Deploy VltUSDY
    console.log("Deploying VltUSDY...");
    const VltUSDYFactory = await ethers.getContractFactory("VltUSDY");
    
    // Deploy mock treasury asset for testing
    const MockTokenFactory = await ethers.getContractFactory("MockERC20");
    const treasuryAsset = await MockTokenFactory.deploy("Treasury Bond", "TBOND");
    await treasuryAsset.deployed();
    console.log("Mock Treasury Asset deployed to:", treasuryAsset.address);

    const vltUSDY = await upgrades.deployProxy(VltUSDYFactory, [
        treasuryAsset.address,
        oracle.address,
        await deployer.getAddress(),
        500 // 5% initial yield rate
    ]);
    await vltUSDY.deployed();
    console.log("VltUSDY deployed to:", vltUSDY.address);

    // Deploy VltUSDe
    console.log("Deploying VltUSDe...");
    const VltUSDeFactory = await ethers.getContractFactory("VltUSDe");
    
    // Deploy mock price feeds
    const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
    const ethUsdFeed = await MockAggregatorFactory.deploy(8, 200000000); // $2000 ETH
    await ethUsdFeed.deployed();
    console.log("ETH/USD Price Feed deployed to:", ethUsdFeed.address);

    const stEthEthFeed = await MockAggregatorFactory.deploy(8, 100000000); // 1:1 ratio
    await stEthEthFeed.deployed();
    console.log("stETH/ETH Price Feed deployed to:", stEthEthFeed.deployed());

    const vltUSDe = await upgrades.deployProxy(VltUSDeFactory, [
        "vltUSDe",
        "vltUSDe",
        await deployer.getAddress(),
        oracle.address,
        ethUsdFeed.address,
        stEthEthFeed.address
    ]);
    await vltUSDe.deployed();
    console.log("VltUSDe deployed to:", vltUSDe.address);

    // Set up oracle price feeds
    console.log("Setting up oracle price feeds...");
    await oracle.setPriceFeed(treasuryAsset.address, ethUsdFeed.address);
    await oracle.setPriceFeed(ethers.constants.AddressZero, ethUsdFeed.address); // ETH

    // Grant roles
    console.log("Setting up roles...");
    await vltUSD.grantRole(await vltUSD.MINTER_ROLE(), await deployer.getAddress());
    await vltUSD.grantRole(await vltUSD.BURNER_ROLE(), await deployer.getAddress());
    await vltUSD.grantRole(await vltUSD.KYC_OPERATOR_ROLE(), await deployer.getAddress());
    await vltUSD.grantRole(await vltUSD.COMPLIANCE_ROLE(), await deployer.getAddress());

    await vltUSDY.grantRole(await vltUSDY.ADMIN_ROLE(), await deployer.getAddress());
    await vltUSDY.grantRole(await vltUSDY.OPERATOR_ROLE(), await deployer.getAddress());
    await vltUSDY.grantRole(await vltUSDY.YIELD_MANAGER_ROLE(), await deployer.getAddress());

    await vltUSDe.grantRole(await vltUSDe.MINTER_ROLE(), await deployer.getAddress());
    await vltUSDe.grantRole(await vltUSDe.BURNER_ROLE(), await deployer.getAddress());
    await vltUSDe.grantRole(await vltUSDe.LIQUIDATOR_ROLE(), await deployer.getAddress());
    await vltUSDe.grantRole(await vltUSDe.STAKING_MANAGER_ROLE(), await deployer.getAddress());

    // Add collateral support
    console.log("Adding collateral support...");
    await vltUSD.setCollateralSupport(treasuryAsset.address, true);
    await vltUSDe.setCollateralSupport(ethers.constants.AddressZero, true); // ETH

    console.log("Deployment completed successfully!");
    console.log("Oracle:", oracle.address);
    console.log("VltUSD:", vltUSD.address);
    console.log("VltUSDY:", vltUSDY.address);
    console.log("VltUSDe:", vltUSDe.address);
    console.log("Treasury Asset:", treasuryAsset.address);
    console.log("ETH/USD Feed:", ethUsdFeed.address);
    console.log("stETH/ETH Feed:", stEthEthFeed.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 