// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IConstraintAdapter Interface
 * @author Cork Team
 * @notice Interface which provides NAV ratio
 */
interface IConstraintAdapter {
    struct ConstraintState {
        uint256 _lastAdjustedRate;
        uint256 _lastAdjustmentTimestamp;
        uint256 _remainingCredits;
    }

    function adjustedRate(MarketId poolId) external returns (uint256 rate);

    function previewAdjustedRate(MarketId poolId) external view returns (uint256 rate);

    function bootstrap(MarketId poolId) external;
}
