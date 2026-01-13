// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract AdjustedRateTests is BaseTest {
    function setUp() public override {
        DEFAULT_RATE_MIN = 0.9 ether;
        DEFAULT_RATE_MAX = 1.1 ether;
        DEFAULT_RATE_CHANGE_PER_DAY_MAX = 0.1 ether;
        DEFAULT_RATE_CHANGE_CAPACITY_MAX = 0.1 ether;
        super.setUp();
    }

    //------------------------------------------------------//
    //----------------------- Tests ------------------------//
    //------------------------------------------------------//
    function test_adjustedRate_shouldWorkCorrectly_withinCreditLimit() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 1.0005 ether);

        uint256 adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.assertEq(adjustedRate, 1.0005 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(_lastAdjustedRate, 1.0005 ether);
        vm.assertEq(_lastAdjustmentTimestamp, 1);
        vm.assertLt(_remainingCredits, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenExceedsCreditLimit() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 2 ether);
        // exhaust credits and go back to original 1
        uint256 adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(_remainingCredits, 0);

        testOracle.setRate(defaultPoolId, 1 ether);

        vm.warp(block.timestamp + 1 days);
        adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.warp(block.timestamp + 1 days / 100);
        testOracle.setRate(defaultPoolId, 1.1 ether);
        adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.assertEq(adjustedRate, 1.001 ether);

        (_lastAdjustedRate, _lastAdjustmentTimestamp, _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(_lastAdjustedRate, 1.001 ether);
        vm.assertEq(_remainingCredits, 0);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenHitMinBoundary() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 0.8 ether);

        uint256 adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.assertEq(adjustedRate, DEFAULT_RATE_MIN);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenHitMaxBoundary() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 1.2 ether);

        uint256 adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.assertEq(adjustedRate, DEFAULT_RATE_MAX);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenSameRate() external __as(address(corkPoolManager)) {
        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);

        uint256 adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.assertEq(adjustedRate, DEFAULT_ORACLE_RATE);

        (uint256 lastAdjustedRateAfter, uint256 lastAdjustmentTimestampAfter, uint256 remainingCreditsAfter) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(lastAdjustedRateAfter, _lastAdjustedRate);
        vm.assertEq(lastAdjustmentTimestampAfter, _lastAdjustmentTimestamp);
        vm.assertEq(remainingCreditsAfter, _remainingCredits);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenCreditRefillOverTime() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 1.1 ether);
        constraintRateAdapter.adjustedRate(defaultPoolId);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(_remainingCredits, 0);

        vm.warp(block.timestamp + 1 days);

        testOracle.setRate(defaultPoolId, 1.0015 ether);
        constraintRateAdapter.adjustedRate(defaultPoolId);

        (_lastAdjustedRate, _lastAdjustmentTimestamp, _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertGt(_remainingCredits, 0);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenMultipleRateChanges() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 1.03 ether);
        uint256 rate1 = constraintRateAdapter.adjustedRate(defaultPoolId);
        vm.assertEq(rate1, 1.03 ether);

        testOracle.setRate(defaultPoolId, 1.06 ether);
        uint256 rate2 = constraintRateAdapter.adjustedRate(defaultPoolId);
        vm.assertEq(rate2, 1.06 ether);

        testOracle.setRate(defaultPoolId, 1.11 ether);
        uint256 rate3 = constraintRateAdapter.adjustedRate(defaultPoolId);
        vm.assertEq(rate3, 1.1 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(_remainingCredits, 0);
    }

    function test_adjustedRate_shouldWorkCorrectly_whenDownwardRateChange() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 0.9995 ether);

        uint256 adjustedRate = constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.assertEq(adjustedRate, 0.9995 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) =
            constraintRateAdapter.constraints(defaultPoolId);
        vm.assertEq(_lastAdjustedRate, 0.9995 ether);
        vm.assertLt(_remainingCredits, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
    }

    function test_adjustedRate_shouldNotConsumeCredits_whenRateBelowMinimum() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 0.9 ether);

        // trigger update rate
        constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.warp(block.timestamp + 2 days);

        testOracle.setRate(defaultPoolId, 0.89 ether);

        // trigger update rate
        constraintRateAdapter.adjustedRate(defaultPoolId);

        (,, uint256 remainingCreditsBefore) = constraintRateAdapter.constraints(defaultPoolId);

        // trigger second update rate
        constraintRateAdapter.adjustedRate(defaultPoolId);

        (,, uint256 remainingCreditsAfter) = constraintRateAdapter.constraints(defaultPoolId);

        assertEq(remainingCreditsAfter, remainingCreditsBefore);
    }

    function test_adjustedRate_shouldNotConsumeCredits_whenRateAboveMaximum() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 1.1 ether);

        // trigger update rate
        constraintRateAdapter.adjustedRate(defaultPoolId);

        vm.warp(block.timestamp + 2 days);

        testOracle.setRate(defaultPoolId, 1.11 ether);

        // trigger update rate
        constraintRateAdapter.adjustedRate(defaultPoolId);

        (,, uint256 remainingCreditsBefore) = constraintRateAdapter.constraints(defaultPoolId);

        // trigger second update rate
        constraintRateAdapter.adjustedRate(defaultPoolId);

        (,, uint256 remainingCreditsAfter) = constraintRateAdapter.constraints(defaultPoolId);

        assertEq(remainingCreditsAfter, remainingCreditsBefore);
    }

    /// @dev using a state variable here to avoid --via-ir to optimize it away and cause a test error in test_adjustedRate_shouldNotChangeAdjustmentTimestamp_WhenNoRateChange
    uint256 storedTimestamp;

    function test_adjustedRate_shouldNotChangeAdjustmentTimestamp_WhenNoRateChange()
        external
        __as(address(corkPoolManager))
    {
        uint256 lastAdjustmentTimestamp = 0;
        testOracle.setRate(defaultPoolId, 1.01 ether);

        // Store in state to prevent optimizer rematerialization
        storedTimestamp = block.timestamp;

        constraintRateAdapter.adjustedRate(defaultPoolId);

        (, lastAdjustmentTimestamp,) = constraintRateAdapter.constraints(defaultPoolId);
        assertEq(lastAdjustmentTimestamp, storedTimestamp);

        vm.warp(block.timestamp + 2 days);

        constraintRateAdapter.adjustedRate(defaultPoolId);

        (, lastAdjustmentTimestamp,) = constraintRateAdapter.constraints(defaultPoolId);

        // Use the stored state variable
        assertEq(lastAdjustmentTimestamp, storedTimestamp);
    }

    function test_adjustedRate_shouldRevert_whenCalledByNonPoolAddress() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.adjustedRate(defaultPoolId);
    }

    function test_adjustedRate_shouldReturnRateMin_whenOracleReturnsZeroAnswer()
        external
        __as(address(corkPoolManager))
    {
        testOracle.setRate(defaultPoolId, 0);

        uint256 rateMin = constraintRateAdapter.adjustedRate(defaultPoolId);
        assertEq(rateMin, DEFAULT_RATE_MIN);
    }
}
