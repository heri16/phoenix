// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";

contract TokenNativeDecimalsToFixedTest is Test {
    // =============== tokenNativeDecimalsToFixed Tests ===============

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly() public pure {
        uint256 amount = 1000 * 1e6; // 1000 USDC (6 decimals)
        uint8 decimals = 6;
        uint256 expected = 1000 ether; // 1000 * 10^18

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldDoNoOp_WhenExactly18Decimals() public pure {
        uint256 amount = 1000 ether; // Already 18 decimals
        uint8 decimals = 18;
        uint256 expected = 1000 ether;

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenDecimalsAreLessThan18() public pure {
        uint256 amount = 1000 * 1e8; // 1000 with 8 decimals (like WBTC)
        uint8 decimals = 8;
        uint256 expected = 1000 * 1e18; // 1000 * 10^18

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenDecimalsAreGreaterThan18() public pure {
        uint256 amount = 1000; // 1000 with 0 decimals
        uint8 decimals = 20;
        uint256 expected = 10; // 1000 * 10^20 -> 1000 / 10^2 -> 1000 / 100 -> 10

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenDecimalsAre0() public pure {
        uint256 amount = 1000; // 1000 with 0 decimals
        uint8 decimals = 0;
        uint256 expected = 1000 ether; // 1000 * 10^18

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenLargeAmount() public pure {
        uint256 amount = 1_000_000 * 1e6; // 1 million USDC
        uint8 decimals = 6;
        uint256 expected = 1_000_000 ether;

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenSmallAmount() public pure {
        uint256 amount = 1 * 1e6; // 1 USDC
        uint8 decimals = 6;
        uint256 expected = 1 ether;

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenZeroAmount() public pure {
        uint256 amount = 0;
        uint8 decimals = 6;
        uint256 expected = 0;

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenVerySmallAmount() public pure {
        uint256 amount = 1; // 1 wei equivalent in 6 decimals
        uint8 decimals = 6;
        uint256 expected = 1e12; // 10^12 wei

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }

    function test_tokenNativeDecimalsToFixed_ShouldWorkCorrectly_WhenDecimalConversionAccuracy() public pure {
        uint256 amount = 123_456_789; // 123.456789 USDC
        uint8 decimals = 6;
        uint256 expected = 123_456_789 * 1e12; // Convert to 18 decimals

        uint256 result = TransferHelper.tokenNativeDecimalsToFixed(amount, decimals);
        assertEq(result, expected);
    }
}
