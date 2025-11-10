// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IPoolManager Interface
 * @author Cork Team
 * @notice IPoolManager interface for CorkPoolManager contract
 */
interface IPoolManager is IUnwindSwap, Initialize {
    struct ExerciseParams {
        MarketId poolId; // The Cork Pool id
        address receiver; // The address that will receive the collateral assets
        uint256 collateralAssetsOut; // The amount of collateral assets to receive
        uint256 cstSharesIn; // The amount of CST shares to lock (must be 0 if compensation is non-zero)
        uint256 referenceAssetsIn; // The amount of reference token compensation to lock (must be 0 if shares is non-zero)
        uint256 fee;
        uint256 swapTokenProvided;
        uint256 referenceAssetProvided;
    }

    struct UnwindExerciseParams {
        MarketId poolId;
        address receiver;
        uint256 cstSharesOut;
        uint256 referenceAssetsOut;
        uint256 collateralAssetsIn;
        uint256 fee;
    }

    struct WithdrawParams {
        MarketId poolId; // The Cork Pool id
        uint256 collateralAssetsOut; // The amount of collateral asset to withdraw
        uint256 referenceAssetsOut; // The amount of reference asset to withdraw
        address owner; // The address that owns the Principal Token to be burned
        address receiver; // The address that will receive the collateral assets and reference assets
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

    /// @notice Emmitted when swapFeePercentage is updated
    /// @param poolId the Cork Pool id
    /// @param swapFeePercentage the new swapFeePercentage
    event SwapFeePercentageUpdated(MarketId indexed poolId, uint256 indexed swapFeePercentage);

    /**
     * @notice Emitted when one or more market actions are paused or unpaused.
     * @dev Each bit in `pausedAction` represents the pause state of a specific market action.
     * @dev  The mapping of bit positions to actions is as follows:
     * @dev  - Bit 0 → Deposit operations (`isDepositPaused`)
     * @dev  - Bit 1 → Swap operations (`isSwapPaused`)
     * @dev  - Bit 2 → Withdrawal operations (`isWithdrawalPaused`)
     * @dev  - Bit 3 → Unwind deposit operations (`isUnwindDepositPaused`)
     * @dev  - Bit 4 → Unwind swap operations (`isUnwindSwapPaused`)
     * @param marketId The unique identifier of the market.
     * @param pausedAction A bitmap representing the pause state of each market action.
     *        Use `1` to indicate *paused* and `0` to indicate *unpaused* for each corresponding bit.
     */
    event MarketActionPausedUpdate(MarketId indexed marketId, uint16 pausedAction);

    /// @notice thrown when mint amount is invalid, e.g trying to mint 100 CPT/100 CST but only capable of minting 50 CPT/50 CST
    error InvalidMintAmount(uint256 expected, uint256 actual);

    /// @notice thrown when unwind deposit amount is invalid, e.g trying to unwind deposit 100 CPT/100 CST but only capable of unwinding 50 CPT/50 CST
    error InvalidUnwindDepositAmount(uint256 expected, uint256 actual);

    /// @notice Emitted when a treasury is set
    /// @param treasury Address of treasury contract/address
    event TreasurySet(address treasury);

    /// @notice Emitted when a shares factory is updated
    /// @param sharesFactory Address of shares factory contract
    event SharesFactorySet(address sharesFactory);

    /**
     * @notice Deposits collateral asset and returns the amount of Principal Token and Swap Token tokens after deposit
     * @param poolId the id of Cork Pool
     * @param collateralAssetsIn the amount of collateral to deposit
     * @param receiver the address that will receive the Principal Token and Swap Token
     * @return cptAndCstSharesOut the amount of Principal Token & Swap Token received
     */
    function deposit(MarketId poolId, uint256 collateralAssetsIn, address receiver) external returns (uint256 cptAndCstSharesOut);

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
     * @param poolId The Cork Pool id
     * @param cstSharesIn The amount of CST shares to lock (must be 0 if referenceAssetsIn is non-zero)
     * @param receiver The address that will receive the collateral assets
     * @return collateralAssetsOut The amount of collateral assets sent to receiver
     * @return referenceAssetsIn The amount of reference asset spent in the operation
     * @return fee The fee amount charged
     */
    function exercise(MarketId poolId, uint256 cstSharesIn, address receiver) external returns (uint256 collateralAssetsOut, uint256 referenceAssetsIn, uint256 fee);

