// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
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

    struct DeployParams {
        Market poolParams;
        MarketId poolId;
        address owner;
    }

    function deployPoolShares(DeployParams calldata params) external returns (address principalToken, address swapToken);
}
