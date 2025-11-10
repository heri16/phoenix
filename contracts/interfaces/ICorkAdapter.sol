// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title ICorkAdapter Interface
 * @author Cork Team
 * @notice Interface for CorkAdapter contract
 */
interface ICorkAdapter {
    struct SafeMintParams {
        MarketId poolId; // The cork pool market id
        uint256 cptAndCstSharesOut; // The amount of cpt and cst shares to mint.
        address receiver; // The address to which shares(CST & CPT) will be minted.
        uint256 maxCollateralAssetsIn; // The maximum amount of collateral assets to spend for minting shares.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeDepositParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssetsIn; // The amount of collateral assets to deposit.
        address receiver; // The address to which shares(CST & CPT) will be minted.
        uint256 minCptAndCstSharesOut; // The minimum amount of shares(CST & CPT) to receive.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindDepositParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssetsOut; // The amount of target collateral to get from the unwind.
        address owner; // The address that owns the CPT and CST shares being burned
        address receiver; // The address to which collateral assets and any excess shares will be sent.
        uint256 maxCptAndCstSharesIn; // The maximum amount of shares to burn for the unwind operation.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindMintParams {
        MarketId poolId; // The cork pool market id
        uint256 cptAndCstSharesIn; // The amount of shares to redeem. Pass type(uint).max to redeem the owner's shares.
        address owner; // The address that owns the CPT and CST shares being burned
        address receiver; // The address to which collateral assets and any excess shares will be sent.
        uint256 minCollateralAssetsOut; // The minimum amount of collateral to receive from the unwind operation.
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeWithdrawParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssetsOut; // The amount of collateral asset to withdraw
        address owner; // The address that owns the CPT shares being burned
        address receiver; // The address to which withdrawn assets will be sent
        uint256 maxCptSharesIn; // The maximum amount of CPT shares to burn for the withdrawal
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeWithdrawOtherParams {
        MarketId poolId; // The cork pool market id
        uint256 referenceAssetsOut; // The amount of reference asset to withdraw
        address owner; // The address that owns the CPT shares being burned
        address receiver; // The address to which withdrawn assets will be sent
        uint256 maxCptSharesIn; // The maximum amount of CPT shares to burn for the withdrawal
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeWithdrawInternalParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssetsOut; // The amount of collateral asset to withdraw (set to 0 if withdrawing reference asset)
        uint256 referenceAssetsOut; // The amount of reference asset to withdraw (set to 0 if withdrawing collateral asset)
        address owner; // The address that owns the CPT shares being burned
        address receiver; // The address to which withdrawn assets will be sent
        uint256 maxCptSharesIn; // The maximum amount of CPT shares to burn for the withdrawal
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeRedeemParams {
        MarketId poolId; // The cork pool market id
        uint256 cptSharesIn; // The amount of CPT tokens to redeem. Pass `type(uint).max` to use the adapter's CPT balance/allowance.
        address owner; // The address that owns the CPT tokens being redeemed
        address receiver; // The address to which redeemed assets will be sent
        uint256 minReferenceAssetsOut; // The minimum amount of reference asset to receive
        uint256 minCollateralAssetsOut; // The minimum amount of collateral asset to receive
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindSwapParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssetsIn; // The amount of collateral assets to use for unwind swap. Pass `type(uint).max` to use the adapter's collateral asset balance.
        address receiver; // The address to which reference assets and swap tokens will be sent
        uint256 minReferenceAssetsOut; // The minimum amount of reference assets to receive
        uint256 minCstSharesOut; // The minimum amount of CST shares to receive
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeSwapParams {
        MarketId poolId; // The cork pool market id
        uint256 collateralAssetsOut; // The amount of collateral assets to receive
        address receiver; // The address to which collateral assets will be sent
        uint256 maxCstSharesIn; // The maximum amount of CST shares to spend for the swap
        uint256 maxReferenceAssetsIn; // The maximum amount of reference token compensation to spend for the swap
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeExerciseParams {
        MarketId poolId; // The cork pool market id
        uint256 cstSharesIn; // The amount of CST shares to lock
        address receiver; // The address to which collateral assets will be sent
        uint256 minCollateralAssetsOut; // The minimum amount of collateral assets to receive
        uint256 maxReferenceAssetsIn; // The maximum amount of reference asset that can be spent
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeExerciseOtherParams {
        MarketId poolId; // The cork pool market id
        uint256 referenceAssetsIn; // The amount of reference token compensation to lock
        address receiver; // The address to which collateral assets will be sent
        uint256 minCollateralAssetsOut; // The minimum amount of collateral assets to receive
        uint256 maxCstSharesIn; // The maximum amount of CST shares that can be spent
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeExerciseInternalParams {
        MarketId poolId; // The cork pool market id
        uint256 cstSharesIn; // The amount of CST shares to lock (set to 0 if using referenceAssets)
        uint256 referenceAssetsIn; // The amount of reference token compensation to lock (set to 0 if using cstShares)
        address receiver; // The address to which collateral assets will be sent
        uint256 minCollateralAssetsOut; // The minimum amount of collateral assets to receive
        uint256 maxOtherTokenIn; // The maximum amount of other asset that can be spent
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindExerciseParams {
        MarketId poolId; // The cork pool market id
        uint256 cstSharesOut; // The amount of CST shares to unlock (must be non-zero)
        address receiver; // The address to which unlocked CST shares and reference token compensation will be sent
        uint256 minReferenceAssetsOut; // The minimum amount of reference token compensation to receive from the unwind exercise
        uint256 maxCollateralAssetsIn; // The maximum amount of collateral assets to spend for the unwind exercise
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindExerciseOtherParams {
        MarketId poolId; // The cork pool market id
        uint256 referenceAssetsOut; // The amount of reference token to unlock (must be non-zero)
        address receiver; // The address to which unlocked CST shares and reference token compensation will be sent
        uint256 minCstSharesOut; // The minimum amount of CST shares to receive from the unwind exercise
        uint256 maxCollateralAssetsIn; // The maximum amount of collateral assets to spend for the unwind exercise
        uint256 deadline; // The deadline by which the transaction must be completed.
    }

    struct SafeUnwindExerciseInternalParams {
        MarketId poolId; // The cork pool market id
        uint256 cstSharesOut; // The amount of CST shares to unlock (must be non-zero if referenceAssetsOut is 0)
        uint256 referenceAssetsOut; // The amount of reference token to unlock (must be non-zero if cstSharesOut is 0)
        address receiver; // The address to which unlocked CST shares and reference token compensation will be sent
        uint256 minOtherAssetOut; // The minimum amount of other asset(CST shares or reference token) to receive from the unwind exercise
        uint256 maxCollateralAssetsIn; // The maximum amount of collateral assets to spend for the unwind exercise
        uint256 deadline; // The deadline by which the transaction must be completed.
    }
}
