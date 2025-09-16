// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IPoolShare Interface
 * @author Cork Team
 * @notice Interface for PoolShare contract with ERC4626-compatible events
 */
interface IPoolShare {
    struct ConstructorParams {
        MarketId poolId;
        uint256 expiry;
        string pairName;
        string symbol;
        address poolManager;
    }

    /// @notice Designed for topic0 compatibility with ERC4626. Emitted by CPT address
    /// @param sender msg.sender
    /// @param owner receiver of shares
    /// @param assets collateral amount added
    /// @param shares amount of CPT or CST minted
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Designed for topic0 compatibility with ERC4626. Emitted by CPT address
    /// @notice Purpose: Enables standard ERC4626 tooling and indexers to track withdrawals seamlessly
    /// @param sender msg.sender with allowance
    /// @param receiver receiver of withdrawn collateral assets
    /// @param owner owner of shares
    /// @param assets collateral amount removed
    /// @param shares amount of CPT burned
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    /// @param sender msg.sender with allowance
    /// @param receiver receiver of withdrawn reference assets
    /// @param owner owner of shares
    /// @param asset reference asset address
    /// @param assets reference asset amount removed
    /// @param shares amount of CPT burned
    event WithdrawOther(address indexed sender, address indexed receiver, address indexed owner, address asset, uint256 assets, uint256 shares);

    /// @notice Emitted when a user deposits a reference asset for a given Cork Pool
    /// @param sender The address of the sender
    /// @param owner The address of the owner
    /// @param asset The address of the reference asset
    /// @param assets The amount of reference assets added to the pool
    /// @param shares The amount of CPT shares minted (zero)
    event DepositOther(address indexed sender, address indexed owner, address asset, uint256 assets, uint256 shares);

    /**
     * @notice Returns the pair name of the shares
     * @return The name of the asset pair
     */
    function pairName() external view returns (string memory);

    /**
     * @notice Returns the pool ID for the shares
     * @return The pool ID for the asset contract
     */
    function poolId() external view returns (MarketId);

    /**
     * @notice Returns the cork pool address
     * @return The address of the cork pool contract
     */
    function poolManager() external view returns (IPoolManager);

    /**
     * @notice Returns the factory address
     * @return The address of the factory contract
     */
    function factory() external view returns (address);

    /**
     * @notice Provides Collateral Assets & Reference Assets reserves for the asset contract
     * @return collateralAsset The Collateral Assets reserve amount for asset contract
     * @return referenceAsset The Reference Assets reserve amount for asset contract
     */
    function getReserves() external view returns (uint256 collateralAsset, uint256 referenceAsset);

    /**
     * @notice Emits a deposit event for ERC4626 compatibility
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the deposit
     * @param receiver The address receiving the shares
     * @param assets The amount of assets deposited
     * @param shares The amount of shares minted
     */
    function emitDeposit(address sender, address receiver, uint256 assets, uint256 shares) external;

    /**
     * @notice Emits a withdraw event for ERC4626 compatibility
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the withdrawal
     * @param receiver The address receiving the assets
     * @param owner The address owning the shares
     * @param assets The amount of assets withdrawn
     * @param shares The amount of shares burned
     */
    function emitWithdraw(address sender, address receiver, address owner, uint256 assets, uint256 shares) external;

    /**
     * @notice Emits a withdraw other event
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the withdrawal
     * @param receiver The address receiving the reference assets
     * @param owner The address owning the shares
     * @param asset The address of the reference asset
     * @param assets The amount of reference assets withdrawn
     * @param shares The amount of shares burned
     */
    function emitWithdrawOther(address sender, address receiver, address owner, address asset, uint256 assets, uint256 shares) external;

    /**
     * @notice Emits a deposit other event
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the deposit
     * @param owner The address receiving the shares
     * @param asset The address of the reference asset
     * @param assets The amount of reference assets deposited
     * @param shares The amount of shares minted
     */
    function emitDepositOther(address sender, address owner, address asset, uint256 assets, uint256 shares) external;

