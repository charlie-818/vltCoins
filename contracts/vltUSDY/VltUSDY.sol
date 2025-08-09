// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IOracle.sol";

/**
 * @title VltUSDY
 * @notice On-Chain U.S. Treasury Yield Stablecoin with ERC4626 vault implementation
 * @dev Implements yield-bearing stablecoin with daily/weekly yield accrual
 */
contract VltUSDY is 
    Initializable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Treasury and yield configuration
    IOracle public oracle;
    IERC20 public treasuryAsset; // Tokenized treasury bond
    uint256 public yieldRate; // Annual yield rate in basis points
    uint256 public lastYieldUpdate;
    uint256 public yieldAccrualPeriod; // Seconds between yield updates
    uint256 public totalYieldEarned;
    uint256 public yieldBuffer; // Buffer for yield distribution

    // User yield tracking
    mapping(address => uint256) public userYieldEarned;
    mapping(address => uint256) public userLastYieldUpdate;
    mapping(address => uint256) public userYieldIndex;

    // Configuration
    uint256 public minYieldRate = 100; // 1% minimum
    uint256 public maxYieldRate = 1000; // 10% maximum
    uint256 public yieldUpdateThreshold = 86400; // 24 hours
    uint256 public maxSlippage = 500; // 5% maximum slippage

    // Events
    event YieldRateUpdated(uint256 newRate, uint256 timestamp);
    event YieldAccrued(uint256 amount, uint256 timestamp);
    event YieldClaimed(address indexed user, uint256 amount);
    event TreasuryAssetUpdated(address indexed newAsset);
    event YieldBufferUpdated(uint256 newBuffer);

    // Errors
    error InvalidYieldRate();
    error YieldUpdateTooFrequent();
    error InsufficientYield();
    error InvalidTreasuryAsset();
    error OracleNotSet();
    error SlippageExceeded();
    error InvalidAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _treasuryAsset Tokenized treasury asset address
     * @param _oracle Oracle address for treasury rates
     * @param admin Admin address
     * @param _yieldRate Initial yield rate in basis points
     */
    function initialize(
        address _treasuryAsset,
        address _oracle,
        address admin,
        uint256 _yieldRate
    ) public initializer {
        __ERC4626_init(IERC20(_treasuryAsset));
        __ERC20_init("vltUSDY", "vltUSDY");
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(YIELD_MANAGER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Initialize configuration
        treasuryAsset = IERC20(_treasuryAsset);
        oracle = IOracle(_oracle);
        yieldRate = _yieldRate;
        yieldAccrualPeriod = 86400; // 24 hours
        lastYieldUpdate = block.timestamp;
    }

    /**
     * @notice Deposit treasury assets and mint vltUSDY
     * @param assets Amount of treasury assets to deposit
     * @param receiver Address to receive vltUSDY tokens
     * @return shares Amount of vltUSDY tokens minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert InvalidAmount();
        }

        // Update yield before deposit
        _updateYield();

        shares = previewDeposit(assets);
        if (shares == 0) {
            revert InvalidAmount();
        }

        // Transfer treasury assets from user
        SafeERC20.safeTransferFrom(treasuryAsset, msg.sender, address(this), assets);

        // Mint vltUSDY tokens
        _mint(receiver, shares);

        // Update user yield tracking
        _updateUserYield(receiver);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Withdraw treasury assets by burning vltUSDY
     * @param assets Amount of treasury assets to withdraw
     * @param receiver Address to receive treasury assets
     * @param owner Address that owns the vltUSDY tokens
     * @return shares Amount of vltUSDY tokens burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override whenNotPaused nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert InvalidAmount();
        }

        // Update yield before withdrawal
        _updateYield();

        shares = previewWithdraw(assets);
        if (shares == 0) {
            revert InvalidAmount();
        }

        // Check allowance and balance
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Burn vltUSDY tokens
        _burn(owner, shares);

        // Transfer treasury assets to receiver
        SafeERC20.safeTransfer(treasuryAsset, receiver, assets);

        // Update user yield tracking
        _updateUserYield(owner);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Mint vltUSDY tokens directly
     * @param shares Amount of vltUSDY tokens to mint
     * @param receiver Address to receive vltUSDY tokens
     * @return assets Amount of treasury assets required
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert InvalidAmount();
        }

        // Update yield before mint
        _updateYield();

        assets = previewMint(shares);
        if (assets == 0) {
            revert InvalidAmount();
        }

        // Transfer treasury assets from user
        SafeERC20.safeTransferFrom(treasuryAsset, msg.sender, address(this), assets);

        // Mint vltUSDY tokens
        _mint(receiver, shares);

        // Update user yield tracking
        _updateUserYield(receiver);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Redeem vltUSDY tokens for treasury assets
     * @param shares Amount of vltUSDY tokens to redeem
     * @param receiver Address to receive treasury assets
     * @param owner Address that owns the vltUSDY tokens
     * @return assets Amount of treasury assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert InvalidAmount();
        }

        // Update yield before redeem
        _updateYield();

        assets = previewRedeem(shares);
        if (assets == 0) {
            revert InvalidAmount();
        }

        // Check allowance and balance
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Burn vltUSDY tokens
        _burn(owner, shares);

        // Transfer treasury assets to receiver
        SafeERC20.safeTransfer(treasuryAsset, receiver, assets);

        // Update user yield tracking
        _updateUserYield(owner);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Claim accumulated yield
     * @param receiver Address to receive the yield
     * @return amount Amount of yield claimed
     */
    function claimYield(address receiver) external whenNotPaused nonReentrant returns (uint256 amount) {
        _updateYield();
        _updateUserYield(msg.sender);

        amount = userYieldEarned[msg.sender];
        if (amount == 0) {
            return 0;
        }

        userYieldEarned[msg.sender] = 0;
        totalYieldEarned -= amount;

        // Transfer yield as treasury assets
        SafeERC20.safeTransfer(treasuryAsset, receiver, amount);

        emit YieldClaimed(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Update yield rate from oracle
     * @dev Only callable by yield manager
     */
    function updateYieldRate() external onlyRole(YIELD_MANAGER_ROLE) {
        if (block.timestamp - lastYieldUpdate < yieldUpdateThreshold) {
            revert YieldUpdateTooFrequent();
        }

        // Get treasury rate from oracle
        (uint256 treasuryRate, , ) = oracle.getPrice(address(treasuryAsset));
        
        // Update yield rate (convert from oracle format to basis points)
        uint256 newYieldRate = (treasuryRate * 10000) / 1e8;
        
        // Ensure rate is within bounds
        if (newYieldRate < minYieldRate) {
            newYieldRate = minYieldRate;
        } else if (newYieldRate > maxYieldRate) {
            newYieldRate = maxYieldRate;
        }

        yieldRate = newYieldRate;
        lastYieldUpdate = block.timestamp;

        emit YieldRateUpdated(newYieldRate, block.timestamp);
    }

    /**
     * @notice Get current yield rate
     * @return rate Current yield rate in basis points
     */
    function getYieldRate() external view returns (uint256 rate) {
        return yieldRate;
    }

    /**
     * @notice Get total yield earned by the vault
     * @return total Total yield earned
     */
    function getTotalYield() external view returns (uint256 total) {
        return totalYieldEarned;
    }

    /**
     * @notice Get yield earned by a specific user
     * @param user User address
     * @return userYield Yield earned by the user
     */
    function getUserYield(address user) external view returns (uint256 userYield) {
        return userYieldEarned[user];
    }

    /**
     * @notice Get APY (Annual Percentage Yield)
     * @return apy APY in basis points
     */
    function getAPY() external view returns (uint256 apy) {
        return yieldRate;
    }

    /**
     * @notice Set yield rate manually (for testing/emergency)
     * @param newRate New yield rate in basis points
     */
    function setYieldRate(uint256 newRate) external onlyRole(ADMIN_ROLE) {
        if (newRate < minYieldRate || newRate > maxYieldRate) {
            revert InvalidYieldRate();
        }
        
        yieldRate = newRate;
        lastYieldUpdate = block.timestamp;
        
        emit YieldRateUpdated(newRate, block.timestamp);
    }

    /**
     * @notice Update treasury asset
     * @param newTreasuryAsset New treasury asset address
     */
    function setTreasuryAsset(address newTreasuryAsset) external onlyRole(ADMIN_ROLE) {
        if (newTreasuryAsset == address(0)) {
            revert InvalidTreasuryAsset();
        }
        
        treasuryAsset = IERC20(newTreasuryAsset);
        emit TreasuryAssetUpdated(newTreasuryAsset);
    }

    /**
     * @notice Set yield update threshold
     * @param newThreshold New threshold in seconds
     */
    function setYieldUpdateThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        yieldUpdateThreshold = newThreshold;
    }

    /**
     * @notice Set yield rate bounds
     * @param minRate Minimum yield rate in basis points
     * @param maxRate Maximum yield rate in basis points
     */
    function setYieldRateBounds(uint256 minRate, uint256 maxRate) external onlyRole(ADMIN_ROLE) {
        if (minRate >= maxRate) {
            revert InvalidYieldRate();
        }
        
        minYieldRate = minRate;
        maxYieldRate = maxRate;
    }

    /**
     * @notice Update yield for the entire vault
     */
    function _updateYield() internal {
        if (block.timestamp - lastYieldUpdate >= yieldAccrualPeriod) {
            uint256 totalAssets = totalAssets();
            if (totalAssets > 0) {
                uint256 yieldAmount = (totalAssets * yieldRate * yieldAccrualPeriod) / (365 days * 10000);
                yieldBuffer += yieldAmount;
                totalYieldEarned += yieldAmount;
                lastYieldUpdate = block.timestamp;
                
                emit YieldAccrued(yieldAmount, block.timestamp);
            }
        }
    }

    /**
     * @notice Update yield for a specific user
     * @param user User address
     */
    function _updateUserYield(address user) internal {
        uint256 userShares = balanceOf(user);
        if (userShares > 0) {
            uint256 totalShares = totalSupply();
            if (totalShares > 0) {
                uint256 userYieldShare = (yieldBuffer * userShares) / totalShares;
                userYieldEarned[user] += userYieldShare;
                yieldBuffer -= userYieldShare;
            }
        }
        userLastYieldUpdate[user] = block.timestamp;
    }

    /**
     * @notice Pause vault operations
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause vault operations
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Required by the OZ UUPS module
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Override totalAssets to include yield buffer
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(treasuryAsset).balanceOf(address(this)) + yieldBuffer;
    }

    /**
     * @notice Override previewDeposit to account for yield
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets;
        }
        return assets * supply / totalAssets();
    }

    /**
     * @notice Override previewMint to account for yield
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        return shares * totalAssets() / supply;
    }

    /**
     * @notice Override previewWithdraw to account for yield
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 0;
        }
        return assets * supply / totalAssets();
    }

    /**
     * @notice Override previewRedeem to account for yield
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 0;
        }
        return shares * totalAssets() / supply;
    }
} 