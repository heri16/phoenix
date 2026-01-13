// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnpauseSwapTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pauseSwaps(defaultPoolId);
    }

    //------------------------------------- Tests for unpauseSwap ----------------------------------------//
    function test_UnpauseSwapRevertWhenCalledByNonManager() public __as(alice) {
        assertTrue(defaultCorkController.isSwapPaused(defaultPoolId));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.UNPAUSER_ROLE()
            )
        );
        defaultCorkController.unpauseSwaps(defaultPoolId);

        assertTrue(defaultCorkController.isSwapPaused(defaultPoolId));
    }

    function test_UnpauseSwapShouldWorkCorrectly() public __as(unpauser) {
        assertTrue(defaultCorkController.isSwapPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 0);
        defaultCorkController.unpauseSwaps(defaultPoolId);

        assertFalse(defaultCorkController.isSwapPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
