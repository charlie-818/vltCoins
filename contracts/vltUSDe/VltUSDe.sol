// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IVault.sol";

/**
 * @title VltUSDe
 * @notice Ethereum-Collateralized, Yield-Bearing Algorithmic Stablecoin
 * @dev Maintains $1.00 peg using overcollateralized ETH deposits with staking rewards
 */
contract VltUSDe is 
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Oracle and price feeds
    IOracle public oracle;
    address public ethUsdFeed;
    address public stEthEthFeed;

    // Collateral and staking
    mapping(address => bool) public supportedCollateral;
    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userDebt;
    address[] public collateralList;

    // Liquid staking protocols
    mapping(address => bool) public supportedLSDs;
    mapping(address => address) public lsdStakingContracts;
    address[] public lsdList;

    // Configuration
    uint256 public minCollateralRatio = 14000; // 140% minimum
    uint256 public liquidationThreshold = 13000; // 130% liquidation threshold
    uint256 public liquidationPenalty = 1000; // 10% liquidation penalty
    uint256 public stakingRewardRate = 500; // 5% annual staking reward
    uint256 public maxSlippage = 500; // 5% maximum slippage

    // Staking rewards
    uint256 public totalStakingRewards;
    mapping(address => uint256) public userStakingRewards;
    mapping(address => uint256) public userLastRewardUpdate;

    // Events
    event Minted(address indexed user, uint256 amount, address indexed collateral, uint256 collateralAmount);
    event Burned(address indexed user, uint256 amount, address indexed collateral, uint256 collateralReturn);
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed collateral, uint256 amount);
    event Liquidated(address indexed user, address indexed collateral, uint256 debtAmount, uint256 collateralSeized);
    event StakingRewardClaimed(address indexed user, uint256 amount);
    event StakingRewardAccrued(uint256 amount, uint256 timestamp);
    event CollateralSupported(address indexed collateral, bool supported);
    event LSDSupported(address indexed lsd, bool supported);

    // Errors
    error InsufficientCollateral();
    error CollateralNotSupported();
    error LSDNotSupported();
    error InvalidCollateralRatio();
    error PositionNotLiquidatable();
    error InvalidAmount();
    error OracleNotSet();
    error SlippageExceeded();
    error StakingFailed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param name Token name
     * @param symbol Token symbol
     * @param admin Admin address
     * @param _oracle Oracle address
     * @param _ethUsdFeed ETH/USD price feed
     * @param _stEthEthFeed stETH/ETH price feed
     */
    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address _oracle,
        address _ethUsdFeed,
        address _stEthEthFeed
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        _grantRole(LIQUIDATOR_ROLE, admin);
        _grantRole(STAKING_MANAGER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Initialize configuration
        oracle = IOracle(_oracle);
        ethUsdFeed = _ethUsdFeed;
        stEthEthFeed = _stEthEthFeed;
    }

    /**
     * @notice Mint vltUSDe with ETH collateral
     * @param mintAmount Amount of vltUSDe to mint
     */
    function mintWithETH(uint256 mintAmount) external payable whenNotPaused nonReentrant {
        if (msg.value == 0 || mintAmount == 0) {
            revert InvalidAmount();
        }

        // Calculate required collateral
        uint256 requiredCollateral = _calculateRequiredCollateral(mintAmount, address(0));
        if (msg.value < requiredCollateral) {
            revert InsufficientCollateral();
        }

        // Update user position
        userCollateral[msg.sender] += msg.value;
        userDebt[msg.sender] += mintAmount;
        collateralBalances[address(0)] += msg.value;

        // Mint vltUSDe
        _mint(msg.sender, mintAmount);

        // Stake ETH for rewards
        _stakeETH(msg.value);

        emit Minted(msg.sender, mintAmount, address(0), msg.value);
        emit CollateralDeposited(msg.sender, address(0), msg.value);
    }

    /**
     * @notice Mint vltUSDe with liquid staking derivative
     * @param lsd Liquid staking derivative address
     * @param lsdAmount Amount of LSD to deposit
     * @param mintAmount Amount of vltUSDe to mint
     */
    function mintWithLSD(
        address lsd,
        uint256 lsdAmount,
        uint256 mintAmount
    ) external whenNotPaused nonReentrant {
        if (!supportedLSDs[lsd]) {
            revert LSDNotSupported();
        }
        if (lsdAmount == 0 || mintAmount == 0) {
            revert InvalidAmount();
        }

        // Calculate required collateral
        uint256 requiredCollateral = _calculateRequiredCollateral(mintAmount, lsd);
        if (lsdAmount < requiredCollateral) {
            revert InsufficientCollateral();
        }

        // Transfer LSD from user
        SafeERC20.safeTransferFrom(IERC20(lsd), msg.sender, address(this), lsdAmount);

        // Update user position
        userCollateral[msg.sender] += lsdAmount;
        userDebt[msg.sender] += mintAmount;
        collateralBalances[lsd] += lsdAmount;

        // Mint vltUSDe
        _mint(msg.sender, mintAmount);

        // Stake LSD for rewards
        _stakeLSD(lsd, lsdAmount);

        emit Minted(msg.sender, mintAmount, lsd, lsdAmount);
        emit CollateralDeposited(msg.sender, lsd, lsdAmount);
    }

    /**
     * @notice Burn vltUSDe and withdraw ETH collateral
     * @param burnAmount Amount of vltUSDe to burn
     * @param collateralAmount Amount of ETH to withdraw
     */
    function burnForETH(uint256 burnAmount, uint256 collateralAmount) external whenNotPaused nonReentrant {
        if (burnAmount == 0 || collateralAmount == 0) {
            revert InvalidAmount();
        }

        // Check user position
        if (userDebt[msg.sender] < burnAmount) {
            revert InvalidAmount();
        }

        // Calculate collateral ratio after burn
        uint256 newDebt = userDebt[msg.sender] - burnAmount;
        uint256 newCollateral = userCollateral[msg.sender] - collateralAmount;
        uint256 collateralRatio = _calculateCollateralRatio(newCollateral, newDebt, address(0));
        
        if (collateralRatio < minCollateralRatio) {
            revert InvalidCollateralRatio();
        }

        // Update user position
        userDebt[msg.sender] = newDebt;
        userCollateral[msg.sender] = newCollateral;
        collateralBalances[address(0)] -= collateralAmount;

        // Burn vltUSDe
        _burn(msg.sender, burnAmount);

        // Unstake and transfer ETH
        _unstakeETH(collateralAmount);
        (bool success, ) = msg.sender.call{value: collateralAmount}("");
        if (!success) {
            revert StakingFailed();
        }

        emit Burned(msg.sender, burnAmount, address(0), collateralAmount);
        emit CollateralWithdrawn(msg.sender, address(0), collateralAmount);
    }

    /**
     * @notice Burn vltUSDe and withdraw LSD collateral
     * @param lsd Liquid staking derivative address
     * @param burnAmount Amount of vltUSDe to burn
     * @param lsdAmount Amount of LSD to withdraw
     */
    function burnForLSD(
        address lsd,
        uint256 burnAmount,
        uint256 lsdAmount
    ) external whenNotPaused nonReentrant {
        if (!supportedLSDs[lsd]) {
            revert LSDNotSupported();
        }
        if (burnAmount == 0 || lsdAmount == 0) {
            revert InvalidAmount();
        }

        // Check user position
        if (userDebt[msg.sender] < burnAmount) {
            revert InvalidAmount();
        }

        // Calculate collateral ratio after burn
        uint256 newDebt = userDebt[msg.sender] - burnAmount;
        uint256 newCollateral = userCollateral[msg.sender] - lsdAmount;
        uint256 collateralRatio = _calculateCollateralRatio(newCollateral, newDebt, lsd);
        
        if (collateralRatio < minCollateralRatio) {
            revert InvalidCollateralRatio();
        }

        // Update user position
        userDebt[msg.sender] = newDebt;
        userCollateral[msg.sender] = newCollateral;
        collateralBalances[lsd] -= lsdAmount;

        // Burn vltUSDe
        _burn(msg.sender, burnAmount);

        // Unstake and transfer LSD
        _unstakeLSD(lsd, lsdAmount);
        SafeERC20.safeTransfer(IERC20(lsd), msg.sender, lsdAmount);

        emit Burned(msg.sender, burnAmount, lsd, lsdAmount);
        emit CollateralWithdrawn(msg.sender, lsd, lsdAmount);
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param user User to liquidate
     * @param collateral Collateral type (address(0) for ETH, LSD address for LSD)
     */
    function liquidate(address user, address collateral) external onlyRole(LIQUIDATOR_ROLE) whenNotPaused nonReentrant {
        if (!isLiquidatable(user, collateral)) {
            revert PositionNotLiquidatable();
        }

        uint256 debtAmount = userDebt[user];
        uint256 collateralAmount = userCollateral[user];
        uint256 liquidationAmount = (collateralAmount * liquidationPenalty) / 10000;
        uint256 liquidatorReward = (liquidationAmount * 500) / 10000; // 5% reward

        // Update user position
        userDebt[user] = 0;
        userCollateral[user] = 0;
        collateralBalances[collateral] -= collateralAmount;

        // Burn user's debt
        _burn(user, debtAmount);

        // Transfer liquidation reward to liquidator
        if (collateral == address(0)) {
            _unstakeETH(liquidatorReward);
            (bool success, ) = msg.sender.call{value: liquidatorReward}("");
            if (!success) {
                revert StakingFailed();
            }
        } else {
            _unstakeLSD(collateral, liquidatorReward);
            SafeERC20.safeTransfer(IERC20(collateral), msg.sender, liquidatorReward);
        }

        emit Liquidated(user, collateral, debtAmount, liquidationAmount);
    }

    /**
     * @notice Claim staking rewards
     * @param receiver Address to receive rewards
     * @return amount Amount of rewards claimed
     */
    function claimStakingRewards(address receiver) external whenNotPaused nonReentrant returns (uint256 amount) {
        _updateStakingRewards(msg.sender);
        
        amount = userStakingRewards[msg.sender];
        if (amount == 0) {
            return 0;
        }

        userStakingRewards[msg.sender] = 0;
        totalStakingRewards -= amount;

        // Transfer rewards as ETH
        (bool success, ) = receiver.call{value: amount}("");
        if (!success) {
            revert StakingFailed();
        }

        emit StakingRewardClaimed(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Check if a position is liquidatable
     * @param user User address
     * @param collateral Collateral type
     * @return liquidatable True if position can be liquidated
     */
    function isLiquidatable(address user, address collateral) public view returns (bool liquidatable) {
        uint256 collateralRatio = _calculateCollateralRatio(userCollateral[user], userDebt[user], collateral);
        return collateralRatio < liquidationThreshold;
    }

    /**
     * @notice Get user's collateral ratio
     * @param user User address
     * @param collateral Collateral type
     * @return ratio Collateral ratio in basis points
     */
    function getUserCollateralRatio(address user, address collateral) external view returns (uint256 ratio) {
        return _calculateCollateralRatio(userCollateral[user], userDebt[user], collateral);
    }

    /**
     * @notice Get total value locked in ETH
     * @return tvl Total value locked in ETH
     */
    function getTotalValueLocked() external view returns (uint256 tvl) {
        for (uint256 i = 0; i < collateralList.length; i++) {
            address collateral = collateralList[i];
            if (supportedCollateral[collateral]) {
                tvl += collateralBalances[collateral];
            }
        }
        return tvl;
    }

    /**
     * @notice Add or remove supported collateral
     * @param collateral Collateral address
     * @param supported Whether to support this collateral
     */
    function setCollateralSupport(address collateral, bool supported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedCollateral[collateral] = supported;
        if (supported) {
            collateralList.push(collateral);
        }
        emit CollateralSupported(collateral, supported);
    }

    /**
     * @notice Add or remove supported LSD
     * @param lsd LSD address
     * @param supported Whether to support this LSD
     * @param stakingContract Staking contract address
     */
    function setLSDSupport(address lsd, bool supported, address stakingContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedLSDs[lsd] = supported;
        if (supported) {
            lsdList.push(lsd);
            lsdStakingContracts[lsd] = stakingContract;
        }
        emit LSDSupported(lsd, supported);
    }

    /**
     * @notice Update configuration parameters
     * @param _minCollateralRatio New minimum collateral ratio
     * @param _liquidationThreshold New liquidation threshold
     * @param _liquidationPenalty New liquidation penalty
     */
    function updateConfiguration(
        uint256 _minCollateralRatio,
        uint256 _liquidationThreshold,
        uint256 _liquidationPenalty
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minCollateralRatio = _minCollateralRatio;
        liquidationThreshold = _liquidationThreshold;
        liquidationPenalty = _liquidationPenalty;
    }

    /**
     * @notice Calculate required collateral for minting
     * @param amount Amount to mint
     * @param collateral Collateral address
     * @return required Required collateral amount
     */
    function _calculateRequiredCollateral(uint256 amount, address collateral) internal view returns (uint256 required) {
        (uint256 price, , ) = oracle.getPrice(collateral == address(0) ? ethUsdFeed : collateral);
        required = (amount * minCollateralRatio * 1e8) / (price * 10000);
    }

    /**
     * @notice Calculate collateral ratio
     * @param collateralAmount Collateral amount
     * @param debtAmount Debt amount
     * @param collateral Collateral address
     * @return ratio Collateral ratio in basis points
     */
    function _calculateCollateralRatio(
        uint256 collateralAmount,
        uint256 debtAmount,
        address collateral
    ) internal view returns (uint256 ratio) {
        if (debtAmount == 0) {
            return type(uint256).max;
        }

        (uint256 price, , ) = oracle.getPrice(collateral == address(0) ? ethUsdFeed : collateral);
        uint256 collateralValue = (collateralAmount * price) / 1e8;
        ratio = (collateralValue * 10000) / debtAmount;
    }

    /**
     * @notice Stake ETH for rewards
     * @param amount Amount of ETH to stake
     */
    function _stakeETH(uint256 amount) internal {
        // Implementation would integrate with Lido, RocketPool, etc.
        // For now, we'll just track the staking
        totalStakingRewards += (amount * stakingRewardRate) / (365 days * 10000);
    }

    /**
     * @notice Stake LSD for rewards
     * @param lsd LSD address
     * @param amount Amount of LSD to stake
     */
    function _stakeLSD(address lsd, uint256 amount) internal {
        // Implementation would integrate with LSD protocols
        // For now, we'll just track the staking
        totalStakingRewards += (amount * stakingRewardRate) / (365 days * 10000);
    }

    /**
     * @notice Unstake ETH
     * @param amount Amount of ETH to unstake
     */
    function _unstakeETH(uint256 amount) internal {
        // Implementation would integrate with staking protocols
    }

    /**
     * @notice Unstake LSD
     * @param lsd LSD address
     * @param amount Amount of LSD to unstake
     */
    function _unstakeLSD(address lsd, uint256 amount) internal {
        // Implementation would integrate with LSD protocols
    }

    /**
     * @notice Update staking rewards for a user
     * @param user User address
     */
    function _updateStakingRewards(address user) internal {
        uint256 userCollateralValue = userCollateral[user];
        if (userCollateralValue > 0) {
            uint256 timeSinceLastUpdate = block.timestamp - userLastRewardUpdate[user];
            uint256 reward = (userCollateralValue * stakingRewardRate * timeSinceLastUpdate) / (365 days * 10000);
            userStakingRewards[user] += reward;
            userLastRewardUpdate[user] = block.timestamp;
        }
    }

    /**
     * @notice Pause contract operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Required by the OZ UUPS module
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Receive ETH for staking
     */
    receive() external payable {}
} 