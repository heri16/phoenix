// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IPool Interface
 * @author Cork Team
 * @notice IPool interface for CorkPool contract
 */
interface IPool is IUnwindSwap, Initialize {
    enum OperationType {
        DEPOSIT,
        UNWIND_SWAP,
        SWAP,
        WITHDRAWAL,
        PREMATURE_WITHDRAWAL
    }

    /// @notice Breaks compatibility with ERC4626. Emitted by Pool Manager address
    /// @param marketId The Cork Pool id
    /// @param sender msg.sender
    /// @param owner receiver of shares
    /// @param assets collateral amount added
    /// @param shares amount of CPT or CST minted
    event Deposit(MarketId indexed marketId, address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Emitted when a user swaps a Swap Token for a given Cork Pool
    /// @param id The Cork Pool id
    /// @param swaper The address of the swaper
    /// @param paUsed The amount of the Reference Asset swaped
    /// @param swapTokenUsed The amount of Swap Token swaped
    /// @param raReceived The amount of  asset received
    /// @param dsExchangeRate The exchange rate of Swap Token at the time of swap
    /// @param feePercentage The fee percentage charged for redemption
    /// @param fee The fee charged for redemption
    event Swap(MarketId indexed id, address indexed swaper, uint256 paUsed, uint256 swapTokenUsed, uint256 raReceived, uint256 dsExchangeRate, uint256 feePercentage, uint256 fee);

    /// @notice Breaks compatibility with ERC4626. Emitted by Pool Manager address
    /// @notice Purpose: Provides comprehensive withdrawal tracking with market context for protocol-level monitoring and analytics
    /// @notice Indexers must be able to easily distinguish withdrawals from swaps
    /// @param marketId The Cork Pool id
    /// @param sender msg.sender with allowance
    /// @param owner owner of shares
    /// @param assets0 collateral amount removed from pool
    /// @param assets1 zero
    /// @param shares0 amount of CPT burned (non-zero)
    /// @param shares1 amount of CST burned (non-zero)
    event WithdrawExtended(MarketId indexed marketId, address indexed sender, address indexed owner, uint256 assets0, uint256 assets1, uint256 shares0, uint256 shares1);

    /// @notice Emmitted when baseRedemptionFeePercentage is updated
    /// @param id the Cork Pool id
    /// @param baseRedemptionFeePercentage the new baseRedemptionFeePercentage
    event BaseRedemptionFeePercentageUpdated(MarketId indexed id, uint256 indexed baseRedemptionFeePercentage);

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

    /**
     * @notice Deposits collateral asset and returns the amount of Principal Token and Swap Token tokens after deposit
     * @param id the id of Cork Pool
     * @param collateralAmountIn the amount of collateral to deposit
     * @param receiver the address that will receive the Principal Token and Swap Token
     * @return received the amount of Principal Token/Swap Token received
     */
    function deposit(MarketId id, uint256 collateralAmountIn, address receiver) external returns (uint256 received);

    /**
     * This determines the rate of how much the user will receive for the amount of asset they want to deposit.
     * for example, if the rate is 1.5, then the user will need to deposit 1.5 token to get 1 Principal Token and Swap Token.
     * @param id the id of the Cork Pool
     * @return rates the exchange rate of Principal Token and Swap Token
     */
    function exchangeRate(MarketId id) external view returns (uint256 rates);

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
    function exercise(MarketId marketId, uint256 shares, uint256 compensation, address receiver, uint256 minAssetsOut, uint256 maxOtherAssetSpent) external returns (uint256 assets, uint256 otherAssetSpent, uint256 fee);

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
     * @param poolId The Cork Pool id
     * @param shares The amount of CST shares to unlock
     * @param receiver The address that will receive the unlocked tokens
     * @param minCompensationOut The minimum amount of reference token compensation that must be unlocked
     * @param maxAssetIn The maximum amount of collateral assets that can be deposited
     * @return assetIn The amount of collateral assets deposited
     * @return compensationOut The amount of reference token compensation unlocked
     */
    function unwindExercise(MarketId poolId, uint256 shares, address receiver, uint256 minCompensationOut, uint256 maxAssetIn) external returns (uint256 assetIn, uint256 compensationOut);

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
     * @notice swap Collateral Asset + Reference Asset with Principal Token at expiry
     * @param id The pair id
     * @param amount The amount of Principal Token to swap
     * @param owner The address that owns the Principal Token
     * @param receiver The address that will receive the assets
     * @return accruedReferenceAsset Amount of reference asset received
     * @return accruedCollateralAsset Amount of collateral asset received
     */
    function redeem(MarketId id, uint256 amount, address owner, address receiver) external returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset);

    /**
     * @notice  returns amount of collateralAsset user will get when swap Collateral Asset with Principal Token+Swap Token
     * @param id The Cork Pool id
     * @param collateralAmountOut amount of collateral to get out
     * @return swapTokenAndPrincipalTokenIn amount of swap token and principal token user spends
     */
    function unwindDeposit(MarketId id, uint256 collateralAmountOut) external returns (uint256 swapTokenAndPrincipalTokenIn);

