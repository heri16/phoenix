// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract PauseWithdrawalsTest is BaseTest {
    //------------------------------------- Tests for pauseWithdrawals ----------------------------------------//
    function test_PauseWithdrawalsRevertWhenCalledByNonManager() public __as(alice) {
        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()));
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    function test_PauseWithdrawalsShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1 << 2);
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
