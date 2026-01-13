// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnpauseUnwindSwapTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pauseUnwindSwaps(defaultPoolId);
    }

    //------------------------------------- Tests for unpauseunwindSwap ----------------------------------------//
    function test_UnpauseUnwindSwapsRevertWhenCalledByNonManager() public __as(alice) {
        assertTrue(defaultCorkController.isUnwindSwapPaused(defaultPoolId));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.UNPAUSER_ROLE()
            )
        );
        defaultCorkController.unpauseUnwindSwaps(defaultPoolId);

        assertTrue(defaultCorkController.isUnwindSwapPaused(defaultPoolId));
    }

    function test_UnpauseUnwindSwapsShouldWorkCorrectly() public __as(unpauser) {
        assertTrue(defaultCorkController.isUnwindSwapPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 0);
        defaultCorkController.unpauseUnwindSwaps(defaultPoolId);

        assertFalse(defaultCorkController.isUnwindSwapPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
