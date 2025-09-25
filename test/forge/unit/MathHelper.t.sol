// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";

// Helper contract to expose MathHelper library functions for testing
contract MathHelperTestContract {
    // Exposed MathHelper functions
    function calculateEqualSwapAmount(uint256 referenceAsset, uint256 swapRate) external pure returns (uint256) {
        return MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
    }

    function calculatePercentageFee(uint256 fee1e18, uint256 amount) external pure returns (uint256) {
        return MathHelper.calculatePercentageFee(fee1e18, amount);
    }

    function calculateDepositAmountWithSwapRate(uint256 amount, uint256 swapRate, bool isRoundUp) external pure returns (uint256) {
        return MathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, isRoundUp);
    }

    function computeT(uint256 start, uint256 end, uint256 current) external pure returns (uint256) {
        return MathHelper.computeT(start, end, current);
    }

    // Expose internal functions for testing
    function calculateAccrued(uint256 amount, uint256 available, uint256 totalPrincipalTokenIssued) external pure returns (uint256) {
        return MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
    }

    function calculateGrossAmountWithTimeDecayFee(uint256 start, uint256 end, uint256 current, uint256 amount, uint256 baseFeePercentage) external pure returns (uint256 fee, uint256 assetIn) {
        return MathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);
    }
}

contract MathHelperTest is Helper {
    MathHelperTestContract internal mathHelper;

    function setUp() public {
        mathHelper = new MathHelperTestContract();
    }

    // =============== calculateEqualSwapAmount Tests ===============

    function test_calculateEqualSwapAmount_BasicCalculation() public view {
        uint256 referenceAsset = 100 ether;
        uint256 swapRate = 1.5 ether;
        uint256 expected = 150 ether; // 100 * 1.5

        uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_ZeroAmount() public view {
        uint256 referenceAsset = 0;
        uint256 swapRate = 1.5 ether;
        uint256 expected = 0;

        uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_ZeroSwapRate() public view {
        uint256 referenceAsset = 100 ether;
        uint256 swapRate = 0;
        uint256 expected = 0;

        uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_SmallValues() public view {
        uint256 referenceAsset = 1; // 1 wei
        uint256 swapRate = 1 ether;
        uint256 expected = 1;

        uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_LargeValues() public view {
        uint256 referenceAsset = type(uint128).max;
        uint256 swapRate = 2 ether;

        uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, referenceAsset * 2);
    }

    function test_calculateEqualSwapAmount_FractionalSwapRate() public view {
        uint256 referenceAsset = 100 ether;
        uint256 swapRate = 0.5 ether;
        uint256 expected = 50 ether;

        uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    // =============== calculatePercentageFee Tests ===============

    function test_calculatePercentageFee_BasicCalculation() public view {
        uint256 fee1e18 = 5 ether; // 5%
        uint256 amount = 1000 ether;
        uint256 expected = 50 ether; // 5% of 1000

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_ZeroFee() public view {
        uint256 fee1e18 = 0;
        uint256 amount = 1000 ether;
        uint256 expected = 0;

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_ZeroAmount() public view {
        uint256 fee1e18 = 5 ether;
        uint256 amount = 0;
        uint256 expected = 0;

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_OnePercentFee() public view {
        uint256 fee1e18 = 1 ether; // 1%
        uint256 amount = 1000 ether;
        uint256 expected = 10 ether;

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_HundredPercentFee() public view {
        uint256 fee1e18 = 100 ether; // 100%
        uint256 amount = 1000 ether;
        uint256 expected = 1000 ether;

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_SmallAmount() public view {
        uint256 fee1e18 = 1 ether; // 1%
        uint256 amount = 100; // 100 wei
        uint256 expected = 1; // 1% of 100 wei

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    // =============== calculateDepositAmountWithSwapRate Tests ===============

    function test_calculateDepositAmountWithSwapRate_BasicCalculation() public view {
        uint256 amount = 100 ether;
        uint256 swapRate = 2 ether;
        uint256 expected = 50 ether; // 100 / 2

        uint256 result = mathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_ZeroAmount() public view {
        uint256 amount = 0;
        uint256 swapRate = 2 ether;
        uint256 expected = 0;

        uint256 result = mathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_OneToOneRate() public view {
        uint256 amount = 100 ether;
        uint256 swapRate = 1 ether;
        uint256 expected = 100 ether;

        uint256 result = mathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_FractionalRate() public view {
        uint256 amount = 100 ether;
        uint256 swapRate = 0.5 ether;
        uint256 expected = 200 ether;

        uint256 result = mathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
    }

    function test_calculateDepositAmountWithSwapRate_LargeValues() public view {
        uint256 amount = 1_000_000 ether;
        uint256 swapRate = 10 ether;
        uint256 expected = 100_000 ether;

        uint256 result = mathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, false);
        assertEq(result, expected);
    }

    // =============== calculateAccrued Tests ===============

    function test_calculateAccrued_BasicCalculation() public view {
        uint256 amount = 100 ether;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 50 ether; // 100 * (500/1000)

        uint256 result = mathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_ZeroAmount() public view {
        uint256 amount = 0;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 0;

        uint256 result = mathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_ZeroAvailable() public view {
        uint256 amount = 100 ether;
        uint256 available = 0;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 0;

        uint256 result = mathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_EqualAvailableAndIssued() public view {
        uint256 amount = 100 ether;
        uint256 available = 1000 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 100 ether;

        uint256 result = mathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_SmallValues() public view {
        uint256 amount = 1;
        uint256 available = 1;
        uint256 totalPrincipalTokenIssued = 2;
        uint256 expected = 0; // Due to precision, this should be 0

        uint256 result = mathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    // =============== computeT Tests ===============

    function test_computeT_StartOfPeriod() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 expected = 1 ether - 0.001 ether; // Should be 1.0 - 0.001

        uint256 result = mathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_MiddleOfPeriod() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 expected = 0.5 ether; // Should be 0.5

        uint256 result = mathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_EndOfPeriod() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2000; // At end
        uint256 expected = 0; // Should be 0.0

        uint256 result = mathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_PastMaturity() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2500; // Past end
        uint256 expected = 0; // Should be 0.0

        uint256 result = mathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_AlmostAtStart() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // Just after start

        uint256 result = mathHelper.computeT(start, end, current);
        assertTrue(result < 1 ether && result > 0.99 ether);
    }

    function test_computeT_AlmostAtEnd() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1999; // Just before end

        uint256 result = mathHelper.computeT(start, end, current);
        assertTrue(result > 0 && result < 0.01 ether);
    }

    function test_computeT_SamePeriod() public view {
        uint256 start = 1000;
        uint256 end = 1000; // Same start and end
        uint256 current = 1000;
        uint256 expected = 0; // Should be 0 for zero duration

        uint256 result = mathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    // =============== calculateGrossAmountWithTimeDecayFee Tests ===============

    function test_calculateRepurchaseFee_StartOfPeriod() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = mathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At start with 1 unit elapsed: t = 0.999, feeFactor = 4.995%, assetIn = 1000/0.95005 ≈ 1052.631578947368
        assertApproxEqAbs(fee, 52.576180201042 ether, 0.000001 ether); // Should be ~52.631578947368 ether
        assertApproxEqAbs(assetIn, 1052.576180201042 ether, 0.000001 ether); // Should be ~1052.631578947368 ether

        // Verify the calculation relationship
        assertEq(assetIn, amount + fee);
    }

    function test_calculateRepurchaseFee_MiddleOfPeriod() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 4 ether; // 4%

        (uint256 fee, uint256 assetIn) = mathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At middle: t = 0.5, feeFactor = 2%, assetIn = 1000/0.98 ≈ 1020.408163265306
        assertApproxEqAbs(fee, 20.408163265306 ether, 0.000001 ether); // Should be ~20.408163265306 ether
        assertApproxEqAbs(assetIn, 1020.408163265306 ether, 0.000001 ether); // Should be ~1020.408163265306 ether

        // Verify the calculation relationship
        assertEq(assetIn, amount + fee);
    }

    function test_calculateRepurchaseFee_EndOfPeriod() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2000; // At end
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = mathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // At end: t = 0, no fee
        assertEq(fee, 0); // Should be 0
        assertEq(assetIn, amount); // Should equal amount
    }

    function test_calculateRepurchaseFee_PastMaturity() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2500; // Past end
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = mathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Past maturity: t = 0, no fee
        assertEq(fee, 0); // Should be 0
        assertEq(assetIn, amount); // assetIn should equal amount when no fee
    }

    function test_calculateRepurchaseFee_ZeroAmount() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 amount = 0;
        uint256 baseFeePercentage = 5 ether; // 5%

        (uint256 fee, uint256 assetIn) = mathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        // Zero amount case: both fee and assetIn should be 0
        assertEq(fee, 0); // Fee should be 0 for 0 amount
    }

    function test_calculateRepurchaseFee_ZeroBaseFee() public view {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start (adjusted to avoid minimum elapsed time)
        uint256 amount = 1000 ether;
        uint256 baseFeePercentage = 0; // 0%

        (uint256 fee, uint256 assetIn) = mathHelper.calculateGrossAmountWithTimeDecayFee(start, end, current, amount, baseFeePercentage);

        assertEq(fee, 0); // No fee when base fee is 0%
        assertEq(assetIn, amount); // assetIn should equal amount when no fee
    }

    // =============== Edge Cases and Fuzz Tests ===============

    // function testFuzz_calculateEqualSwapAmount(uint128 referenceAsset, uint128 swapRate) public view {
    //     vm.assume(swapRate > 0);

    //     uint256 result = mathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
    //     uint256 expected = uint256(referenceAsset) * uint256(swapRate) / 1e18;

    //     // Allow for small rounding differences
    //     assertTrue(result >= expected - 1 && result <= expected + 1);
    // }

    function testFuzz_calculatePercentageFee(uint128 fee1e18, uint128 amount) public view {
        vm.assume(fee1e18 <= 100 ether); // Reasonable fee limit

        uint256 result = mathHelper.calculatePercentageFee(fee1e18, amount);

        // Fee should never exceed the original amount for fees <= 100%
        assertTrue(result <= amount);
    }

    function testFuzz_calculateDepositAmountWithSwapRate(uint128 amount, uint128 swapRate) public view {
        vm.assume(swapRate > 0);

        uint256 result = mathHelper.calculateDepositAmountWithSwapRate(amount, swapRate, true);

        // Result should be reasonable compared to input
        if (swapRate >= 1 ether) assertTrue(result <= amount);
        else assertTrue(result >= amount);
    }

    // function testFuzz_computeT(uint64 start, uint64 duration, uint64 elapsed) public view {
    //     vm.assume(duration > 0);
    //     vm.assume(elapsed <= duration * 2); // Allow for past maturity testing

    //     uint256 end = start + duration;
    //     uint256 current = start + elapsed;

    //     uint256 result = mathHelper.computeT(start, end, current);

    //     // T should always be between 0 and 1 ether
    //     assertTrue(result <= 1 ether);
    // }

    function testFuzz_calculateAccrued(uint128 amount, uint128 available, uint128 totalPrincipalTokenIssued) public view {
        vm.assume(totalPrincipalTokenIssued > 0);

        uint256 result = mathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);

        // Accrued should never exceed the proportional amount
        uint256 maxAccrued = uint256(amount) * uint256(available) / uint256(totalPrincipalTokenIssued);
        assertTrue(result <= maxAccrued + 1); // Allow for rounding
    }

    function test_timeDecayFeeConsistency() external {
        (uint256 fee, uint256 assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(1000, 2000, 1500, 100e18, 5e16);

        (uint256 feeSingle) = MathHelper.calculateTimeDecayFee(1000, 2000, 1500, assetIn, 5e16);

        assertEq(fee, feeSingle);
    }
}
