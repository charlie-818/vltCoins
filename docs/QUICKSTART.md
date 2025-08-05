# vltCoins Quick Start Guide

This guide will help you get started with the vltCoins stablecoin suite quickly.

## Prerequisites

- Node.js 16+ 
- npm or yarn
- Git
- An Ethereum wallet with testnet ETH (Sepolia/Goerli)

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd vltCoins

# Install dependencies
npm install

# Copy environment file
cp env.example .env
```

## Configuration

Edit your `.env` file with your configuration:

```bash
# Network RPC URLs (get from Alchemy, Infura, etc.)
SEPOLIA_RPC_URL=https://eth-sepolia.alchemyapi.io/v2/YOUR_API_KEY
GOERLI_RPC_URL=https://eth-goerli.alchemyapi.io/v2/YOUR_API_KEY

# Your private key (for deployment)
PRIVATE_KEY=your_private_key_here

# API Keys
ETHERSCAN_API_KEY=your_etherscan_api_key

# Gas Reporter
REPORT_GAS=true
```

## Quick Start

### 1. Compile Contracts

```bash
npm run compile
```

### 2. Run Tests

```bash
# Run all tests
npm test

# Run with gas reporting
npm run gas

# Run with coverage
npm run test:coverage
```

### 3. Deploy to Testnet

```bash
# Deploy to Sepolia
npm run deploy:sepolia

# Verify contracts on Etherscan
npm run verify:sepolia
```

## Contract Overview

### vltUSD - Fully Collateralized Stablecoin

**Purpose**: Regulatory-compliant stablecoin with KYC controls.

**Key Functions**:
```javascript
// Mint tokens (requires KYC verification)
await vltUSD.connect(minter).mint(
    userAddress,
    ethers.utils.parseEther("1000"),
    collateralAddress,
    ethers.utils.parseEther("1")
);

// Burn tokens for collateral
await vltUSD.connect(burner).burn(
    userAddress,
    ethers.utils.parseEther("500"),
    collateralAddress
);

// Set KYC status
await vltUSD.connect(kycOperator).setKYCStatus(userAddress, true);
```

### vltUSDY - Treasury Yield Stablecoin

**Purpose**: Yield-bearing stablecoin backed by U.S. Treasury assets.

**Key Functions**:
```javascript
// Deposit treasury assets
await vltUSDY.deposit(
    ethers.utils.parseEther("1000"),
    userAddress
);

// Withdraw treasury assets
await vltUSDY.withdraw(
    ethers.utils.parseEther("500"),
    userAddress,
    userAddress
);

// Claim accumulated yield
await vltUSDY.claimYield(userAddress);
```

### vltUSDe - Algorithmic ETH-Collateralized Stablecoin

**Purpose**: Algorithmic stablecoin using ETH collateral with staking rewards.

**Key Functions**:
```javascript
// Mint with ETH collateral
await vltUSDe.mintWithETH(
    ethers.utils.parseEther("1000"),
    { value: ethers.utils.parseEther("1") }
);

// Mint with LSD collateral
await vltUSDe.mintWithLSD(
    lsdAddress,
    ethers.utils.parseEther("1"),
    ethers.utils.parseEther("1000")
);

// Claim staking rewards
await vltUSDe.claimStakingRewards(userAddress);
```

## Testing Examples

### Basic Interaction Test

```javascript
// Test vltUSD minting
describe("vltUSD Minting", function () {
    it("Should mint tokens with sufficient collateral", async function () {
        // Setup
        const userAddress = await user1.getAddress();
        const mintAmount = ethers.utils.parseEther("1000");
        const collateralAmount = ethers.utils.parseEther("1");

        // Verify KYC
        await vltUSD.connect(kycOperator).setKYCStatus(userAddress, true);

        // Mint tokens
        await vltUSD.connect(minter).mint(
            userAddress,
            mintAmount,
            mockToken.address,
            collateralAmount
        );

        // Verify
        expect(await vltUSD.balanceOf(userAddress)).to.equal(mintAmount);
    });
});
```

### Oracle Integration Test

```javascript
// Test oracle price feeds
describe("Oracle Integration", function () {
    it("Should get accurate price data", async function () {
        const price = await oracle.getPrice(mockToken.address);
        expect(price.price).to.be.gt(0);
        expect(price.timestamp).to.be.gt(0);
    });
});
```

## Development Workflow

### 1. Local Development

```bash
# Start local hardhat node
npx hardhat node

