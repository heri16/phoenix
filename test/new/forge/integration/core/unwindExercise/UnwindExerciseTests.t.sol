// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract UnwindExerciseTests is BaseTest {
    uint256 internal constant EXPIRY = 1 days;
    uint256 internal depositAmount = 2000 ether;
    uint256 internal swapAmount = 1000 ether;

    // ================================ UnwindExercise Tests ================================ //

    function test_unwindExerciseBasic_ShouldWorkCorrectly() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        uint256 desiredCstSharesOut = 0.5 ether;
        (address principalToken,) = corkPoolManager.shares(defaultPoolId);

        // Take state snapshot before unwindExercise
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedCollateralAssetsIn, uint256 expectedRefAssetsOut, uint256 expectedFee) = corkPoolManager.previewUnwindExercise(defaultPoolId, desiredCstSharesOut);

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(defaultPoolId, alice, alice, expectedCollateralAssetsIn, expectedRefAssetsOut, 0, 0, true);
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(defaultPoolId, alice, expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Deposit(alice, alice, expectedCollateralAssetsIn - expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(alice, alice, alice, address(referenceAsset), expectedRefAssetsOut, 0);
        (uint256 collateralAssetsIn, uint256 refAssetsOut, uint256 fee) = corkPoolManager.unwindExercise(defaultPoolId, desiredCstSharesOut, alice);

        // Take state snapshot after unwindExercise
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Assert unwindExercise return values match preview
        assertEq(collateralAssetsIn, expectedCollateralAssetsIn, "collateralAssetsIn should match preview");
        assertEq(refAssetsOut, expectedRefAssetsOut, "RefAssetsOut should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // Assert alice balance changes
        assertEq(stateAfter.userCollateral, stateBefore.userCollateral - collateralAssetsIn, "User should spend correct collateral amount");
        assertEq(stateAfter.userRef, stateBefore.userRef + refAssetsOut, "User should recieve correct amount of reference asset compensation");
        assertEq(stateAfter.userSwapToken, stateBefore.userSwapToken + desiredCstSharesOut, "User should recieve correct amount of cst shares");
        assertEq(stateAfter.userPrincipalToken, stateBefore.userPrincipalToken, "User principal token balance should remain unchanged");

        // Assert contract balance changes
        assertEq(stateAfter.contractCollateral, stateBefore.contractCollateral + collateralAssetsIn - fee, "Contract collateral balance should increase by assets collateralAssetsIn excluding fee");
        assertEq(stateAfter.contractRef, stateBefore.contractRef - refAssetsOut, "Contract should sent reference asset refAssetsOut");

        // Assert pool asset tracking
        assertEq(stateAfter.poolCollateral, stateBefore.poolCollateral + (collateralAssetsIn - fee), "Pool collateral should increase by assets In minus fee");
        assertEq(stateAfter.poolRef, stateBefore.poolRef - refAssetsOut, "Pool reference assets should decrease by refAssetsOut");

        // Assert internal state changes
        assertEq(stateAfter.internalState.pool.balances.collateralAsset.locked, stateBefore.internalState.pool.balances.collateralAsset.locked + (collateralAssetsIn - fee), "Locked collateral should increase by assets In minus fee");
        assertEq(stateAfter.internalState.pool.balances.referenceAssetBalance, stateBefore.internalState.pool.balances.referenceAssetBalance - refAssetsOut, "Reference asset balance should decrease by refAssetsOut");
        assertEq(stateAfter.internalState.pool.balances.swapTokenBalance, stateBefore.internalState.pool.balances.swapTokenBalance - desiredCstSharesOut, "Swap token balance should decrease by shares spent");

        // Fees tracking
        assertEq(stateAfter.treasuryCollateral - stateBefore.treasuryCollateral, fee, "Treasury should receive fee");

        // Verify no changes to principal token balances (exercise doesn't affect CPT)
        assertEq(stateAfter.userPrincipalToken, stateBefore.userPrincipalToken, "User principal token balance should remain unchanged");
        assertEq(stateAfter.principalTokenTotalSupply, stateBefore.principalTokenTotalSupply, "Principal token total supply should remain unchanged");
    }

    function test_unwindExercise_ShouldWorkWithDifferentOwnerReceiver() external __as(alice) __depositAndSwap(depositAmount, swapAmount, alice) {
        overridePrank(bob);
        _deposit(defaultPoolId, depositAmount, currentCaller());
        _swap(defaultPoolId, swapAmount, currentCaller());

        uint256 desiredCstSharesOut = 0.3 ether;

        uint256 bobCaBefore = collateralAsset.balanceOf(bob);
        uint256 bobRaBefore = referenceAsset.balanceOf(bob);
        uint256 bobCstBefore = swapToken.balanceOf(bob);
        uint256 aliceCaBefore = collateralAsset.balanceOf(alice);

        (uint256 collateralAssetsIn, uint256 compensation, uint256 fee) = corkPoolManager.unwindExercise(defaultPoolId, desiredCstSharesOut, alice);

        uint256 bobCaAfter = collateralAsset.balanceOf(bob);
        uint256 bobRaAfter = referenceAsset.balanceOf(bob);
        uint256 bobCstAfter = swapToken.balanceOf(bob);
        uint256 aliceCaAfter = collateralAsset.balanceOf(alice);

        assertGt(collateralAssetsIn, 0, "Should unlock collateralAssetsIn");
        assertGt(compensation, 0, "Should unlock reference asset compensation");
        assertEq(bobCaBefore - bobCaAfter, collateralAssetsIn, "bob should spend collateral assets");
        assertEq(bobCstAfter, bobCstBefore, "bob should not receive cst shares");
        assertEq(bobRaAfter, bobRaBefore, "bob should not receive reference assets");
        assertEq(aliceCaAfter, aliceCaBefore, "alice should not pay any collateral assets or fees");
    }

    // ================================ Max Unwind Exercise Tests ================================ //

    function test_maxUnwindExercise_ShouldReturnCorrectAmount_WhenLessReferenceAssetThanRespctiveCst() external __as(alice) __depositAndSwap(500 ether, 100 ether, alice) {
        testOracle.setRate(defaultPoolId, 0.9 ether); // 90%

        uint256 maxShares = corkPoolManager.maxUnwindExercise(defaultPoolId, alice);
        uint256 expectedShares = MathHelper.calculateEqualSwapAmount(101_010_101_010_101_010_102, 0.9 ether);
        assertEq(maxShares, expectedShares, "Should return max shares");
    }

    // ================================ Preview Unwind Exercise Tests ================================ //

    function test_previewUnwindExercise_ShouldReturnCorrectAmounts() external {
        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateUnwindSwapFeeRate(defaultPoolId, 0);

        overridePrank(alice);
        uint256 cstSharesOut = 1 ether;
        (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultPoolId, cstSharesOut);

        assertEq(collateralAssetsIn, 1 ether, "Should receive correct collateral assets");
        assertEq(referenceAssetsOut, 1 ether, "Should receive correct reference assets");
        assertEq(fee, 0, "Should have exact fee");
    }

    function test_previewUnwindExercise_ShouldReturnSameValueAsPoolManager() external __as(alice) __depositAndSwap(depositAmount, swapAmount, alice) {
        uint256 cstSharesOut = 1 ether;

        (uint256 poolManagerCaAssetsIn, uint256 poolManagerCompensation, uint256 poolManagerFee) = corkPoolManager.previewUnwindExercise(defaultPoolId, cstSharesOut);
        (uint256 poolShareCaAssetsIn, uint256 poolShareCompensation, uint256 poolShareFee) = swapToken.previewUnwindExercise(cstSharesOut);

        assertEq(poolShareCaAssetsIn, poolManagerCaAssetsIn, "PoolShare previewUnwindExercise sharesIn should match PoolManager previewUnwindExercise");
        assertEq(poolShareCompensation, poolManagerCompensation, "PoolShare previewUnwindExercise compensation should match PoolManager previewUnwindExercise");
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewUnwindExercise fee should match PoolManager previewUnwindExercise");
    }

    function test_previewUnwindExercise_ShouldReturnZero_AfterExpiry() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultPoolId, 100 ether);
        assertEq(collateralAssetsIn, 0, "Should return zero collateralAssetsIn");
        assertEq(referenceAssetsOut, 0, "Should return zero referenceAssetsOut");
        assertEq(fee, 0, "Should return zero fee");
    }

    function test_previewUnwindExercise_ShouldReturnZero_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultPoolId, 100 ether);
        assertEq(collateralAssetsIn, 0, "Should return zero collateralAssetsIn");
        assertEq(referenceAssetsOut, 0, "Should return zero referenceAssetsOut");
        assertEq(fee, 0, "Should return zero fee");
    }

    // ================================ Max Unwind Exercise Tests ================================ //

    function test_maxUnwindExercise_ShouldReturnSameValueAsPoolManager() external __as(alice) __depositAndSwap(depositAmount, swapAmount, alice) {
        uint256 poolManagerResult = corkPoolManager.maxUnwindExercise(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxUnwindExercise(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindExercise should match PoolManager maxUnwindExercise");
    }

    function test_maxUnwindExercise_ShouldReturnZero_AfterExpiry() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 maxCstSharesOut) = corkPoolManager.maxUnwindExercise(defaultPoolId, alice);
        assertEq(maxCstSharesOut, 0, "Should return zero maxCstSharesOut");
    }

    function test_maxUnwindExercise_ShouldReturnZero_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        (uint256 maxCstSharesOut) = corkPoolManager.maxUnwindExercise(defaultPoolId, alice);
        assertEq(maxCstSharesOut, 0, "Should return zero maxCstSharesOut");
    }

    // ================================ Negative Test Cases ================================ //

    function test_unwindExercise_ShouldRevert_WhenInsufficientReferenceAssetLiquidity() external __as(alice) __depositAndSwap(400 ether, 200 ether, alice) {
        // Setup: We need swapAssetOut <= swapTokenBalance
        // but compensationOut > referenceAssetBalance to ensure correct edge case is tested

        overridePrank(DEFAULT_ADDRESS);
        testOracle.setRate(defaultPoolId, 0.5 ether);

        // Get reference asset balance of pool
        (, uint256 referenceAssets) = corkPoolManager.assets(defaultPoolId);

        (, address swapToken) = corkPoolManager.shares(defaultPoolId);
        // Get the swap token balance in pool
        uint256 cstInPool = IERC20(swapToken).balanceOf(address(corkPoolManager));

        uint256 unwindAmount = 200 ether;
        (uint256 previewCollateralAssetsIn, uint256 previewReferenceAsset,) = corkPoolManager.previewUnwindExercise(defaultPoolId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut > referenceAssets balance of pool)
        assertGt(previewReferenceAsset, referenceAssets, "Reference asset check MUST exceed available");

        // 2. Swap token check (swapAssetOut <= available swap tokens balance of pool)
        assertLe(previewCollateralAssetsIn, cstInPool, "Swap asset required MUST be less than available");

        overridePrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", referenceAssets, previewReferenceAsset));
        corkPoolManager.unwindExercise(defaultPoolId, unwindAmount, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenInsufficientSwapTokenLiquidity() external __as(alice) __depositAndSwap(400 ether, 200 ether, alice) {
        // Setup: We need referenceAssetOut <= referenceAssetBalance
        // but swapAssetOut > swapTokenBalance to ensure correct edge case is tested
        overridePrank(DEFAULT_ADDRESS);
        testOracle.setRate(defaultPoolId, 1.1 ether);

        // Get reference asset balance of pool
        (, uint256 referenceAssets) = corkPoolManager.assets(defaultPoolId);

        (, address swapToken) = corkPoolManager.shares(defaultPoolId);
        // Get the swap token balance in pool
        uint256 cstInPool = IERC20(swapToken).balanceOf(address(corkPoolManager));

        uint256 unwindAmount = 220 ether;
        (uint256 previewCollateralAssetsIn, uint256 previewReferenceAsset,) = corkPoolManager.previewUnwindExercise(defaultPoolId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut <= referenceAssets balance of pool)
        assertLe(previewReferenceAsset, referenceAssets, "Reference asset check MUST less than available");

        // 2. Swap token check (swapAssetOut > available swap tokens balance of pool)
        assertGt(previewCollateralAssetsIn, cstInPool, "Swap asset required MUST exceed available");

        overridePrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", cstInPool, unwindAmount));
        corkPoolManager.unwindExercise(defaultPoolId, unwindAmount, alice);
    }

    function test_unwindExercise_ShouldRevertAfterExpiry() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        vm.expectRevert(IErrors.Expired.selector);
        corkPoolManager.unwindExercise(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindExercise(defaultPoolId, 0, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(defaultPoolId, 100 ether, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.unwindExercise(fakePoolId, 1 ether, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenGloballyPaused() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        // Pause the entire contract (not just swaps for a specific pool)
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenInsufficientCollateralAssetBalance() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        // Transfer away all collateral assets so user has none for unwindExercise
        collateralAsset.transfer(bob, referenceAsset.balanceOf(alice));

        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", alice, 10_101_010_101_010_102, 505_050_446_004_455_252));
        corkPoolManager.unwindExercise(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenReceiverIsZeroAddress() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        corkPoolManager.unwindExercise(defaultPoolId, 0.5 ether, address(0));
    }

    function test_previewUnwindExercise_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.previewUnwindExercise(fakePoolId, 1 ether);
    }

    function test_maxUnwindExercise_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxUnwindExercise(fakePoolId, alice);
    }

    // ================================ Fuzz Tests ================================ //

    function testFuzz_unwindExercise_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(2 ether, collateralAsset.decimals());
        uint256 normalizedSwapAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        // First deposit and swap to have tokens for unwinding
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());
        corkPoolManager.swap(defaultPoolId, normalizedSwapAmount, currentCaller());

        uint256 desiredCstSharesOut = 0.5 ether;

        // Take snapshots before unwindExercise
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedCollateralAssetsIn, uint256 expectedRefAssetsOut, uint256 expectedFee) = corkPoolManager.previewUnwindExercise(defaultPoolId, desiredCstSharesOut);

        (uint256 collateralAssetsIn, uint256 refAssetsOut, uint256 fee) = corkPoolManager.unwindExercise(defaultPoolId, desiredCstSharesOut, alice);

        // Take snapshots after unwindExercise
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(collateralAssetsIn, expectedCollateralAssetsIn, "collateralAssetsIn should match preview");
        assertEq(refAssetsOut, expectedRefAssetsOut, "RefAssetsOut should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // ================================ User State Changes ================================ //
        assertEq(afterSnapshot.userCollateral, beforeSnapshot.userCollateral - collateralAssetsIn, "User should spend correct collateral amount");
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef + refAssetsOut, "User should receive correct amount of reference asset compensation");
        assertEq(afterSnapshot.userSwapToken, beforeSnapshot.userSwapToken + desiredCstSharesOut, "User should receive correct amount of cst shares");
        assertEq(afterSnapshot.userPrincipalToken, beforeSnapshot.userPrincipalToken, "User principal token balance should remain unchanged");

        // ================================ Contract State Changes ================================ //
        assertEq(afterSnapshot.contractCollateral, beforeSnapshot.contractCollateral + collateralAssetsIn - fee, "Contract collateral balance should increase by assets collateralAssetsIn excluding fee");
        assertEq(afterSnapshot.contractRef, beforeSnapshot.contractRef - refAssetsOut, "Contract should send reference asset refAssetsOut");

        // ================================ Pool Internal State Changes ================================ //
        assertEq(afterSnapshot.poolCollateral, beforeSnapshot.poolCollateral + (collateralAssetsIn - fee), "Pool collateral should increase by assets In minus fee");
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef - refAssetsOut, "Pool reference assets should decrease by refAssetsOut");

        // ================================ Internal State Consistency ================================ //
        assertEq(afterSnapshot.internalState.pool.balances.collateralAsset.locked, beforeSnapshot.internalState.pool.balances.collateralAsset.locked + (collateralAssetsIn - fee), "Locked collateral should increase by assets In minus fee");
        assertEq(afterSnapshot.internalState.pool.balances.referenceAssetBalance, beforeSnapshot.internalState.pool.balances.referenceAssetBalance - refAssetsOut, "Reference asset balance should decrease by refAssetsOut");
        assertEq(afterSnapshot.internalState.pool.balances.swapTokenBalance, beforeSnapshot.internalState.pool.balances.swapTokenBalance - desiredCstSharesOut, "Swap token balance should decrease by shares spent");

        // ================================ Treasury State Changes ================================ //
        assertEq(afterSnapshot.treasuryCollateral, beforeSnapshot.treasuryCollateral + fee, "Treasury should receive fee");

        // ================================ Token Supply Consistency ================================ //
        assertEq(afterSnapshot.swapTokenTotalSupply, beforeSnapshot.swapTokenTotalSupply, "Swap token total supply should remain unchanged");
        assertEq(afterSnapshot.principalTokenTotalSupply, beforeSnapshot.principalTokenTotalSupply, "Principal token total supply should remain unchanged");
    }

    function testFuzz_previewUnwindExercise_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(2 ether, collateralAsset.decimals());
        uint256 normalizedSwapAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        // First deposit and swap to have tokens for unwinding
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());
        corkPoolManager.swap(defaultPoolId, normalizedSwapAmount, currentCaller());

        uint256 desiredCstSharesOut = 0.5 ether;

        // Preview unwind exercise
        (uint256 previewCollateralAssetsIn, uint256 previewRefAssetsOut, uint256 previewFee) = corkPoolManager.previewUnwindExercise(defaultPoolId, desiredCstSharesOut);

        // Execute actual unwind exercise
        (uint256 actualCollateralAssetsIn, uint256 actualRefAssetsOut, uint256 actualFee) = corkPoolManager.unwindExercise(defaultPoolId, desiredCstSharesOut, alice);

        // Verify preview matches actual
        assertEq(previewCollateralAssetsIn, actualCollateralAssetsIn, "Preview collateral assets in should match actual collateral assets in");
        assertEq(previewRefAssetsOut, actualRefAssetsOut, "Preview ref assets out should match actual ref assets out");
        assertEq(previewFee, actualFee, "Preview fee should match actual fee");
    }
}
