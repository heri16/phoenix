// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract PreviewAdjustedRateTests is BaseTest {
    function test_previewAdjustedRate_shouldWorkCorrectly() external __as(address(corkPoolManager)) {
        testOracle.setRate(defaultPoolId, 1.0005 ether);

        uint256 previewRate = constraintRateAdapter.previewAdjustedRate(defaultPoolId);
        vm.assertEq(previewRate, 1.0005 ether);
    }

    function test_corkPool_shouldShowSameRateAsPreviewAdjustedRate() external __as(address(corkPoolManager)) {
        uint256 rate = corkPoolManager.swapRate(defaultPoolId);
        uint256 previewRate = constraintRateAdapter.previewAdjustedRate(defaultPoolId);

        vm.assertEq(rate, 1 ether);
        vm.assertEq(previewRate, 1 ether);

        testOracle.setRate(defaultPoolId, 0.9 ether);

        rate = corkPoolManager.swapRate(defaultPoolId);
        previewRate = constraintRateAdapter.previewAdjustedRate(defaultPoolId);

        vm.assertEq(rate, 0.9 ether);
        vm.assertEq(previewRate, 0.9 ether);
    }

    function test_previewAdjustedRate_shouldRevert_whenCalledByNonPoolAddress() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.previewAdjustedRate(defaultPoolId);
    }
}
