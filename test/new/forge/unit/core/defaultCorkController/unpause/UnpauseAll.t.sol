// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {Market} from "contracts/libraries/Market.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract UnpauseAllTest is BaseTest {
    function setUp() public override {
        super.setUp();

        overridePrank(pauser);
        defaultCorkController.pauseAll();
    }

    //------------------------------------- Tests for unpauseAll ----------------------------------------//
    function test_UnpauseAllShouldRevertWhenCalledByNonDefaultAdmin() public __as(alice) {
        // Should be paused by default
        assertTrue(corkPoolManager.paused());

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.DEFAULT_ADMIN_ROLE()));
        defaultCorkController.unpauseAll();

        assertTrue(corkPoolManager.paused());
    }

    function test_UnpauseAllShouldWorkCorrectly() public __as(DEFAULT_ADDRESS) {
        // Should be paused by default
        assertTrue(corkPoolManager.paused());

        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Unpaused(address(defaultCorkController));
        defaultCorkController.unpauseAll();

        assertFalse(corkPoolManager.paused());

        // Create new pool should work
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams({
                pool: Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 2 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 1 ether, rateChangeCapacityMax: 1 ether}),
                unwindSwapFeePercentage: 0,
                swapFeePercentage: 0,
                isWhitelistEnabled: false
            })
        );

        overridePrank(alice);
        vm.deal(alice, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Deposit should work
        corkPoolManager.deposit(defaultPoolId, 1000 ether, alice);

        // Mint should work
        corkPoolManager.mint(defaultPoolId, 1000 ether, alice);

        // Swap should work
        corkPoolManager.swap(defaultPoolId, 1 ether, alice);

        // Exercise should work
        corkPoolManager.exercise(defaultPoolId, 1 ether, alice);

        // Exercise other should work
        corkPoolManager.exerciseOther(defaultPoolId, 1 ether, alice);

        // Unwind deposit should work
        corkPoolManager.unwindDeposit(defaultPoolId, 1 ether, alice, alice);

        // Unwind mint should work
        corkPoolManager.unwindMint(defaultPoolId, 1 ether, alice, alice);

        // Unwind swap should work
        corkPoolManager.unwindSwap(defaultPoolId, 1 ether, alice);

        // Unwind exercise should work
        corkPoolManager.unwindExercise(defaultPoolId, 1 ether, alice);

        // Unwind exercise other should work
        corkPoolManager.unwindExerciseOther(defaultPoolId, 1 ether, alice);

        // Fast forward to expiry
        vm.warp(block.timestamp + 2 days);

        // Withdraw should work
        corkPoolManager.withdraw(defaultPoolId, 0.01 ether, alice, alice);

        // Withdraw other should work
        corkPoolManager.withdrawOther(defaultPoolId, 0.01 ether, alice, alice);
    }
    //-----------------------------------------------------------------------------------------------------//
}
