// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

type MarketId is bytes32;

/**
 * @dev represent a Collateral Asset/Reference Asset pair
 */
struct Market {
    // collateralAsset
    address collateralAsset;
    // referenceAsset
    address referenceAsset;
    // expiry in unix epoch timestamp in seconds
    uint256 expiryTimestamp;
    // lower limit of rate
    uint256 rateMin;
    // upper limit of rate
    uint256 rateMax;
    // maximum rate change allowance per day
    uint256 rateChangePerDayMax;
    // maximum accumulated rate change allowance for burst
    uint256 rateChangeCapacityMax;
    // IRateOracle contract address
    address rateOracle;
}
