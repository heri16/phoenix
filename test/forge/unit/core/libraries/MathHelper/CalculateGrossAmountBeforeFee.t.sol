// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateGrossAmountBeforeFeeTest is Test {
    // =============== calculateGrossAmountBeforeFee Tests ===============

    function test_calculateGrossAmountBeforeFee_BasicCalculation() public pure {
        uint256 desiredAmount = 100 ether;
        uint256 feeRate = 5 ether; // 5%
        // grossAmount = 100 / (1 - 0.05) = 100 / 0.95 = 105.263157894736842105 ether, rounded up to 105.263157894736842106 ether
        uint256 expected = 105.263_157_894_736_842_106 ether;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_ZeroDesiredAmount() public pure {
        uint256 desiredAmount = 0;
        uint256 feeRate = 5 ether; // 5%
        uint256 expected = 0;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_ZeroFeeRate() public pure {
        uint256 desiredAmount = 100 ether;
        uint256 feeRate = 0; // 0%
        uint256 expected = 100 ether; // No fee, so gross = desired

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_OnePercentFee_WithRoundingCeil() public pure {
        uint256 desiredAmount = 1000 ether;
        uint256 feeRate = 1 ether; // 1%
        // grossAmount = 1000 / 0.99 = 1010.101010101010101010 ether, rounded up to 1010.101010101010101011 ether
        uint256 expected = 1010.101_010_101_010_101_011 ether;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_SmallAmount() public pure {
        uint256 desiredAmount = 100 wei;
        uint256 feeRate = 1 ether; // 1%
        // grossAmount = 100 wei / 0.99 = 101.010101010101010101 wei, rounded up to 102 wei as we are using ceil rounding
        uint256 expected = 102 wei;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_LargeAmount() public pure {
        uint256 desiredAmount = 1_000_000 ether;
        uint256 feeRate = 5 ether; // 5%
        // grossAmount = 1000000 / 0.95 = 1052631.578947368421052631 ether, rounded up to 1052631.578947368421052632 ether
        uint256 expected = 1_052_631.578_947_368_421_052_632 ether;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_FractionalFeeRate() public pure {
        uint256 desiredAmount = 1000 ether;
        uint256 feeRate = 2.5 ether; // 2.5%
        // grossAmount = 1000 / 0.975 = 1025.641025641025641025 ether, rounded up to 1025.641025641025641026 ether
        uint256 expected = 1025.641_025_641_025_641_026 ether;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_VerySmallFeeRate() public pure {
        uint256 desiredAmount = 1000 ether;
        uint256 feeRate = 0.01 ether; // 0.01%
        // grossAmount = 1000 / 0.9999 = 1000.100010001000100010 ether, rounded up to 1000.100010001000100011 ether
        uint256 expected = 1000.100_010_001_000_100_011 ether;

        uint256 result = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        assertEq(result, expected);
    }

    function test_calculateGrossAmountBeforeFee_VerifyInverseFeeCalculation() public pure {
        uint256 desiredAmount = 1000 ether;
        uint256 feeRate = 5 ether; // 5%

        uint256 grossAmount = MathHelper.calculateGrossAmountBeforeFee(desiredAmount, feeRate);
        // Now calculate the fee from grossAmount and verify it gives us back the desiredAmount
        uint256 fee = MathHelper.calculatePercentageFee(feeRate, grossAmount);
        uint256 netAmount = grossAmount - fee;

        // The net amount should be equal to or very close to the desired amount
        // Due to rounding (ceil on gross, ceil on fee), we might be slightly over
        assertGe(netAmount, desiredAmount);
        // But should be within 1 wei tolerance due to rounding
        assertApproxEqAbs(netAmount, desiredAmount, 1);
    }
}
