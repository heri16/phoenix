// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract ExerciseOtherTests is BaseTest {
    uint256 constant EXPIRY = 1 days;
    uint256 depositAmount = 1000 ether;
    uint256 exerciseCompensation = 100 ether;

    // ================================ Basic ExerciseOther Tests ================================ //

    function test_exerciseOther_ShouldWorkWithCompensation() external __as(alice) __deposit(depositAmount, alice) {
        // Get state before exercise
        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        // Preview to get expected values
        (uint256 expectedAssets, uint256 expectedOtherSpent, uint256 expectedFee) = corkPoolManager.previewExerciseOther(defaultPoolId, exerciseCompensation);

        // Expect both PoolSwap and ERC4626-compatible deposit events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(defaultPoolId, alice, alice, expectedAssets, exerciseCompensation, 0, 0, false);
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolFee(defaultPoolId, alice, expectedFee, 0);
        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.Withdraw(alice, alice, alice, expectedAssets + expectedFee, 0);
        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.DepositOther(alice, alice, address(referenceAsset), exerciseCompensation, 0);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);

        // Get state after exercise
        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        // Verify return values
        assertEq(assets, 99 ether, "Should receive collateral assets");
        assertEq(otherAssetSpent, 100 ether, "Should spend reference assets");
        assertEq(fee, 1 ether, "Should have exact fee");

        // Verify user asset balance changes
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");
        assertEq(before.userSwapToken - _after.userSwapToken, otherAssetSpent, "User spend swap token balance ");

        // Verify contract asset balance changes
        assertEq(before.contractCollateral - _after.contractCollateral, assets + fee, "Contract should transfer collateral + fee");
        assertEq(_after.contractRef - before.contractRef, otherAssetSpent, "Contract should receive reference assets");

        // Verify pool internal state changes
        assertEq(_after.internalState.pool.balances.referenceAssetBalance - before.internalState.pool.balances.referenceAssetBalance, otherAssetSpent, "Pool reference asset balance should increase");
        assertEq(before.internalState.pool.balances.collateralAsset.locked - _after.internalState.pool.balances.collateralAsset.locked, assets + fee, "Pool locked collateral should decrease by assets + fee");

        uint256 treasuryBalance = collateralAsset.balanceOf(CORK_PROTOCOL_TREASURY);
        assertEq(treasuryBalance, fee, "Treasury should receive fee");
    }

    // ================================ Negative Tests Cases ================================ //

    function test_exerciseOther_ShouldRevertIfNotEnoughLiquidityForFee() external __as(alice) __deposit(1 ether, alice) {
        uint256 exerciseCompensationLarge = 10 ether;

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensationLarge, alice);
    }

    function test_exerciseOther_ShouldRevertIfUninitialized() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.exerciseOther(MarketId.wrap(bytes32(uint256(1))), 1 ether, alice);
    }

    function test_exerciseOther_ShouldRevert_WhenCompensationAmountIsZero() external __as(alice) __deposit(depositAmount, alice) {
        vm.expectPartialRevert(IErrors.InvalidParams.selector);
        corkPoolManager.exerciseOther(defaultPoolId, 0, alice);
    }

    function test_exerciseOther_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectPartialRevert(IErrors.Expired.selector);
        corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);
    }

    function test_exerciseOther_ShouldRevert_WhenPaused() external __as(alice) __deposit(depositAmount, alice) {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        overridePrank(alice);
        vm.expectPartialRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);
    }

    function test_exerciseOther_ShouldRevert_WhenGloballyPaused() external __as(alice) __deposit(depositAmount, alice) {
        // Pause globally
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectPartialRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);
    }

    function test_exerciseOther_ShouldRevert_WhenInsufficientReferenceAllowance() external __as(alice) __deposit(depositAmount, alice) {
        // Reset allowance to insufficient amount
        referenceAsset.approve(address(corkPoolManager), exerciseCompensation - 1);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);
    }

    function test_exerciseOther_ShouldRevert_WhenInsufficientReferenceBalance() external __as(alice) __deposit(depositAmount, alice) {
        // Transfer away most reference assets
        uint256 userBalance = referenceAsset.balanceOf(alice);
        referenceAsset.transfer(bob, userBalance - exerciseCompensation + 1);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);
    }

    function test_previewExerciseOther_ShouldRevertIfUninitialized() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.previewExerciseOther(MarketId.wrap(bytes32(uint256(1))), 1 ether);
    }

    function test_maxExerciseOther_ShouldRevertIfUninitialized() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxExerciseOther(MarketId.wrap(bytes32(uint256(1))), alice);
    }

    // ================================ Preview ExerciseOther Tests ================================ //

    function test_previewExerciseOther_ShouldReturnCorrectAmounts() external {
        uint256 compensation = exerciseCompensation;
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.previewExerciseOther(defaultPoolId, compensation);

        assertEq(assets, 99 ether, "Should receive collateral assets");
        assertEq(otherAssetSpent, 100 ether, "Should spend reference assets");
        assertEq(fee, 1 ether, "Should have exact fee");
    }

    function test_previewExerciseOther_ShouldReturnSameValueAsPoolManager() external __as(alice) __deposit(depositAmount, alice) {
        // exercise first so that it won't return 0
        corkPoolManager.exerciseOther(defaultPoolId, 10 ether, alice);

        uint256 compensation = 50 ether;
        (uint256 poolManagerAssets, uint256 poolManagerOtherAssetSpent, uint256 poolManagerFee) = corkPoolManager.previewExerciseOther(defaultPoolId, compensation);
        (uint256 poolShareAssets, uint256 poolShareOtherAssetSpent, uint256 poolShareFee) = PoolShare(swapToken).previewExerciseOther(compensation);

        assertEq(poolShareAssets, poolManagerAssets, "PoolShare previewExerciseOther assets should match PoolManager previewExerciseOther");
        assertEq(poolShareOtherAssetSpent, poolManagerOtherAssetSpent, "PoolShare previewExerciseOther otherAssetSpent should match PoolManager previewExerciseOther");
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewExerciseOther fee should match PoolManager previewExerciseOther");
    }

    // ================================ Max ExerciseOther Tests ================================ //

    function test_maxExerciseOther_ShouldReturnMaxAmountCorrectly() external __as(alice) __deposit(depositAmount, alice) {
        uint256 maxCompensation = corkPoolManager.maxExerciseOther(defaultPoolId, alice);
        assertEq(maxCompensation, depositAmount, "Should return user's reference asset balance");
    }

    function test_maxExerciseOther_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        uint256 maxCompensation = corkPoolManager.maxExerciseOther(defaultPoolId, alice);
        assertEq(maxCompensation, 0, "Should return 0 when expired");
    }

    function test_maxExerciseOther_ShouldReturnZero_WhenPaused() external __as(alice) __deposit(depositAmount, alice) {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        uint256 maxCompensation = corkPoolManager.maxExerciseOther(defaultPoolId, alice);
        assertEq(maxCompensation, 0, "Should return 0 when paused");
    }

    function test_maxExerciseOther_ShouldReturnSameValueAsPoolManager() external __as(alice) __deposit(depositAmount, alice) {
        uint256 poolManagerResult = corkPoolManager.maxExerciseOther(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxExerciseOther(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxExerciseOther should match PoolManager maxExerciseOther");
    }

    // ================================ Different Decimals Tests ================================ //

    function test_exerciseOther_ShouldWorkWith6DecimalCollateral() external __createPool(1 days, 6, 18) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __as(alice) {
        depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal); // 6 decimal collateral

        _deposit(defaultPoolId, depositAmount, alice);

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensation, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        assertEq(assets, TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal), "Should receive collateral assets");
        assertEq(otherAssetSpent, 100 ether, "Should spend reference assets");
        assertEq(fee, TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal), "Should have exact fee");

        // Verify asset balance changes accounting for decimals
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userSwapToken - _after.userSwapToken, otherAssetSpent, "User should spend swap token");
    }

    function test_exerciseOther_ShouldWorkWith6DecimalReference() external __createPool(1 days, 18, 6) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __as(alice) {
        depositAmount = 1000 ether;

        _deposit(defaultPoolId, depositAmount, alice);

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        uint256 normalizedCompensation = TransferHelper.normalizeDecimals(exerciseCompensation, TARGET_DECIMALS, referenceDecimal);
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, normalizedCompensation, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        assertEq(assets, 99 ether, "Should receive collateral assets");
        assertEq(otherAssetSpent, exerciseCompensation, "Should spend swap token");
        assertEq(fee, 1 ether, "Should have exact fee");

        // Verify asset balance changes accounting for decimals
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userSwapToken - _after.userSwapToken, otherAssetSpent, "User should spend swap token");
    }

    function test_exerciseOther_ShouldWorkWithBoth6Decimals() external __createPool(1 days, 6, 6) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __as(alice) {
        depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal); // 6 decimal collateral

        _deposit(defaultPoolId, depositAmount, alice);

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        uint256 normalizedCompensation = TransferHelper.normalizeDecimals(exerciseCompensation, TARGET_DECIMALS, referenceDecimal);
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, normalizedCompensation, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        assertEq(assets, TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal), "Should receive collateral assets");
        assertEq(otherAssetSpent, 100 ether, "Should spend swap token");
        assertEq(fee, TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal), "Should have exact fee");

        // Verify asset balance changes accounting for decimals
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userSwapToken - _after.userSwapToken, otherAssetSpent, "User should spend swap token");
    }

    // ================================ Edge Case Tests ================================ //

    function test_exerciseOther_ShouldWorkWithMinimumCompensation() external __as(alice) __deposit(depositAmount, alice) {
        uint256 minimumCompensation = 1 wei; // Very small amount

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, minimumCompensation, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        // Should atleast cost something to do

        // Verify return values
        assertEq(assets, 0, "Shouldn't receive collateral assets");
        assertEq(otherAssetSpent, 1, "Should spend reference assets");
        assertEq(fee, 1, "Should have exact fee");

        // Verify state consistency
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userSwapToken - _after.userSwapToken, otherAssetSpent, "User should spend swap token");
    }

    function test_exerciseOther_PreviewShouldMatchActual() external __as(alice) __deposit(depositAmount, alice) {
        uint256 testCompensation = 50 ether;

        (uint256 previewAssets, uint256 previewOtherSpent, uint256 previewFee) = corkPoolManager.previewExerciseOther(defaultPoolId, testCompensation);
        (uint256 actualAssets, uint256 actualOtherSpent, uint256 actualFee) = corkPoolManager.exerciseOther(defaultPoolId, testCompensation, alice);

        assertEq(actualAssets, previewAssets, "Actual assets should match preview");
        assertEq(actualOtherSpent, previewOtherSpent, "Actual other spent should match preview");
        assertEq(actualFee, previewFee, "Actual fee should match preview");
    }

    function test_exerciseOther_ShouldWorkWithDifferentReceiver() external __as(alice) __deposit(depositAmount, alice) {
        uint256 testCompensation = 50 ether;
        address receiver = bob;

        uint256 receiverCollateralBefore = collateralAsset.balanceOf(receiver);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, testCompensation, receiver);

        uint256 receiverCollateralAfter = collateralAsset.balanceOf(receiver);

        assertEq(receiverCollateralAfter - receiverCollateralBefore, assets, "Receiver should receive collateral assets");
    }

    // ================================ FUZZ EXERCISE OTHER TESTS ================================ //

    function testFuzz_exerciseOther(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 exerciseCompensationNormalized = TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, referenceDecimal);

        // First deposit to get shares
        corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Get state before exercise
        StateSnapshot memory before = _getStateSnapshot(currentCaller(), defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(defaultPoolId, exerciseCompensationNormalized, currentCaller());

        // Get state after exercise
        StateSnapshot memory _after = _getStateSnapshot(currentCaller(), defaultPoolId);

        // Expected values based on 1% fee
        uint256 expectedAssets = TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 expectedOtherSpent = 100 ether; // Always in 18 decimals for swap tokens
        uint256 expectedFee = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

        // Verify return values
        assertEq(assets, expectedAssets, "Should receive correct collateral assets");
        assertEq(otherAssetSpent, expectedOtherSpent, "Should spend correct swap tokens");
        assertEq(fee, expectedFee, "Should have correct fee");

        // Verify user asset balance changes
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, exerciseCompensationNormalized, "User should spend reference assets");
        assertEq(before.userSwapToken - _after.userSwapToken, otherAssetSpent, "User spend swap token balance");

        // Verify contract asset balance changes
        assertEq(before.contractCollateral - _after.contractCollateral, assets + fee, "Contract should transfer collateral + fee");
        assertEq(_after.contractRef - before.contractRef, exerciseCompensationNormalized, "Contract should receive reference assets");

        // Verify pool internal state changes
        assertEq(_after.internalState.pool.balances.referenceAssetBalance - before.internalState.pool.balances.referenceAssetBalance, exerciseCompensationNormalized, "Pool reference asset balance should increase");
        assertEq(before.internalState.pool.balances.collateralAsset.locked - _after.internalState.pool.balances.collateralAsset.locked, assets + fee, "Pool locked collateral should decrease by assets + fee");

        uint256 treasuryBalance = collateralAsset.balanceOf(CORK_PROTOCOL_TREASURY);
        assertEq(treasuryBalance, fee, "Treasury should receive fee");
    }

    function testFuzz_previewExerciseOther(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 compensation = TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, referenceDecimal);

        // First deposit to get shares for actual execution
        corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Preview exercise other
        (uint256 previewAssets, uint256 previewOtherSpent, uint256 previewFee) = corkPoolManager.previewExerciseOther(defaultPoolId, compensation);

        // Execute actual exercise other
        (uint256 actualAssets, uint256 actualOtherSpent, uint256 actualFee) = corkPoolManager.exerciseOther(defaultPoolId, compensation, currentCaller());

        // Verify preview matches actual
        assertEq(previewAssets, actualAssets, "Preview assets should match actual assets");
        assertEq(previewOtherSpent, actualOtherSpent, "Preview other spent should match actual other spent");
        assertEq(previewFee, actualFee, "Preview fee should match actual fee");

        // Also verify expected values based on 1% fee and decimal normalization
        uint256 expectedAssets = TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 expectedOtherSpent = 100 ether; // Always in 18 decimals for swap tokens
        uint256 expectedFee = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

        assertEq(actualAssets, expectedAssets, "Should receive correct collateral assets");
        assertEq(actualOtherSpent, expectedOtherSpent, "Should spend correct swap tokens");
        assertEq(actualFee, expectedFee, "Should have correct fee");
    }
}

