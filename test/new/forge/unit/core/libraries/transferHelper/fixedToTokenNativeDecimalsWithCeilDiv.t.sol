// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";

contract FixedToTokenNativeDecimalsWithCeilDivTest is Test {
    // =============== fixedToTokenNativeDecimalsWithCeilDiv Tests ===============

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldWorkCorrectly() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimals = 6;
        uint256 expected = 1000 * 1e6; // 1000 USDC

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldDoNoOp_WhenExactly18Decimals() public pure {
        uint256 amount = 1000 ether; // Already 18 decimals
        uint8 decimals = 18;
        uint256 expected = 1000 ether;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenDecimalsAreLessThan18() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimals = 10;
        uint256 expected = 1000 * 1e10; // 1000 * 10^18 -> 1000 * 10^8 -> 100000000000000000

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenDecimalsAreGreaterThan18() public pure {
        uint256 amount = 1000; // 1000 wei
        uint8 decimals = 20;
        uint256 expected = 1000 * 1e2; // 1000 wei -> 1000 * 10^2 -> 1000 * 100 -> 100000

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenDecimalsAre0() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimals = 0;
        uint256 expected = 1000; // 1000 with 0 decimals

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_LargeAmount() public pure {
        uint256 amount = 1_000_000 ether; // 1 million * 10^18
        uint8 decimals = 6;
        uint256 expected = 1_000_000 * 1e6;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_SmallAmount() public pure {
        uint256 amount = 1 ether; // 1 * 10^18
        uint8 decimals = 6;
        uint256 expected = 1 * 1e6;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenZeroAmount() public pure {
        uint256 amount = 0;
        uint8 decimals = 6;
        uint256 expected = 0;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenExactDivision() public pure {
        uint256 amount = 1e12; // Very small amount in 18 decimals
        uint8 decimals = 6;
        // 1e12 / 1e12 = 1 (exact division, no rounding needed)
        uint256 expected = 1;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_ShouldRoundUpCorrectly_WhenDecreasingDecimals() public pure {
        uint256 amount = 1500; // 1500 wei (very small in 18 decimals)
        uint8 decimals = 6;
        // 1500 / 1e12 = 0.0000000015, rounds up to 1 with ceilDiv
        uint256 expected = 1;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_DecimalConversionAccuracy() public pure {
        uint256 amount = 123_456_789 * 1e12; // 123.456789 in 18 decimals
        uint8 decimals = 6;
        uint256 expected = 123_456_789; // Convert to 6 decimals

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_CompareWithNormalVersion() public pure {
        // Test case where ceilDiv makes a difference
        uint256 amount = 1500; // Amount that doesn't divide evenly
        uint8 decimals = 6;

        uint256 resultCeilDiv = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        uint256 resultNormal = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);

        // ceilDiv should round up, normal should round down
        // 1500 / 10^12 = 0.0000000015 -> ceilDiv rounds to 1, normal rounds to 0
        assertEq(resultCeilDiv, 1);
        assertEq(resultNormal, 0);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_EdgeCaseBoundary() public pure {
        uint256 amount = 999_999_999_999; // Just below 10^12
        uint8 decimals = 6;
        // 999_999_999_999 / 10^12 = 0.999999999999 -> ceilDiv rounds to 1
        uint256 expected = 1;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_LargeNumberWithRemainder() public pure {
        uint256 amount = 5_555_555_555_555; // 5.555555555555 when divided by 10^12
        uint8 decimals = 6;
        // 5_555_555_555_555 / 10^12 = 5.555555555555 -> ceilDiv rounds to 6
        uint256 expected = 6;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_SmallRemainder() public pure {
        uint256 amount = 1_000_000_000_001; // 1 + 1 wei
        uint8 decimals = 6;
        // 1_000_000_000_001 / 10^12 = 1.000000000001 -> ceilDiv rounds to 2
        uint256 expected = 2;

        uint256 result = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        assertEq(result, expected);
    }

    function test_fixedToTokenNativeDecimalsWithCeilDiv_PreventingRoundingLoss() public pure {
        // This test demonstrates the key use case for ceilDiv: ensuring users don't lose tokens due to rounding
        uint256 amount = 1_500_000_000_000; // 1.5 in 18 decimals
        uint8 decimals = 6;

        uint256 resultCeilDiv = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(amount, decimals);
        uint256 resultNormal = TransferHelper.fixedToTokenNativeDecimals(amount, decimals);

        // ceilDiv: 1_500_000_000_000 / 10^12 = 1.5 -> rounds to 2
        // normal: 1_500_000_000_000 / 10^12 = 1.5 -> rounds to 1
        assertEq(resultCeilDiv, 2);
        assertEq(resultNormal, 1);

        // CeilDiv ensures the user gets at least the amount they should receive
        assertGt(resultCeilDiv, resultNormal);
    }
}
