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

    const INITIAL_SUPPLY = ethers.utils.parseEther("1000000"); // 1M tokens
    const MIN_COLLATERAL_RATIO = 14000; // 140%

    async function deployVltUSDFixture() {
        const [owner, user1, user2, admin, minter, burner, kycOperator, compliance] = await ethers.getSigners();

        // Deploy mock oracle
        const OracleFactory = await ethers.getContractFactory("ChainlinkOracle");
        const oracle = await OracleFactory.deploy(await owner.getAddress());

        // Deploy mock token for collateral
        const MockTokenFactory = await ethers.getContractFactory("MockERC20");
        const mockToken = await MockTokenFactory.deploy("Mock Token", "MTK");

        // Deploy VltUSD implementation
        const VltUSDFactory = await ethers.getContractFactory("VltUSD");
        const vltUSDImpl = await VltUSDFactory.deploy();

        // Deploy proxy
        const ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
        const proxy = await ProxyFactory.deploy(
            vltUSDImpl.address,
            vltUSDImpl.interface.encodeFunctionData("initialize", [
                "vltUSD",
                "vltUSD",
                await admin.getAddress(),
                oracle.address,
                MIN_COLLATERAL_RATIO
            ])
        );

        const vltUSD = VltUSDFactory.attach(proxy.address);

        // Set up price feed in oracle
        const mockPriceFeed = await ethers.getContractFactory("MockAggregatorV3");
        const priceFeed = await mockPriceFeed.deploy(8, 200000000); // $2000 price
        await oracle.setPriceFeed(mockToken.address, priceFeed.address);

        // Grant roles
        await vltUSD.grantRole(await vltUSD.MINTER_ROLE(), await minter.getAddress());
        await vltUSD.grantRole(await vltUSD.BURNER_ROLE(), await burner.getAddress());
        await vltUSD.grantRole(await vltUSD.KYC_OPERATOR_ROLE(), await kycOperator.getAddress());
        await vltUSD.grantRole(await vltUSD.COMPLIANCE_ROLE(), await compliance.getAddress());

        // Add collateral support
        await vltUSD.setCollateralSupport(mockToken.address, true);

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
            expect(await vltUSD.oracle()).to.equal(oracle.address);
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
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, mockToken.address, collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "KYCNotVerified");
        });
    });

    describe("Minting", function () {
        beforeEach(async function () {
            // Verify KYC for user1
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
            
            // Mint collateral tokens to user1
            await mockToken.mint(await user1.getAddress(), ethers.utils.parseEther("1000"));
            await mockToken.connect(user1).approve(vltUSD.address, ethers.utils.parseEther("1000"));
        });

        it("Should mint tokens with sufficient collateral", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await vltUSD.connect(minter).mint(userAddress, mintAmount, mockToken.address, collateralAmount);

            expect(await vltUSD.balanceOf(userAddress)).to.equal(mintAmount);
            expect(await vltUSD.reserves(mockToken.address)).to.equal(collateralAmount);
        });

        it("Should revert with insufficient collateral", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("0.5"); // Insufficient

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, mockToken.address, collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "InsufficientCollateral");
        });

        it("Should revert with unsupported collateral", async function () {
            const userAddress = await user1.getAddress();
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, ethers.constants.AddressZero, collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "CollateralNotSupported");
        });
    });

    describe("Burning", function () {
        beforeEach(async function () {
            // Verify KYC for user1
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
            
            // Mint tokens and collateral
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");
            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(vltUSD.address, collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, mockToken.address, collateralAmount);
        });

        it("Should burn tokens and return collateral", async function () {
            const userAddress = await user1.getAddress();
            const burnAmount = ethers.utils.parseEther("500");
            const initialBalance = await mockToken.balanceOf(userAddress);

            await vltUSD.connect(burner).burn(userAddress, burnAmount, mockToken.address);

            expect(await vltUSD.balanceOf(userAddress)).to.equal(ethers.utils.parseEther("500"));
            expect(await vltUSD.reserves(mockToken.address)).to.be.lt(ethers.utils.parseEther("1"));
        });

        it("Should revert with insufficient reserves", async function () {
            const userAddress = await user1.getAddress();
            const burnAmount = ethers.utils.parseEther("2000"); // More than minted

            await expect(
                vltUSD.connect(burner).burn(userAddress, burnAmount, mockToken.address)
            ).to.be.revertedWithCustomError(vltUSD, "InsufficientCollateral");
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

            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(userAddress, mintAmount, mockToken.address, collateralAmount)
            ).to.be.revertedWithCustomError(vltUSD, "UserBlacklisted");
        });

        it("Should prevent blacklisted users from transferring", async function () {
            // First mint tokens to user1
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");
            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(vltUSD.address, collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, mockToken.address, collateralAmount);

            // Blacklist user1
            await vltUSD.connect(compliance).setBlacklistStatus(await user1.getAddress(), true);

            // Try to transfer
            await expect(
                vltUSD.connect(user1).transfer(await user2.getAddress(), ethers.utils.parseEther("100"))
            ).to.be.revertedWithCustomError(vltUSD, "UserBlacklisted");
        });
    });

    describe("Reserves and Collateral", function () {
        beforeEach(async function () {
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);
        });

        it("Should calculate total reserves correctly", async function () {
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(vltUSD.address, collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, mockToken.address, collateralAmount);

            const totalReservesUSD = await vltUSD.getTotalReservesUSD();
            expect(totalReservesUSD).to.be.gt(0);
        });

        it("Should calculate collateral ratio correctly", async function () {
            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await mockToken.mint(await user1.getAddress(), collateralAmount);
            await mockToken.connect(user1).approve(vltUSD.address, collateralAmount);
            await vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, mockToken.address, collateralAmount);

            const collateralRatio = await vltUSD.getCollateralRatio(mockToken.address);
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

            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await expect(
                vltUSD.connect(minter).mint(await user1.getAddress(), mintAmount, mockToken.address, collateralAmount)
            ).to.be.revertedWith("Pausable: paused");
        });
    });

    describe("Access Control", function () {
        it("Should prevent non-authorized users from minting", async function () {
            await vltUSD.connect(kycOperator).setKYCStatus(await user1.getAddress(), true);

            const mintAmount = ethers.utils.parseEther("1000");
            const collateralAmount = ethers.utils.parseEther("1");

            await expect(
                vltUSD.connect(user1).mint(await user1.getAddress(), mintAmount, mockToken.address, collateralAmount)
            ).to.be.revertedWith("AccessControl");
        });

        it("Should prevent non-authorized users from burning", async function () {
            await expect(
                vltUSD.connect(user1).burn(await user1.getAddress(), ethers.utils.parseEther("100"), mockToken.address)
            ).to.be.revertedWith("AccessControl");
        });
    });
}); 