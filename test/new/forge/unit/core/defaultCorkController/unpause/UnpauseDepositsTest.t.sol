// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract UnpauseDepositsTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pauseDeposits(defaultPoolId);
    }

    //------------------------------------- Tests for unpauseDeposits ----------------------------------------//
    function test_UnpauseDepositsShouldRevertWhenCalledByNonManager() public __as(alice) {
        assertTrue(defaultCorkController.isDepositPaused(defaultPoolId));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.DEFAULT_ADMIN_ROLE()));
        defaultCorkController.unpauseDeposits(defaultPoolId);
    }

    function test_UnpauseDepositsShouldWorkCorrectly() public __as(DEFAULT_ADDRESS) {
        assertTrue(defaultCorkController.isDepositPaused(defaultPoolId));

        vm.expectEmit(true, false, false, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 0);
        defaultCorkController.unpauseDeposits(defaultPoolId);

        assertFalse(defaultCorkController.isDepositPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