# Run tests on local network
npx hardhat test --network localhost
```

### 2. Contract Interaction

```javascript
// Connect to deployed contract
const vltUSD = await ethers.getContractAt("VltUSD", contractAddress);

// Get contract state
const totalSupply = await vltUSD.totalSupply();
const reserves = await vltUSD.getTotalReservesUSD();
```

### 3. Gas Optimization

```bash
# Check gas usage
npm run gas

# Optimize specific functions
npx hardhat size-contracts
```

## Common Issues & Solutions

### 1. Compilation Errors

**Issue**: Solidity version conflicts
```bash
# Solution: Update hardhat.config.ts
solidity: {
    version: "0.8.20",
    settings: {
        optimizer: {
            enabled: true,
            runs: 200,
        },
    },
}
```

### 2. Test Failures

**Issue**: Oracle not configured
```bash
# Solution: Set up mock price feeds in tests
const mockPriceFeed = await MockAggregatorFactory.deploy(8, 200000000);
await oracle.setPriceFeed(tokenAddress, mockPriceFeed.address);
```

### 3. Deployment Issues

**Issue**: Insufficient gas
```bash
# Solution: Increase gas limit in deployment script
const tx = await contract.deploy({
    gasLimit: 5000000
});
```

### 4. Role Access Errors

**Issue**: Missing role permissions
```bash
# Solution: Grant roles after deployment
await contract.grantRole(await contract.MINTER_ROLE(), minterAddress);
```

## Security Best Practices

### 1. Access Control

```javascript
// Always check roles before critical operations
modifier onlyRole(bytes32 role) {
    require(hasRole(role, msg.sender), "AccessControl: unauthorized");
    _;
}
```

### 2. Input Validation

```javascript
// Validate all inputs
function mint(address to, uint256 amount) external {
    require(to != address(0), "Invalid recipient");
    require(amount > 0, "Invalid amount");
    // ... rest of function
}
```

### 3. Reentrancy Protection

```javascript
// Use nonReentrant modifier
function withdraw(uint256 amount) external nonReentrant {
    // ... withdrawal logic
}
```

## Monitoring & Debugging

### 1. Event Logging

```javascript
// Listen to contract events
vltUSD.on("Minted", (to, amount, collateral, collateralAmount) => {
    console.log(`Minted ${amount} to ${to}`);
});
```

### 2. Gas Tracking

```bash
# Monitor gas usage
npm run gas

# Check specific function gas costs
npx hardhat test --gas
```

### 3. Error Handling

```javascript
// Handle contract errors
try {
    await contract.mint(user, amount);
} catch (error) {
    console.error("Mint failed:", error.message);
}
```

## Integration Examples

### 1. Frontend Integration

```javascript
// Web3.js integration
const provider = new ethers.providers.Web3Provider(window.ethereum);
const signer = provider.getSigner();
const vltUSD = new ethers.Contract(contractAddress, abi, signer);

// Mint tokens
const tx = await vltUSD.mint(userAddress, amount, collateral, collateralAmount);
await tx.wait();
```

### 2. Backend Integration

```javascript
// Node.js integration
const { ethers } = require("hardhat");
const vltUSD = await ethers.getContractAt("VltUSD", contractAddress);

// Get contract state
const totalSupply = await vltUSD.totalSupply();
const reserves = await vltUSD.getTotalReservesUSD();
```

## Next Steps

1. **Read the Documentation**: Check `README.md` and `docs/ARCHITECTURE.md`
2. **Run Tests**: Ensure all tests pass before deployment
3. **Deploy to Testnet**: Use Sepolia for testing
4. **Audit**: Consider professional security audit
5. **Monitor**: Set up monitoring and alerting

## Support

- **Documentation**: Check the docs folder
- **Issues**: Create GitHub issues for bugs
- **Discussions**: Use GitHub discussions for questions
- **Security**: Report security issues privately

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License. 