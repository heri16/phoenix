// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SafeExerciseOtherTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal exerciseAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(bravo);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        _deposit(defaultPoolId, 2000 ether, bravo);

        swapToken.transfer(address(corkAdapter), exerciseAmount);

        _giveAssets(address(corkAdapter));
    }

    // ================================ SAFE_EXERCISE_OTHER TESTS ================================ //

    function test_safeExerciseOther_ShouldWorkCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before swap
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after swap
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral - exerciseAmount,
            "Contract should sent correct amount of collateral assets"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef + exerciseAmount,
            "Contract should take correct amount of reference assets"
        );
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeExerciseOther_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: address(0),
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp - 1
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: address(0),
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: 0,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenSlippageExeceed()
        external
        __giveAssets(address(corkAdapter))
        __as(BUNDLER3_ADDRESS)
    {
        // When minCollateralAssetsOut is too high
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount + 1,
                maxCstSharesIn: type(uint256).max,
                deadline: block.timestamp
            })
        );

        // When maxCstSharesIn is too low
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: 0,
                maxCstSharesIn: exerciseAmount - 1,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, (1 << 1)); // logical OR to enable the 2nd bit

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenExercisesPaused() public __as(pauser) {
        defaultCorkController.pauseSwaps(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeExerciseOther_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeExerciseOther(
            ICorkAdapter.SafeExerciseOtherParams({
                poolId: defaultPoolId,
                referenceAssetsIn: exerciseAmount,
                receiver: alice,
                minCollateralAssetsOut: exerciseAmount,
                maxCstSharesIn: exerciseAmount,
                deadline: block.timestamp
            })
        );
    }
}
