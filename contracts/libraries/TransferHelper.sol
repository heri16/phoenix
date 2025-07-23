// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library TransferHelper {
    uint8 internal constant TARGET_DECIMALS = 18;

    function normalizeDecimals(uint256 amount, uint8 decimalsBefore, uint8 decimalsAfter) internal pure returns (uint256) {
        // If we need to increase the decimals
        if (decimalsBefore > decimalsAfter) {
            // Then we shift right the amount by the number of decimals
            amount = amount / 10 ** (decimalsBefore - decimalsAfter);
            // If we need to decrease the number
        } else if (decimalsBefore < decimalsAfter) {
            // then we shift left by the difference
            amount = amount * 10 ** (decimalsAfter - decimalsBefore);
        }
        // If nothing changed this is a no-op
        return amount;
    }

    function tokenNativeDecimalsToFixed(uint256 amount, IERC20Metadata token) internal view returns (uint256) {
        uint8 decimals = token.decimals();
        return normalizeDecimals(amount, decimals, TARGET_DECIMALS);
    }

    function tokenNativeDecimalsToFixed(uint256 amount, address token) internal view returns (uint256) {
        return tokenNativeDecimalsToFixed(amount, IERC20Metadata(token));
    }

    function fixedToTokenNativeDecimals(uint256 amount, IERC20Metadata token) internal view returns (uint256) {
        uint8 decimals = token.decimals();
        return normalizeDecimals(amount, TARGET_DECIMALS, decimals);
    }

    function fixedToTokenNativeDecimals(uint256 amount, address token) internal view returns (uint256) {
        return fixedToTokenNativeDecimals(amount, IERC20Metadata(token));
    }
}
