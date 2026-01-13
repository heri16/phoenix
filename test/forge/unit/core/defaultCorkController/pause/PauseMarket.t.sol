// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PauseMarketTest is BaseTest {
    //------------------------------------- Tests for pauseMarket ----------------------------------------//

    function test_PauseMarketShouldRevertWhenCalledByNonPauser() public __as(alice) {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()
            )
        );
        defaultCorkController.pauseMarket(defaultPoolId);
    }

    function test_PauseMarketShouldDisableAllPoolFunctions() public __as(pauser) {
        defaultCorkController.pauseMarket(defaultPoolId);

        assertTrue(defaultCorkController.isDepositPaused(defaultPoolId));
        assertTrue(defaultCorkController.isSwapPaused(defaultPoolId));
        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(defaultPoolId));
        assertTrue(defaultCorkController.isUnwindSwapPaused(defaultPoolId));
        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.mint(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.swap(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exerciseOther(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindDeposit(defaultPoolId, 1 ether, bravo, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindMint(defaultPoolId, 1 ether, bravo, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExerciseOther(defaultPoolId, 1 ether, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.redeem(defaultPoolId, 1 ether, bravo, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(defaultPoolId, 1 ether, bravo, bravo);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 1 ether, bravo, bravo);
    }

    //-----------------------------------------------------------------------------------------------------//
}