    /**
     * @notice returns amount of value locked in Cork Pool
     * @param id The Cork Pool id
     * @param collateralAsset true if you want to get value locked in Collateral Asset, false if you want to get value locked in Reference Asset
     * @return lockedAmount the amount of value locked in the Cork Pool
     */
    function valueLocked(MarketId id, bool collateralAsset) external view returns (uint256 lockedAmount);

    /**
     * @notice returns base redemption fees (1e18 = 1%)
     * @param id The Cork Pool id
     * @return fees the base redemption fee
     */
    function baseRedemptionFee(MarketId id) external view returns (uint256 fees);

    /**
     * @notice Returns the pause status for all operations in a market
     * @param marketId The Cork Pool id
     * @return depositPaused True if deposits are paused
     * @return unwindSwapPaused True if unwind swaps are paused
     * @return swapPaused True if swaps are paused
     * @return withdrawalPaused True if withdrawals are paused
     * @return unwindDepositAndMintPaused True if unwind deposits and mints are paused
     */
    function pausedStates(MarketId marketId) external view returns (bool depositPaused, bool unwindSwapPaused, bool swapPaused, bool withdrawalPaused, bool unwindDepositAndMintPaused);

    /**
     * @notice Update operation status for different market operation types
     * @param marketId The Cork Pool id
     * @param operationType The type of operation to update : deposit/unwindSwap/swap/withdrawal/premature-withdrawal
     * @param isPaused Whether to pause or unpause the operation
     */
    function setPausedState(MarketId marketId, OperationType operationType, bool isPaused) external;

    /**
     * @notice Previews the amount of CPT and CST tokens that would be minted for a deposit
     * @param id The Cork Pool id
     * @param collateralAssetIn The amount of collateral asset to deposit
     * @return received The amount of CPT and CST tokens that would be minted
     */
    function previewDeposit(MarketId id, uint256 collateralAssetIn) external view returns (uint256 received);

    /**
     * @notice Previews the amount of CST tokens that would be received for a swap
     * @param id The Cork Pool id
     * @param amount The amount of collateral asset to swap
     * @return received The amount of CST tokens that would be received
     * @return _exchangeRate The exchange rate used for the swap
     * @return fee The fee that would be charged
     * @return cstUsed The amount of CST tokens used in the calculation
     */
    function previewSwap(MarketId id, uint256 amount) external view returns (uint256 received, uint256 _exchangeRate, uint256 fee, uint256 cstUsed);

