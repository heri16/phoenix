// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Extsload} from "contracts/core/Extsload.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {State} from "contracts/libraries/State.sol";

/**
 * @title CorkPoolManagerStorage Abstract Contract
 * @author Cork Team
 * @notice Abstract CorkPoolManagerStorage contract for providing base for CorkPoolManager contract
 */
abstract contract CorkPoolManagerStorage is IErrors, ReentrancyGuardTransient, Extsload {
    using PoolLibrary for State;

    struct Storage {
        mapping(MarketId => State) states;
        address SHARES_FACTORY;
        address CONSTRAINT_ADAPTER;
        address TREASURY;
        address WHITELIST_MANAGER;
    }

    // ERC-7201 Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cork.storage.CorkPoolManagerStorage")) - 1)) & ~bytes32(uint256(0xff)) = 0xca60d71d44db08890954961692d4c0e9107284a789e12b27f483ad59d898d200
    bytes32 private constant _CORK_POOL_MANAGER_STORAGE_POSITION = 0xca60d71d44db08890954961692d4c0e9107284a789e12b27f483ad59d898d200;

    ///======================================================///
    ///================= INITIALIZATION FUNCTIONS ===========///
    ///======================================================///

    /// @notice initializes the CorkPoolManagerStorage
    function initializeCorkPoolManagerStorage(address sharesFactory, address constraintRateAdapter, address treasury, address whitelistManager) internal {
        require(sharesFactory != address(0) && constraintRateAdapter != address(0) && treasury != address(0) && whitelistManager != address(0), ZeroAddress());

        Storage storage ms = data();
        ms.SHARES_FACTORY = sharesFactory;
        ms.CONSTRAINT_ADAPTER = constraintRateAdapter;
        ms.TREASURY = treasury;
        ms.WHITELIST_MANAGER = whitelistManager;
    }

    ///======================================================///
    ///================= VIEW FUNCTIONS =====================///
    ///======================================================///

    /// @notice returns the address of the treasury
    function _getTreasuryAddress() internal view returns (address) {
        return data().TREASURY;
    }

    /// @notice returns the address of the constraint rate adapter
    function _getConstraintRateAdapter() internal view returns (address) {
        return data().CONSTRAINT_ADAPTER;
    }

    /// @notice returns the address of the whitelist manager
    function _getWhitelistManager() internal view returns (address) {
        return data().WHITELIST_MANAGER;
    }

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

    function data() internal pure returns (Storage storage ms) {
        // slither-disable-next-line assembly
        assembly {
            ms.slot := _CORK_POOL_MANAGER_STORAGE_POSITION
        }
    }

    function _onlyInitialized(MarketId id) internal view {
        require(data().states[id].isInitialized(), NotInitialized());
    }
}