    /**
     * @notice Returns the maximum amount of CPT and CST tokens that can be minted
     * @param owner The address of the owner
     * @return maxAmount The maximum amount of CPT and CST tokens that can be minted
     */
    function maxMint(address owner) external view returns (uint256 maxAmount);

    /**
     * @notice Returns the maximum amount of collateral asset that can be deposited
     * @param owner The address of the owner
     * @return maxCollateralAssets The maximum amount of collateral asset that can be deposited
     */
    function maxDeposit(address owner) external view returns (uint256 maxCollateralAssets);

    /**
     * @notice Gets the maximum amount of collateral asset that can be received by unwinding deposit
     * @param owner The address to check balances for
     * @return maxCollateralAssetAmountOut The maximum amount of collateral asset that can be received
     */
    function maxUnwindDeposit(address owner) external view returns (uint256 maxCollateralAssetAmountOut);

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be burned in unwind mint
     * @param owner The address to check balances for
     * @return maxCptAndCstSharesIn The maximum amount of tokens that can be burned
     */
    function maxUnwindMint(address owner) external view returns (uint256 maxCptAndCstSharesIn);

    /**
     * @notice Returns the maximum amount of assets that could be transferred from `owner` through `withdraw`.
     * @param owner The address of the owner
     * @return maxCollateralAssets The maximum amount of assets that could be withdrawn
     */
    function maxWithdraw(address owner) external view returns (uint256 maxCollateralAssets);

    /**
     * @notice Returns the maximum amount of reference assets that could be transferred from `owner` through `withdraw`.
     * @param owner The address of the owner
     * @return maxReferenceAssets The maximum amount of reference assets that could be withdrawn
     */
    function maxWithdrawOther(address owner) external view returns (uint256 maxReferenceAssets);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred from `owner` through `exercise` and not cause a revert.
     * @param owner The address of the owner
     * @return maxCstShares The maximum amount of CST shares that could be used in exercise
     */
    function maxExercise(address owner) external view returns (uint256 maxCstShares);

    /**
     * @notice Returns the maximum amount of reference assets that could be used as compensation in `exercise` and not cause a revert.
     * @param owner The address of the owner
     * @return maxReferenceAssets The maximum amount of reference assets that could be used as compensation in exercise
     */
    function maxExerciseOther(address owner) external view returns (uint256 maxReferenceAssets);

    /**
     * @notice Returns the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert.
     * @param owner The address of the owner
     * @return maxShares The maximum amount of CPT shares that could be redeemed
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /**
     * @notice Returns the maximum amount of collateral assets that could be transferred from `owner` through `swap` and not cause a revert.
     * @param owner The address of the owner
     * @return maxAssets The maximum amount of collateral assets that could be transferred through swap
     */
    function maxSwap(address owner) external view returns (uint256 maxAssets);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred through `unwindExercise` and not cause a revert.
     * @param receiver The address that would receive the unlocked tokens (not used for calculation)
     * @return maxShares The maximum amount of CST shares that could be unlocked through unwindExercise
     */
    function maxUnwindExercise(address receiver) external view returns (uint256 maxShares);

    /**
     * @notice Returns the maximum amount of reference assets that would be unlocked through `unwindExercise` and not cause a revert.
     * @param receiver The address that would receive the unlocked tokens (not used for calculation)
     * @return maxReferenceAssets The maximum amount of reference assets that would be unlocked through unwindExercise
     */
    function maxUnwindExerciseOther(address receiver) external view returns (uint256 maxReferenceAssets);

    /**
     * @notice Returns the maximum amount of assets that could be transferred through `unwindSwap` and not cause a revert.
     * @param receiver The address that would receive the unlocked tokens (not used for calculation)
     * @return maxAmount The maximum amount of collateral assets that could be transferred through unwindSwap
     */
    function maxUnwindSwap(address receiver) external view returns (uint256 maxAmount);

