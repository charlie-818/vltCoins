# vltCoins - Interconnected Ethereum-Based Stablecoin Suite

A comprehensive suite of three interoperable Ethereum-based stablecoins designed for maximum functionality with minimal changes, prioritizing efficiency and security.

## Overview

The vltCoins suite consists of three distinct stablecoins, each serving specific use cases while maintaining interoperability:

1. **vltUSD** - Fully Collateralized USD Stablecoin
2. **vltUSDY** - On-Chain U.S. Treasury Yield Stablecoin  
3. **vltUSDe** - Ethereum-Collateralized, Yield-Bearing Algorithmic Stablecoin

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     vltUSD      │    │    vltUSDY      │    │    vltUSDe      │
│                 │    │                 │    │                 │
│ • ERC-20       │    │ • ERC-4626      │    │ • ERC-20        │
│ • KYC/Compliance│   │ • Yield-bearing  │    │ • ETH Collateral│
│ • Oracle Price  │    │ • Treasury Rates│    │ • Staking Rewards│
│ • Role-based    │    │ • Vault Logic   │    │ • Algorithmic   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Chainlink     │
                    │     Oracle      │
                    │                 │
                    │ • Price Feeds   │
                    │ • Treasury Rates│
                    │ • Validation    │
                    └─────────────────┘
```

## Features

### Core Features
- **Upgradeable Architecture**: All contracts use UUPS proxy pattern
- **Role-Based Access Control**: Granular permissions for different operations
- **Oracle Integration**: Chainlink price feeds with fallback mechanisms
- **Pausable Operations**: Emergency controls for all contracts
- **Comprehensive Testing**: Full test coverage with mock contracts
- **Gas Optimization**: Efficient contract design with minimal gas usage

### Security Features
- **Reentrancy Protection**: All external calls protected
- **Input Validation**: Comprehensive parameter validation
- **Circuit Breakers**: Automatic pause mechanisms for anomalies
- **Audit-Ready**: Clean, documented code following best practices

## Contract Details

### vltUSD - Fully Collateralized USD Stablecoin

**Purpose**: Regulatory-compliant, fully collateralized stablecoin with KYC controls.

**Key Features**:
- ERC-20 compliant with upgradeable architecture
- KYC/AML compliance controls
- Blacklist functionality for regulatory compliance
- Oracle-based proof-of-reserves
- Role-based minting/burning permissions
- Minimum 140% collateralization ratio

**Use Cases**:
- Institutional DeFi
- Regulatory-compliant transactions
- Cross-border payments
- Reserve-backed stablecoin operations

### vltUSDY - Treasury Yield Stablecoin

**Purpose**: Yield-bearing stablecoin backed by U.S. Treasury assets.

**Key Features**:
- ERC-4626 vault implementation
- Daily/weekly yield accrual
- Transparent APY display
- Oracle-connected treasury rates
- Modular yield source architecture
- Automatic yield distribution

**Use Cases**:
- Yield farming strategies
- Treasury-backed DeFi protocols
- Stable yield generation
- Institutional treasury management

### vltUSDe - Algorithmic ETH-Collateralized Stablecoin

**Purpose**: Algorithmic stablecoin using overcollateralized ETH deposits with staking rewards.

**Key Features**:
- ETH and LSD collateral support
- Automatic staking integration
- Algorithmic peg maintenance
- Liquidation mechanisms
- Staking reward distribution
- Real-time collateral ratio enforcement

**Use Cases**:
- ETH yield optimization
- DeFi composability
- Cross-protocol integration
- Capital efficiency strategies

## Installation & Setup

### Prerequisites
- Node.js 16+
- npm or yarn
- Hardhat
- TypeScript

### Installation
```bash
# Clone repository
git clone <repository-url>
cd vltCoins

# Install dependencies
npm install

# Copy environment file
cp env.example .env

# Configure environment variables
# Edit .env with your configuration
```

### Environment Configuration
```bash
# Network RPC URLs
MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_API_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.alchemyapi.io/v2/YOUR_API_KEY
GOERLI_RPC_URL=https://eth-goerli.alchemyapi.io/v2/YOUR_API_KEY

# Private Key (for deployment)
PRIVATE_KEY=your_private_key_here

# API Keys
ETHERSCAN_API_KEY=your_etherscan_api_key
COINMARKETCAP_API_KEY=your_coinmarketcap_api_key

