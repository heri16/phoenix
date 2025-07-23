// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";

type MarketId is bytes32;

/**
 * @dev represent a Collateral Asset/Reference Asset pair
 */
struct Market {
    // referenceAsset/principalToken
    address referenceAsset;
    // collateralAsset/swapToken
    address collateralAsset;
    // expiry in unix epoch timestamp in seconds
    uint256 expiryTimestamp;
    // IExchangeRateProvider contract address
    address exchangeRateProvider;
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

    function initialize(address referenceAsset, address collateralAsset, uint256 expiry, address exchangeRateProvider) internal pure returns (Market memory marketKey) {
        if (referenceAsset == address(0) || collateralAsset == address(0)) revert IErrors.ZeroAddress();
        if (referenceAsset == collateralAsset) revert IErrors.InvalidAddress();
        if (expiry == 0) revert IErrors.InvalidExpiry();
        if (exchangeRateProvider == address(0)) revert IErrors.ZeroAddress();

        marketKey = Market(referenceAsset, collateralAsset, expiry, exchangeRateProvider);
    }

    function underlyingAsset(Market memory market) internal pure returns (address collateralAsset, address referenceAsset) {
        referenceAsset = market.referenceAsset;
        collateralAsset = market.collateralAsset;
    }

    function isInitialized(Market memory market) internal pure returns (bool status) {
        status = market.referenceAsset != address(0) && market.collateralAsset != address(0);
    }
}
