// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IExchangeRateProvider Interface
 * @author Cork Team
 * @notice Interface which provides exchange rate
 */
interface IExchangeRateProvider {
    event RateUpdated(MarketId indexed id, uint256 newRate);

    /**
     * @notice returns the exchange rate of the Cork Pool
     * @return rate the exchange rate of the Cork Pool
     */
    function rate() external view returns (uint256 rate);

    /**
     * @notice returns the exchange rate of the Cork Pool
     * @param id the id of the Cork Pool
     * @return rate the exchange rate of the Cork Pool
     */
    function rate(MarketId id) external view returns (uint256 rate);

    /**
     * @notice updates the exchange rate of the Cork Pool
     * @param id the id of the Cork Pool
     * @param newRate the exchange rate of the Swap Token, token that are non-rebasing MUST set this to 1e18, and rebasing tokens should set this to the current exchange rate in the market
     */
    function setRate(MarketId id, uint256 newRate) external;
}
