// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {SwapToken, SwapTokenLibrary} from "contracts/libraries/SwapToken.sol";

/**
 * @title Guard Library Contract
 * @author Cork Team
 * @notice Guard library which implements modifiers for Swap Token related features
 */
library Guard {
    using SwapTokenLibrary for SwapToken;

    function _onlyNotExpired(SwapToken storage swapToken) internal view {
        if (swapToken.isExpired()) revert IErrors.Expired();
    }

    function _onlyExpired(SwapToken storage swapToken) internal view {
        if (!swapToken.isExpired()) revert IErrors.NotExpired();
    }

    function _onlyInitialized(SwapToken storage swapToken) internal view {
        if (!swapToken.isInitialized()) revert IErrors.Uninitialized();
    }

    function safeBeforeExpired(SwapToken storage swapToken) internal view {
        _onlyInitialized(swapToken);
        _onlyNotExpired(swapToken);
    }

    function safeAfterExpired(SwapToken storage swapToken) internal view {
        _onlyInitialized(swapToken);
        _onlyExpired(swapToken);
    }
}
