// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title ISharesFactory Interface
 * @author Cork Team
 * @notice Interface for SharesFactory contract
 */
interface ISharesFactory is IErrors {
    /// @notice emitted when a new Principal Token + Swap Token shares are deployed
    /// @param collateralAsset Address of Collateral Asset(Collateral Asset) contract
    /// @param principalToken Address of Principal Token(Cork Principal Token) contract
    /// @param swapToken Address of Swap Token(Cork Swap Token) contract
    event SharesDeployed(address indexed collateralAsset, address indexed principalToken, address indexed swapToken);

    /// @notice emitted when a cork pool is changed in shares factory
    /// @param oldCorkPool old cork pool address
    /// @param newCorkPool new cork pool address
    event CorkPoolChanged(address indexed oldCorkPool, address indexed newCorkPool);

    /**
     * @notice for safety checks in pool core, also act as kind of like a registry
     * @param share the address of Share contract
     */
    function isDeployed(address share) external view returns (bool);

    /**
     * @notice for getting list of deployed SwapShares with this factory
     * @param poolId id of the pool
     * @return principalToken deployed Principal Token shares
     * @return swapToken deployed Swap Token shares
     */
    function poolShares(MarketId poolId) external view returns (address principalToken, address swapToken);

    struct DeployParams {
        Market poolParams;
        address owner;
        uint256 swapRate;
    }

    function deployPoolShares(DeployParams calldata params) external returns (address principalToken, address swapToken);
}
