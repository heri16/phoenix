// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Shares} from "contracts/libraries/State.sol";

/**
 * @title Guard Library Contract
 * @author Cork Team
 * @notice Guard library which implements modifiers for Swap Token related features
 */
library Guard {
    function safeBeforeExpired(Shares storage swapToken) internal view {
        require(swapToken.swap != address(0) && swapToken.principal != address(0), IErrors.Uninitialized());
        require(!PoolShare(swapToken.swap).isExpired(), IErrors.Expired());
    }

    function safeAfterExpired(Shares storage swapToken) internal view {
        require(swapToken.swap != address(0) && swapToken.principal != address(0), IErrors.Uninitialized());
        require(PoolShare(swapToken.swap).isExpired(), IErrors.NotExpired());
    }
}
