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
     * @notice Returns the cork pool manager address
     * @return The address of the cork pool manager contract
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

    /// @notice returns true if the share is expired
    function isExpired() external view returns (bool);

    ///@notice returns the expiry timestamp if 0 then it means it never expires
    function expiry() external view returns (uint256);

    ///@notice returns the timestamp when the share was issued
    function issuedAt() external view returns (uint256);

    /**
     * @notice Emits a deposit event for ERC4626 compatibility
     * @dev This function can only be called by the cork pool manager contract (owner)
     * @param sender The address initiating the deposit
     * @param receiver The address receiving the shares
     * @param assets The amount of assets deposited
     * @param shares The amount of shares minted
     */
    function emitDeposit(address sender, address receiver, uint256 assets, uint256 shares) external;

    /**
     * @notice Emits a withdraw event for ERC4626 compatibility
     * @dev This function can only be called by the cork pool manager contract (owner)
     * @param sender The address initiating the withdrawal
     * @param receiver The address receiving the assets
     * @param owner The address owning the shares
     * @param assets The amount of assets withdrawn
     * @param shares The amount of shares burned
     */
    function emitWithdraw(address sender, address receiver, address owner, uint256 assets, uint256 shares) external;

    /**
     * @notice Emits a withdraw other event
     * @dev This function can only be called by the cork pool manager contract (owner)
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
     * @dev This function can only be called by the cork pool manager contract (owner)
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
     * @return maxCptAndCstSharesOut The maximum amount of CPT and CST tokens that can be minted
     */
    function maxMint(address owner) external view returns (uint256 maxCptAndCstSharesOut);

    /**
     * @notice Returns the maximum amount of collateral asset that can be deposited
     * @param owner The address of the owner
     * @return maxCollateralAssetsIn The maximum amount of collateral asset that can be deposited
     */
    function maxDeposit(address owner) external view returns (uint256 maxCollateralAssetsIn);

    /**
     * @notice Gets the maximum amount of collateral asset that can be received by unwinding deposit
     * @param owner The address to check balances for
     * @return maxCollateralAssetsOut The maximum amount of collateral asset that can be received
     */
    function maxUnwindDeposit(address owner) external view returns (uint256 maxCollateralAssetsOut);

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be burned in unwind mint
     * @param owner The address to check balances for
     * @return maxCptAndCstSharesIn The maximum amount of tokens that can be burned
     */
    function maxUnwindMint(address owner) external view returns (uint256 maxCptAndCstSharesIn);

    /**
     * @notice Returns the maximum amount of assets that could be transferred from `owner` through `withdraw`.
     * @param owner The address of the owner
     * @return maxCollateralAssetsOut The maximum amount of assets that could be withdrawn
     */
    function maxWithdraw(address owner) external view returns (uint256 maxCollateralAssetsOut);

    /**
     * @notice Returns the maximum amount of reference assets that could be transferred from `owner` through `withdraw`.
     * @param owner The address of the owner
     * @return maxReferenceAssetsOut The maximum amount of reference assets that could be withdrawn
     */
    function maxWithdrawOther(address owner) external view returns (uint256 maxReferenceAssetsOut);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred from `owner` through `exercise` and not cause a revert.
     * @param owner The address of the owner
     * @return maxCstSharesIn The maximum amount of CST shares that could be used in exercise
     */
    function maxExercise(address owner) external view returns (uint256 maxCstSharesIn);

    /**
     * @notice Returns the maximum amount of reference assets that could be used as compensation in `exercise` and not cause a revert.
     * @param owner The address of the owner
     * @return maxReferenceAssetsIn The maximum amount of reference assets that could be used as compensation in exercise
     */
    function maxExerciseOther(address owner) external view returns (uint256 maxReferenceAssetsIn);

    /**
     * @notice Returns the maximum amount of CPT shares that could be transferred from `owner` through `redeem` and not cause a revert.
     * @param owner The address of the owner
     * @return maxCptSharesIn The maximum amount of CPT shares that could be redeemed
     */
    function maxRedeem(address owner) external view returns (uint256 maxCptSharesIn);

    /**
     * @notice Returns the maximum amount of collateral assets that could be transferred from `owner` through `swap` and not cause a revert.
     * @param owner The address of the owner
     * @return maxCollateralAssetsOut The maximum amount of collateral assets that could be transferred through swap
     */
    function maxSwap(address owner) external view returns (uint256 maxCollateralAssetsOut);

    /**
     * @notice Returns the maximum amount of CST shares that could be transferred through `unwindExercise` and not cause a revert.
     * @param owner The address of the owner (not used for calculation)
     * @return maxCstSharesOut The maximum amount of CST shares that could be unlocked through unwindExercise
     */
    function maxUnwindExercise(address owner) external view returns (uint256 maxCstSharesOut);

    /**
     * @notice Returns the maximum amount of reference assets that would be unlocked through `unwindExercise` and not cause a revert.
     * @param owner The address of the owner (not used for calculation)
     * @return maxReferenceAssetsOut The maximum amount of reference assets that would be unlocked through unwindExercise
     */
    function maxUnwindExerciseOther(address owner) external view returns (uint256 maxReferenceAssetsOut);

    /**
     * @notice Returns the maximum amount of assets that could be transferred through `unwindSwap` and not cause a revert.
     * @param owner The address of the owner (not used for calculation)
     * @return maxCollateralAssetsIn The maximum amount of collateral assets that could be transferred through unwindSwap
     */
    function maxUnwindSwap(address owner) external view returns (uint256 maxCollateralAssetsIn);

    /**
     * @notice Previews the outcome of exercising CST shares
     * @param cstSharesIn The amount of CST shares to exercise (must be non-zero)
     * @return collateralAssetsOut The amount of collateral assets that would be received
     * @return referenceAssetsIn The amount of reference asset that would be spent
     * @return fee The fee amount that would be charged
     */
    function previewExercise(uint256 cstSharesIn) external view returns (uint256 collateralAssetsOut, uint256 referenceAssetsIn, uint256 fee);

    /**
     * @notice Previews the outcome of exercising CST shares
     * @param referenceAssetsIn The amount of reference asset compensation to provide (must be non-zero)
     * @return collateralAssetsOut The amount of collateral assets that would be received
     * @return cstSharesIn The amount of other asset that would be spent
     * @return fee The fee amount that would be charged
     */
    function previewExerciseOther(uint256 referenceAssetsIn) external view returns (uint256 collateralAssetsOut, uint256 cstSharesIn, uint256 fee);

    /**
     * @notice Previews the outcome of unwinding an exercise operation
     * @param cstSharesOut The amount of CST tokens to mint
     * @return collateralAssetsIn The amount of collateral asset that would be required
     * @return referenceAssetsOut The amount of reference asset compensation that would be received
     * @return fee The fee amount that would be charged
     */
    function previewUnwindExercise(uint256 cstSharesOut) external view returns (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee);

    /**
     * @notice Previews the outcome of unwinding an exercise operation
     * @param referenceAssetsOut The amount of reference token to mint
     * @return collateralAssetsIn The amount of collateral asset that would be required
     * @return cstSharesOut The amount of CST tokens that would be received
     * @return fee The fee amount that would be charged
     */
    function previewUnwindExerciseOther(uint256 referenceAssetsOut) external view returns (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee);

    /**
     * @notice Previews the amount of CPT and CST tokens that would be minted for a deposit
     * @param collateralAssetsIn The amount of collateral asset to deposit
     * @return cptAndCstSharesOut The amount of CPT and CST tokens that would be minted
     */
    function previewDeposit(uint256 collateralAssetsIn) external view returns (uint256 cptAndCstSharesOut);

    /**
     * @notice Previews the amount of CST shares and reference token compensation that would be required for a swap
     * @param collateralAssetsOut The exact amount of collateral assets that would be received
     * @return cstSharesIn The amount of CST shares that would be locked from msg.sender
     * @return referenceAssetsIn The amount of reference token that would be locked from msg.sender
     * @return fee The fee amount that would be charged
     */
    function previewSwap(uint256 collateralAssetsOut) external view returns (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee);

    /**
     * @notice Previews the amounts of assets that would be received when redeeming CPT tokens
     * @param cptSharesIn The amount of CPT tokens to redeem
     * @return referenceAssetsOut The amount of reference asset that would be received
     * @return collateralAssetsOut The amount of collateral asset that would be received
     */
    function previewRedeem(uint256 cptSharesIn) external view returns (uint256 referenceAssetsOut, uint256 collateralAssetsOut);

    /**
     * @notice Previews the amount of CPT and CST tokens needed to unwind deposit for specific collateral amount
     * @param collateralAssetsOut The desired amount of collateral asset to receive
     * @return cptAndCstSharesIn The amount of CPT and CST tokens that would need to be burned
     */
    function previewUnwindDeposit(uint256 collateralAssetsOut) external view returns (uint256 cptAndCstSharesIn);

    /**
     * @notice Previews the outcome of unwinding a swap operation
     * @param collateralAssetsIn The amount of CPT tokens to unwind
     * @return cstSharesOut The amount of CST tokens that would be received
     * @return referenceAssetsOut The amount of reference asset that would be received
     * @return fee The fee amount that would be charged
     */
    function previewUnwindSwap(uint256 collateralAssetsIn) external view returns (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee);

    /**
     * @notice Previews the amount of collateral needed to mint specific amounts of CPT and CST tokens
     * @param cptAndCstSharesOut The desired amount of CPT and CST tokens to mint
     * @return collateralAssetsIn The amount of collateral asset that would be required
     */
    function previewMint(uint256 cptAndCstSharesOut) external view returns (uint256 collateralAssetsIn);

    /**
     * @notice Previews the amount of collateral that would be received when unwinding mint
     * @param cptAndCstSharesIn The amount of CPT and CST tokens to burn
     * @return collateralAssetsOut The amount of collateral asset that would be received
     */
    function previewUnwindMint(uint256 cptAndCstSharesIn) external view returns (uint256 collateralAssetsOut);

    /**
     * @notice Previews the amount of CPT tokens needed to withdraw specific amounts of assets
     * @param collateralAssetsOut The desired amount of collateral asset to withdraw
     * @return cptSharesIn The amount of CPT tokens that would need to be burned
     * @return actualCollateralAssetsOut The actual amount of collateral asset that would be withdrawn
     * @return actualReferenceAssetsOut The actual amount of reference asset that would be withdrawn
     */
    function previewWithdraw(uint256 collateralAssetsOut) external view returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut);

    /**
     * @notice Previews the amount of CPT tokens needed to withdraw specific amounts of assets
     * @param referenceAssetsOut The desired amount of reference asset to withdraw
     * @return cptSharesIn The amount of CPT tokens that would need to be burned
     * @return actualCollateralAssetsOut The actual amount of collateral asset that would be withdrawn
     * @return actualReferenceAssetsOut The actual amount of reference asset that would be withdrawn
     */
    function previewWithdrawOther(uint256 referenceAssetsOut) external view returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut);
}