    /**
     * @notice Exercise function that locks up CST shares or compensation in reference token
     * and sends collateral assets to receiver
     * @param poolId The Cork Pool id
     * @param referenceAssetsIn The amount of reference token compensation to lock
     * @param receiver The address that will receive the collateral assets
     * @return collateralAssetsOut The amount of collateral assets sent to receiver
     * @return cstSharesIn The amount of CST asset spent in the operation
     * @return fee The fee amount charged
     */
    function exerciseOther(MarketId poolId, uint256 referenceAssetsIn, address receiver) external returns (uint256 collateralAssetsOut, uint256 cstSharesIn, uint256 fee);

    /**
     * @notice Preview the exercise operation without executing it
     * @param marketId The Cork Pool id
     * @param cstSharesIn The amount of CST shares to lock (must be non-zero)
     * @return collateralAssetsOut The amount of collateral assets that would be sent to receiver
     * @return referenceAssetsIn The amount of reference asset that would be spent in the operation
     * @return fee The fee amount that would be charged
     */
    function previewExercise(MarketId marketId, uint256 cstSharesIn) external view returns (uint256 collateralAssetsOut, uint256 referenceAssetsIn, uint256 fee);

    /**
     * @notice Preview the exercise operation without executing it
     * @param marketId The Cork Pool id
     * @param referenceAssetsIn The amount of reference token compensation to lock (must be non-zero)
     * @return collateralAssetsOut The amount of collateral assets that would be sent to receiver
     * @return cstSharesIn The amount of CST asset that would be spent in the operation
     * @return fee The fee amount that would be charged
     */
    function previewExerciseOther(MarketId marketId, uint256 referenceAssetsIn) external view returns (uint256 collateralAssetsOut, uint256 cstSharesIn, uint256 fee);

    /**
     * @notice unwindExercise - unlocks CST shares and reference token compensation by depositing collateral assets
     * @param poolId The Cork Pool id
     * @param cstSharesOut The amount of CST shares to unlock (must be non-zero)
     * @param receiver The address that will receive the unlocked tokens
     * @return collateralAssetsIn The amount of collateral assets deposited
     * @return referenceAssetsOut The amount of reference token compensation unlocked
     * @return fee The fee amount sent to cork protocol
     */
    function unwindExercise(MarketId poolId, uint256 cstSharesOut, address receiver) external returns (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee);

    /**
     * @notice unwindExercise - unlocks CST shares and reference token compensation by depositing collateral assets
     * @param poolId The Cork Pool id
     * @param referenceAssetsOut The amount of reference token to unlock (must be non-zero)
     * @param receiver The address that will receive the unlocked tokens
     * @return collateralAssetsIn The amount of collateral assets deposited
     * @return cstSharesOut The amount of CST tokens received
     * @return fee The fee amount sent to cork protocol
     */
    function unwindExerciseOther(MarketId poolId, uint256 referenceAssetsOut, address receiver) external returns (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee);

    /**
     * @notice Previews the outcome of unwinding an exercise operation
     * @param poolId The Cork Pool id
     * @param cstSharesOut The amount of CST tokens to mint
     * @return collateralAssetsIn The amount of collateral asset that would be required
     * @return referenceAssetsOut The amount of reference token compensation that would be received
     * @return fee The fee amount that would be charged
     */
    function previewUnwindExercise(MarketId poolId, uint256 cstSharesOut) external view returns (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee);

