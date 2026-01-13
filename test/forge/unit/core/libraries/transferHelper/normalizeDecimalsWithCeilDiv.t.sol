// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";

contract NormalizeDecimalsWithCeilDivTest is Test {
    // =============== normalizeDecimalsWithCeilDiv Tests ===============

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenIncreasingDecimals() public pure {
        uint256 amount = 1000;
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        // 1000 * 10^(18-6) = 1000 * 10^12
        uint256 expected = 1000 * 1e12;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenDecreasingDecimals() public pure {
        uint256 amount = 1000 * 1e12;
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 1000 * 10^12 / 10^(18-6) = 1000 * 10^12 / 10^12 = 1000
        uint256 expected = 1000;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldDoNoOp_WhenSameDecimals() public pure {
        uint256 amount = 1000 ether;
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 18;
        uint256 expected = 1000 ether;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenDecimalsAre0() public pure {
        uint256 amount = 1000;
        uint8 decimalsBefore = 0;
        uint8 decimalsAfter = 18;
        uint256 expected = 1000 ether;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenZeroAmount() public pure {
        uint256 amount = 0;
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        uint256 expected = 0;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenConvertingFrom6To18Decimals() public pure {
        uint256 amount = 1000 * 1e6; // 1000 * 10^6
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        uint256 expected = 1000 ether; // 1000 * 10^18

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenConvertingFrom18To6Decimals() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        uint256 expected = 1000 * 1e6; // 1000 * 10^18 -> 1000 * 10^6 -> 1000000000

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenExactDivision() public pure {
        uint256 amount = 1000 * 1e12;
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        uint256 expected = 1000;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenLargeAmount() public pure {
        uint256 amount = 1_000_000 * 1e6; // 1 million USDC
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        uint256 expected = 1_000_000 ether;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldRoundUpCorrectly() public pure {
        uint256 amount = 1_234_567_890_123; // Amount with many digits
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 1_234_567_890_123 / 10^12 = 1.234567890123, rounded up to 2 with ceilDiv
        uint256 expected = 2;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_ShouldWorkCorrectly_WhenConvertingMinToMax() public pure {
        uint256 amount = 1;
        uint8 decimalsBefore = 0;
        uint8 decimalsAfter = 18;
        uint256 expected = 1 ether;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_CompareWithNormalizeDecimals() public pure {
        // Test case where ceilDiv makes a difference
        uint256 amount = 1500; // Amount that doesn't divide evenly
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;

        uint256 resultCeilDiv = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        uint256 resultNormal = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);

        // ceilDiv should round up, normal should round down
        // 1500 / 10^12 = 0.0000000015 -> ceilDiv rounds to 1, normal rounds to 0
        assertEq(resultCeilDiv, 1);
        assertEq(resultNormal, 0);
    }

    function test_normalizeDecimalsWithCeilDiv_EdgeCaseBoundary() public pure {
        uint256 amount = 999_999_999_999; // Just below 10^12
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 999_999_999_999 / 10^12 = 0.999999999999 -> ceilDiv rounds to 1
        uint256 expected = 1;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimalsWithCeilDiv_LargeNumberWithRemainder() public pure {
        uint256 amount = 5_555_555_555_555; // 5.555555555555 when divided by 10^12
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 5_555_555_555_555 / 10^12 = 5.555555555555 -> ceilDiv rounds to 6
        uint256 expected = 6;

        uint256 result = TransferHelper.normalizeDecimalsWithCeilDiv(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }
}
