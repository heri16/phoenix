// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library TransferHelper {
    using Math for uint256;

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

    function normalizeDecimalsWithCeilDiv(uint256 amount, uint8 decimalsBefore, uint8 decimalsAfter) internal pure returns (uint256) {
        // If we need to increase the decimals
        if (decimalsBefore > decimalsAfter) {
            // Then we shift right the amount by the number of decimals
            amount = amount.ceilDiv(10 ** (decimalsBefore - decimalsAfter));

            // If we need to decrease the number
        } else if (decimalsBefore < decimalsAfter) {
            // then we shift left by the difference
            amount = amount * 10 ** (decimalsAfter - decimalsBefore);
        }
        // If nothing changed this is a no-op
        return amount;
    }

    function tokenNativeDecimalsToFixed(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return normalizeDecimals(amount, decimals, TARGET_DECIMALS);
    }

    function fixedToTokenNativeDecimals(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return normalizeDecimals(amount, TARGET_DECIMALS, decimals);
    }

    function fixedToTokenNativeDecimalsWithCeilDiv(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return normalizeDecimalsWithCeilDiv(amount, TARGET_DECIMALS, decimals);
    }
}