    /**
     * @notice Previews the outcome of unwinding an exercise operation
     * @param poolId The Cork Pool id
     * @param referenceAssetsOut The amount of reference token to mint
     * @return collateralAssetsIn The amount of collateral asset that would be required
     * @return cstSharesOut The amount of CST tokens that would be received
     * @return fee The fee amount that would be charged
     */
    function previewUnwindExerciseOther(MarketId poolId, uint256 referenceAssetsOut) external view returns (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred through `unwindExercise` and not cause a revert.
     * @dev MUST NOT revert.
     * @dev This assumes that the user has infinite collateral assets, i.e. MUST NOT rely on `balanceOf` of collateral asset.
     * @dev Address parameter is not used for calculation, but is required to match the interface as well as in future it will allow support for owner parameter
     * @param poolId The Cork Pool id
     * @return maxCstSharesOut The maximum amount of CST shares that could be unlocked through unwindExercise
     */
    function maxUnwindExercise(MarketId poolId, address) external view returns (uint256 maxCstSharesOut);

    /**
     * @notice Returns the maximum amount of reference assets that would be unlocked through `unwindExercise` and not cause a revert.
     * @dev MUST NOT revert.
     * @dev This assumes that the user has infinite collateral assets, i.e. MUST NOT rely on `balanceOf` of collateral asset.
     * @dev Address parameter is not used for calculation, but is required to match the interface as well as in future it will allow support for owner parameter
     * @param poolId The Cork Pool id
     * @return maxReferenceAssetsOut The maximum amount of reference assets that would be unlocked through unwindExercise
     */
    function maxUnwindExerciseOther(MarketId poolId, address) external view returns (uint256 maxReferenceAssetsOut);

    /**
     * @notice swap Collateral Asset + Reference Asset with Principal Token at expiry
     * @param poolId The pair id
     * @param cptSharesIn The amount of Principal Token to swap
     * @param owner The address that owns the Principal Token
     * @param receiver The address that will receive the assets
     * @return referenceAssetsOut Amount of reference asset received
     * @return collateralAssetsOut Amount of collateral asset received
     */
    function redeem(MarketId poolId, uint256 cptSharesIn, address owner, address receiver) external returns (uint256 referenceAssetsOut, uint256 collateralAssetsOut);

    /**
     * @notice  returns amount of collateralAsset user will get when swap Collateral Asset with Principal Token+Swap Token
     * @param poolId The Cork Pool id
     * @param collateralAssetsOut amount of collateral to get out
     * @param owner The address that owns the Principal Token and Swap Token to be burned
     * @param receiver The address that will receive the collateral assets
     * @return cptAndCstSharesIn amount of swap token and principal token user spends
     */
    function unwindDeposit(MarketId poolId, uint256 collateralAssetsOut, address owner, address receiver) external returns (uint256 cptAndCstSharesIn);

    /**
     * @notice returns the tvl amount of both reference and collateral assets in Cork Pool
     * @param poolId The Cork Pool id
     * @return collateralAssets The amount of collateral assets locked in the pool
     * @return referenceAssets The amount of reference assets locked in the pool
     */
    function assets(MarketId poolId) external view returns (uint256 collateralAssets, uint256 referenceAssets);

    /**
     * @notice returns swap fees in 18 decimals precision (1e18 = 1%)
     * @param poolId The Cork Pool id
     * @return fees the base redemption fee
     */
    function swapFee(MarketId poolId) external view returns (uint256 fees);

    /**
     * @notice Updates the pause status of various market operations for a given pool.
     * @dev Each bit in `newPauseBitMap` represents the pause state of a specific operation type.
     * @dev The mapping of bit positions to operations is as follows:
     * @dev - Bit 0 → Deposit operations (`isDepositPaused`)
     * @dev - Bit 1 → Swap operations (`isSwapPaused`)
     * @dev - Bit 2 → Withdrawal operations (`isWithdrawalPaused`)
     * @dev - Bit 3 → Unwind deposit operations (`isUnwindDepositPaused`)
     * @dev - Bit 4 → Unwind swap operations (`isUnwindSwapPaused`)
     * @param marketId The unique identifier of the Cork Pool.
     * @param newPauseBitMap A bitmap representing pause states for each operation type.
     *        Use `1` to indicate paused and `0` to indicate unpaused for each corresponding bit.
     */
    function setPausedBitMap(MarketId marketId, uint16 newPauseBitMap) external;

    /**
     * @notice Returns the pause status for all operations in a market
     * @dev Each bit in `pauseBitMap` represents the pause state of a specific operation type.
     * @dev The mapping of bit positions to operations is as follows:
     * @dev - Bit 0 → Deposit operations (`isDepositPaused`)
     * @dev - Bit 1 → Swap operations (`isSwapPaused`)
     * @dev - Bit 2 → Withdrawal operations (`isWithdrawalPaused`)
     * @dev - Bit 3 → Unwind deposit operations (`isUnwindDepositPaused`)
     * @dev - Bit 4 → Unwind swap operations (`isUnwindSwapPaused`)
     * @param marketId The unique identifier of the Cork Pool.
     */
    function getPausedBitMap(MarketId marketId) external view returns (uint16 pauseBitMap);

    /**
     * @notice Pauses or unpauses the whole protocol
     * @param isAllPaused Whether to pause or unpause the protocol
     */
    function setAllPaused(bool isAllPaused) external;

    /**
     * @notice Update the treasury address(where fees will be sent)
     * @param newTreasury The new treasury address
     * will emit `TreasurySet` event
     */
    function setTreasuryAddress(address newTreasury) external;

    /**
     * @notice Update the shares factory address. Will emit `SharesFactorySet` event
     * @param newSharesFactory The new shares factory address
     */
    function setSharesFactory(address newSharesFactory) external;

    /**
     * @notice Previews the amount of CPT and CST tokens that would be minted for a deposit
     * @param poolId The Cork Pool id
     * @param collateralAssetsIn The amount of collateral asset to deposit
     * @return cptAndCstSharesOut The amount of CPT and CST tokens that would be minted
     */
    function previewDeposit(MarketId poolId, uint256 collateralAssetsIn) external view returns (uint256 cptAndCstSharesOut);

    /**
     * @notice Previews the amount of CST shares and reference token compensation that would be required for a swap
     * @param poolId The Cork Pool id
     * @param collateralAssetsOut The exact amount of collateral assets that would be received
     * @return cstSharesIn The amount of CST shares that would be locked from msg.sender
     * @return referenceAssetsIn The amount of reference token that would be locked from msg.sender
     * @return fee The fee amount that would be charged
     */
    function previewSwap(MarketId poolId, uint256 collateralAssetsOut) external view returns (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee);

    /**
     * @notice Previews the amounts of assets that would be received when redeeming CPT tokens
     * @param poolId The Cork Pool id
     * @param cptSharesIn The amount of CPT tokens to redeem
     * @return referenceAssetsOut The amount of reference asset that would be received
     * @return collateralAssetsOut The amount of collateral asset that would be received
     */
    function previewRedeem(MarketId poolId, uint256 cptSharesIn) external view returns (uint256 referenceAssetsOut, uint256 collateralAssetsOut);

    /**
     * @notice Previews the amount of CPT and CST tokens needed to unwind deposit for specific collateral amount
     * @param poolId The Cork Pool id
     * @param collateralAssetsOut The desired amount of collateral asset to receive
     * @return cptAndCstSharesIn The amount of CPT and CST tokens that would need to be burned
     */
    function previewUnwindDeposit(MarketId poolId, uint256 collateralAssetsOut) external view returns (uint256 cptAndCstSharesIn);

    /**
     * @notice Previews the outcome of unwinding a swap operation
     * @param poolId The Cork Pool id
     * @param collateralAssetsIn The amount of CPT tokens to unwind
     * @return cstSharesOut The amount of CST tokens that would be received
     * @return referenceAssetsOut The amount of reference asset that would be received
     * @return fee The fee amount that would be charged
     */
    function previewUnwindSwap(MarketId poolId, uint256 collateralAssetsIn) external view returns (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee);

    /**
     * @notice Mints a specific amount of CPT and CST tokens by depositing collateral
     * @param poolId The market identifier
     * @param cptAndCstSharesOut The desired amount of CPT and CST tokens to mint
     * @param receiver The address that will receive the CPT and CST tokens
     * @return collateralAssetsIn The amount of collateral asset spent
     */
    function mint(MarketId poolId, uint256 cptAndCstSharesOut, address receiver) external returns (uint256 collateralAssetsIn);

    /**
     * @notice Previews the amount of collateral needed to mint specific amounts of CPT and CST tokens
     * @param poolId The Cork Pool id
     * @param cptAndCstSharesOut The desired amount of CPT and CST tokens to mint
     * @return collateralAssetsIn The amount of collateral asset that would be required
     */
    function previewMint(MarketId poolId, uint256 cptAndCstSharesOut) external view returns (uint256 collateralAssetsIn);

    /**
     * @notice returns amount of collateralAsset user will get when swap Collateral Asset with Principal Token+Swap Token
     * @param poolId The Cork Pool id
     * @param cptAndCstSharesIn the amount of swap token and principal token to unwind
     * @param owner The address that owns the CPT and CST tokens to be burned
     * @param receiver The address that will receive the collateral assets
     * @return collateralAssetsOut amount of Collateral Asset user received
     */
    function unwindMint(MarketId poolId, uint256 cptAndCstSharesIn, address owner, address receiver) external returns (uint256 collateralAssetsOut);

    /**
     * @notice Previews the amount of collateral that would be received when unwinding mint
     * @param poolId The Cork Pool id
     * @param cptAndCstSharesIn The amount of CPT and CST tokens to burn
     * @return collateralAssetsOut The amount of collateral asset that would be received
     */
    function previewUnwindMint(MarketId poolId, uint256 cptAndCstSharesIn) external view returns (uint256 collateralAssetsOut);

    /**
     * @notice Returns the maximum amount of CPT and CST tokens that can be minted
     * @param poolId The Cork Pool id
     * @param owner The address of the owner
     * @return maxCptAndCstSharesOut The maximum amount of CPT and CST tokens that can be minted
     */
    function maxMint(MarketId poolId, address owner) external view returns (uint256 maxCptAndCstSharesOut);

    /**
     * @notice Returns the maximum amount of collateral asset that can be deposited
     * @param poolId The Cork Pool id
     * @param owner The address of the owner
     * @return maxCollateralAssetsIn The maximum amount of collateral asset that can be deposited
     */
    function maxDeposit(MarketId poolId, address owner) external view returns (uint256 maxCollateralAssetsIn);

    /**
     * @notice Gets the maximum amount of collateral asset that can be received by unwinding deposit
     * @param poolId The Cork Pool id
     * @param owner The address to check balances for
     * @return collateralAssetsOut The maximum amount of collateral asset that can be received
     */
    function maxUnwindDeposit(MarketId poolId, address owner) external view returns (uint256 collateralAssetsOut);

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be burned in unwind mint
     * @param poolId The Cork Pool id
     * @param owner The address to check balances for
     * @return maxCptAndCstSharesIn The maximum amount of tokens that can be burned
     */
    function maxUnwindMint(MarketId poolId, address owner) external view returns (uint256 maxCptAndCstSharesIn);

    /// @notice This function burns `sharesIn` (CPT) from `owner` and send exactly `collateralAssetOut` of collateral token from the vault to `receiver`. Also sends `referenceAssetOut` of reference token from the vault to `receiver`. See https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.4/contracts/token/ERC20/extensions/ERC4626.sol#L197
    /// @notice Alternative: This function burns `sharesIn` (CPT) from `owner` and send exactly `referenceAssetOut` of reference token from the vault to `receiver`. Also sends `collateralAssetOut` of collateral token from the vault to `receiver`.
    /// @notice WARNING : this function MAY gives out inexact collateralAssetOut due to rounding errors.
    /// it may give up to 2e(collateralAssetDecimals - 17). for 18 decimals token on both sides(colltaeral & reference), it'll give excess token up to 2 wei
    /**
     * @param poolId The Cork Pool id
     * @param collateralAssetsOut The amount of collateral asset to withdraw
     * @param owner The address of the owner
     * @param receiver The address of the receiver
     * @return cptSharesIn The amount of CPT tokens burned
     * @return actualCollateralAssetsOut The amount of collateral asset received
     * @return actualReferenceAssetsOut The amount of reference asset received
     */
    function withdraw(MarketId poolId, uint256 collateralAssetsOut, address owner, address receiver) external returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut);

