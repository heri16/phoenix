// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnpauseTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pause();
    }

    //------------------------------------- Tests for unpause ----------------------------------------//

    function test_UnpauseShouldRevertWhenCalledByNonManager() public __as(alice) {
        assertTrue(defaultCorkController.paused());

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.UNPAUSER_ROLE()
            )
        );
        defaultCorkController.unpause();
        assertTrue(defaultCorkController.paused());
    }

    function test_UnpauseShouldRevertWhenNotPaused() public __as(unpauser) {
        defaultCorkController.unpause();
        assertFalse(defaultCorkController.paused());

        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        defaultCorkController.unpause();

        assertFalse(defaultCorkController.paused());
    }

    function test_UnpauseShouldWorkCorrectly() public __as(unpauser) {
        assertTrue(defaultCorkController.paused());

        vm.expectEmit(false, false, false, true);
        emit PausableUpgradeable.Unpaused(unpauser);
        defaultCorkController.unpause();

        assertFalse(defaultCorkController.paused());
    }
}
