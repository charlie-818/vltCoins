// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVault
 * @notice Interface for vault operations including collateral management and yield
 * @dev Extends ERC4626 for yield-bearing vault functionality
 */
interface IVault {
    /**
     * @notice Deposit collateral into the vault
     * @param collateral The collateral token address
     * @param amount The amount to deposit
     * @param receiver The address to receive vault shares
     * @return shares The amount of vault shares minted
     */
    function deposit(
        address collateral,
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    /**
     * @notice Withdraw collateral from the vault
     * @param collateral The collateral token address
     * @param shares The amount of shares to burn
     * @param receiver The address to receive the collateral
     * @param owner The address that owns the shares
     * @return amount The amount of collateral withdrawn
     */
    function withdraw(
        address collateral,
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 amount);

    /**
     * @notice Get the total value locked in the vault
     * @param collateral The collateral token address
     * @return tvl The total value locked
     */
    function getTotalValueLocked(address collateral) external view returns (uint256 tvl);

    /**
     * @notice Get the collateral ratio for a specific collateral
     * @param collateral The collateral token address
     * @return ratio The collateral ratio (basis points)
     */
    function getCollateralRatio(address collateral) external view returns (uint256 ratio);

    /**
     * @notice Get the minimum collateral ratio
     * @return minRatio The minimum collateral ratio (basis points)
     */
    function getMinCollateralRatio() external view returns (uint256 minRatio);

    /**
     * @notice Get the liquidation threshold for a collateral
     * @param collateral The collateral token address
     * @return threshold The liquidation threshold (basis points)
     */
    function getLiquidationThreshold(address collateral) external view returns (uint256 threshold);

    /**
     * @notice Check if a position is liquidatable
     * @param user The user address
     * @param collateral The collateral token address
     * @return liquidatable True if position can be liquidated
     */
    function isLiquidatable(address user, address collateral) external view returns (bool liquidatable);

    /**
     * @notice Liquidate an undercollateralized position
     * @param user The user to liquidate
     * @param collateral The collateral token address
     * @param liquidator The address performing the liquidation
     */
    function liquidate(
        address user,
        address collateral,
        address liquidator
    ) external;

    /**
     * @notice Get the yield rate for the vault
     * @return rate The yield rate (basis points)
     */
    function getYieldRate() external view returns (uint256 rate);

    /**
     * @notice Claim accumulated yield
     * @param receiver The address to receive the yield
     * @return amount The amount of yield claimed
     */
    function claimYield(address receiver) external returns (uint256 amount);

    /**
     * @notice Get the total yield earned by the vault
     * @return totalYield The total yield earned
     */
    function getTotalYield() external view returns (uint256 totalYield);

    /**
     * @notice Get the yield earned by a specific user
     * @param user The user address
     * @return userYield The yield earned by the user
     */
    function getUserYield(address user) external view returns (uint256 userYield);

    /**
     * @notice Pause vault operations
     * @dev Only callable by authorized roles
     */
    function pause() external;

    /**
     * @notice Unpause vault operations
     * @dev Only callable by authorized roles
     */
    function unpause() external;

    /**
     * @notice Check if vault is paused
     * @return paused True if vault is paused
     */
    function isPaused() external view returns (bool paused);

    /**
     * @notice Emergency withdrawal function
     * @param collateral The collateral token address
     * @param amount The amount to withdraw
     * @param receiver The address to receive the collateral
     */
    function emergencyWithdraw(
        address collateral,
        uint256 amount,
        address receiver
    ) external;

    /**
     * @notice Get supported collateral tokens
     * @return collaterals Array of supported collateral addresses
     */
    function getSupportedCollaterals() external view returns (address[] memory collaterals);

    /**
     * @notice Check if a collateral is supported
     * @param collateral The collateral token address
     * @return supported True if collateral is supported
     */
    function isCollateralSupported(address collateral) external view returns (bool supported);
} 