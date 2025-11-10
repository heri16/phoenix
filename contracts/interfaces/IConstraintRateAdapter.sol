// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IConstraintRateAdapter Interface
 * @author Cork Team
 * @notice Interface which provides NAV ratio
 */
interface IConstraintRateAdapter {
    struct ConstraintState {
        uint256 _lastAdjustedRate;
        uint256 _lastAdjustmentTimestamp;
        uint256 _remainingCredits;
    }

    struct RateCalculationParams {
        uint256 newRate;
        uint256 lastAdjustedRate;
        uint256 remainingCredits;
        uint256 lastAdjustmentTimestamp;
        uint256 currentTimestamp;
        uint256 rateChangePerDayMax;
        uint256 rateChangeCapacityMax;
        uint256 rateMin;
        uint256 rateMax;
    }

    // ======================================================
    // VIEW FUNCTIONS
    // ======================================================
    function adjustedRate(MarketId poolId) external returns (uint256 rate);

    function previewAdjustedRate(MarketId poolId) external view returns (uint256 rate);

    // ======================================================
    // CORE FUNCTIONS
    // ======================================================
    function bootstrap(MarketId poolId) external;
}
