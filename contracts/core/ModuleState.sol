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

    mapping(MarketId => State) internal states;

    address internal SHARES_FACTORY;

    address internal CONFIG;

    /// @notice __gap variable to prevent storage collisions
    // slither-disable-next-line unused-state
    uint256[48] private __gap;

    /**
     * @dev checks if caller is config contract or not
     */
    function onlyConfig() internal view {
        if (msg.sender != CONFIG) revert OnlyConfigAllowed();
    }

    /// @notice returns the address of the shares factory
    function factory() external view returns (address) {
        return SHARES_FACTORY;
    }

    /// @notice initializes the module state
    function initializeModuleState(address _sharesFactory, address _config) internal {
        if (_sharesFactory == address(0) || _config == address(0)) revert ZeroAddress();

        SHARES_FACTORY = _sharesFactory;
        CONFIG = _config;
    }

    /// @notice returns the address of the treasury
    function getTreasuryAddress() public view returns (address) {
        return CorkConfig(CONFIG).treasury();
    }

    function onlyInitialized(MarketId id) internal view {
        if (!states[id].isInitialized()) revert NotInitialized();
    }

    function corkPoolDepositAndMintNotPaused(MarketId id) internal view {
        if (states[id].pool.isDepositPaused) revert Paused();
    }

    function corkPoolSwapNotPaused(MarketId id) internal view {
        if (states[id].pool.isSwapPaused) revert Paused();
    }

    function corkPoolWithdrawalNotPaused(MarketId id) internal view {
        if (states[id].pool.isWithdrawalPaused) revert Paused();
    }

    function corkPoolUnwindDepositAndMintNotPaused(MarketId id) internal view {
        if (states[id].pool.isReturnPaused) revert Paused();
    }

    function corkPoolUnwindSwapNotPaused(MarketId id) internal view {
        if (states[id].pool.isUnwindSwapPaused) revert Paused();
    }
}
