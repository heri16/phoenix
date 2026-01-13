// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PauseUnwindDepositAndMintTest is BaseTest {
    //------------------------------------- Tests for pauseUnwindDepositAndMints ----------------------------------------//
    function test_PauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public __as(alice) {
        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()
            )
        );
        defaultCorkController.pauseUnwindDepositAndMints(defaultPoolId);

        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));
    }

    function test_PauseUnwindDepositAndMintsShouldWorkCorrectly() public __as(pauser) {
        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1 << 3);
        defaultCorkController.pauseUnwindDepositAndMints(defaultPoolId);

        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));
    }

    //-----------------------------------------------------------------------------------------------------//
}
