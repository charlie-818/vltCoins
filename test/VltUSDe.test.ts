import { expect } from "chai";
import { ethers } from "hardhat";

describe("VltUSDe", function () {
  it("mints with ETH and burns for ETH within collateral ratio", async function () {
    const [admin, user] = await ethers.getSigners();

    // Deploy oracle
    const Oracle = await ethers.getContractFactory("ChainlinkOracle");
    const oracle = await Oracle.deploy(await admin.getAddress());

    // Mock feeds
    const MockAgg = await ethers.getContractFactory("MockAggregatorV3");
    const ethUsd = await MockAgg.deploy(8, 3000_00000000); // $3,000
    // set price feed mapping: we use the feed address itself as the asset key as per usage in contract
    await oracle.setPriceFeed(await ethUsd.getAddress(), await ethUsd.getAddress());

    // Deploy impl and proxy
    const Impl = await ethers.getContractFactory("VltUSDe");
    const impl = await Impl.deploy();
    const Proxy = await ethers.getContractFactory("MockERC1967Proxy");
    const proxy = await Proxy.deploy(
      await impl.getAddress(),
      impl.interface.encodeFunctionData("initialize", [
        "vltUSDe",
        "vltUSDe",
        await admin.getAddress(),
        await oracle.getAddress(),
        await ethUsd.getAddress(),
        ethers.ZeroAddress // not used in this test
      ])
    );
    const vltUSDe = Impl.attach(await proxy.getAddress());

    // Mint with ETH: target 100 vltUSDe
    const mintAmount = ethers.parseEther("100");
    // required collateral = amount * 140% / price
    // price = $3000 => 3000e8, amount = 100e18
    // required = 100e18 * 14000 * 1e8 / (3000e8 * 10000) = 100e18 * 1.4 / 3000 ~= 0.0466 ETH
    const collateral = ethers.parseEther("0.1");
    await vltUSDe.connect(user).mintWithETH(mintAmount, { value: collateral });

    expect(await vltUSDe.balanceOf(await user.getAddress())).to.equal(mintAmount);

    // Burn half and withdraw some ETH ensuring ratio maintained
    const burnAmount = ethers.parseEther("50");
    const withdrawAmount = ethers.parseEther("0.02");
    await vltUSDe.connect(user).burnForETH(burnAmount, withdrawAmount);

    expect(await vltUSDe.balanceOf(await user.getAddress())).to.equal(ethers.parseEther("50"));
  });
});


