// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SafeUnwindExerciseTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal unwindExerciseAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(bravo);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 0);

        _deposit(defaultPoolId, 2000 ether, bravo);

        _swap(defaultPoolId, 1000 ether, bravo);

        _giveAssets(address(corkAdapter));
    }

    // ================================ SAFE_UNWIND_EXERCISE TESTS ================================ //

    function test_safeUnwindExercise_ShouldWorkCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before swap
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after swap
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral + unwindExerciseAmount,
            "Contract should get correct amount of collateral assets"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef - unwindExerciseAmount,
            "Contract should send correct amount of reference assets"
        );
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeUnwindExercise_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: address(0),
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp - 1
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: address(0),
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: 0,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenSlippageExeceed()
        external
        __giveAssets(address(corkAdapter))
        __as(BUNDLER3_ADDRESS)
    {
        // When maxCollateralAssetsIn is too high
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount + 1,
                minReferenceAssetsOut: type(uint256).max,
                deadline: block.timestamp
            })
        );

        // When minReferenceAssetsOut is too low
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: 0,
                minReferenceAssetsOut: unwindExerciseAmount - 1,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4); // logical OR to enable the 5th bit

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenUnwindExercisesPaused() public __as(pauser) {
        defaultCorkController.pauseUnwindSwaps(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindExercise_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindExercise(
            ICorkAdapter.SafeUnwindExerciseParams({
                poolId: defaultPoolId,
                cstSharesOut: unwindExerciseAmount,
                receiver: alice,
                maxCollateralAssetsIn: unwindExerciseAmount,
                minReferenceAssetsOut: unwindExerciseAmount,
                deadline: block.timestamp
            })
        );
    }
}
