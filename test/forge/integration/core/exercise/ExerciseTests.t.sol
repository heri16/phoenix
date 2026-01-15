// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract ExerciseTests is BaseTest {
    uint256 constant EXPIRY = 1 days;
    uint256 depositAmount = 1000 ether;
    uint256 exerciseShares = 100 ether;

    // ================================ Basic Exercise Tests ================================ //

    function test_exercise_ShouldWorkWithShares() external __as(alice) __deposit(depositAmount, alice) {
        // Get state before exercise
        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        // Preview to get expected values
        (uint256 expectedAssets, uint256 expectedOtherSpent, uint256 expectedFee) =
            corkPoolManager.previewExercise(defaultPoolId, exerciseShares);

        // Expect both PoolSwap and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(defaultPoolId, alice, alice, expectedAssets, expectedOtherSpent, 0, 0, false);
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolFee(defaultPoolId, alice, expectedFee, 0, false);
        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.Withdraw(alice, alice, alice, expectedAssets + expectedFee, 0);
        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.DepositOther(alice, alice, address(referenceAsset), expectedOtherSpent, 0);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);

        // Get state after exercise
        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        // Verify return values
        assertEq(assets, 99 ether, "Should receive collateral assets");
        assertEq(otherAssetSpent, 100 ether, "Should spend reference assets");
        assertEq(fee, 1 ether, "Should have exact fee");

        // Verify user asset balance changes
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");

        uint256 userSwapTokenAfter = swapToken.balanceOf(alice);
        uint256 contractSwapTokenAfter = swapToken.balanceOf(address(corkPoolManager));

        // User should have depositAmount - exerciseShares remaining
        assertEq(userSwapTokenAfter, depositAmount - exerciseShares, "User should have remaining swap tokens");
        assertEq(contractSwapTokenAfter, exerciseShares, "Contract should have received swap tokens");

        // Verify contract asset balance changes
        assertEq(
            before.contractCollateral - _after.contractCollateral,
            assets + fee,
            "Contract should transfer collateral + fee"
        );
        assertEq(_after.contractRef - before.contractRef, otherAssetSpent, "Contract should receive reference assets");

        // Verify pool internal state changes
        assertEq(
            _after.internalState.pool.balances.swapTokenBalance - before.internalState.pool.balances.swapTokenBalance,
            exerciseShares,
            "Pool swap token balance should increase"
        );
        assertEq(
            _after.internalState.pool.balances.referenceAssetBalance
                - before.internalState.pool.balances.referenceAssetBalance,
            otherAssetSpent,
            "Pool reference asset balance should increase"
        );
        assertEq(
            before.internalState.pool.balances.collateralAsset.locked
                - _after.internalState.pool.balances.collateralAsset.locked,
            assets + fee,
            "Pool locked collateral should decrease by assets + fee"
        );

        uint256 treasuryBalance = collateralAsset.balanceOf(CORK_PROTOCOL_TREASURY);
        assertEq(treasuryBalance, fee, "Treasury should receive fee");

        // Verify no changes to principal token balances (exercise doesn't affect cPT)
        assertEq(
            _after.userPrincipalToken, before.userPrincipalToken, "User principal token balance should remain unchanged"
        );
        assertEq(
            _after.principalTokenTotalSupply,
            before.principalTokenTotalSupply,
            "Principal token total supply should remain unchanged"
        );
    }

    // ================================ Negative Tests Cases ================================ //

    function test_exercise_ShouldRevertIfNotEnoughLiquidityForFee() external __as(alice) __deposit(1 ether, alice) {
        uint256 exerciseSharesLarge = 10 ether;

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.exercise(defaultPoolId, exerciseSharesLarge, alice);
    }

    function test_exercise_ShouldRevertIfUninitialized() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.exercise(MarketId.wrap(bytes32(uint256(1))), 1 ether, alice);
    }

    function test_exercise_ShouldRevert_WhenSharesAmountIsZero() external __as(alice) __deposit(depositAmount, alice) {
        vm.expectPartialRevert(IErrors.InvalidParams.selector);
        corkPoolManager.exercise(defaultPoolId, 0, alice);
    }

    function test_exercise_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectPartialRevert(IErrors.Expired.selector);
        corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);
    }

    function test_previewExercise_ShouldReturnAllZeros_WhenZeroShares()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.previewExercise(defaultPoolId, 0);

        assertEq(assets, 0, "Should return 0 assets for zero shares");
        assertEq(otherAssetSpent, 0, "Should return 0 other asset spent for zero shares");
        assertEq(fee, 0, "Should return 0 fee for zero shares");
    }

    function test_previewExercise_ShouldReturnAllZeros_WhenSwapPaused()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        overridePrank(alice);
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.previewExercise(defaultPoolId, exerciseShares);

        assertEq(assets, 0, "Should return 0 assets when swap paused");
        assertEq(otherAssetSpent, 0, "Should return 0 other asset spent when swap paused");
        assertEq(fee, 0, "Should return 0 fee when swap paused");
    }

    function test_previewExercise_ShouldReturnAllZeros_WhenExpired()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        vm.warp(block.timestamp + 2 days);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.previewExercise(defaultPoolId, exerciseShares);

        assertEq(assets, 0, "Should return 0 assets when expired");
        assertEq(otherAssetSpent, 0, "Should return 0 other asset spent when expired");
        assertEq(fee, 0, "Should return 0 fee when expired");
    }

    function test_exercise_ShouldRevert_WhenPaused() external __as(alice) __deposit(depositAmount, alice) {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        overridePrank(alice);
        vm.expectPartialRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);
    }

    function test_previewExercise_ShouldRevertIfUninitialized() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.previewExercise(MarketId.wrap(bytes32(uint256(1))), 1 ether);
    }

    function test_maxExercise_ShouldRevertIfUninitialized() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxExercise(MarketId.wrap(bytes32(uint256(1))), alice);
    }

    function test_exercise_ShouldRevert_WhenGloballyPaused() external __as(alice) __deposit(depositAmount, alice) {
        // Pause globally
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectPartialRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);
    }

    // ================================ Preview Exercise Tests ================================ //

    function test_previewExercise_ShouldReturnCorrectAmounts() external {
        uint256 shares = exerciseShares;
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.previewExercise(defaultPoolId, shares);

        assertEq(assets, 99 ether, "Should receive collateral assets");
        assertEq(otherAssetSpent, 100 ether, "Should spend reference assets");
        assertEq(fee, 1 ether, "Should have exact fee");
    }

    function test_previewExercise_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        // exercise first so that it won't return 0
        corkPoolManager.exercise(defaultPoolId, 10 ether, alice);

        uint256 shares = 50 ether;
        (uint256 poolManagerAssets, uint256 poolManagerOtherAssetSpent, uint256 poolManagerFee) =
            corkPoolManager.previewExercise(defaultPoolId, shares);
        (uint256 poolShareAssets, uint256 poolShareOtherAssetSpent, uint256 poolShareFee) =
            PoolShare(swapToken).previewExercise(shares);

        assertEq(
            poolShareAssets,
            poolManagerAssets,
            "PoolShare previewExercise assets should match PoolManager previewExercise"
        );
        assertEq(
            poolShareOtherAssetSpent,
            poolManagerOtherAssetSpent,
            "PoolShare previewExercise otherAssetSpent should match PoolManager previewExercise"
        );
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewExercise fee should match PoolManager previewExercise");
    }

    // ================================ Max Exercise Tests ================================ //

    function test_maxExercise_ShouldReturnUserBalance() external __as(alice) __deposit(depositAmount, alice) {
        uint256 maxShares = corkPoolManager.maxExercise(defaultPoolId, alice);
        assertEq(maxShares, depositAmount, "Should return user's cST balance");
    }

    function test_maxExercise_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        uint256 maxShares = corkPoolManager.maxExercise(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when expired");
    }

    function test_maxExercise_ShouldReturnZero_WhenPaused() external __as(alice) __deposit(depositAmount, alice) {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        uint256 maxShares = corkPoolManager.maxExercise(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when paused");
    }

    function test_maxExercise_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        uint256 poolManagerResult = corkPoolManager.maxExercise(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxExercise(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxExercise should match PoolManager maxExercise");
    }

    function test_maxExercise_ShouldReturnZero_WhenNotInitialized() external __as(alice) {
        MarketId uninitializedPoolId = MarketId.wrap(bytes32("0x123"));

        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxExercise(uninitializedPoolId, alice);
    }

    function test_maxExercise_ShouldReturnZero_WhenUserHasZeroCST()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        swapToken.transfer(bob, swapToken.balanceOf(alice));

        uint256 maxShares = corkPoolManager.maxExercise(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when user has no cST balance");
    }

    function test_maxExercise_ShouldReturnZero_WhenUserHasZeroReferenceAsset()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        referenceAsset.transfer(bob, referenceAsset.balanceOf(alice));

        uint256 maxShares = corkPoolManager.maxExercise(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when user has no reference asset balance");
    }

    function test_maxExercise_ShouldReturnLimitedShares_WhenUserHasInsufficientReferenceAsset() external {
        // Setup: Give alice assets and approvals
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        // Deposit to get cST shares
        overridePrank(alice);
        _deposit(defaultPoolId, depositAmount, alice);

        // Give alice exactly 10 cST shares (transfer excess away)
        uint256 aliceCurrentCST = swapToken.balanceOf(alice);
        uint256 excessCST = aliceCurrentCST - 10 ether;
        swapToken.transfer(bob, excessCST);

        // Give alice exactly 1 reference asset (transfer excess away)
        uint256 aliceCurrentRef = referenceAsset.balanceOf(alice);
        uint256 excessRef = aliceCurrentRef - 1 ether;
        referenceAsset.transfer(bob, excessRef);

        // Verify alice has 10 cST and 1 reference asset
        assertEq(swapToken.balanceOf(alice), 10 ether, "alice should have 10 cST shares");
        assertEq(referenceAsset.balanceOf(alice), 1 ether, "alice should have 1 reference asset");

        // Check maxExercise - should be limited by reference asset availability
        uint256 maxShares = corkPoolManager.maxExercise(defaultPoolId, alice);

        // Since alice only has 1 reference asset but 10 cST, maxExercise should return
        // less than 10 (limited by reference asset availability)
        assertEq(maxShares, 1 ether);
    }

    // ================================ Different Decimals Tests ================================ //

    function test_exercise_ShouldWorkWith6DecimalCollateral()
        external
        __createPool(1 days, 6, 18)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
    {
        depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal); // 6 decimal collateral

        _deposit(defaultPoolId, depositAmount, alice);

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        assertEq(
            assets,
            TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal),
            "Should receive collateral assets"
        );
        assertEq(otherAssetSpent, 100 ether, "Should spend reference assets");
        assertEq(
            fee, TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal), "Should have exact fee"
        );

        // Verify asset balance changes accounting for decimals
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");
    }

    function test_exercise_ShouldWorkWith6DecimalReference()
        external
        __createPool(1 days, 18, 6)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
    {
        depositAmount = 1000 ether;

        _deposit(defaultPoolId, depositAmount, alice);

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        assertEq(assets, 99 ether, "Should receive collateral assets");
        assertEq(
            otherAssetSpent,
            TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, referenceDecimal),
            "Should spend reference assets"
        );
        assertEq(fee, 1 ether, "Should have exact fee");

        // Verify asset balance changes accounting for decimals
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");
    }

    function test_exercise_ShouldWorkWithBoth6Decimals()
        external
        __createPool(1 days, 6, 6)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
    {
        depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal); // 6 decimal collateral

        _deposit(defaultPoolId, depositAmount, alice);

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, exerciseShares, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        assertEq(
            assets,
            TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal),
            "Should receive collateral assets"
        );
        assertEq(
            otherAssetSpent,
            TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, referenceDecimal),
            "Should spend reference assets"
        );
        assertEq(
            fee,
            TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal),
            "Should Should have exact fee"
        );

        // Verify asset balance changes accounting for decimals
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");
    }

    // ================================ Edge Case Tests ================================ //

    function test_exercise_ShouldWorkWithMinimumShares() external __as(alice) __deposit(depositAmount, alice) {
        uint256 minimumShares = 1 wei; // Very small amount

        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, minimumShares, alice);

        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        // Should atleast cost something to do

        // Verify return values
        assertEq(assets, 0, "Shouldn't receive collateral assets");
        assertEq(otherAssetSpent, 1, "Should spend reference assets");
        assertEq(fee, 1, "Should have exact fee");

        // Verify state consistency
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");
    }

    function test_exercise_PreviewShouldMatchActual() external __as(alice) __deposit(depositAmount, alice) {
        uint256 testShares = 50 ether;

        (uint256 previewAssets, uint256 previewOtherSpent, uint256 previewFee) =
            corkPoolManager.previewExercise(defaultPoolId, testShares);
        (uint256 actualAssets, uint256 actualOtherSpent, uint256 actualFee) =
            corkPoolManager.exercise(defaultPoolId, testShares, alice);

        assertEq(actualAssets, previewAssets, "Actual assets should match preview");
        assertEq(actualOtherSpent, previewOtherSpent, "Actual other spent should match preview");
        assertEq(actualFee, previewFee, "Actual fee should match preview");
    }

    function test_exercise_ShouldWorkWithDifferentReceiver() external __as(alice) __deposit(depositAmount, alice) {
        uint256 testShares = 50 ether;
        address receiver = bob;

        uint256 receiverCollateralBefore = collateralAsset.balanceOf(receiver);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, testShares, receiver);

        uint256 receiverCollateralAfter = collateralAsset.balanceOf(receiver);

        assertEq(
            receiverCollateralAfter - receiverCollateralBefore, assets, "Receiver should receive collateral assets"
        );
    }

    // ================================ FUZZ EXERCISE TESTS ================================ //

    function testFuzz_exercise(uint8 _collateralDecimal, uint8 _referenceDecimal)
        external
        __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal)
        __giveAssets(bravo)
        __approveAllTokens(bravo, address(corkPoolManager))
    {
        uint256 depositAmountNormalized =
            TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 exerciseSharesNormalized = 100 ether; // Always in 18 decimals

        // First deposit to get shares
        corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Get state before exercise
        StateSnapshot memory before = _getStateSnapshot(currentCaller(), defaultPoolId);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, exerciseSharesNormalized, currentCaller());

        // Get state after exercise
        StateSnapshot memory _after = _getStateSnapshot(currentCaller(), defaultPoolId);

        // Expected values based on 1% fee
        uint256 expectedAssets = TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 expectedOtherSpent = TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, referenceDecimal);
        uint256 expectedFee = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

        // Verify return values
        assertEq(assets, expectedAssets, "Should receive correct collateral assets");
        assertEq(otherAssetSpent, expectedOtherSpent, "Should spend correct reference assets");
        assertEq(fee, expectedFee, "Should have correct fee");

        // Verify user asset balance changes
        assertEq(_after.userCollateral - before.userCollateral, assets, "User should receive collateral assets");
        assertEq(before.userRef - _after.userRef, otherAssetSpent, "User should spend reference assets");

        uint256 userSwapTokenAfter = swapToken.balanceOf(currentCaller());
        uint256 contractSwapTokenAfter = swapToken.balanceOf(address(corkPoolManager));

        // User should have depositAmount - exerciseShares remaining
        assertEq(
            userSwapTokenAfter,
            before.userSwapToken - exerciseSharesNormalized,
            "User should have remaining swap tokens"
        );
        assertEq(
            contractSwapTokenAfter,
            before.contractSwapToken + exerciseSharesNormalized,
            "Contract should have received swap tokens"
        );

        // Verify contract asset balance changes
        assertEq(
            before.contractCollateral - _after.contractCollateral,
            assets + fee,
            "Contract should transfer collateral + fee"
        );
        assertEq(_after.contractRef - before.contractRef, otherAssetSpent, "Contract should receive reference assets");

        // Verify pool internal state changes
        assertEq(
            _after.internalState.pool.balances.swapTokenBalance - before.internalState.pool.balances.swapTokenBalance,
            exerciseSharesNormalized,
            "Pool swap token balance should increase"
        );
        assertEq(
            _after.internalState.pool.balances.referenceAssetBalance
                - before.internalState.pool.balances.referenceAssetBalance,
            otherAssetSpent,
            "Pool reference asset balance should increase"
        );
        assertEq(
            before.internalState.pool.balances.collateralAsset.locked
                - _after.internalState.pool.balances.collateralAsset.locked,
            assets + fee,
            "Pool locked collateral should decrease by assets + fee"
        );

        uint256 treasuryBalance = collateralAsset.balanceOf(CORK_PROTOCOL_TREASURY);
        assertEq(treasuryBalance, fee, "Treasury should receive fee");

        // Verify no changes to principal token balances (exercise doesn't affect cPT)
        assertEq(
            _after.userPrincipalToken, before.userPrincipalToken, "User principal token balance should remain unchanged"
        );
        assertEq(
            _after.principalTokenTotalSupply,
            before.principalTokenTotalSupply,
            "Principal token total supply should remain unchanged"
        );
    }

    function testFuzz_previewExercise(uint8 _collateralDecimal, uint8 _referenceDecimal)
        external
        __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal)
        __giveAssets(bravo)
        __approveAllTokens(bravo, address(corkPoolManager))
    {
        uint256 depositAmountNormalized =
            TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 shares = 100 ether;

        // First deposit to get shares for actual execution
        corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Preview exercise
        (uint256 previewAssets, uint256 previewOtherSpent, uint256 previewFee) =
            corkPoolManager.previewExercise(defaultPoolId, shares);

        // Execute actual exercise
        (uint256 actualAssets, uint256 actualOtherSpent, uint256 actualFee) =
            corkPoolManager.exercise(defaultPoolId, shares, currentCaller());

        // Verify preview matches actual
        assertEq(previewAssets, actualAssets, "Preview assets should match actual assets");
        assertEq(previewOtherSpent, actualOtherSpent, "Preview other spent should match actual other spent");
        assertEq(previewFee, actualFee, "Preview fee should match actual fee");

        // Also verify expected values based on 1% fee and decimal normalization
        uint256 expectedAssets = TransferHelper.normalizeDecimals(99 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 expectedOtherSpent = TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, referenceDecimal);
        uint256 expectedFee = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

        assertEq(actualAssets, expectedAssets, "Should receive correct collateral assets");
        assertEq(actualOtherSpent, expectedOtherSpent, "Should spend correct reference assets");
        assertEq(actualFee, expectedFee, "Should have correct fee");
    }

    function testFuzz_exerciseShouldNotRevert_WhenUsingMaxExerciseInput(
        uint8 _collateralDecimal,
        uint8 _referenceDecimal,
        bool lessCst,
        uint256 depositAmount,
        uint256 rate
    )
        external
        __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
    {
        // Bound rate to reasonable values
        rate = bound(rate, 0.4 ether, 1.5 ether);
        depositAmount = bound(depositAmount, 1 ether, type(uint64).max);

        // Deposit to get CST shares
        _deposit(defaultPoolId, depositAmount, alice);

        // Set the oracle rate
        testOracle.setRate(rate);

        uint8 cstDecimals = 18; // CST shares are always 18 decimals
        uint8 refDecimals = referenceAsset.decimals();
        uint256 refBalance = referenceAsset.balanceOf(alice);
        uint256 cstBalance = swapToken.balanceOf(alice);

        // Create edge case by keeping only a small amount of one token
        uint256 toKeep = bound(uint256(0.001 ether), 0.001 ether, 0.005 ether);

        if (lessCst) {
            // Transfer CST so that the balance of CST is really small
            swapToken.transfer(address(2), cstBalance - toKeep);
        } else {
            // Transfer ref so that the balance of ref is really small
            uint256 refToKeep = TransferHelper.fixedToTokenNativeDecimals(toKeep, refDecimals);
            referenceAsset.transfer(address(2), refBalance - refToKeep);
        }

        // Get max exercisable CST shares
        uint256 cstSharesIn = corkPoolManager.maxExercise(defaultPoolId, alice);

        // should not revert
        corkPoolManager.exercise(defaultPoolId, cstSharesIn, alice);
    }
}
