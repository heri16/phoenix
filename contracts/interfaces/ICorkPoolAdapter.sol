// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title ICorkPoolAdapter Interface
 * @author Cork Team
 * @notice Interface for CorkPoolAdapter contract
 */
interface ICorkPoolAdapter {
    struct SafeMintParams {
        MarketId poolId; // The cork pool market id
        uint256 shares; // The amount of vault shares to mint.
        address receiver; // The address to which shares(CST & CPT) will be minted.
        uint256 maxAssetsIn; // The maximum amount of collateral assets to spend for minting shares.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeDepositParams {
        MarketId poolId; // The cork pool market id
        uint256 assets; // The amount of collateral assets to deposit.
        address receiver; // The address to which shares(CST & CPT) will be minted.
        uint256 minSharesOut; // The minimum amount of shares(CST & CPT) to receive.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindDepositParams {
        MarketId poolId; // The cork pool market id
        uint256 assets; // The amount of target collateral to get from the unwind.
        address owner; // The address that owns the CPT and CST shares being burned
        address receiver; // The address to which collateral assets and any excess shares will be sent.
        uint256 maxSharesIn; // The maximum amount of shares to burn for the unwind operation.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindMintParams {
        MarketId poolId; // The cork pool market id
        uint256 shares; // The amount of shares to redeem. Pass type(uint).max to redeem the owner's shares.
        address owner; // The address that owns the CPT and CST shares being burned
        address receiver; // The address to which collateral assets and any excess shares will be sent.
        uint256 minAssetsOut; // The minimum amount of collateral to receive from the unwind operation.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeWithdrawParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssets; // The amount of collateral asset to withdraw (set to 0 if withdrawing reference asset)
        uint256 referenceAssets; // The amount of reference asset to withdraw (set to 0 if withdrawing collateral asset)
        address owner; // The address that owns the CPT shares being burned
        address receiver; // The address to which withdrawn assets will be sent
        uint256 maxSharesIn; // The maximum amount of CPT shares to burn for the withdrawal
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeRedeemParams {
        MarketId poolId; // The cork pool market id
        uint256 cptShares; // The amount of CPT tokens to redeem. Pass `type(uint).max` to use the adapter's CPT balance/allowance.
        address owner; // The address that owns the CPT tokens being redeemed
        address receiver; // The address to which redeemed assets will be sent
        uint256 minReferenceAssetsOut; // The minimum amount of reference asset to receive
        uint256 minCollateralAssetsOut; // The minimum amount of collateral asset to receive
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindSwapParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssets; // The amount of collateral assets to use for unwind swap. Pass `type(uint).max` to use the adapter's collateral asset balance.
        address receiver; // The address to which reference assets and swap tokens will be sent
        uint256 minReferenceAssetsOut; // The minimum amount of reference assets to receive
        uint256 minCstSharesOut; // The minimum amount of swap tokens to receive
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeSwapParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssets; // The amount of collateral assets to receive
        address owner; // The address that owns the CST shares and reference tokens being swapped
        address receiver; // The address to which collateral assets will be sent
        uint256 maxCstSharesIn; // The maximum amount of CST shares to spend for the swap
        uint256 maxReferenceAssetsIn; // The maximum amount of reference token compensation to spend for the swap
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeExerciseParams {
        MarketId poolId; // The cork pool market id
        uint256 cstShares; // The amount of CST shares to lock (set to 0 if using referenceAssets)
        uint256 referenceAssets; // The amount of reference token compensation to lock (set to 0 if using cstShares)
        address owner; // The address that owns the CST shares and reference tokens being exercised
        address receiver; // The address to which collateral assets will be sent
        uint256 minCollateralAssetsOut; // The minimum amount of collateral assets to receive
        uint256 maxOtherTokenIn; // The maximum amount of other asset that can be spent
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindExerciseParams {
        MarketId poolId; // The cork pool market id
        uint256 shares; // The amount of CST shares to unlock.
        address receiver; // The address to which unlocked CST shares and reference token compensation will be sent
        uint256 minReferenceAssetsOut; // The minimum amount of reference token compensation to receive
        uint256 maxCollateralAssetsIn; // The maximum amount of collateral assets to spend for the unwind exercise
        uint256 deadline; // The deadline by which the transaction must be completed.
    }
}
