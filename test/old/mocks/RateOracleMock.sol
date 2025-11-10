// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {MarketId} from "contracts/libraries/Market.sol";

contract RateOracleMock is IRateOracle {
    // mapping(MarketId => uint256) rates;
    uint256 lastUpdated;

    /// @inheritdoc IRateOracle
    function rate() external view returns (uint256 rate) {
        rate = lastUpdated;
    }

    /**
     * @notice updates the relative NAV ratio of the Cork Pool Assets
     * @param newRate the relative NAV ratio of the Cork Pool Assets
     */
    function setRate(uint256 newRate) external {
        lastUpdated = newRate;
    }

    /**
     * @notice updates the relative NAV ratio of the Cork Pool Assets
     * @param id the id of the Cork Pool
     * @param newRate the relative NAV ratio of the Cork Pool Assets
     */
    function setRate(MarketId id, uint256 newRate) external {
        // rates[id] = newRate;
        lastUpdated = newRate;
    }
}
