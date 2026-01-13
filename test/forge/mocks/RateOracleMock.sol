// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IComposableRateOracle, IRateOracle} from "contracts/interfaces/IRateOracle.sol";

contract RateOracleMock is IComposableRateOracle {
    uint256 lastUpdated;
    uint8 _decimals = 18;
    bool _revert;

    /// @inheritdoc IRateOracle
    function rate() external view returns (uint256 rate) {
        require(_revert == false, "mock revert");

        rate = lastUpdated;
    }

    /**
     * @notice updates the relative NAV ratio of the Cork Pool Assets
     * @param newRate the relative NAV ratio of the Cork Pool Assets
     */
    function setRate(uint256 newRate) external {
        lastUpdated = newRate;
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function setRateShouldRevert(bool _shouldRevert) external {
        _revert = _shouldRevert;
    }

    /**
     * @notice updates the relative NAV ratio of the Cork Pool Assets
     * @param id the id of the Cork Pool
     * @param newRate the relative NAV ratio of the Cork Pool Assets
     */
    function setRate(MarketId id, uint256 newRate) external {
        lastUpdated = newRate;
    }

    /// @notice Returns the precision of the feed.
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /// @notice Returns Chainlink's `latestRoundData` return values.
    /// @notice Only the `answer` field is used.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, int256(lastUpdated), 0, 0, 0);
    }
}
