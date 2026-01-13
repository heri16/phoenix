// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnpauseUnwindDepositAndMintTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pauseUnwindDepositAndMints(defaultPoolId);
    }

    //------------------------------------- Tests for unpauseUnwindDepositAndMints ----------------------------------------//
    function test_UnpauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public __as(alice) {
        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.UNPAUSER_ROLE()
            )
        );
        defaultCorkController.unpauseUnwindDepositAndMints(defaultPoolId);

        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));
    }

    function test_UnpauseUnwindDepositAndMintsShouldWorkCorrectly() public __as(unpauser) {
        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 0);
        defaultCorkController.unpauseUnwindDepositAndMints(defaultPoolId);

        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