    /// @notice This function burns `sharesIn` (CPT) from `owner` and send exactly `collateralAssetOut` of collateral token from the vault to `receiver`. Also sends `referenceAssetOut` of reference token from the vault to `receiver`. See https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.4/contracts/token/ERC20/extensions/ERC4626.sol#L197
    /// @notice Alternative: This function burns `sharesIn` (CPT) from `owner` and send exactly `referenceAssetOut` of reference token from the vault to `receiver`. Also sends `collateralAssetOut` of collateral token from the vault to `receiver`.
    /// @notice WARNING : this function MAY gives out inexact collateralAssetOut due to rounding errors.
    /// it may give up to 2e(collateralAssetDecimals - 17). for 18 decimals token on both sides(colltaeral & reference), it'll give excess token up to 2 wei
    /**
     * @param poolId The Cork Pool id
     * @param referenceAssetsOut The amount of reference asset to withdraw
     * @param owner The address of the owner
     * @param receiver The address of the receiver
     * @return cptSharesIn The amount of CPT tokens burned
     * @return actualCollateralAssetsOut The amount of collateral asset received
     * @return actualReferenceAssetsOut The amount of reference asset received
     */
    function withdrawOther(MarketId poolId, uint256 referenceAssetsOut, address owner, address receiver) external returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut);

