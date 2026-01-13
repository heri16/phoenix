// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";

contract NormalizeDecimalsTest is Test {
    // =============== normalizeDecimals Tests ===============

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenIncreasingDecimals() public pure {
        uint256 amount = 1000;
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        // 1000 * 10^(18-6) = 1000 * 10^12
        uint256 expected = 1000 * 1e12;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenDecreasingDecimals() public pure {
        uint256 amount = 1000 * 1e12;
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 1000 * 10^12 / 10^(18-6) = 1000 * 10^12 / 10^12 = 1000
        uint256 expected = 1000;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldDoNoOp_WhenSameDecimals() public pure {
        uint256 amount = 1000 ether;
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 18;
        uint256 expected = 1000 ether;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenDecimalsAre0() public pure {
        uint256 amount = 1000;
        uint8 decimalsBefore = 0;
        uint8 decimalsAfter = 18;
        uint256 expected = 1000 ether;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenConvertingFrom6To18Decimals() public pure {
        uint256 amount = 1000 * 1e6; // 1000 USDC
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        uint256 expected = 1000 ether; // 1000 * 10^18

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenConvertingFrom18To6Decimals() public pure {
        uint256 amount = 1000 ether; // 1000 * 10^18
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        uint256 expected = 1000 * 1e6; // 1000 USDC

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldRoundDown_WhenDecreasingDecimals() public pure {
        uint256 amount = 1001; // 1001 units with 18 decimals
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 1001 / 10^12 = 0.000000001001 = 0 (rounded down)
        uint256 expected = 0;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenExactDivision() public pure {
        uint256 amount = 1000 * 1e12;
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        uint256 expected = 1000;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenZeroAmount() public pure {
        uint256 amount = 0;
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        uint256 expected = 0;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenLargeAmount() public pure {
        uint256 amount = 1_000_000 * 1e6; // 1 million USDC
        uint8 decimalsBefore = 6;
        uint8 decimalsAfter = 18;
        uint256 expected = 1_000_000 ether;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenPrecisionLoss() public pure {
        uint256 amount = 1_234_567_890_123; // Amount with many digits
        uint8 decimalsBefore = 18;
        uint8 decimalsAfter = 6;
        // 1_234_567_890_123 / 10^12 = 1 (loses precision)
        uint256 expected = 1;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }

    function test_normalizeDecimals_ShouldWorkCorrectly_WhenConvertingMinToMax() public pure {
        uint256 amount = 1;
        uint8 decimalsBefore = 0;
        uint8 decimalsAfter = 18;
        uint256 expected = 1 ether;

        uint256 result = TransferHelper.normalizeDecimals(amount, decimalsBefore, decimalsAfter);
        assertEq(result, expected);
    }
}
