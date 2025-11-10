// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title Initialize Interface
 * @author Cork Team
 * @notice Initialize interface for providing Initialization related functions through CorkPoolManager contract
 */
interface Initialize {
    /**
     * @notice initialize a new pool, this will initialize Cork Pool and Liquidity Vault and deploy new LV token
     * @dev Only callable by controller contract Deploy new CPT and CST tokens for the market
     * @param poolParams Parameters for the new pool
     */
    function createNewPool(Market calldata poolParams) external;

    /**
     * @notice update Cork Pool unwindSwap fee rate for a pair
     * @dev Only callable by controller contract
     * @param id id of the pair
     * @param newUnwindSwapFeePercentage new value of unwindSwap fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external;

    /**
     * @notice update Cork Pool base redemption fee percentage
     * @param newSwapFeePercentage new value of base redemption fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateSwapFeePercentage(MarketId id, uint256 newSwapFeePercentage) external;

    /**
     * @notice returns the address of Principal Token and Swap Token associated with a certain Swap Token id
     * @param id the id of Cork Pool
     * @return principalToken address of the Principal Token token
     * @return swapToken address of the Swap Token token
     */
    function shares(MarketId id) external view returns (address principalToken, address swapToken);

    /**
     * @notice Generates a unique market ID from market parameters
     * @param marketParameters The market parameters
     * marketParameters.referenceAsset The address of the reference asset (e.g., ETH for depeg protection)
     * marketParameters.collateralAsset The address of the collateral asset (e.g., stETH)
     * marketParameters.expiryTimestamp The expiry timestamp for the market
     * marketParameters.rateOracle The address of the IRateOracle contract
     * marketParameters.rateMin The minimum rate for the market
     * marketParameters.rateMax The maximum rate for the market
     * marketParameters.rateChangePerDayMax The maximum rate change per day for the market
     * marketParameters.rateChangeCapacityMax The maximum rate change capacity for the market
     * @return marketId The unique market identifier
     */
    function getId(Market calldata marketParameters) external view returns (MarketId marketId);

    /**
     * @notice Gets the market parameters for a given market ID
     * @param id The market identifier
     * @return parameters The complete market structure containing all market details
     */
    function market(MarketId id) external view returns (Market memory parameters);

    /// @notice Emitted when a new LV and Cork Pool is initialized with a given pair
    /// @param id The Cork Pool id
    /// @param referenceAsset The address of the pegged asset
    /// @param collateralAsset The address of the redemption asset
    /// @param expiry The expiry interval of the Swap Token
    event MarketCreated(MarketId indexed id, address indexed referenceAsset, address indexed collateralAsset, uint256 expiry, address rateOracle, address principalToken, address swapToken);
}
