# vltCoins Technical Architecture

## System Overview

The vltCoins suite is designed as a modular, upgradeable system of three interconnected stablecoins, each optimized for specific use cases while maintaining interoperability and security.

## Core Architecture Principles

### 1. Modularity
- Each stablecoin is a separate, focused contract
- Shared interfaces for common functionality
- Pluggable oracle and collateral systems

### 2. Upgradeability
- UUPS proxy pattern for all contracts
- Immutable logic separation from upgradeable storage
- Backward compatibility maintained

### 3. Security-First
- Role-based access control throughout
- Reentrancy protection on all external calls
- Comprehensive input validation
- Emergency pause mechanisms

### 4. Gas Efficiency
- Optimized storage patterns
- Minimal external calls
- Efficient loops and iterations
- Custom errors over require statements

## Contract Architecture

### vltUSD - Fully Collateralized Stablecoin

```
┌─────────────────────────────────────────────────────────────┐
│                        VltUSD                              │
├─────────────────────────────────────────────────────────────┤
│  ERC20Upgradeable                                          │
│  ├── name(), symbol(), decimals()                         │
│  ├── balanceOf(), totalSupply()                           │
│  └── transfer(), approve(), allowance()                   │
├─────────────────────────────────────────────────────────────┤
│  AccessControlUpgradeable                                  │
│  ├── MINTER_ROLE                                          │
│  ├── BURNER_ROLE                                          │
│  ├── KYC_OPERATOR_ROLE                                    │
│  ├── COMPLIANCE_ROLE                                       │
│  └── UPGRADER_ROLE                                        │
├─────────────────────────────────────────────────────────────┤
│  PausableUpgradeable                                      │
│  ├── pause() / unpause()                                  │
│  └── whenNotPaused modifier                               │
├─────────────────────────────────────────────────────────────┤
│  ReentrancyGuardUpgradeable                               │
│  └── nonReentrant modifier                                │
├─────────────────────────────────────────────────────────────┤
│  UUPSUpgradeable                                          │
│  └── _authorizeUpgrade()                                  │
├─────────────────────────────────────────────────────────────┤
│  Core Logic                                               │
│  ├── mint() - KYC verified, collateralized minting       │
│  ├── burn() - Collateral return with validation           │
│  ├── setKYCStatus() - KYC management                     │
│  ├── setBlacklistStatus() - Compliance controls           │
│  └── getTotalReservesUSD() - Reserve calculation         │
└─────────────────────────────────────────────────────────────┘
```

**Key Features:**
- KYC/AML compliance controls
- Blacklist functionality
- Oracle-based reserve validation
- Role-based permissions
- Minimum 140% collateralization

### vltUSDY - Treasury Yield Stablecoin

```
┌─────────────────────────────────────────────────────────────┐
│                        VltUSDY                             │
├─────────────────────────────────────────────────────────────┤
│  ERC4626Upgradeable                                       │
│  ├── deposit() / withdraw()                               │
│  ├── mint() / redeem()                                    │
│  ├── previewDeposit() / previewWithdraw()                │
│  ├── previewMint() / previewRedeem()                     │
│  └── totalAssets()                                        │
├─────────────────────────────────────────────────────────────┤
│  AccessControlUpgradeable                                  │
│  ├── ADMIN_ROLE                                           │
│  ├── OPERATOR_ROLE                                        │
│  ├── YIELD_MANAGER_ROLE                                   │
│  └── UPGRADER_ROLE                                        │
├─────────────────────────────────────────────────────────────┤
│  Yield Management                                         │
│  ├── yieldRate - Annual yield rate (basis points)        │
│  ├── yieldBuffer - Accumulated yield for distribution    │
│  ├── userYieldEarned - Per-user yield tracking           │
│  ├── _updateYield() - Yield accrual logic                │
│  └── claimYield() - Yield distribution                    │
├─────────────────────────────────────────────────────────────┤
│  Oracle Integration                                       │
│  ├── updateYieldRate() - Oracle-based rate updates       │
│  ├── getAPY() - Current yield rate                       │
│  └── yieldUpdateThreshold - Rate update frequency        │
└─────────────────────────────────────────────────────────────┘
```

**Key Features:**
- ERC-4626 vault standard compliance
- Daily/weekly yield accrual
- Oracle-connected treasury rates
- Transparent APY display
- Modular yield source architecture

### vltUSDe - Algorithmic ETH-Collateralized Stablecoin

