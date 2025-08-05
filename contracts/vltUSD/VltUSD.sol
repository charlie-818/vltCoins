// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title VltUSD
 * @notice Fully collateralized USD stablecoin with KYC controls and regulatory functions
 * @dev Implements ERC-20 with upgradeable architecture and role-based access control
 */
contract VltUSD is 
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant KYC_OPERATOR_ROLE = keccak256("KYC_OPERATOR_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Oracle and reserves
    IOracle public oracle;
    mapping(address => uint256) public reserves; // collateral => amount
    mapping(address => bool) public supportedCollateral;
    address[] public collateralList;

    // KYC and compliance
    mapping(address => bool) public kycVerified;
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public userMintLimits;
    mapping(address => uint256) public userBurnLimits;

    // Configuration
    uint256 public minCollateralRatio; // basis points (14000 = 140%)
    uint256 public maxMintLimit;
    uint256 public maxBurnLimit;
    uint256 public totalReserves;
    uint256 public lastReserveUpdate;

    // Events
    event Minted(address indexed to, uint256 amount, address indexed collateral, uint256 collateralAmount);
    event Burned(address indexed from, uint256 amount, address indexed collateral, uint256 collateralAmount);
    event CollateralAdded(address indexed collateral, uint256 amount);
    event CollateralRemoved(address indexed collateral, uint256 amount);
    event ReserveUpdated(uint256 totalReserves, uint256 timestamp);
    event KYCVerified(address indexed user, bool verified);
    event Blacklisted(address indexed user, bool blacklisted);
    event MintLimitUpdated(address indexed user, uint256 limit);
    event BurnLimitUpdated(address indexed user, uint256 limit);
    event CollateralSupported(address indexed collateral, bool supported);

    // Errors
    error InsufficientCollateral();
    error CollateralNotSupported();
    error KYCNotVerified();
    error UserBlacklisted();
    error MintLimitExceeded();
    error BurnLimitExceeded();
    error InvalidCollateralRatio();
    error InvalidAmount();
    error OracleNotSet();
    error ReserveUpdateFailed();

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
     * @param _minCollateralRatio Minimum collateral ratio in basis points
     */
    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address _oracle,
        uint256 _minCollateralRatio
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
        _grantRole(KYC_OPERATOR_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Initialize configuration
        oracle = IOracle(_oracle);
        minCollateralRatio = _minCollateralRatio;
        maxMintLimit = 1000000 * 10**decimals(); // 1M vltUSD
        maxBurnLimit = 1000000 * 10**decimals(); // 1M vltUSD
    }

    /**
     * @notice Mint vltUSD tokens with collateral
     * @param to Recipient address
     * @param amount Amount to mint
     * @param collateral Collateral token address
     * @param collateralAmount Amount of collateral to deposit
     */
    function mint(
        address to,
        uint256 amount,
        address collateral,
        uint256 collateralAmount
    ) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        if (!kycVerified[to]) {
            revert KYCNotVerified();
        }
        if (blacklisted[to]) {
            revert UserBlacklisted();
        }
        if (!supportedCollateral[collateral]) {
            revert CollateralNotSupported();
        }
        if (amount == 0 || collateralAmount == 0) {
            revert InvalidAmount();
        }
        if (userMintLimits[to] + amount > maxMintLimit) {
            revert MintLimitExceeded();
        }

        // Calculate required collateral based on oracle price
        uint256 requiredCollateral = _calculateRequiredCollateral(amount, collateral);
        if (collateralAmount < requiredCollateral) {
            revert InsufficientCollateral();
        }

        // Update reserves
        reserves[collateral] += collateralAmount;
        totalReserves += collateralAmount;
        lastReserveUpdate = block.timestamp;

        // Mint tokens
        _mint(to, amount);
        userMintLimits[to] += amount;

        emit Minted(to, amount, collateral, collateralAmount);
        emit CollateralAdded(collateral, collateralAmount);
        emit ReserveUpdated(totalReserves, block.timestamp);
    }

    /**
     * @notice Burn vltUSD tokens and withdraw collateral
     * @param from Address to burn from
     * @param amount Amount to burn
     * @param collateral Collateral token address
     */
    function burn(
        address from,
        uint256 amount,
        address collateral
    ) external onlyRole(BURNER_ROLE) whenNotPaused nonReentrant {
        if (blacklisted[from]) {
            revert UserBlacklisted();
        }
        if (!supportedCollateral[collateral]) {
            revert CollateralNotSupported();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (userBurnLimits[from] + amount > maxBurnLimit) {
            revert BurnLimitExceeded();
        }

        // Calculate collateral to return
        uint256 collateralAmount = _calculateCollateralReturn(amount, collateral);
        if (reserves[collateral] < collateralAmount) {
            revert InsufficientCollateral();
        }

        // Update reserves
        reserves[collateral] -= collateralAmount;
        totalReserves -= collateralAmount;
        lastReserveUpdate = block.timestamp;

        // Burn tokens
        _burn(from, amount);
        userBurnLimits[from] += amount;

        emit Burned(from, amount, collateral, collateralAmount);
        emit CollateralRemoved(collateral, collateralAmount);
        emit ReserveUpdated(totalReserves, block.timestamp);
    }

    /**
     * @notice Verify KYC status for a user
     * @param user User address
     * @param verified KYC verification status
     */
    function setKYCStatus(address user, bool verified) external onlyRole(KYC_OPERATOR_ROLE) {
        kycVerified[user] = verified;
        emit KYCVerified(user, verified);
    }

    /**
     * @notice Set blacklist status for a user
     * @param user User address
     * @param blacklisted Blacklist status
     */
    function setBlacklistStatus(address user, bool blacklisted) external onlyRole(COMPLIANCE_ROLE) {
        VltUSD.blacklisted[user] = blacklisted;
        emit Blacklisted(user, blacklisted);
    }

    /**
     * @notice Set mint limit for a user
     * @param user User address
     * @param limit Mint limit
     */
    function setMintLimit(address user, uint256 limit) external onlyRole(COMPLIANCE_ROLE) {
        userMintLimits[user] = limit;
        emit MintLimitUpdated(user, limit);
    }

    /**
     * @notice Set burn limit for a user
     * @param user User address
     * @param limit Burn limit
     */
    function setBurnLimit(address user, uint256 limit) external onlyRole(COMPLIANCE_ROLE) {
        userBurnLimits[user] = limit;
        emit BurnLimitUpdated(user, limit);
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
     * @notice Update oracle address
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        oracle = IOracle(_oracle);
    }

    /**
     * @notice Update minimum collateral ratio
     * @param _minCollateralRatio New minimum collateral ratio in basis points
     */
    function setMinCollateralRatio(uint256 _minCollateralRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minCollateralRatio < 10000) { // Minimum 100%
            revert InvalidCollateralRatio();
        }
        minCollateralRatio = _minCollateralRatio;
    }

    /**
     * @notice Update mint and burn limits
     * @param _maxMintLimit New maximum mint limit
     * @param _maxBurnLimit New maximum burn limit
     */
    function setLimits(uint256 _maxMintLimit, uint256 _maxBurnLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxMintLimit = _maxMintLimit;
        maxBurnLimit = _maxBurnLimit;
    }

    /**
     * @notice Get total reserves in USD
     * @return total Total reserves in USD (8 decimals)
     */
    function getTotalReservesUSD() external view returns (uint256 total) {
        if (address(oracle) == address(0)) {
            revert OracleNotSet();
        }

        for (uint256 i = 0; i < collateralList.length; i++) {
            address collateral = collateralList[i];
            if (supportedCollateral[collateral] && reserves[collateral] > 0) {
                (uint256 price, , ) = oracle.getPrice(collateral);
                total += (reserves[collateral] * price) / 1e8;
            }
        }
    }

    /**
     * @notice Get collateral ratio for a specific collateral
     * @param collateral Collateral address
     * @return ratio Collateral ratio in basis points
     */
    function getCollateralRatio(address collateral) external view returns (uint256 ratio) {
        if (!supportedCollateral[collateral]) {
            return 0;
        }

        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return type(uint256).max;
        }

        (uint256 price, , ) = oracle.getPrice(collateral);
        uint256 collateralValue = (reserves[collateral] * price) / 1e8;
        ratio = (collateralValue * 10000) / totalSupply;
    }

    /**
     * @notice Calculate required collateral for minting
     * @param amount Amount to mint
     * @param collateral Collateral address
     * @return required Required collateral amount
     */
    function _calculateRequiredCollateral(uint256 amount, address collateral) internal view returns (uint256 required) {
        (uint256 price, , ) = oracle.getPrice(collateral);
        required = (amount * minCollateralRatio * 1e8) / (price * 10000);
    }

    /**
     * @notice Calculate collateral return for burning
     * @param amount Amount to burn
     * @param collateral Collateral address
     * @return returnAmount Collateral return amount
     */
    function _calculateCollateralReturn(uint256 amount, address collateral) internal view returns (uint256 returnAmount) {
        (uint256 price, , ) = oracle.getPrice(collateral);
        returnAmount = (amount * 1e8) / price;
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
     * @notice Override transfer to check blacklist
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        
        if (blacklisted[from] || blacklisted[to]) {
            revert UserBlacklisted();
        }
    }
} 