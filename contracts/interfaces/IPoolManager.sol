// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IPoolManager Interface
 * @author Cork Team
 * @notice IPoolManager interface for CorkPool contract
 */
interface IPoolManager is IUnwindSwap, Initialize {
    struct ExerciseParams {
        MarketId poolId; // The Cork Pool id
        uint256 shares; // The amount of CST shares to lock (must be 0 if compensation is non-zero)
        uint256 compensation; // The amount of reference token compensation to lock (must be 0 if shares is non-zero)
        address receiver; // The address that will receive the collateral assets
        uint256 minAssetsOut; // The minimum amount of collateral assets that must be received
        uint256 maxOtherAssetSpent; // The maximum amount of other asset that can be spent
    }

    struct WithdrawParams {
        MarketId poolId; // The Cork Pool id
        uint256 collateralAssetOut; // The amount of collateral asset to withdraw
        uint256 referenceAssetOut; // The amount of reference asset to withdraw
        address owner; // The address that owns the Principal Token to be burned
        address receiver; // The address that will receive the collateral assets and reference assets
    }

    struct UnwindExerciseParams {
        MarketId poolId; // The Cork Pool id
        uint256 shares; // The amount of CST shares to unlock
        address receiver; // The address that will receive the unlocked tokens
        uint256 minCompensationOut; // The minimum amount of reference token compensation that must be unlocked
        uint256 maxAssetsIn; // The maximum amount of collateral assets that can be deposited
    }

    struct PausedStates {
        bool depositPaused;
        bool unwindSwapPaused;
        bool swapPaused;
        bool withdrawalPaused;
        bool unwindDepositAndMintPaused;
    }

    enum OperationType {
        DEPOSIT,
        UNWIND_SWAP,
        SWAP,
        WITHDRAWAL,
        PREMATURE_WITHDRAWAL
    }

    /// @param poolId The Cork Pool id
    /// @param sender The sender address
    /// @param owner The owner/receiver of shares
    /// @param amount0 The collateral asset amount
    /// @param amount1 The reference asset amount
    /// @param isRemove The assets removed or added (false when added, true when removed)
    event PoolModifyLiquidity(MarketId indexed poolId, address indexed sender, address indexed owner, uint256 amount0, uint256 amount1, bool isRemove);

    /// @notice Emitted when a user swaps a Swap Token for a given Cork Pool
    /// @param poolId The Cork Pool id
    /// @param sender The address of the sender
    /// @param owner The address of the owner
    /// @param amount0 The amount of the collateral asset removed after fees
    /// @param amount1 The amount of the reference asset added after fees
    /// @param lpFeeAmount0 collateral asset fee earned by CPT holders, and accounted separately from the pool (zero)
    /// @param lpFeeAmount1  reference asset fee earned by CPT holders, and accounted separately from the pool (zero)
    /// @param isUnwind Whether the swap is a repurchase (true if unwind or false when swap)
    event PoolSwap(MarketId indexed poolId, address indexed sender, address indexed owner, uint256 amount0, uint256 amount1, uint256 lpFeeAmount0, uint256 lpFeeAmount1, bool isUnwind);

    /// @notice Emitted when a user swaps a Swap Token for a given Cork Pool
    /// @param poolId The Cork Pool id
    /// @param sender The address of the sender
    /// @param devFeeAmountInCollateralAsset The amount of the collateral asset fee to cork protocol
    /// @param devFeeAmountInReferenceAsset The amount of the reference asset fee to cork protocol
    event PoolFee(MarketId indexed poolId, address indexed sender, uint256 devFeeAmountInCollateralAsset, uint256 devFeeAmountInReferenceAsset);

    /// @notice Emmitted when baseRedemptionFeePercentage is updated
    /// @param poolId the Cork Pool id
    /// @param baseRedemptionFeePercentage the new baseRedemptionFeePercentage
    event BaseRedemptionFeePercentageUpdated(MarketId indexed poolId, uint256 indexed baseRedemptionFeePercentage);

    /// @notice emitted when deposit is paused
    event DepositPaused(MarketId indexed marketId);