# Oracle Addresses (Chainlink)
CHAINLINK_ETH_USD_FEED=0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
CHAINLINK_STETH_ETH_FEED=0x86392dC19c0b719886221c78AB11eb8Cf5c52812
CHAINLINK_TREASURY_RATE_FEED=0x8fffffd4afb6115b954bd326cbe7b4ba576818f6
```

## Development

### Compile Contracts
```bash
npm run compile
```

### Run Tests
```bash
# Run all tests
npm test

# Run with gas reporting
npm run gas

# Run with coverage
npm run test:coverage
```

### Code Quality
```bash
# Lint contracts
npm run lint

# Run security analysis
npm run audit
```

## Deployment

### Testnet Deployment (Sepolia)
```bash
# Deploy to Sepolia
npm run deploy:sepolia

# Verify contracts
npm run verify:sepolia
```

### Mainnet Deployment
```bash
# Deploy to mainnet (after thorough testing)
npm run deploy:mainnet

# Verify contracts
npm run verify:mainnet
```

## Usage Examples

### vltUSD Operations

```javascript
// Mint vltUSD with collateral
await vltUSD.connect(minter).mint(
    userAddress,
    ethers.utils.parseEther("1000"),
    collateralAddress,
    ethers.utils.parseEther("1")
);

// Burn vltUSD for collateral
await vltUSD.connect(burner).burn(
    userAddress,
    ethers.utils.parseEther("500"),
    collateralAddress
);

// Set KYC status
await vltUSD.connect(kycOperator).setKYCStatus(userAddress, true);
```

### vltUSDY Operations

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

// Claim yield
await vltUSDY.claimYield(userAddress);
```

### vltUSDe Operations

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

## Oracle Integration

The suite uses Chainlink oracles for price feeds and data validation:

### Supported Price Feeds
- ETH/USD
- stETH/ETH
- Treasury Rates
- Custom asset prices

### Oracle Features
- Staleness checks
- Deviation thresholds
- Fallback mechanisms
- Multi-oracle support

## Security Considerations

### Access Control
- Role-based permissions for all critical functions
- Multi-signature support for admin operations
- Time-locked upgrades for governance

### Economic Security
- Overcollateralization requirements
- Liquidation mechanisms
- Circuit breakers for extreme market conditions
- Slippage protection

### Technical Security
- Reentrancy protection on all external calls
- Input validation and bounds checking
- Emergency pause functionality
- Upgradeable architecture with proper validation

## Testing Strategy

### Test Coverage
- Unit tests for all contract functions
- Integration tests for cross-contract interactions
- Edge case testing for economic scenarios
- Security testing for common vulnerabilities

### Test Categories
- **Functional Tests**: Verify core functionality
- **Security Tests**: Check for vulnerabilities
- **Economic Tests**: Validate economic logic
- **Integration Tests**: Test contract interactions
- **Gas Tests**: Optimize gas usage

## Gas Optimization

### Optimizations Implemented
- Efficient storage patterns
- Minimal external calls
- Optimized loops and iterations
- Batch operations where possible
- Custom errors instead of require statements

### Gas Usage Targets
- vltUSD: ~50k gas for mint/burn operations
- vltUSDY: ~80k gas for deposit/withdraw operations
- vltUSDe: ~100k gas for mint/burn operations

## Monitoring & Analytics

### Key Metrics
- Total Value Locked (TVL)
- Collateral ratios
- Yield rates
- Liquidation events
- User activity

### Monitoring Tools
- Chainlink price feed monitoring
- Gas usage tracking
- Event logging and analysis
- Economic health indicators

## Contributing

### Development Guidelines
1. Follow existing code patterns
2. Add comprehensive tests for new features
3. Update documentation for any changes
4. Ensure gas optimization for new functions
5. Follow security best practices

### Code Review Process
1. Automated testing and linting
2. Security analysis with Slither
3. Manual code review
4. Economic impact assessment
5. Gas usage verification

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For technical support or questions:
- Create an issue in the repository
- Review the documentation
- Check the test files for usage examples

## Roadmap

### Phase 1 (Current)
- ✅ Core contract implementation
- ✅ Oracle integration
- ✅ Basic testing framework
- ✅ Deployment scripts

### Phase 2 (Next)
- [ ] Advanced liquidation mechanisms
- [ ] Multi-oracle support
- [ ] Governance integration
- [ ] Advanced yield strategies

### Phase 3 (Future)
- [ ] Cross-chain functionality
- [ ] Advanced DeFi integrations
- [ ] Institutional features
- [ ] Mobile SDK

## Disclaimer

This software is provided "as is" without warranty of any kind. Users should conduct their own security audits and due diligence before using in production environments. 