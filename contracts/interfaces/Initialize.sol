// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title Initialize Interface
 * @author Cork Team
 * @notice Initialize interface for providing Initialization related functions through CorkPool contract
 */
interface Initialize {
    /**
     * @notice initialize a new pool, this will initialize Cork Pool and Liquidity Vault and deploy new LV token
     * @dev Only callable by config contract Deploy new CPT and CST tokens for the market
     * @param poolParams Parameters for the new pool
     */
    function createNewPool(Market calldata poolParams) external;

    /**
     * @notice update Cork Pool unwindSwap fee rate for a pair
     * @dev Only callable by config contract
     * @param id id of the pair
     * @param newUnwindSwapFeePercentage new value of unwindSwap fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external;

    /**
     * @notice update Cork Pool base redemption fee percentage
     * @param newBaseRedemptionFeePercentage new value of base redemption fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateBaseRedemptionFeePercentage(MarketId id, uint256 newBaseRedemptionFeePercentage) external;

    /**
     * @notice get next expiry time from id
     * @param id id of the pair
     * @return expiry next expiry time in seconds
     */
    function expiry(MarketId id) external view returns (uint256 expiry);

    /**
     * @notice returns the address of the underlying Collateral Asset and Reference Asset token
     * @param id the id of Cork Pool
     * @return collateralAsset address of the underlying Collateral Asset token
     * @return referenceAsset address of the underlying Reference Asset token
     */
    function underlyingAsset(MarketId id) external view returns (address collateralAsset, address referenceAsset);

    /**
     * @notice returns the address of Principal Token and Swap Token associated with a certain Swap Token id
     * @param id the id of Cork Pool
     * @return principalToken address of the Principal Token token
     * @return swapToken address of the Swap Token token
     */
    function shares(MarketId id) external view returns (address principalToken, address swapToken);

    /**
     * @notice Generates a unique market ID from market parameters
     * @param market The market parameters
     * market.referenceAsset The address of the reference asset (e.g., ETH for depeg protection)
     * market.collateralAsset The address of the collateral asset (e.g., stETH)
     * market.expiryTimestamp The expiry timestamp for the market
     * market.rateOracle The address of the IRateOracle contract
     * market.rateMin The minimum rate for the market
     * market.rateMax The maximum rate for the market
     * market.rateChangePerDayMax The maximum rate change per day for the market
     * market.rateChangeCapacityMax The maximum rate change capacity for the market
     * @return marketId The unique market identifier
     */
    function getId(Market calldata market) external view returns (MarketId marketId);

    /**
     * @notice Gets the market information for a given market ID
     * @param id The market identifier
     * @return market The complete market structure containing all market details
     */
    function market(MarketId id) external view returns (Market memory market);

    /**
     * @notice Gets the core details of a market
     * @param id The market identifier
     * @return referenceAsset The address of the reference asset
     * @return collateralAsset The address of the collateral asset
     * @return expiryTimestamp The timestamp when the market expires
     * @return rateOracle The address of the IRateOracle contract
     */
    function marketDetails(MarketId id) external view returns (address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax);

    /// @notice Emitted when a new LV and Cork Pool is initialized with a given pair
    /// @param id The Cork Pool id
    /// @param referenceAsset The address of the pegged asset
    /// @param collateralAsset The address of the redemption asset
    /// @param expiry The expiry interval of the Swap Token
    event MarketCreated(MarketId indexed id, address indexed referenceAsset, address indexed collateralAsset, uint256 expiry, address rateOracle, address principalToken, address swapToken);
}