    /**
     * @notice Previews the outcome of exercising CST shares
     * @param shares The amount of CST shares to exercise
     * @param compensation The amount of reference asset compensation to provide
     * @return assets The amount of collateral assets that would be received
     * @return otherAssetSpent The amount of other asset that would be spent
     * @return fee The fee amount that would be charged
     */
    function previewExercise(uint256 shares, uint256 compensation) external view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee);

    /**
     * @notice Previews the outcome of unwinding an exercise operation
     * @param shares The amount of CST tokens to mint
     * @return assetIn The amount of collateral asset that would be required
     * @return compensationOut The amount of reference asset compensation that would be received
     */
    function previewUnwindExercise(uint256 shares) external view returns (uint256 assetIn, uint256 compensationOut);

    /**
     * @notice Previews the amount of CPT and CST tokens that would be minted for a deposit
     * @param collateralAssets The amount of collateral asset to deposit
     * @return outShares The amount of CPT and CST tokens that would be minted
     */
    function previewDeposit(uint256 collateralAssets) external view returns (uint256 outShares);

    /**
     * @notice Previews the amount of CST shares and reference token compensation that would be required for a swap
     * @param collateralAssets The exact amount of collateral assets that would be received
     * @return suppliedCstShares The amount of CST shares that would be locked from msg.sender
     * @return suppliedReferenceAssets The amount of reference token that would be locked from msg.sender
     */
    function previewSwap(uint256 collateralAssets) external view returns (uint256 suppliedCstShares, uint256 suppliedReferenceAssets);

    /**
     * @notice Previews the amounts of assets that would be received when redeeming CPT tokens
     * @param cptShares The amount of CPT tokens to redeem
     * @return outReferenceAssets The amount of reference asset that would be received
     * @return outCollateralAssets The amount of collateral asset that would be received
     */
    function previewRedeem(uint256 cptShares) external view returns (uint256 outReferenceAssets, uint256 outCollateralAssets);

    /**
     * @notice Previews the amount of CPT and CST tokens needed to unwind deposit for specific collateral amount
     * @param collateralAssets The desired amount of collateral asset to receive
     * @return suppliedShares The amount of CPT and CST tokens that would need to be burned
     */
    function previewUnwindDeposit(uint256 collateralAssets) external view returns (uint256 suppliedShares);

    /**
     * @notice Previews the outcome of unwinding a swap operation
     * @param collateralAssets The amount of CPT tokens to unwind
     * @return outReferenceAssets The amount of reference asset that would be received
     * @return outCstShares The amount of CST tokens that would be received
     */
    function previewUnwindSwap(uint256 collateralAssets) external view returns (uint256 outReferenceAssets, uint256 outCstShares);

    /**
     * @notice Previews the amount of collateral needed to mint specific amounts of CPT and CST tokens
     * @param shares The desired amount of CPT and CST tokens to mint
     * @return suppliedCollateralAssets The amount of collateral asset that would be required
     */
    function previewMint(uint256 shares) external view returns (uint256 suppliedCollateralAssets);

    /**
     * @notice Previews the amount of collateral that would be received when unwinding mint
     * @param shares The amount of CPT and CST tokens to burn
     * @return outCollateralAssets The amount of collateral asset that would be received
     */
    function previewUnwindMint(uint256 shares) external view returns (uint256 outCollateralAssets);

    /**
     * @notice Previews the amount of CPT tokens needed to withdraw specific amounts of assets
     * @param collateralAssetOut The desired amount of collateral asset to withdraw
     * @param referenceAssetOut The desired amount of reference asset to withdraw
     * @return sharesIn The amount of CPT tokens that would need to be burned
     * @return actualReferenceAssetOut The actual amount of reference asset that would be withdrawn
     */
    function previewWithdraw(uint256 collateralAssetOut, uint256 referenceAssetOut) external view returns (uint256 sharesIn, uint256 actualReferenceAssetOut);
}
