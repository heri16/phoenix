// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Market} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PauseAllTest is BaseTest {
    //------------------------------------- Tests for pauseAll ----------------------------------------//
    function test_PauseAllRevertWhenCalledByNonPauser() public __as(alice) {
        // Should be unpaused by default
        assertFalse(corkPoolManager.paused());

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.PAUSER_ROLE()
            )
        );
        defaultCorkController.pauseAll();

        assertFalse(corkPoolManager.paused());
    }

    function test_PauseAllShouldWorkCorrectly() public __as(pauser) {
        // Should be unpaused by default
        assertFalse(corkPoolManager.paused());

        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Paused(address(defaultCorkController));
        defaultCorkController.pauseAll();

        assertTrue(corkPoolManager.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.createNewPool(
            Market({
                collateralAsset: address(collateralAsset),
                referenceAsset: address(referenceAsset),
                expiryTimestamp: 1 days,
                rateOracle: address(testOracle),
                rateMin: 0.9 ether,
                rateMax: 1.1 ether,
                rateChangePerDayMax: 1 ether,
                rateChangeCapacityMax: 1 ether
            })
        );

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
