// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateGrossAmountWithTimeDecayFeeTest is Test {
    // =============== calculateGrossAmountWithTimeDecayFee Tests ===============

    function test_calculateGrossAmountWithTimeDecayFee_BasicFunctionality() public pure {
        uint256 start = 0;
        uint256 end = 1 days;
        uint256 current = 0.9 days; // At start
        uint256 amount = 999;
        uint256 baseFeePercentage = 1 ether; // 1%

        (uint256 fee,) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // atleast 1 wei of fee
        assertEq(1, fee);
    }

    function test_calculateGrossAmountWithTimeDecayFee_StartOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At start with 1 unit elapsed: t = 0.999, feeFactor = 4.995%, assetIn = 1000/0.95005 ≈ 1052.631578947368
        assertApproxEqAbs(fee, 52.576_180_201_042 ether, 0.000_001 ether); // Should be ~52.631578947368 ether
        assertApproxEqAbs(assetIn, 1052.576_180_201_042 ether, 0.000_001 ether); // Should be ~1052.631578947368 ether

        // Verify the calculation relationship
        assertEq(assetIn, amount + fee);
    }

    function test_calculateGrossAmountWithTimeDecayFee_MiddleOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 4 ether; // 4%

        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At middle: t = 0.5, feeFactor = 2%, assetIn = 1000/0.98 ≈ 1020.408163265306
        assertApproxEqAbs(fee, 20.408_163_265_306 ether, 0.000_001 ether); // Should be ~20.408163265306 ether
        assertApproxEqAbs(assetIn, 1020.408_163_265_306 ether, 0.000_001 ether); // Should be ~1020.408163265306 ether

        // Verify the calculation relationship
        assertEq(assetIn, amount + fee);
    }

    function test_calculateGrossAmountWithTimeDecayFee_EndOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2000; // At end
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At end: t = 0, no fee
        assertEq(fee, 0); // Should be 0
        assertEq(assetIn, amount); // Should equal amount
    }

    function test_calculateGrossAmountWithTimeDecayFee_PastMaturity() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2500; // Past end
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Past maturity: t = 0, no fee
        assertEq(fee, 0); // Should be 0
        assertEq(assetIn, amount); // assetIn should equal amount when no fee
    }

    function test_calculateGrossAmountWithTimeDecayFee_ZeroAmount() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 amount = 0;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee,) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Zero amount case: both fee and assetIn should be 0
        assertEq(fee, 0); // Fee should be 0 for 0 amount
    }

    function test_calculateGrossAmountWithTimeDecayFee_ZeroBaseFee() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start (adjusted to avoid minimum elapsed time)
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 0; // 0%

        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        assertEq(fee, 0); // No fee when base fee is 0%
        assertEq(assetIn, amount); // assetIn should equal amount when no fee
    }

    function test_calculateGrossAmountWithTimeDecayFee_RoundingCeil() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway through the period
        uint256 amount = 999 wei;
        uint256 baseFeePercentage = 1 ether; // 1%

        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At middle: t = 0.5, feeFactor = 0.5%
        // grossAmount = 999 / (1 - 0.005) = 999 / 0.995 = 1004.020100502512562814 wei
        // With ceil rounding, this should round up to 1005 wei
        // fee = assetIn - amount = 1005 - 999 = 6 wei
        assertEq(assetIn, 1005 wei);
        assertEq(fee, 6 wei);
    }
}
