// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Market} from "contracts/libraries/Market.sol";

/**
 * @dev State structure
 * @dev as there are some fields that are used in Cork Pool but not in LV
 */
struct State {
    Market info;
    /// @dev epoch => Shares(Principal Token + Swap Token)
    Shares shares;
    PoolState pool;
    // @dev decimals of the reference asset token
    uint8 referenceDecimals;
    // @dev decimals of the collateral asset token
    uint8 collateralDecimals;
}

/// @dev struct for shares
struct Shares {
    address swap;
    address principal;
    uint256 withdrawn;
}

/**
 * @dev CollateralAssetManager struct for managing collateral asset
 */
struct CollateralAssetManager {
    address _address;
    uint256 locked;
}

/**
 * @dev PoolState structure for Cork Pool Core
 */
struct PoolState {
    Balances balances;
    uint256 unwindSwapFeePercentage;
    CorkPoolPoolArchive poolArchive;
    bool liquiditySeparated;
    bool isDepositPaused;
    bool isSwapPaused;
    bool isWithdrawalPaused;
    bool isReturnPaused;
    bool isUnwindSwapPaused;
    uint256 baseRedemptionFeePercentage;
}

/**
 * @dev CorkPoolPoolArchive structure for Cork Pool Pools
 */
struct CorkPoolPoolArchive {
    uint256 collateralAssetAccrued;
    uint256 referenceAssetAccrued;
}

/**
 * @dev Balances structure for managing balances in Cork Pool Core
 */
struct Balances {
    CollateralAssetManager collateralAsset;
    uint256 swapTokenBalance;
    uint256 referenceAssetBalance;
}
