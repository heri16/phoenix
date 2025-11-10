// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateDepositAmountWithSwapRateTest is Test {
    // =============== calculateDepositAmountWithSwapRate Tests ===============

    function test_calculateDepositAmountWithSwapRate_BasicCalculation() public pure {
        uint256 amount = 100 ether;
        uint256 swapRate = 2 ether;
        uint256 expected = 50 ether; // 100 / 2

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
        result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_ZeroAmount() public pure {
        uint256 amount = 0;
        // Swap rate will not be zero in any case as it is not possible to have a swap rate of 0
        uint256 swapRate = 2 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
        result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_OneToOneRate() public pure {
        uint256 amount = 100 ether;
        uint256 swapRate = 1 ether;
        uint256 expected = 100 ether;

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
        result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_FractionalRate() public pure {
        uint256 amount = 100 ether;
        uint256 swapRate = 0.5 ether;
        uint256 expected = 200 ether;

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
        result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_LargeValues() public pure {
        uint256 amount = 1_000_000 ether;
        uint256 swapRate = 10 ether;
        uint256 expected = 100_000 ether;

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
        result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_RoundingUp() public pure {
        uint256 amount = 12_345 wei;
        uint256 swapRate = 2 ether;
        // First 12345 wei * 1 ether = 12345 ether
        // then 12345 ether / 2 ether = 6172.5 wei, rounded up to 6173 wei as we are using ceil rounding
        uint256 expected = 6173 wei;

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_RoundingDown() public pure {
        uint256 amount = 2 wei;
        uint256 swapRate = 0.499_999_999_999_999_999 ether;
        // First 2 wei * 1 ether = 2 ether
        // then 2 ether / 0.499999999999999999 ether = 4.000000000000000004 wei, rounded down to 4 wei as we are using floor rounding
        uint256 expected = 4 wei;

        uint256 result = MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
    }
}
