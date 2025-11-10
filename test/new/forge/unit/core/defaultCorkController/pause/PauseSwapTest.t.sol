// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract PauseSwapTest is BaseTest {
    //------------------------------------- Tests for pauseSwap ----------------------------------------//
    function test_PauseSwapRevertWhenCalledByNonManager() public __as(alice) {
        assertFalse(defaultCorkController.isSwapPaused(defaultPoolId));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()));
        defaultCorkController.pauseSwaps(defaultPoolId);

        assertFalse(defaultCorkController.isSwapPaused(defaultPoolId));
    }

    function test_PauseSwapShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.isSwapPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1 << 1);
        defaultCorkController.pauseSwaps(defaultPoolId);

        assertTrue(defaultCorkController.isSwapPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
