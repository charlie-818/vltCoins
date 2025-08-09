import { expect } from "chai";
import { ethers } from "hardhat";

describe("VltUSDY", function () {
  it("deposits and withdraws treasury asset; accrues yield", async function () {
    const [admin, user] = await ethers.getSigners();

    // Mock treasury asset
    const MockToken = await ethers.getContractFactory("MockERC20");
    const treasury = await MockToken.deploy("Treasury", "TRSY");

    // Mint to user
    await treasury.mint(await user.getAddress(), ethers.parseEther("1000"));

    // Oracle
    const Oracle = await ethers.getContractFactory("ChainlinkOracle");
    const oracle = await Oracle.deploy(await admin.getAddress());

    // Deploy impl + proxy
    const Impl = await ethers.getContractFactory("VltUSDY");
    const impl = await Impl.deploy();
    const Proxy = await ethers.getContractFactory("MockERC1967Proxy");
    const proxy = await Proxy.deploy(
      await impl.getAddress(),
      impl.interface.encodeFunctionData("initialize", [
        await treasury.getAddress(),
        await oracle.getAddress(),
        await admin.getAddress(),
        300 // 3% initial yield
      ])
    );
    const vltUSDY = Impl.attach(await proxy.getAddress());

    // Approve and deposit
    await treasury.connect(user).approve(await vltUSDY.getAddress(), ethers.parseEther("500"));
    await vltUSDY.connect(user).deposit(ethers.parseEther("500"), await user.getAddress());

    expect(await vltUSDY.balanceOf(await user.getAddress())).to.equal(ethers.parseEther("500"));

    // Redeem some
    await vltUSDY.connect(user).redeem(ethers.parseEther("100"), await user.getAddress(), await user.getAddress());
    expect(await vltUSDY.balanceOf(await user.getAddress())).to.equal(ethers.parseEther("400"));
  });
});


