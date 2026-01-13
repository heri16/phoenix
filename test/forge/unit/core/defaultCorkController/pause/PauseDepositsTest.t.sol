// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PauseDepositsTest is BaseTest {
    //------------------------------------- Tests for pauseDeposits ----------------------------------------//
    function test_PauseDepositsRevertWhenCalledByNonManager() public __as(alice) {
        assertFalse(defaultCorkController.isDepositPaused(defaultPoolId));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()
            )
        );
        defaultCorkController.pauseDeposits(defaultPoolId);

        assertFalse(defaultCorkController.isDepositPaused(defaultPoolId));
    }

    function test_PauseDepositsShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.isDepositPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1);
        defaultCorkController.pauseDeposits(defaultPoolId);

        assertTrue(defaultCorkController.isDepositPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