    /**
     * @notice Previews the amount of CPT tokens needed to withdraw specific amounts of assets
     * @param marketId The Cork Pool id
     * @param collateralAssetsOut The desired amount of collateral asset to withdraw
     * @return cptSharesIn The amount of CPT tokens that would need to be burned
     * @return actualCollateralAssetsOut The actual amount of collateral asset that would be withdrawn
     * @return actualReferenceAssetsOut The actual amount of reference asset that would be withdrawn
     */
    function previewWithdraw(MarketId marketId, uint256 collateralAssetsOut) external view returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut);

    /**
     * @notice Previews the amount of CPT tokens needed to withdraw specific amounts of assets
     * @param marketId The Cork Pool id
     * @param referenceAssetsOut The desired amount of reference asset to withdraw
     * @return cptSharesIn The amount of CPT tokens that would need to be burned
     * @return actualCollateralAssetsOut The actual amount of collateral asset that would be withdrawn
     * @return actualReferenceAssetsOut The actual amount of reference asset that would be withdrawn
     */
    function previewWithdrawOther(MarketId marketId, uint256 referenceAssetsOut) external view returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut);

    /**
     * @notice Returns the maximum amount of assets that could be transferred from `owner` through `withdraw`.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return maxCollateralAssetsOut The maximum amount of assets that could be withdrawn
     */
    function maxWithdraw(MarketId marketId, address owner) external view returns (uint256 maxCollateralAssetsOut);

    /**
     * @notice Returns the maximum amount of reference assets that could be transferred from `owner` through `withdraw`.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return maxReferenceAssetsOut The maximum amount of reference assets that could be withdrawn
     */
    function maxWithdrawOther(MarketId marketId, address owner) external view returns (uint256 maxReferenceAssetsOut);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred from `owner` through `exercise` and not cause a revert.
     * @dev MUST NOT be higher than the actual maximum that would be accepted (should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, including global caps and owner's balance of CST and reference asset.
     * @dev MUST factor in other restrictive conditions, like if swap is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return maxCstSharesIn The maximum amount of CST shares that could be used in exercise
     */
    function maxExercise(MarketId marketId, address owner) external view returns (uint256 maxCstSharesIn);

    /**
     * @notice Returns the maximum amount of reference assets that could be used as compensation in `exercise` and not cause a revert.
     * @dev MUST NOT be higher than the actual maximum that would be accepted (should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, including global caps and owner's balance of reference asset.
     * @dev MUST factor in other restrictive conditions, like if swap is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return maxReferenceAssetsIn The maximum amount of reference assets that could be used as compensation in exercise
     */
    function maxExerciseOther(MarketId marketId, address owner) external view returns (uint256 maxReferenceAssetsIn);

    /**
     * @notice Swap function that locks up shares of Cork Swap Token and compensation of reference token
     * from msg.sender and sends exactly assets of collateral token from the vault to receiver
     * @param marketId The Cork Pool id
     * @param collateralAssetsOut The exact amount of collateral assets to send to receiver
     * @param receiver The address that will receive the collateral assets
     * @return cstSharesIn The amount of CST shares locked from msg.sender
     * @return referenceAssetsIn The amount of reference token locked from msg.sender
     * @return fee The fee amount sent to cork protocol
     */
    function swap(MarketId marketId, uint256 collateralAssetsOut, address receiver) external returns (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee);

    /**
     * @notice Returns the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert.
     * @dev MUST return the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, for example, global caps and owner's balance of CPT. MUST factor in other restrictive conditions, like if redemption is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param poolId The Cork Pool id
     * @param owner The address of the owner
     * @return maxCptSharesIn The maximum amount of CPT shares that could be redeemed
     */
    function maxRedeem(MarketId poolId, address owner) external view returns (uint256 maxCptSharesIn);

    /**
     * @notice Returns the maximum amount of collateral assets that could be transferred from `owner` through `swap` and not cause a revert.
     * @dev MUST return the maximum amount of collateral assets that could be transferred from `owner` through `swap` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, for example, global caps and owner's balance of CST and reference asset. MUST factor in other restrictive conditions, like if swaps are entirely disabled (even temporarily due to pause), it MUST return 0.
     * @dev Uses optimal balance logic: calculates maximum CST shares usable based on reference asset capacity, then takes minimum of that and actual CST balance to find effective shares that can be swapped.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return maxCollateralAssetsOut The maximum amount of collateral assets that could be transferred through swap
     */
    function maxSwap(MarketId marketId, address owner) external view returns (uint256 maxCollateralAssetsOut);
}
