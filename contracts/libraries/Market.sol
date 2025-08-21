// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";

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

/**
 * @title MarketLibrary Contract
 * @author Cork Team
 * @notice Market Library which implements functions for handling Market operations
 */
library MarketLibrary {
    function toId(Market memory marketKey) internal pure returns (MarketId id) {
        id = MarketId.wrap(keccak256(abi.encode(marketKey)));
    }

    function initialize(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax) internal view returns (Market memory marketParams) {
        require(referenceAsset != address(0) && collateralAsset != address(0), IErrors.ZeroAddress());
        require(referenceAsset != collateralAsset, IErrors.InvalidAddress());
        require(expiryTimestamp > block.timestamp, IErrors.InvalidExpiry());
        require(rateOracle != address(0), IErrors.ZeroAddress());

        marketParams = Market({collateralAsset: collateralAsset, referenceAsset: referenceAsset, expiryTimestamp: expiryTimestamp, rateMin: rateMin, rateMax: rateMax, rateChangePerDayMax: rateChangePerDayMax, rateChangeCapacityMax: rateChangeCapacityMax, rateOracle: rateOracle});
    }

    function underlyingAsset(Market memory market) internal pure returns (address collateralAsset, address referenceAsset) {
        referenceAsset = market.referenceAsset;
        collateralAsset = market.collateralAsset;
    }

    function isInitialized(Market memory market) internal pure returns (bool status) {
        status = market.referenceAsset != address(0) && market.collateralAsset != address(0);
    }
}
