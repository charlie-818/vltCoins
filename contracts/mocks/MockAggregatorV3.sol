// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockAggregatorV3
 * @notice Mock Chainlink price feed for testing
 */
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _price;
    uint256 private _timestamp;
    uint80 private _roundId;

    constructor(uint8 decimals_, int256 price_) {
        _decimals = decimals_;
        _price = price_;
        _timestamp = block.timestamp;
        _roundId = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _id) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_id, _price, _timestamp, _timestamp, _id);
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _timestamp, _timestamp, _roundId);
    }

    /**
     * @notice Set the mock price
     * @param price New price
     */
    function setPrice(int256 price) external {
        _price = price;
        _timestamp = block.timestamp;
        _roundId++;
    }

    /**
     * @notice Set the mock timestamp
     * @param timestamp New timestamp
     */
    function setTimestamp(uint256 timestamp) external {
        _timestamp = timestamp;
    }
} 