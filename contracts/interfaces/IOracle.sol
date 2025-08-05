// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @notice Interface for oracle price feeds and data validation
 * @dev Supports Chainlink, Pyth, and other oracle providers
 */
interface IOracle {
    /**
     * @notice Get the latest price for a given asset
     * @param asset The asset address or identifier
     * @return price The latest price (8 decimals)
     * @return timestamp The timestamp of the price update
     * @return roundId The round ID for Chainlink feeds
     */
    function getPrice(address asset) external view returns (
        uint256 price,
        uint256 timestamp,
        uint80 roundId
    );

    /**
     * @notice Get the latest price with staleness check
     * @param asset The asset address or identifier
     * @param maxAge Maximum age of price data in seconds
     * @return price The latest price (8 decimals)
     * @return timestamp The timestamp of the price update
     */
    function getPriceWithStalenessCheck(
        address asset,
        uint256 maxAge
    ) external view returns (uint256 price, uint256 timestamp);

    /**
     * @notice Check if price data is stale
     * @param asset The asset address or identifier
     * @param maxAge Maximum age of price data in seconds
     * @return True if price is stale
     */
    function isPriceStale(address asset, uint256 maxAge) external view returns (bool);

    /**
     * @notice Get the price deviation from a reference price
     * @param asset The asset address or identifier
     * @param referencePrice The reference price to compare against
     * @return deviation The deviation percentage (basis points)
     */
    function getPriceDeviation(
        address asset,
        uint256 referencePrice
    ) external view returns (uint256 deviation);

    /**
     * @notice Get the oracle type (Chainlink, Pyth, etc.)
     * @return oracleType The oracle type identifier
     */
    function getOracleType() external view returns (string memory oracleType);

    /**
     * @notice Get the heartbeat interval for the oracle
     * @return heartbeat The heartbeat interval in seconds
     */
    function getHeartbeat() external view returns (uint256 heartbeat);

    /**
     * @notice Get the minimum price deviation threshold
     * @return threshold The minimum deviation threshold in basis points
     */
    function getMinDeviationThreshold() external view returns (uint256 threshold);

    /**
     * @notice Get the maximum price deviation threshold
     * @return threshold The maximum deviation threshold in basis points
     */
    function getMaxDeviationThreshold() external view returns (uint256 threshold);
} 