// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {CollateralAssetManager} from "contracts/libraries/CollateralAssetManager.sol";
import {Market} from "contracts/libraries/Market.sol";
import {SwapToken} from "contracts/libraries/SwapToken.sol";

/**
 * @dev State structure
 * @dev as there are some fields that are used in Cork Pool but not in LV
 */
struct State {
    Market info;
    /// @dev epoch => SwapToken(Principal Token + Swap Token)
    SwapToken swapToken;
    PoolState pool;
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
    uint256 principalTokenAttributed;
}

/**
 * @dev Balances structure for managing balances in Cork Pool Core
 */
struct Balances {
    CollateralAssetManager collateralAsset;
    uint256 swapTokenBalance;
    uint256 referenceAssetBalance;
}
