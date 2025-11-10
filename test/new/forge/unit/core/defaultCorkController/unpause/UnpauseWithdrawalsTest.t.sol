// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract UnpauseWithdrawalsTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pauseWithdrawals(defaultPoolId);
    }

    //------------------------------------- Tests for unpauseWithdrawals ----------------------------------------//
    function test_UnpauseWithdrawalsRevertWhenCalledByNonManager() public __as(alice) {
        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.DEFAULT_ADMIN_ROLE()));
        defaultCorkController.unpauseWithdrawals(defaultPoolId);

        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    function test_UnpauseWithdrawalsShouldWorkCorrectly() public __as(DEFAULT_ADDRESS) {
        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 0);
        defaultCorkController.unpauseWithdrawals(defaultPoolId);

        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