```
┌─────────────────────────────────────────────────────────────┐
│                        VltUSDe                             │
├─────────────────────────────────────────────────────────────┤
│  ERC20Upgradeable                                         │
│  ├── Standard ERC-20 functionality                        │
│  └── Custom mint/burn logic                              │
├─────────────────────────────────────────────────────────────┤
│  Collateral Management                                    │
│  ├── userCollateral - User collateral tracking            │
│  ├── userDebt - User debt tracking                       │
│  ├── collateralBalances - Total collateral per type      │
│  └── supportedCollateral - Supported collateral types    │
├─────────────────────────────────────────────────────────────┤
│  Liquid Staking Integration                               │
│  ├── supportedLSDs - Supported LSD protocols             │
│  ├── lsdStakingContracts - Staking contract addresses    │
│  ├── _stakeETH() / _stakeLSD() - Staking logic          │
│  └── _unstakeETH() / _unstakeLSD() - Unstaking logic    │
├─────────────────────────────────────────────────────────────┤
│  Liquidation System                                       │
│  ├── minCollateralRatio - Minimum ratio (140%)           │
│  ├── liquidationThreshold - Liquidation trigger (130%)   │
│  ├── liquidationPenalty - Penalty percentage (10%)       │
│  ├── isLiquidatable() - Liquidation check               │
│  └── liquidate() - Liquidation execution                 │
├─────────────────────────────────────────────────────────────┤
│  Staking Rewards                                          │
│  ├── stakingRewardRate - Annual reward rate (5%)         │
│  ├── userStakingRewards - Per-user reward tracking       │
│  ├── _updateStakingRewards() - Reward calculation        │
│  └── claimStakingRewards() - Reward distribution         │
└─────────────────────────────────────────────────────────────┘
```

**Key Features:**
- ETH and LSD collateral support
- Automatic staking integration
- Algorithmic peg maintenance
- Real-time collateral ratio enforcement
- Staking reward distribution

## Oracle Integration