    /// @notice emitted when deposit is unpaused
    event DepositUnpaused(MarketId indexed marketId);

    /// @notice emitted when unwindSwap is paused
    event UnwindSwapPaused(MarketId indexed marketId);

    /// @notice emitted when unwindSwap is unpaused
    event UnwindSwapUnpaused(MarketId indexed marketId);

    /// @notice emitted when swap is paused
    event SwapPaused(MarketId indexed marketId);

    /// @notice emitted when swap is unpaused
    event SwapUnpaused(MarketId indexed marketId);

    /// @notice emitted when withdrawal is paused
    event WithdrawalPaused(MarketId indexed marketId);

    /// @notice emitted when withdrawal is unpaused
    event WithdrawalUnpaused(MarketId indexed marketId);

    /// @notice emitted when premature withdrawal is paused
    event ReturnPaused(MarketId indexed marketId);

    /// @notice emitted when premature withdrawal is unpaused
    event ReturnUnpaused(MarketId indexed marketId);

    /// @notice thrown when mint amount is invalid, e.g trying to mint 100 CPT/100 CST but only capable of minting 50 CPT/50 CST
    error InvalidMintAmount(uint256 expected, uint256 actual);

    /// @notice thrown when unwind deposit amount is invalid, e.g trying to unwind deposit 100 CPT/100 CST but only capable of unwinding 50 CPT/50 CST
    error InvalidUnwindDepositAmount(uint256 expected, uint256 actual);

    /**
     * @notice Deposits collateral asset and returns the amount of Principal Token and Swap Token tokens after deposit
     * @param poolId the id of Cork Pool
     * @param collateralAssetAmountIn the amount of collateral to deposit
     * @param receiver the address that will receive the Principal Token and Swap Token
     * @return received the amount of Principal Token/Swap Token received
     */
    function deposit(MarketId poolId, uint256 collateralAssetAmountIn, address receiver) external returns (uint256 received);

    /**
     * This determines the rate of how much the user will receive for the amount of asset they want to deposit.
     * for example, if the rate is 1.5, then the user will need to deposit 1.5 token to get 1 Principal Token and Swap Token.
     * @param poolId the id of the Cork Pool
     * @return rate the swap rate of the Swap Token
     */
    function swapRate(MarketId poolId) external view returns (uint256 rate);

    /**
     * @notice Exercise function that locks up CST shares or compensation in reference token
     * and sends collateral assets to receiver
     * @param marketId The Cork Pool id
     * @param shares The amount of CST shares to lock (must be 0 if compensation is non-zero)
     * @param compensation The amount of reference token compensation to lock
     * (must be 0 if shares is non-zero)
     * @param receiver The address that will receive the collateral assets
     * @param minAssetsOut The minimum amount of collateral assets that must be received
     * @param maxOtherAssetSpent The maximum amount of other asset that can be spent
     * @return assets The amount of collateral assets sent to receiver
     * @return otherAssetSpent The amount of other asset spent in the operation
     * @return fee The fee amount charged
     */

    /**
     * @notice Exercise function that locks up CST shares or compensation in reference token
     * and sends collateral assets to receiver
     * @param params The parameters for the exercise operation
     * @dev params.shares The amount of CST shares to lock (must be 0 if compensation is non-zero)
     * @dev params.compensation The amount of reference token compensation to lock
     * (must be 0 if shares is non-zero)
     * @dev params.receiver The address that will receive the collateral assets
     * @dev params.minAssetsOut The minimum amount of collateral assets that must be received
     * @dev params.maxOtherAssetSpent The maximum amount of other asset that can be spent
     * @return assets The amount of collateral assets sent to receiver
     * @return otherAssetSpent The amount of other asset spent in the operation
     * @return fee The fee amount charged
     */
    function exercise(ExerciseParams memory params) external returns (uint256 assets, uint256 otherAssetSpent, uint256 fee);

