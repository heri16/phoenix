// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract PauseTest is BaseTest {
    //------------------------------------- Tests for pause ----------------------------------------//
    function test_PauseShouldRevertWhenCalledByNonManager() public __as(alice) {
        assertFalse(defaultCorkController.paused());

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()));
        defaultCorkController.pause();

        assertFalse(defaultCorkController.paused());
    }

    function test_PauseShouldRevertWhenAlreadyPaused() public __as(pauser) {
        defaultCorkController.pause();
        assertTrue(defaultCorkController.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        defaultCorkController.pause();

        assertTrue(defaultCorkController.paused());
    }

    function test_PauseShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.paused());

        vm.expectEmit(false, false, false, true);
        emit PausableUpgradeable.Paused(pauser);
        defaultCorkController.pause();

        assertTrue(defaultCorkController.paused());
    }

    //-----------------------------------------------------------------------------------------------------//
}
