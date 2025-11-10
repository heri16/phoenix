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
 * @notice Represents the full state of a Cork Pool within the Core contract.
 * @dev The `pauseBitMap` field encodes pause states for different pool operations.
 * @dev The mapping of bit positions to operations is as follows:
 * @dev - Bit 0 → Deposit operations (`isDepositPaused`)
 * @dev - Bit 1 → Swap operations (`isSwapPaused`)
 * @dev - Bit 2 → Withdrawal operations (`isWithdrawalPaused`)
 * @dev - Bit 3 → Unwind deposit operations (`isUnwindDepositPaused`)
 * @dev - Bit 4 → Unwind swap operations (`isUnwindSwapPaused`)
 */
struct PoolState {
    Balances balances;
    uint256 unwindSwapFeePercentage;
    CorkPoolPoolArchive poolArchive;
    bool liquiditySeparated;
    uint16 pauseBitMap;
    uint256 swapFeePercentage;
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
