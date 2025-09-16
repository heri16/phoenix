pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IConstraintAdapter} from "contracts/interfaces/IConstraintAdapter.sol";

import {Helper} from "test/forge/Helper.sol";

contract RateUpdateTest is Helper {
    function setUp() external {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        createMarket(10 days);
        vm.startPrank(address(corkPool));
    }

    function defaultRateMin() internal pure override returns (uint256) {
        return 0.9 ether;
    }

    function defaultRateMax() internal pure override returns (uint256) {
        return 1.1 ether;
    }

    function defaultRateChangePerDayMax() internal pure override returns (uint256) {
        return 0.1 ether;
    }

    function defaultRateChangeCapacityMax() internal pure override returns (uint256) {
        return 0.1 ether;
    }

    function test_shouldUpdateRateDownCorrectly() external {
        uint256 rate = corkPool.swapRate(defaultCurrencyId);

        vm.assertEq(rate, 1 ether);

        testOracle.setRate(defaultCurrencyId, 0.9 ether);

        rate = corkPool.swapRate(defaultCurrencyId);

        vm.assertEq(rate, 0.9 ether);
    }

    function test_constraintAdapter_bootstrap() external {
        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);

        vm.assertEq(_lastAdjustedRate, DEFAULT_ORACLE_RATE);
        vm.assertEq(_lastAdjustmentTimestamp, block.timestamp);
        vm.assertEq(_remainingCredits, defaultRateChangeCapacityMax());
    }

    function test_constraintAdapter_adjustedRate_withinCreditLimit() external {
        testOracle.setRate(defaultCurrencyId, 1.0005 ether);

        uint256 adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.assertEq(adjustedRate, 1.0005 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_lastAdjustedRate, 1.0005 ether);
        vm.assertLt(_remainingCredits, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
    }

    function test_constraintAdapter_adjustedRate_exceedsCreditLimit() external {
        testOracle.setRate(defaultCurrencyId, 2 ether);
        // exhaust credits and go back to original 1
        uint256 adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_remainingCredits, 0);

        testOracle.setRate(defaultCurrencyId, 1 ether);

        vm.warp(block.timestamp + 1 days);
        adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.warp(block.timestamp + 1 days / 100);
        testOracle.setRate(defaultCurrencyId, 1.1 ether);
        adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.assertEq(adjustedRate, 1.001 ether);

        (_lastAdjustedRate, _lastAdjustmentTimestamp, _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_lastAdjustedRate, 1.001 ether);
        vm.assertEq(_remainingCredits, 0);
    }

    function test_constraintAdapter_adjustedRate_hitMinBoundary() external {
        testOracle.setRate(defaultCurrencyId, 0.8 ether);

        uint256 adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.assertEq(adjustedRate, DEFAULT_RATE_MIN);
    }

    function test_constraintAdapter_adjustedRate_hitMaxBoundary() external {
        testOracle.setRate(defaultCurrencyId, 1.2 ether);

        uint256 adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.assertEq(adjustedRate, DEFAULT_RATE_MAX);
    }

    function test_constraintAdapter_adjustedRate_noChangeWhenSameRate() external {
        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);

        uint256 adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.assertEq(adjustedRate, DEFAULT_ORACLE_RATE);

        (uint256 __lastAdjustedRate, uint256 __lastAdjustmentTimestamp, uint256 after_remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(after_remainingCredits, _remainingCredits);
    }

    function test_constraintAdapter_creditRefillOverTime() external {
        testOracle.setRate(defaultCurrencyId, 1.1 ether);
        constraintAdapter.adjustedRate(defaultCurrencyId);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_remainingCredits, 0);

        vm.warp(block.timestamp + 1 days);

        testOracle.setRate(defaultCurrencyId, 1.0015 ether);
        constraintAdapter.adjustedRate(defaultCurrencyId);

        (_lastAdjustedRate, _lastAdjustmentTimestamp, _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertGt(_remainingCredits, 0);
    }

    function test_constraintAdapter_previewAdjustedRate() external {
        testOracle.setRate(defaultCurrencyId, 1.0005 ether);

        uint256 previewRate = constraintAdapter.previewAdjustedRate(defaultCurrencyId);
        vm.assertEq(previewRate, 1.0005 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_remainingCredits, defaultRateChangeCapacityMax());
    }

    function test_constraintAdapter_onlyCorkPoolModifier() external {
        vm.stopPrank();
        vm.startPrank(address(0x123));

        vm.expectRevert();
        constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.expectRevert();
        constraintAdapter.previewAdjustedRate(defaultCurrencyId);

        vm.expectRevert();
        constraintAdapter.bootstrap(defaultCurrencyId);
    }

    function test_constraintAdapter_multipleRateChanges() external {
        testOracle.setRate(defaultCurrencyId, 1.03 ether);
        uint256 rate1 = constraintAdapter.adjustedRate(defaultCurrencyId);
        vm.assertEq(rate1, 1.03 ether);

        testOracle.setRate(defaultCurrencyId, 1.06 ether);
        uint256 rate2 = constraintAdapter.adjustedRate(defaultCurrencyId);
        vm.assertEq(rate2, 1.06 ether);

        testOracle.setRate(defaultCurrencyId, 1.11 ether);
        uint256 rate3 = constraintAdapter.adjustedRate(defaultCurrencyId);
        vm.assertEq(rate3, 1.1 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_remainingCredits, 0);
    }

    function test_constraintAdapter_downwardRateChange() external {
        testOracle.setRate(defaultCurrencyId, 0.9995 ether);

        uint256 adjustedRate = constraintAdapter.adjustedRate(defaultCurrencyId);

        vm.assertEq(adjustedRate, 0.9995 ether);

        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintAdapter.constraints(defaultCurrencyId);
        vm.assertEq(_lastAdjustedRate, 0.9995 ether);
        vm.assertLt(_remainingCredits, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
    }
}
