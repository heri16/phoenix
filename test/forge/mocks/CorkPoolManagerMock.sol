pragma solidity ^0.8.30;

import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {MarketId, PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {State} from "contracts/libraries/State.sol";

/// @title CorkPoolManagerMock Contract, used for testing CorkPoolManager contract, mostly here for getter functions
contract CorkPoolManagerMock is CorkPoolManager {
    using PoolLibrary for State;

    function state(MarketId poolId) external view returns (State memory) {
        return data().states[poolId];
    }

    function availableForUnwindSwap(MarketId poolId) external view returns (uint256 referenceAsset, uint256 swapToken) {
        State storage self = data().states[poolId];

        referenceAsset = self.pool.balances.referenceAssetBalance;
        swapToken = self.pool.balances.swapTokenBalance;
    }

    function expiry(MarketId poolId) external view returns (uint256 _expiry) {
        _expiry = PoolLibrary.nextExpiry(data().states[poolId]);
    }

    function underlyingAsset(MarketId poolId) external view returns (address collateralAsset, address referenceAsset) {
        State memory state = data().states[poolId];
        referenceAsset = state.info.referenceAsset;
        collateralAsset = state.info.collateralAsset;
    }

    function getPoolBalances(MarketId poolId)
        external
        view
        returns (uint256 collateralAssetLocked, uint256 swapTokenBalance, uint256 referenceAssetBalance)
    {
        State storage state = data().states[poolId];
        collateralAssetLocked = state.pool.balances.collateralAsset.locked;
        swapTokenBalance = state.pool.balances.swapTokenBalance;
        referenceAssetBalance = state.pool.balances.referenceAssetBalance;
    }

    /// @notice Helper function for testing - sets a partially initialized market (for mutation testing)
    function setPartiallyInitializedMarket(MarketId poolId, address nonZeroAddress, bool isReferenceNonZero) external {
        State storage state = data().states[poolId];
        if (isReferenceNonZero) {
            state.info.referenceAsset = nonZeroAddress;
            state.info.collateralAsset = address(0);
        } else {
            state.info.collateralAsset = nonZeroAddress;
            state.info.referenceAsset = address(0);
        }
    }

    function exposeInitializeCorkPoolManagerStorage(
        address constraintRateAdapter,
        address treasury,
        address whitelistManager
    ) external {
        initializeCorkPoolManagerStorage(constraintRateAdapter, treasury, whitelistManager);
    }
}