    /**
     * @notice Previews the amounts of assets that would be received when redeeming CPT tokens
     * @param id The Cork Pool id
     * @param amount The amount of CPT tokens to redeem
     * @return accruedReferenceAsset The amount of reference asset that would be received
     * @return accruedCollateralAsset The amount of collateral asset that would be received
     */
    function previewRedeem(MarketId id, uint256 amount) external view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset);

    /**
     * @notice Previews the amount of CPT and CST tokens needed to unwind deposit for specific collateral amount
     * @param id The Cork Pool id
     * @param collateralAssetAmountOut The desired amount of collateral asset to receive
     * @return swapTokenAndPrincipalTokenIn The amount of CPT and CST tokens that would need to be burned
     */
    function previewUnwindDeposit(MarketId id, uint256 collateralAssetAmountOut) external view returns (uint256 swapTokenAndPrincipalTokenIn);

    /**
     * @notice Previews the outcome of unwinding a swap operation
     * @param id The Cork Pool id
     * @param amount The amount of CPT tokens to unwind
     * @return receivedRef The amount of reference asset that would be received
     * @return receivedCst The amount of CST tokens that would be received
     * @return feePercentage The fee percentage that would be applied
     * @return fee The fee amount that would be charged
     * @return exchangeRates The exchange rate that would be used
     */
    function previewUnwindSwap(MarketId id, uint256 amount) external view returns (uint256 receivedRef, uint256 receivedCst, uint256 feePercentage, uint256 fee, uint256 exchangeRates);

    /**
     * @notice Mints a specific amount of CPT and CST tokens by depositing collateral
     * @param id The market identifier
     * @param swapAndPricipalTokenAmountOut The desired amount of CPT and CST tokens to mint
     * @param receiver The address that will receive the CPT and CST tokens
     * @return collateralAmountIn The amount of collateral asset required
     * @return exchangeRate The exchange rate used
     */
    function mint(MarketId id, uint256 swapAndPricipalTokenAmountOut, address receiver) external returns (uint256 collateralAmountIn, uint256 exchangeRate);

    /**
     * @notice Previews the amount of collateral needed to mint specific amounts of CPT and CST tokens
     * @param id The Cork Pool id
     * @param swapAndPricipalTokenAmountOut The desired amount of CPT and CST tokens to mint
     * @return collateralAmountIn The amount of collateral asset that would be required
     * @return exchangeRate The current exchange rate
     */
    function previewMint(MarketId id, uint256 swapAndPricipalTokenAmountOut) external view returns (uint256 collateralAmountIn, uint256 exchangeRate);

    /**
     * @notice returns amount of collateralAsset user will get when swap Collateral Asset with Principal Token+Swap Token
     * @param id The Cork Pool id
     * @param cptAndCstAmountIn the amount of swap token and principal token to unwind
     * @return collateralAsset amount of Collateral Asset user received
     */
    function unwindMint(MarketId id, uint256 cptAndCstAmountIn) external returns (uint256 collateralAsset);

    /**
     * @notice Previews the amount of collateral that would be received when unwinding mint
     * @param id The Cork Pool id
     * @param cptAndCstAmountIn The amount of CPT and CST tokens to burn
     * @return collateralAsset The amount of collateral asset that would be received
     */
    function previewUnwindMint(MarketId id, uint256 cptAndCstAmountIn) external view returns (uint256 collateralAsset);

    /**
     * @notice Returns the maximum amount of CPT and CST tokens that can be minted
     * @param id The Cork Pool id
     * @param owner The address of the owner
     * @return amount The maximum amount of CPT and CST tokens that can be minted
     */
    function maxMint(MarketId id, address owner) external view returns (uint256 amount);

    /**
     * @notice Returns the maximum amount of collateral asset that can be deposited
     * @param id The Cork Pool id
     * @param owner The address of the owner
     * @return amount The maximum amount of collateral asset that can be deposited
     */
    function maxDeposit(MarketId id, address owner) external view returns (uint256 amount);

    /**
     * @notice Gets the maximum amount of collateral asset that can be received by unwinding deposit
     * @param id The Cork Pool id
     * @param owner The address to check balances for
     * @return collateralAssetAmountOut The maximum amount of collateral asset that can be received
     */
    function maxUnwindDeposit(MarketId id, address owner) external view returns (uint256 collateralAssetAmountOut);

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be burned in unwind mint
     * @param id The Cork Pool id
     * @param owner The address to check balances for
     * @return swapTokenAndPrincipalTokenIn The maximum amount of tokens that can be burned
     */
    function maxUnwindMint(MarketId id, address owner) external view returns (uint256 swapTokenAndPrincipalTokenIn);

    /// @notice This function burns `sharesIn` (CPT) from `owner` and send exactly `collateralAssetOut` of collateral token from the vault to `receiver`. Also sends `referenceAssetOut` of reference token from the vault to `receiver`. See https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.4/contracts/token/ERC20/extensions/ERC4626.sol#L197
    /// @notice **EITHER** collateralAssetOut or referenceAssetOut **MUST BE** non-zero.
    /// @notice Alternative: This function burns `sharesIn` (CPT) from `owner` and send exactly `referenceAssetOut` of reference token from the vault to `receiver`. Also sends `collateralAssetOut` of collateral token from the vault to `receiver`.
    /**
     * @param marketId The Cork Pool id
     * @param collateralAssetOut The amount of collateral asset to withdraw
     * @param referenceAssetOut The amount of reference asset to withdraw
     * @param owner The address of the owner
     * @param receiver The address of the receiver
     * @return sharesIn The amount of CPT tokens burned
     * @return actualReferenceAssetOut The amount of reference asset received
     */
    function withdraw(MarketId marketId, uint256 collateralAssetOut, uint256 referenceAssetOut, address owner, address receiver) external returns (uint256 sharesIn, uint256 actualReferenceAssetOut);

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
     * @notice Returns the maximum amount of CST shares that could be transferred from `owner` through `exercise` and not cause a revert.
     * @dev MUST NOT be higher than the actual maximum that would be accepted (should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, including global caps and owner's balance of CST and reference asset.
     * @dev MUST factor in other restrictive conditions, like if exchange is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param marketId The Cork Pool id
     * @param owner The address of the owner
     * @return shares The maximum amount of CST shares that could be used in exercise
     */
    function maxExercise(MarketId marketId, address owner) external view returns (uint256 shares);

    /**
     * @notice Swap function that locks up shares of Cork Swap Token and compensation of reference token
     * from msg.sender and sends exactly assets of collateral token from the vault to receiver
     * @param marketId The Cork Pool id
     * @param assets The exact amount of collateral assets to send to receiver
     * @param receiver The address that will receive the collateral assets
     * @return shares The amount of CST shares locked from msg.sender
     * @return compensation The amount of reference token locked from msg.sender
     */
    function swap(MarketId marketId, uint256 assets, address receiver) external returns (uint256 shares, uint256 compensation);

    /**
     * @notice Returns the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert.
     * @dev MUST return the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, for example, global caps and owner's balance of CPT. MUST factor in other restrictive conditions, like if redemption is entirely disabled (even temporarily) it MUST return 0.
     * @dev MUST NOT revert.
     * @param id The Cork Pool id
     * @param owner The address of the owner
     * @return shares The maximum amount of CPT shares that could be redeemed
     */
    function maxRedeem(MarketId id, address owner) external view returns (uint256 shares);

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