    /**
     * @notice Preview the exercise operation without executing it
     * @param marketId The Cork Pool id
     * @param shares The amount of CST shares to lock (must be 0 if compensation is non-zero)
     * @param compensation The amount of reference token compensation to lock
     * (must be 0 if shares is non-zero)
     * @return assets The amount of collateral assets that would be sent to receiver
     * @return otherAssetSpent The amount of other asset that would be spent in the operation
     * @return fee The fee amount that would be charged
     */
    function previewExercise(MarketId marketId, uint256 shares, uint256 compensation) external view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee);

    /**
     * @notice unwindExercise - unlocks CST shares and reference token compensation by depositing collateral assets
     * @param params The parameters for the unwind exercise operation
     * params.poolId The Cork Pool id
     * params.shares The amount of CST shares to unlock
     * params.receiver The address that will receive the unlocked tokens
     * params.minCompensationOut The minimum amount of reference token compensation that must be unlocked
     * params.maxAssetsIn The maximum amount of collateral assets that can be deposited
     * @return assetIn The amount of collateral assets deposited
     * @return compensationOut The amount of reference token compensation unlocked
     * @return fee The fee amount sent to cork protocol
     */
    function unwindExercise(UnwindExerciseParams calldata params) external returns (uint256 assetIn, uint256 compensationOut, uint256 fee);

    /**
     * @notice Previews the outcome of unwinding an exercise operation
     * @param poolId The Cork Pool id
     * @param shares The amount of CST tokens to mint
     * @return assetIn The amount of collateral asset that would be required
     * @return compensationOut The amount of reference asset compensation that would be received
     */
    function previewUnwindExercise(MarketId poolId, uint256 shares) external view returns (uint256 assetIn, uint256 compensationOut);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred through `unwindExercise` and not cause a revert.
     * @dev MUST NOT revert.
     * @dev This assumes that the user has infinite collateral assets, i.e. MUST NOT rely on `balanceOf` of collateral asset.
     * @param poolId The Cork Pool id
     * @param receiver The address that would receive the unlocked tokens (not used for calculation)
     * @return shares The maximum amount of CST shares that could be unlocked through unwindExercise
     */
    function maxUnwindExercise(MarketId poolId, address receiver) external view returns (uint256 shares);

    /**
     * @notice Returns the maximum amount of reference assets that would be unlocked through `unwindExercise` and not cause a revert.
     * @dev MUST NOT revert.
     * @dev This assumes that the user has infinite collateral assets, i.e. MUST NOT rely on `balanceOf` of collateral asset.
     * @param poolId The Cork Pool id
     * @param receiver The address that would receive the unlocked tokens (not used for calculation)
     * @return maxReferenceAssets The maximum amount of reference assets that would be unlocked through unwindExercise
     */
    function maxUnwindExerciseOther(MarketId poolId, address receiver) external view returns (uint256 maxReferenceAssets);

    /**
     * @notice swap Collateral Asset + Reference Asset with Principal Token at expiry
     * @param poolId The pair id
     * @param amount The amount of Principal Token to swap
     * @param owner The address that owns the Principal Token
     * @param receiver The address that will receive the assets
     * @return accruedReferenceAsset Amount of reference asset received
     * @return accruedCollateralAsset Amount of collateral asset received
     */
    function redeem(MarketId poolId, uint256 amount, address owner, address receiver) external returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset);

    /**
     * @notice  returns amount of collateralAsset user will get when swap Collateral Asset with Principal Token+Swap Token
     * @param poolId The Cork Pool id
     * @param collateralAssetAmountOut amount of collateral to get out
     * @param owner The address that owns the Principal Token and Swap Token to be burned
     * @param receiver The address that will receive the collateral assets
     * @return cptAndCstSharesIn amount of swap token and principal token user spends
     */
    function unwindDeposit(MarketId poolId, uint256 collateralAssetAmountOut, address owner, address receiver) external returns (uint256 cptAndCstSharesIn);

    /**
     * @notice returns amount of value locked in Cork Pool
     * @param poolId The Cork Pool id
     * @return collateralAssets The amount of collateral assets locked in the pool
     * @return referenceAssets The amount of reference assets locked in the pool
     */
    function valueLocked(MarketId poolId) external view returns (uint256 collateralAssets, uint256 referenceAssets);

    /**
     * @notice returns base redemption fees (1e18 = 1%)
     * @param poolId The Cork Pool id
     * @return fees the base redemption fee
     */
    function baseRedemptionFee(MarketId poolId) external view returns (uint256 fees);

    /**
     * @notice Returns the pause status for all operations in a market
     * @param marketId The Cork Pool id
     * @return pausedStates The pause status for all operations in a market
     * pausedStates.depositPaused True if deposits are paused
     * pausedStates.unwindSwapPaused True if unwind swaps are paused
     * pausedStates.swapPaused True if swaps are paused
     * pausedStates.withdrawalPaused True if withdrawals are paused
     * pausedStates.unwindDepositAndMintPaused True if unwind deposits and mints are paused
     */
    function pausedStates(MarketId marketId) external view returns (PausedStates memory);

    /**
     * @notice Update operation status for different market operation types
     * @param marketId The Cork Pool id
     * @param operationType The type of operation to update : deposit/unwindSwap/swap/withdrawal/premature-withdrawal
     * @param isPaused Whether to pause or unpause the operation
     */
    function setPausedState(MarketId marketId, OperationType operationType, bool isPaused) external;

    /**
     * @notice Previews the amount of CPT and CST tokens that would be minted for a deposit
     * @param poolId The Cork Pool id
     * @param collateralAssetIn The amount of collateral asset to deposit
     * @return received The amount of CPT and CST tokens that would be minted
     */
    function previewDeposit(MarketId poolId, uint256 collateralAssetIn) external view returns (uint256 received);

    /**
     * @notice Previews the amount of CST shares and reference token compensation that would be required for a swap
     * @param poolId The Cork Pool id
     * @param assets The exact amount of collateral assets that would be received
     * @return sharesOut The amount of CST shares that would be locked from msg.sender
     * @return compensation The amount of reference token that would be locked from msg.sender
     */
    function previewSwap(MarketId poolId, uint256 assets) external view returns (uint256 sharesOut, uint256 compensation);

    /**
     * @notice Previews the amounts of assets that would be received when redeeming CPT tokens
     * @param poolId The Cork Pool id
     * @param amount The amount of CPT tokens to redeem
     * @return accruedReferenceAsset The amount of reference asset that would be received
     * @return accruedCollateralAsset The amount of collateral asset that would be received
     */
    function previewRedeem(MarketId poolId, uint256 amount) external view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset);

    /**
     * @notice Previews the amount of CPT and CST tokens needed to unwind deposit for specific collateral amount
     * @param poolId The Cork Pool id
     * @param collateralAssetAmountOut The desired amount of collateral asset to receive
     * @return cptAndCstSharesIn The amount of CPT and CST tokens that would need to be burned
     */
    function previewUnwindDeposit(MarketId poolId, uint256 collateralAssetAmountOut) external view returns (uint256 cptAndCstSharesIn);

    /**
     * @notice Previews the outcome of unwinding a swap operation
     * @param poolId The Cork Pool id
     * @param amount The amount of CPT tokens to unwind
     * @return returnParams The return parameters for the unwind swap
     * returnParams.receivedReferenceAsset The amount of reference asset that would be received
     * returnParams.receivedSwapToken The amount of CST tokens that would be received
     * returnParams.feePercentage The fee percentage that would be applied
     * returnParams.fee The fee amount that would be charged
     * returnParams.swapRate The swap rate that would be used during the unwind swap
     */
    function previewUnwindSwap(MarketId poolId, uint256 amount) external view returns (IUnwindSwap.UnwindSwapReturnParams memory returnParams);

    /**
     * @notice Mints a specific amount of CPT and CST tokens by depositing collateral
     * @param poolId The market identifier
     * @param swapAndPricipalTokenAmountOut The desired amount of CPT and CST tokens to mint
     * @param receiver The address that will receive the CPT and CST tokens
     * @return collateralAssetAmountIn The amount of collateral asset required
     */
    function mint(MarketId poolId, uint256 swapAndPricipalTokenAmountOut, address receiver) external returns (uint256 collateralAssetAmountIn);

    /**
     * @notice Previews the amount of collateral needed to mint specific amounts of CPT and CST tokens
     * @param poolId The Cork Pool id
     * @param swapAndPricipalTokenAmountOut The desired amount of CPT and CST tokens to mint
     * @return collateralAssetAmountIn The amount of collateral asset that would be required
     */
    function previewMint(MarketId poolId, uint256 swapAndPricipalTokenAmountOut) external view returns (uint256 collateralAssetAmountIn);

    /**
     * @notice returns amount of collateralAsset user will get when swap Collateral Asset with Principal Token+Swap Token
     * @param poolId The Cork Pool id
     * @param cptAndCstSharesIn the amount of swap token and principal token to unwind
     * @param owner The address that owns the CPT and CST tokens to be burned
     * @param receiver The address that will receive the collateral assets
     * @return collateralAssetOut amount of Collateral Asset user received
     */
    function unwindMint(MarketId poolId, uint256 cptAndCstSharesIn, address owner, address receiver) external returns (uint256 collateralAssetOut);

    /**
     * @notice Previews the amount of collateral that would be received when unwinding mint
     * @param poolId The Cork Pool id
     * @param cptAndCstSharesIn The amount of CPT and CST tokens to burn
     * @return collateralAssetOut The amount of collateral asset that would be received
     */
    function previewUnwindMint(MarketId poolId, uint256 cptAndCstSharesIn) external view returns (uint256 collateralAssetOut);

    /**
     * @notice Returns the maximum amount of CPT and CST tokens that can be minted
     * @param poolId The Cork Pool id
     * @param owner The address of the owner
     * @return amount The maximum amount of CPT and CST tokens that can be minted
     */
    function maxMint(MarketId poolId, address owner) external view returns (uint256 amount);

    /**
     * @notice Returns the maximum amount of collateral asset that can be deposited
     * @param poolId The Cork Pool id
     * @param owner The address of the owner
     * @return amount The maximum amount of collateral asset that can be deposited
     */
    function maxDeposit(MarketId poolId, address owner) external view returns (uint256 amount);

    /**
     * @notice Gets the maximum amount of collateral asset that can be received by unwinding deposit
     * @param poolId The Cork Pool id
     * @param owner The address to check balances for
     * @return collateralAssetAmountOut The maximum amount of collateral asset that can be received
     */
    function maxUnwindDeposit(MarketId poolId, address owner) external view returns (uint256 collateralAssetAmountOut);

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be burned in unwind mint
     * @param poolId The Cork Pool id
     * @param owner The address to check balances for
     * @return cptAndCstSharesIn The maximum amount of tokens that can be burned
     */
    function maxUnwindMint(MarketId poolId, address owner) external view returns (uint256 cptAndCstSharesIn);

    /// @notice This function burns `sharesIn` (CPT) from `owner` and send exactly `collateralAssetOut` of collateral token from the vault to `receiver`. Also sends `referenceAssetOut` of reference token from the vault to `receiver`. See https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.4/contracts/token/ERC20/extensions/ERC4626.sol#L197
    /// @notice **EITHER** collateralAssetOut or referenceAssetOut **MUST BE** non-zero.
    /// @notice Alternative: This function burns `sharesIn` (CPT) from `owner` and send exactly `referenceAssetOut` of reference token from the vault to `receiver`. Also sends `collateralAssetOut` of collateral token from the vault to `receiver`.
    /// @notice WARNING : this function MAY gives out inexact collateralAssetOut due to rounding errors.
    /// it may give up to 2e(collateralAssetDecimals - 17). for 18 decimals token on both sides(colltaeral & reference), it'll give excess token up to 2 wei
    /**
     * @param params The parameters for the withdraw operation
     * params.poolId The Cork Pool id
     * params.collateralAssetOut The amount of collateral asset to withdraw
     * params.referenceAssetOut The amount of reference asset to withdraw
     * params.owner The address of the owner
     * params.receiver The address of the receiver
     * @return sharesIn The amount of CPT tokens burned
     * @return actualCollateralAssetOut The amount of collateral asset received
     * @return actualReferenceAssetOut The amount of reference asset received
     */
    function withdraw(WithdrawParams calldata params) external returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut);

    /**
     * @notice Previews the amount of CPT tokens needed to withdraw specific amounts of assets
     * @param marketId The Cork Pool id
     * @param collateralAssetOut The desired amount of collateral asset to withdraw
     * @param referenceAssetOut The desired amount of reference asset to withdraw
     * @return sharesIn The amount of CPT tokens that would need to be burned
     * @return actualReferenceAssetOut The actual amount of reference asset that would be withdrawn
     */
    function previewWithdraw(MarketId marketId, uint256 collateralAssetOut, uint256 referenceAssetOut) external view returns (uint256 sharesIn, uint256 actualReferenceAssetOut);

    /**
     * @notice Returns the maximum amount of assets that could be transferred from `owner` through `withdraw`.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return assets The maximum amount of assets that could be withdrawn
     */
    function maxWithdraw(MarketId marketId, address owner) external view returns (uint256 assets);

    /**
     * @notice Returns the maximum amount of reference assets that could be transferred from `owner` through `withdraw`.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return referenceAssets The maximum amount of reference assets that could be withdrawn
     */
    function maxWithdrawOther(MarketId marketId, address owner) external view returns (uint256 referenceAssets);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred from `owner` through `exercise` and not cause a revert.
     * @dev MUST NOT be higher than the actual maximum that would be accepted (should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, including global caps and owner's balance of CST and reference asset.
     * @dev MUST factor in other restrictive conditions, like if swap is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return shares The maximum amount of CST shares that could be used in exercise
     */
    function maxExercise(MarketId marketId, address owner) external view returns (uint256 shares);

    /**
     * @notice Returns the maximum amount of reference assets that could be used as compensation in `exercise` and not cause a revert.
     * @dev MUST NOT be higher than the actual maximum that would be accepted (should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, including global caps and owner's balance of reference asset.
     * @dev MUST factor in other restrictive conditions, like if swap is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return maxReferenceAssets The maximum amount of reference assets that could be used as compensation in exercise
     */
    function maxExerciseOther(MarketId marketId, address owner) external view returns (uint256 maxReferenceAssets);

    /**
     * @notice Swap function that locks up shares of Cork Swap Token and compensation of reference token
     * from msg.sender and sends exactly assets of collateral token from the vault to receiver
     * @param marketId The Cork Pool id
     * @param assets The exact amount of collateral assets to send to receiver
     * @param receiver The address that will receive the collateral assets
     * @return shares The amount of CST shares locked from msg.sender
     * @return compensation The amount of reference token locked from msg.sender
     * @return fee The fee amount sent to cork protocol
     */
    function swap(MarketId marketId, uint256 assets, address receiver) external returns (uint256 shares, uint256 compensation, uint256 fee);

    /**
     * @notice Returns the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert.
     * @dev MUST return the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, for example, global caps and owner's balance of CPT. MUST factor in other restrictive conditions, like if redemption is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param poolId The Cork Pool id
     * @param owner The address of the owner
     * @return shares The maximum amount of CPT shares that could be redeemed
     */
    function maxRedeem(MarketId poolId, address owner) external view returns (uint256 shares);

    /**
     * @notice Returns the maximum amount of collateral assets that could be transferred from `owner` through `swap` and not cause a revert.
     * @dev MUST return the maximum amount of collateral assets that could be transferred from `owner` through `swap` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, for example, global caps and owner's balance of CST and reference asset. MUST factor in other restrictive conditions, like if swaps are entirely disabled (even temporarily due to pause), it MUST return 0.
     * @dev Uses optimal balance logic: calculates maximum CST shares usable based on reference asset capacity, then takes minimum of that and actual CST balance to find effective shares that can be swapped.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return assets The maximum amount of collateral assets that could be transferred through swap
     */
    function maxSwap(MarketId marketId, address owner) external view returns (uint256 assets);
}