### ChainlinkOracle Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ChainlinkOracle                         │
├─────────────────────────────────────────────────────────────┤
│  Price Feed Management                                    │
│  ├── priceFeeds[asset] => feed address                   │
│  ├── setPriceFeed() - Add/update price feeds             │
│  └── setPriceFeeds() - Batch price feed updates          │
├─────────────────────────────────────────────────────────────┤
│  Price Validation                                         │
│  ├── getPrice() - Latest price with validation           │
│  ├── getPriceWithStalenessCheck() - Staleness validation │
│  ├── isPriceStale() - Staleness check                    │
│  └── getPriceDeviation() - Deviation calculation         │
├─────────────────────────────────────────────────────────────┤
│  Configuration                                            │
│  ├── heartbeat - Price update frequency                  │
│  ├── minDeviationThreshold - Min deviation (1%)          │
│  ├── maxDeviationThreshold - Max deviation (10%)         │
│  └── stalenessThreshold - Staleness limit (1 hour)      │
├─────────────────────────────────────────────────────────────┤
│  Access Control                                           │
│  ├── ADMIN_ROLE - Configuration management               │
│  ├── OPERATOR_ROLE - Operational functions               │
│  └── pause() / unpause() - Emergency controls            │
└─────────────────────────────────────────────────────────────┘
```

### Oracle Features

1. **Multi-Asset Support**
   - ETH/USD price feeds
   - stETH/ETH ratio feeds
   - Treasury rate feeds
   - Custom asset price feeds

2. **Validation Mechanisms**
   - Staleness checks
   - Deviation thresholds
   - Round ID validation
   - Price sanity checks

3. **Fallback Logic**
   - Multiple oracle support
   - Circuit breakers
   - Emergency pause functionality

## Security Architecture

### Access Control Matrix

| Function | Admin | Minter | Burner | KYC Op | Compliance | Yield Manager | Liquidator | Staking Manager |
|----------|-------|--------|--------|--------|------------|---------------|------------|-----------------|
| mint() | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| burn() | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| setKYCStatus() | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| setBlacklistStatus() | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| liquidate() | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| updateYieldRate() | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| pause() | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

### Security Mechanisms

1. **Reentrancy Protection**
   ```solidity
   modifier nonReentrant() {
       require(!_locked, "Reentrant call");
       _locked = true;
       _;
       _locked = false;
   }
   ```

2. **Input Validation**
   ```solidity
   function mint(address to, uint256 amount, address collateral, uint256 collateralAmount) 
       external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
       if (amount == 0 || collateralAmount == 0) {
           revert InvalidAmount();
       }
       // ... rest of function
   }
   ```

3. **Circuit Breakers**
   ```solidity
   function getPriceWithStalenessCheck(address asset, uint256 maxAge) 
       external view returns (uint256 price, uint256 timestamp) {
       (price, timestamp, ) = this.getPrice(asset);
       
       if (block.timestamp - timestamp > maxAge) {
           revert StalePrice();
       }
   }
   ```

## Gas Optimization

### Storage Optimization

1. **Packed Structs**
   ```solidity
   struct UserPosition {
       uint128 collateral;  // 16 bytes
       uint128 debt;        // 16 bytes
   }
   ```

2. **Efficient Mappings**
   ```solidity
   mapping(address => uint256) public userCollateral;
   mapping(address => uint256) public userDebt;
   ```

3. **Custom Errors**
   ```solidity
   error InsufficientCollateral();
   error CollateralNotSupported();
   error KYCNotVerified();
   ```

### Function Optimization

1. **Batch Operations**
   ```solidity
   function setPriceFeeds(address[] calldata assets, address[] calldata feeds) 
       external onlyRole(ADMIN_ROLE) {
       for (uint256 i = 0; i < assets.length; i++) {
           priceFeeds[assets[i]] = feeds[i];
       }
   }
   ```

2. **Minimal External Calls**
   ```solidity
   function _calculateRequiredCollateral(uint256 amount, address collateral) 
       internal view returns (uint256 required) {
       (uint256 price, , ) = oracle.getPrice(collateral);
       required = (amount * minCollateralRatio * 1e8) / (price * 10000);
   }
   ```

## Testing Architecture

### Test Categories

1. **Unit Tests**
   - Individual function testing
   - Edge case validation
   - Error condition testing

2. **Integration Tests**
   - Cross-contract interactions
   - Oracle integration testing
   - Role-based access testing

3. **Economic Tests**
   - Collateral ratio calculations
   - Yield accrual validation
   - Liquidation scenarios

4. **Security Tests**
   - Reentrancy attack simulation
   - Access control validation
   - Emergency scenario testing

### Mock Contracts

1. **MockERC20**
   - Standard ERC-20 implementation
   - Mint/burn functionality for testing

2. **MockAggregatorV3**
   - Chainlink price feed simulation
   - Configurable prices and timestamps

3. **MockOracle**
   - Oracle interface implementation
   - Test-specific price feeds

## Deployment Architecture

### Proxy Pattern

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Proxy Admin   │    │   ERC1967Proxy  │    │ Implementation  │
│                 │    │                 │    │                 │
│ • Upgrade logic │    │ • Storage       │    │ • Logic         │
│ • Access control│    │ • Delegate calls│    │ • Functions     │
│ • Timelock      │    │ • Fallback      │    │ • Events        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Deployment Process

1. **Implementation Deployment**
   - Deploy implementation contract
   - Verify implementation contract

2. **Proxy Deployment**
   - Deploy proxy with implementation
   - Initialize proxy with parameters

3. **Role Setup**
   - Grant roles to appropriate addresses
   - Set up multi-signature controls

4. **Oracle Configuration**
   - Set price feeds for supported assets
   - Configure validation parameters

5. **Collateral Setup**
   - Add supported collateral types
   - Set collateral ratios and limits

## Monitoring & Analytics

### Key Metrics

1. **Economic Metrics**
   - Total Value Locked (TVL)
   - Collateral ratios
   - Yield rates
   - Liquidation events

2. **Technical Metrics**
   - Gas usage per operation
   - Transaction success rates
   - Oracle update frequency
   - Error rates

3. **Security Metrics**
   - Failed access attempts
   - Emergency pause events
   - Oracle staleness events
   - Deviation threshold breaches

### Monitoring Tools

1. **Chainlink Price Feeds**
   - Real-time price monitoring
   - Staleness detection
   - Deviation alerts

2. **Gas Usage Tracking**
   - Per-function gas costs
   - Optimization opportunities
   - Cost analysis

3. **Event Logging**
   - Comprehensive event emission
   - Indexed parameters for filtering
   - Historical data analysis

## Future Enhancements

### Phase 2 Features

1. **Advanced Liquidation**
   - Dutch auction liquidation
   - Partial liquidation support
   - Dynamic liquidation incentives

2. **Multi-Oracle Support**
   - Redundant oracle feeds
   - Weighted price aggregation
   - Oracle governance

3. **Governance Integration**
   - DAO governance
   - Parameter voting
   - Emergency proposals

### Phase 3 Features

1. **Cross-Chain Functionality**
   - Layer 2 integration
   - Cross-chain bridges
   - Multi-chain deployments

2. **Advanced DeFi Integrations**
   - AMM integration
   - Lending protocol support
   - Yield aggregator compatibility

3. **Institutional Features**
   - KYC/AML compliance
   - Regulatory reporting
   - Institutional onboarding

## Conclusion

The vltCoins architecture prioritizes security, efficiency, and modularity while maintaining the flexibility needed for future enhancements. The upgradeable design allows for continuous improvement while the comprehensive testing and monitoring ensure reliability in production environments. 