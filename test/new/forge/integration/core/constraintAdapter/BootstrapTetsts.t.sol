// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract BootstrapTests is BaseTest {
    function test_bootstrap_shouldSetParametersCorrectly() external {
        (uint256 _lastAdjustedRate, uint256 _lastAdjustmentTimestamp, uint256 _remainingCredits) = constraintRateAdapter.constraints(defaultPoolId);

        vm.assertEq(_lastAdjustedRate, DEFAULT_ORACLE_RATE);
        vm.assertEq(_lastAdjustmentTimestamp, block.timestamp);
        vm.assertEq(_remainingCredits, defaultRateChangeCapacityMax());
    }

    function test_bootstrap_shouldRevert_whenCalledByNonPoolAddress() external {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.bootstrap(defaultPoolId);
    }
}
