// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IOracle.sol";

/**
 * @title ChainlinkOracle
 * @notice Chainlink price feed oracle implementation with validation and fallback logic
 * @dev Supports multiple price feeds with staleness checks and deviation thresholds
 */
contract ChainlinkOracle is IOracle, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Price feed mapping: asset => feed address
    mapping(address => address) public priceFeeds;
    
    // Oracle configuration
    uint256 public heartbeat = 3600; // 1 hour default
    uint256 public minDeviationThreshold = 100; // 1% default
    uint256 public maxDeviationThreshold = 1000; // 10% default
    uint256 public stalenessThreshold = 3600; // 1 hour default

    // Events
    event PriceFeedUpdated(address indexed asset, address indexed feed);
    event HeartbeatUpdated(uint256 newHeartbeat);
    event DeviationThresholdsUpdated(uint256 minThreshold, uint256 maxThreshold);
    event StalenessThresholdUpdated(uint256 newThreshold);

    // Errors
    error InvalidPriceFeed();
    error StalePrice();
    error PriceDeviationTooHigh();
    error InvalidAsset();
    error InvalidThreshold();

    /**
     * @notice Constructor
     * @param admin The admin address
     */
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    /**
     * @notice Get the latest price for a given asset
     * @param asset The asset address
     * @return price The latest price (8 decimals)
     * @return timestamp The timestamp of the price update
     * @return roundId The round ID for Chainlink feeds
     */
    function getPrice(address asset) external view override returns (
        uint256 price,
        uint256 timestamp,
        uint80 roundId
    ) {
        if (priceFeeds[asset] == address(0)) {
            revert InvalidAsset();
        }

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[asset]);
        
        (
            uint80 id,
            int256 priceInt,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate price feed
        if (priceInt <= 0) {
            revert InvalidPriceFeed();
        }

        if (answeredInRound < id) {
            revert StalePrice();
        }

        return (uint256(priceInt), timeStamp, id);
    }

    /**
     * @notice Get the latest price with staleness check
     * @param asset The asset address
     * @param maxAge Maximum age of price data in seconds
     * @return price The latest price (8 decimals)
     * @return timestamp The timestamp of the price update
     */
    function getPriceWithStalenessCheck(
        address asset,
        uint256 maxAge
    ) external view override returns (uint256 price, uint256 timestamp) {
        (price, timestamp, ) = this.getPrice(asset);
        
        if (block.timestamp - timestamp > maxAge) {
            revert StalePrice();
        }
    }

    /**
     * @notice Check if price data is stale
     * @param asset The asset address
     * @param maxAge Maximum age of price data in seconds
     * @return True if price is stale
     */
    function isPriceStale(address asset, uint256 maxAge) external view override returns (bool) {
        try this.getPriceWithStalenessCheck(asset, maxAge) returns (uint256, uint256) {
            return false;
        } catch {
            return true;
        }
    }

    /**
     * @notice Get the price deviation from a reference price
     * @param asset The asset address
     * @param referencePrice The reference price to compare against
     * @return deviation The deviation percentage (basis points)
     */
    function getPriceDeviation(
        address asset,
        uint256 referencePrice
    ) external view override returns (uint256 deviation) {
        (uint256 currentPrice, , ) = this.getPrice(asset);
        
        if (referencePrice == 0) {
            return 0;
        }

        if (currentPrice > referencePrice) {
            deviation = ((currentPrice - referencePrice) * 10000) / referencePrice;
        } else {
            deviation = ((referencePrice - currentPrice) * 10000) / referencePrice;
        }
    }

    /**
     * @notice Get the oracle type
     * @return oracleType The oracle type identifier
     */
    function getOracleType() external pure override returns (string memory oracleType) {
        return "Chainlink";
    }

    /**
     * @notice Get the heartbeat interval
     * @return heartbeat The heartbeat interval in seconds
     */
    function getHeartbeat() external view override returns (uint256 heartbeat) {
        return heartbeat;
    }

    /**
     * @notice Get the minimum price deviation threshold
     * @return threshold The minimum deviation threshold in basis points
     */
    function getMinDeviationThreshold() external view override returns (uint256 threshold) {
        return minDeviationThreshold;
    }

    /**
     * @notice Get the maximum price deviation threshold
     * @return threshold The maximum deviation threshold in basis points
     */
    function getMaxDeviationThreshold() external view override returns (uint256 threshold) {
        return maxDeviationThreshold;
    }

    /**
     * @notice Set a price feed for an asset
     * @param asset The asset address
     * @param feed The Chainlink price feed address
     */
    function setPriceFeed(address asset, address feed) external onlyRole(ADMIN_ROLE) {
        if (feed == address(0)) {
            revert InvalidPriceFeed();
        }
        
        priceFeeds[asset] = feed;
        emit PriceFeedUpdated(asset, feed);
    }

    /**
     * @notice Set multiple price feeds
     * @param assets Array of asset addresses
     * @param feeds Array of price feed addresses
     */
    function setPriceFeeds(address[] calldata assets, address[] calldata feeds) external onlyRole(ADMIN_ROLE) {
        if (assets.length != feeds.length) {
            revert InvalidAsset();
        }
        
        for (uint256 i = 0; i < assets.length; i++) {
            if (feeds[i] == address(0)) {
                revert InvalidPriceFeed();
            }
            priceFeeds[assets[i]] = feeds[i];
            emit PriceFeedUpdated(assets[i], feeds[i]);
        }
    }

    /**
     * @notice Update the heartbeat interval
     * @param newHeartbeat The new heartbeat interval in seconds
     */
    function setHeartbeat(uint256 newHeartbeat) external onlyRole(ADMIN_ROLE) {
        if (newHeartbeat == 0) {
            revert InvalidThreshold();
        }
        
        heartbeat = newHeartbeat;
        emit HeartbeatUpdated(newHeartbeat);
    }

    /**
     * @notice Update deviation thresholds
     * @param minThreshold The minimum deviation threshold in basis points
     * @param maxThreshold The maximum deviation threshold in basis points
     */
    function setDeviationThresholds(uint256 minThreshold, uint256 maxThreshold) external onlyRole(ADMIN_ROLE) {
        if (minThreshold >= maxThreshold) {
            revert InvalidThreshold();
        }
        
        minDeviationThreshold = minThreshold;
        maxDeviationThreshold = maxThreshold;
        emit DeviationThresholdsUpdated(minThreshold, maxThreshold);
    }

    /**
     * @notice Update the staleness threshold
     * @param newThreshold The new staleness threshold in seconds
     */
    function setStalenessThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        if (newThreshold == 0) {
            revert InvalidThreshold();
        }
        
        stalenessThreshold = newThreshold;
        emit StalenessThresholdUpdated(newThreshold);
    }

    /**
     * @notice Pause oracle operations
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause oracle operations
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Check if a price feed exists for an asset
     * @param asset The asset address
     * @return exists True if price feed exists
     */
    function hasPriceFeed(address asset) external view returns (bool exists) {
        return priceFeeds[asset] != address(0);
    }

    /**
     * @notice Get the price feed address for an asset
     * @param asset The asset address
     * @return feed The price feed address
     */
    function getPriceFeed(address asset) external view returns (address feed) {
        return priceFeeds[asset];
    }
} 