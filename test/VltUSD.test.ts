import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory, Signer, BigNumber } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("VltUSD", function () {
    let vltUSD: Contract;
    let oracle: Contract;
    let mockToken: Contract;
    let owner: Signer;
    let user1: Signer;
    let user2: Signer;
    let admin: Signer;
    let minter: Signer;
    let burner: Signer;
    let kycOperator: Signer;
    let compliance: Signer;

    const INITIAL_SUPPLY = ethers.parseEther("1000000"); // 1M tokens
    const MIN_COLLATERAL_RATIO = 14000; // 140%

    async function deployVltUSDFixture() {
        const [owner, user1, user2, admin, minter, burner, kycOperator, compliance] = await ethers.getSigners();

        // Deploy mock oracle
        const OracleFactory = await ethers.getContractFactory("ChainlinkOracle");
        const oracle = await OracleFactory.deploy(await owner.getAddress());

        // Deploy mock token for collateral
        const MockTokenFactory = await ethers.getContractFactory("MockERC20");
        const mockToken = await MockTokenFactory.deploy("Mock Token", "MTK");

        // Deploy VltUSD behind a simple ERC1967 proxy for realism
        const VltUSDFactory = await ethers.getContractFactory("VltUSD");
        const impl = await VltUSDFactory.deploy();
        const Proxy = await ethers.getContractFactory("MockERC1967Proxy");
        const proxy = await Proxy.deploy(
            await impl.getAddress(),
            impl.interface.encodeFunctionData("initialize", [
                "vltUSD",
                "vltUSD",
                await admin.getAddress(),
                await oracle.getAddress(),
                MIN_COLLATERAL_RATIO,
            ])
        );
        const vltUSD = VltUSDFactory.attach(await proxy.getAddress());

        // Set up price feed in oracle
        const mockPriceFeed = await ethers.getContractFactory("MockAggregatorV3");
        const priceFeed = await mockPriceFeed.deploy(8, 200000000000); // $2000 price (8 decimals)
        await oracle.setPriceFeed(await mockToken.getAddress(), await priceFeed.getAddress());

        // Grant roles
        await vltUSD.connect(admin).grantRole(await vltUSD.MINTER_ROLE(), await minter.getAddress());
        await vltUSD.connect(admin).grantRole(await vltUSD.BURNER_ROLE(), await burner.getAddress());
        await vltUSD.connect(admin).grantRole(await vltUSD.KYC_OPERATOR_ROLE(), await kycOperator.getAddress());
        await vltUSD.connect(admin).grantRole(await vltUSD.COMPLIANCE_ROLE(), await compliance.getAddress());

        // Add collateral support
        await vltUSD.connect(admin).setCollateralSupport(await mockToken.getAddress(), true);

        return { vltUSD, oracle, mockToken, owner, user1, user2, admin, minter, burner, kycOperator, compliance };
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deployVltUSDFixture);
        vltUSD = fixture.vltUSD;
        oracle = fixture.oracle;
        mockToken = fixture.mockToken;
        owner = fixture.owner;
        user1 = fixture.user1;
        user2 = fixture.user2;
        admin = fixture.admin;
        minter = fixture.minter;
        burner = fixture.burner;
        kycOperator = fixture.kycOperator;
        compliance = fixture.compliance;
    });

    describe("Deployment", function () {
        it("Should initialize with correct parameters", async function () {
            expect(await vltUSD.name()).to.equal("vltUSD");
            expect(await vltUSD.symbol()).to.equal("vltUSD");
            expect(await vltUSD.decimals()).to.equal(18);
            expect(await vltUSD.minCollateralRatio()).to.equal(MIN_COLLATERAL_RATIO);
            expect(await vltUSD.oracle()).to.equal(await oracle.getAddress());
        });

        it("Should grant correct roles to admin", async function () {
            const adminAddress = await admin.getAddress();
            expect(await vltUSD.hasRole(await vltUSD.DEFAULT_ADMIN_ROLE(), adminAddress)).to.be.true;
            expect(await vltUSD.hasRole(await vltUSD.MINTER_ROLE(), adminAddress)).to.be.true;
            expect(await vltUSD.hasRole(await vltUSD.BURNER_ROLE(), adminAddress)).to.be.true;
        });
    });

    describe("KYC Management", function () {
        it("Should allow KYC operator to verify users", async function () {
            const userAddress = await user1.getAddress();
            await vltUSD.connect(kycOperator).setKYCStatus(userAddress, true);
            expect(await vltUSD.kycVerified(userAddress)).to.be.true;
        });

        it("Should prevent non-KYC users from minting", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, await mockToken.getAddress(), collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "KYCNotVerified");
        });
    });

    describe("Minting", function () {
        beforeEach(async function () {
            // Verify KYC for user1
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
            
            // Mint collateral tokens to user1
            await mockToken.mint(await user1.getAddress(), ethers.parseEther("1000"));
            await mockToken.connect(user1).approve(await vltUSD.getAddress(), ethers.parseEther("1000"));
        });

        it("Should mint tokens with sufficient collateral", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await vltUSD.connect(minter).mint(userAddress, mintAmount, await mockToken.getAddress(), collateralAmount);

            expect(await vltUSD.balanceOf(userAddress)).to.equal(mintAmount);
            expect(await vltUSD.reserves(await mockToken.getAddress())).to.equal(collateralAmount);
        });

        it("Should revert with insufficient collateral", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("0.5"); // Insufficient

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, await mockToken.getAddress(), collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "InsufficientCollateral");
        });

        it("Should revert with unsupported collateral", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, ethers.ZeroAddress, collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "CollateralNotSupported");
        });
    });

    describe("Burning", function () {
        beforeEach(async function () {
            // Verify KYC for user1
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
            
            // Mint tokens and collateral
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");
            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(await vltUSD.getAddress(), collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, await mockToken.getAddress(), collateralAmount);
        });

        it("Should burn tokens and return collateral", async function () {
            const userAddress = await user1.getAddress();
            const burnAmount = ethers.parseEther("500");
            const initialBalance = await mockToken.balanceOf(userAddress);

            await vltUSD.connect(burner).burn(userAddress, burnAmount, await mockToken.getAddress());

            expect(await vltUSD.balanceOf(userAddress)).to.equal(ethers.parseEther("500"));
            expect(await vltUSD.reserves(await mockToken.getAddress())).to.be.lt(ethers.parseEther("1"));
        });

        it("Should revert with insufficient reserves", async function () {
            const userAddress = await user1.getAddress();
            const burnAmount = ethers.parseEther("2000"); // More than minted

            await expect(
                vltUSD.connect(burner).burn(userAddress, burnAmount, await mockToken.getAddress())
            ).to.be.reverted;
        });
    });

    describe("Compliance", function () {
        it("Should allow compliance to blacklist users", async function () {
            const userAddress = await user1.getAddress();
            await vltUSD.connect(compliance).setBlacklistStatus(userAddress, true);
            expect(await vltUSD.blacklisted(userAddress)).to.be.true;
        });

        it("Should prevent blacklisted users from minting", async function () {
            const userAddress = await user1.getAddress();
            await vltUSD.connect(kycOperator).setKYCStatus(userAddress, true);
            await vltUSD.connect(compliance).setBlacklistStatus(userAddress, true);

            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, await mockToken.getAddress(), collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "UserBlacklisted");
        });

        it("Should prevent blacklisted users from transferring", async function () {
            // First mint tokens to user1
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");
            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(await vltUSD.getAddress(), collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, await mockToken.getAddress(), collateralAmount);

            // Blacklist user1
            await vltUSD.connect(compliance).setBlacklistStatus(await user1.getAddress(), true);

            // Try to transfer
            await expect(
                vltUSD.connect(user1).transfer(await user2.getAddress(), ethers.parseEther("100"))
            ).to.be.revertedWithCustomError(vltUSD, "UserBlacklisted");
        });
    });

    describe("Reserves and Collateral", function () {
        beforeEach(async function () {
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
        });

        it("Should calculate total reserves correctly", async function () {
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(await vltUSD.getAddress(), collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, await mockToken.getAddress(), collateralAmount);

            const totalReservesUSD = await vltUSD.getTotalReservesUSD();
            expect(totalReservesUSD).to.be.gt(0);
        });

        it("Should calculate collateral ratio correctly", async function () {
            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(await vltUSD.getAddress(), collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, await mockToken.getAddress(), collateralAmount);

            const collateralRatio = await vltUSD.getCollateralRatio(await mockToken.getAddress());
            expect(collateralRatio).to.be.gte(MIN_COLLATERAL_RATIO);
        });
    });

    describe("Pausing", function () {
        it("Should allow admin to pause and unpause", async function () {
            await vltUSD.connect(admin).pause();
            expect(await vltUSD.paused()).to.be.true;

            await vltUSD.connect(admin).unpause();
            expect(await vltUSD.paused()).to.be.false;
        });

        it("Should prevent operations when paused", async function () {
            await vltUSD.connect(admin).pause();
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);

            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, await mockToken.getAddress(), collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "EnforcedPause");
        });
    });

    describe("Access Control", function () {
        it("Should prevent non-authorized users from minting", async function () {
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);

            const mintAmount = ethers.parseEther("1000");
            const collateralAmount = ethers.parseEther("1");

            await expect(
                vltUSD.connect(user1).mint(await user1.getAddress(), mintAmount, await mockToken.getAddress(), collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "AccessControlUnauthorizedAccount");
        });

        it("Should prevent non-authorized users from burning", async function () {
            await expect(
                vltUSD.connect(user1).burn(await user1.getAddress(), ethers.parseEther("100"), await mockToken.getAddress())
            ).to.be.revertedWithCustomError(vltUSD, "AccessControlUnauthorizedAccount");
        });
    });
}); 