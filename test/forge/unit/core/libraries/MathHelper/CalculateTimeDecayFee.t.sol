// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateTimeDecayFeeTest is Test {
    // =============== calculateTimeDecayFee Tests ===============

    function test_calculateTimeDecayFee_StartOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At start with 1 unit elapsed: t = 0.999, feeFactor = 4.995%
        // fee = 1000 * 0.04995 = 49.95 ether
        assertEq(fee, 49.95 ether);
    }

    function test_calculateTimeDecayFee_MiddleOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 4 ether; // 4%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At middle: t = 0.5, feeFactor = 2%
        // fee = 1000 * 0.02 = 20 ether
        assertEq(fee, 20 ether);
    }

    function test_calculateTimeDecayFee_EndOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2000; // At end
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At end: t = 0, no fee
        assertEq(fee, 0);
    }

    function test_calculateTimeDecayFee_PastMaturity() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2500; // Past end
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Past maturity: t = 0, no fee
        assertEq(fee, 0);
    }

    function test_calculateTimeDecayFee_ZeroAmount() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 amount = 0;
        uint256 baseFeePercentage = 5 ether; // 5%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Zero amount case: fee should be 0
        assertEq(fee, 0);
    }

    function test_calculateTimeDecayFee_ZeroBaseFee() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 0; // 0%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Zero base fee: no fee regardless of time
        assertEq(fee, 0);
    }

    function test_calculateTimeDecayFee_RoundingCeil() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 amount = 999 wei;
        uint256 baseFeePercentage = 1 ether; // 1%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At middle: t = 0.5, feeFactor = 0.5%
        // fee = 999 * 0.005 = 4.995 wei, rounded up to 5 wei with ceil rounding
        assertEq(fee, 5 wei);
    }

    function test_calculateTimeDecayFee_minimumFee() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1999; // Almost the end of the period
        uint256 amount = 100 wei;
        uint256 baseFeePercentage = 1; // 0.0000...00001%

        uint256 fee = MathHelper.calculateTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At middle: t = 0.5, feeFactor = 0.5%
        // grossAmount = 100 / (1 - 0.0000...00001) = 100.000...0001 wei
        // With ceil rounding, this should round up to 101 wei
        // fee = assetIn - amount = 101 - 100 = 1 wei
        assertEq(fee, 1);
    }
}
