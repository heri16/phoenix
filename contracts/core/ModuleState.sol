// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {Extsload} from "contracts/core/Extsload.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {State} from "contracts/libraries/State.sol";

/**
 * @title ModuleState Abstract Contract
 * @author Cork Team
 * @notice Abstract ModuleState contract for providing base for CorkPool contract
 */
abstract contract ModuleState is IErrors, ReentrancyGuardTransient, Extsload {
    using PoolLibrary for State;

    struct ModuleStateStorage {
        mapping(MarketId => State) states;
        address SHARES_FACTORY;
        address CONFIG;
        address CONSTRAINT_ADAPTER;
    }

    // ERC-7201 Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cork.storage.ModuleState")) - 1)) & ~bytes32(uint256(0xff)) = 0x0f7db58ac1e2c527c1cd5fdc0769579505d2274a0d47c6ed16fd32c06f09dd00
    bytes32 private constant _MODULE_STATE_STORAGE_POSITION = 0x0f7db58ac1e2c527c1cd5fdc0769579505d2274a0d47c6ed16fd32c06f09dd00;

    ///======================================================///
    ///================= INITIALIZATION FUNCTIONS ===========///
    ///======================================================///

    /// @notice initializes the module state
    function initializeModuleState(address sharesFactory, address config, address constraintAdapter) internal {
        require(sharesFactory != address(0) && config != address(0) && constraintAdapter != address(0), ZeroAddress());

        ModuleStateStorage storage ms = data();
        ms.SHARES_FACTORY = sharesFactory;
        ms.CONFIG = config;
        ms.CONSTRAINT_ADAPTER = constraintAdapter;
    }

    ///======================================================///
    ///================= VIEW FUNCTIONS =====================///
    ///======================================================///

    /// @notice returns the address of the shares factory
    function factory() external view returns (address) {
        return data().SHARES_FACTORY;
    }

    /// @notice returns the address of the treasury
    function getTreasuryAddress() public view returns (address) {
        return CorkConfig(data().CONFIG).treasury();
    }

    function getConstraintAdapter() public view returns (address) {
        return data().CONSTRAINT_ADAPTER;
    }

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

    function data() internal pure returns (ModuleStateStorage storage ms) {
        assembly {
            ms.slot := _MODULE_STATE_STORAGE_POSITION
        }
    }

    /**
     * @dev checks if caller is config contract or not
     */
    function onlyConfig() internal view {
        require(msg.sender == data().CONFIG, OnlyConfigAllowed());
    }

    function onlyInitialized(MarketId id) internal view {
        require(data().states[id].isInitialized(), NotInitialized());
    }

    function corkPoolDepositAndMintNotPaused(MarketId id) internal view {
        require(!data().states[id].pool.isDepositPaused, Paused());
    }

    function corkPoolSwapNotPaused(MarketId id) internal view {
        require(!data().states[id].pool.isSwapPaused, Paused());
    }

    function corkPoolWithdrawalNotPaused(MarketId id) internal view {
        require(!data().states[id].pool.isWithdrawalPaused, Paused());
    }

    function corkPoolUnwindDepositAndMintNotPaused(MarketId id) internal view {
        require(!data().states[id].pool.isReturnPaused, Paused());
    }

    function corkPoolUnwindSwapAndExerciseNotPaused(MarketId id) internal view {
        require(!data().states[id].pool.isUnwindSwapPaused, Paused());
    }
}
