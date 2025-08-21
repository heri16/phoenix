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
}
