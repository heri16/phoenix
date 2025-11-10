// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";

contract FixedToTokenNativeDecimalsTest is Test {
    // =============== fixedToTokenNativeDecimals Tests ===============

    function test_fixedToTokenNativeDecimals_ShouldWorkCorrectly() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimals = 6;
        uint256 expected = 1000 * 1e6; // 1000 USDC

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_ShouldDoNoOp_WhenExactly18Decimals() public pure {
        uint256 amount = 1000 ether; // Exactly 18 decimals
        uint8 decimals = 18;
        uint256 expected = amount;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_ShouldWorkCorrectly_WhenDecimalsAreLessThan18() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimals = 8;
        uint256 expected = 1000 * 1e8; // 1000 * 10^18 -> 1000 * 10^8 -> 1000000000

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_ShouldWorkCorrectly_WhenDecimalsAreGreaterThan18() public pure {
        uint256 amount = 1000; // 1000 wei
        uint8 decimals = 20;
        uint256 expected = 1000 * 1e2; // 1000 wei -> 1000 * 10^2 -> 1000 * 100 -> 100000

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_ShouldWorkCorrectly_WhenDecimalsAre0() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimals = 0;
        uint256 expected = 1000; // 1000 with 0 decimals

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_LargeAmount() public pure {
        uint256 amount = 1_000_000 ether; // 1 million * 10^18
        uint8 decimals = 6;
        uint256 expected = 1_000_000 * 1e6;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_SmallAmount() public pure {
        uint256 amount = 1 ether; // 1 * 10^18
        uint8 decimals = 6;
        uint256 expected = 1 * 1e6;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_ShouldWorkCorrectly_WhenZeroAmount() public pure {
        uint256 amount = 0;
        uint8 decimals = 6;
        uint256 expected = 0;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_ShouldWorkCorrectly_WhenRoundingDown() public pure {
        uint256 amount = 1e12; // Very small amount in 18 decimals
        uint8 decimals = 6;
        // 1e12 / 1e12 = 1
        uint256 expected = 1;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_PrecisionLoss() public pure {
        uint256 amount = 1500; // 1500 wei (very small in 18 decimals)
        uint8 decimals = 6;
        // 1500 / 1e12 = 0 (rounds down, loses precision)
        uint256 expected = 0;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_DecimalConversionAccuracy() public pure {
        uint256 amount = 123_456_789 * 1e12; // 123.456789 in 18 decimals
        uint8 decimals = 6;
        uint256 expected = 123_456_789; // Convert to 6 decimals

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimals_RoundTripConversion() public pure {
        uint256 originalAmount = 1000 * 1e6; // 1000 USDC
        uint8 decimals = 6;

        // Convert to fixed
        uint256 fixedAmount = TransferHelper.tokenNativeDecimalsToFixed(originalAmount, decimals);

        // Convert back to native
        uint256 result = TransferHelper.fixedToTokenNativeDecimals(fixedAmount, decimals);

        // Should get back the original amount
        assertEq(result, originalAmount);
    }

    function test_fixedToTokenNativeDecimals_ExactDivision() public pure {
        uint256 amount = 1000 * 1e18; // Exact amount
        uint8 decimals = 6;
        uint256 expected = 1000 * 1e6;

        uint256 result = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);
        assertEq(result, expected);
    }
}
