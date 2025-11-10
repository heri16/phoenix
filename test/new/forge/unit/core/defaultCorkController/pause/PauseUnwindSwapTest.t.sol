// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract PauseUnwindSwapTest is BaseTest {
    //------------------------------------- Tests for pauseunwindSwap ----------------------------------------//
    function test_PauseUnwindSwapsRevertWhenCalledByNonManager() public __as(alice) {
        assertFalse(defaultCorkController.isDepositPaused(defaultPoolId));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()));
        defaultCorkController.pauseUnwindSwaps(defaultPoolId);

        assertFalse(defaultCorkController.isDepositPaused(defaultPoolId));
    }

    function test_PauseUnwindSwapsShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.isUnwindSwapPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1 << 4);
        defaultCorkController.pauseUnwindSwaps(defaultPoolId);

        assertTrue(defaultCorkController.isUnwindSwapPaused(defaultPoolId));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(defaultPoolId, 0, address(8));
    }

    function test_PauseUnwindExerciseShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.isUnwindSwapPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1 << 4);
        defaultCorkController.pauseUnwindSwaps(defaultPoolId);

        assertTrue(defaultCorkController.isUnwindSwapPaused(defaultPoolId));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(defaultPoolId, 1, address(8));
    }

    //-----------------------------------------------------------------------------------------------------//
}
