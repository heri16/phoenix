// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MinimalAggregatorV3Interface} from "./MinimalAggregatorV3Interface.sol";

/**
 * @title IRateOracle Interface
 * @author Cork Team
 * @notice Interface which provides NAV ratio
 */
interface IRateOracle {
    /**
     * @notice Returns the NAV of 1 token of reference asset quoted in 1 token of collateral asset, scaled by 1e18.
     * @return rate the relative NAV ratio of the Cork Pool Assets
     */
    function rate() external view returns (uint256);
}

/**
 * @title IComposableRateOracle Interface
 * @author Cork Team
 * @notice Interface which provides a composable rate oracle
 */
interface IComposableRateOracle is IRateOracle, MinimalAggregatorV3Interface {}
