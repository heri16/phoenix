pragma solidity ^0.8.30;

import {CorkPool} from "contracts/core/CorkPool.sol";
import {MarketId, PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {State} from "contracts/libraries/State.sol";

/// @title CorkPoolMock Contract, used for testing CorkPool contract, mostly here for getter functions
contract CorkPoolMock is CorkPool {
    using PoolLibrary for State;

    function unwindSwapRate(MarketId poolId) external view returns (uint256 rate) {
        rate = data().states[poolId].unwindSwapRate(poolId, data().CONSTRAINT_ADAPTER);
    }

    function availableForUnwindSwap(MarketId poolId) external view returns (uint256 referenceAsset, uint256 swapToken) {
        (referenceAsset, swapToken) = data().states[poolId].availableForUnwindSwap();
    }

    function expiry(MarketId poolId) external view returns (uint256 _expiry) {
        _expiry = PoolLibrary.nextExpiry(data().states[poolId]);
    }

    function underlyingAsset(MarketId poolId) external view returns (address collateralAsset, address referenceAsset) {
        State memory state = data().states[poolId];
        referenceAsset = state.info.referenceAsset;
        collateralAsset = state.info.collateralAsset;
    }
}
