// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnwindExerciseOtherTests is BaseTest {
    uint256 internal constant EXPIRY = 1 days;
    uint256 internal depositAmount = 2000 ether;
    uint256 internal swapAmount = 1000 ether;

    // ================================ UnwindExerciseOther Tests ================================ //

    function test_unwindExerciseOtherBasic_ShouldWorkCorrectly()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        uint256 desiredReferenceAssetsOut = 0.5 ether;
        (address principalToken,) = corkPoolManager.shares(defaultPoolId);

        // Take state snapshot before unwindExerciseOther
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedCollateralAssetsIn, uint256 expectedCstSharesOut, uint256 expectedFee) =
            corkPoolManager.previewUnwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut);

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(
            defaultPoolId, alice, alice, expectedCollateralAssetsIn, expectedCstSharesOut, 0, 0, true
        );
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(defaultPoolId, alice, expectedFee, 0, true);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Deposit(alice, alice, expectedCollateralAssetsIn - expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(alice, alice, alice, address(referenceAsset), expectedCstSharesOut, 0);
        (uint256 collateralAssetsIn, uint256 refAssetsOut, uint256 fee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut, alice);

        // Take state snapshot after unwindExerciseOther
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Assert unwindExerciseOther return values match preview
        assertEq(collateralAssetsIn, expectedCollateralAssetsIn, "collateralAssetsIn should match preview");
        assertEq(refAssetsOut, expectedCstSharesOut, "RefAssetsOut should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // Assert alice balance changes
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral - collateralAssetsIn,
            "User should spend correct collateral amount"
        );
        assertEq(
            stateAfter.userRef,
            stateBefore.userRef + refAssetsOut,
            "User should recieve correct amount of reference asset compensation"
        );
        assertEq(
            stateAfter.userSwapToken,
            stateBefore.userSwapToken + desiredReferenceAssetsOut,
            "User should recieve correct amount of cST shares"
        );
        assertEq(
            stateAfter.userPrincipalToken,
            stateBefore.userPrincipalToken,
            "User principal token balance should remain unchanged"
        );

        // Assert contract balance changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral + collateralAssetsIn - fee,
            "Contract collateral balance should increase by assets collateralAssetsIn excluding fee"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef - refAssetsOut,
            "Contract should sent reference asset refAssetsOut"
        );

        // Assert pool asset tracking
        assertEq(
            stateAfter.poolCollateral,
            stateBefore.poolCollateral + (collateralAssetsIn - fee),
            "Pool collateral should increase by assets In minus fee"
        );
        assertEq(
            stateAfter.poolRef,
            stateBefore.poolRef - refAssetsOut,
            "Pool reference assets should decrease by refAssetsOut"
        );

        // Assert internal state changes
        assertEq(
            stateAfter.internalState.pool.balances.collateralAsset.locked,
            stateBefore.internalState.pool.balances.collateralAsset.locked + (collateralAssetsIn - fee),
            "Locked collateral should increase by assets In minus fee"
        );
        assertEq(
            stateAfter.internalState.pool.balances.referenceAssetBalance,
            stateBefore.internalState.pool.balances.referenceAssetBalance - refAssetsOut,
            "Reference asset balance should decrease by refAssetsOut"
        );
        assertEq(
            stateAfter.internalState.pool.balances.swapTokenBalance,
            stateBefore.internalState.pool.balances.swapTokenBalance - desiredReferenceAssetsOut,
            "Swap token balance should decrease by shares spent"
        );

        // Fees tracking
        assertEq(stateAfter.treasuryCollateral - stateBefore.treasuryCollateral, fee, "Treasury should receive fee");

        // Verify no changes to principal token balances (exercise doesn't affect cPT)
        assertEq(
            stateAfter.userPrincipalToken,
            stateBefore.userPrincipalToken,
            "User principal token balance should remain unchanged"
        );
        assertEq(
            stateAfter.principalTokenTotalSupply,
            stateBefore.principalTokenTotalSupply,
            "Principal token total supply should remain unchanged"
        );
    }

    function test_unwindExerciseOther_ShouldWorkWithDifferentOwnerReceiver()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        overridePrank(bob);
        _deposit(defaultPoolId, depositAmount, currentCaller());
        _swap(defaultPoolId, swapAmount, currentCaller());

        uint256 desiredReferenceAssetsOut = 0.3 ether;

        uint256 bobCaBefore = collateralAsset.balanceOf(bob);
        uint256 bobRaBefore = referenceAsset.balanceOf(bob);
        uint256 bobCstBefore = swapToken.balanceOf(bob);
        uint256 aliceCaBefore = collateralAsset.balanceOf(alice);

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut, alice);

        uint256 bobCaAfter = collateralAsset.balanceOf(bob);
        uint256 bobRaAfter = referenceAsset.balanceOf(bob);
        uint256 bobCstAfter = swapToken.balanceOf(bob);
        uint256 aliceCaAfter = collateralAsset.balanceOf(alice);

        assertGt(collateralAssetsIn, 0, "Should unlock collateralAssetsIn");
        assertGt(cstSharesOut, 0, "Should unlock reference asset cstSharesOut");
        assertEq(bobCaBefore - bobCaAfter, collateralAssetsIn, "bob should spend collateral assets");
        assertEq(bobCstAfter, bobCstBefore, "bob should not receive cST shares");
        assertEq(bobRaAfter, bobRaBefore, "bob should not receive reference assets");
        assertEq(aliceCaAfter, aliceCaBefore, "alice should not pay any collateral assets or fees");
    }

    function test_unwindExerciseOther_ShouldRequireMoreAsset_WhenDustAmount()
        external
        __createPoolBounded(1 days, 6, 18)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        testOracle.setRate(0.99 ether);

        StateSnapshot memory initialSnapshot = _getStateSnapshot(alice, defaultPoolId);

        uint256 desiredReferenceAssetsOut = 1;

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut, alice);

        StateSnapshot memory finalSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // should at least cost something
        // NOTE : currently it does 2 ceil div, thus requiring 2 collateral assetIn in edgecase like this
        assertEq(collateralAssetsIn, 2);
        assertEq(finalSnapshot.userRef - initialSnapshot.userRef, desiredReferenceAssetsOut);
        assertEq(cstSharesOut, 0);
        assertEq(finalSnapshot.userSwapToken - initialSnapshot.userSwapToken, 0);
    }

    // ================================ Preview Unwind Exercise Other Tests ================================ //

    function test_previewUnwindExercise_ShouldReturnCorrectAmounts() external {
        overridePrank(bravo);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        uint256 referenceAssetsOut = 1 ether;
        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.previewUnwindExercise(defaultPoolId, referenceAssetsOut);

        assertEq(collateralAssetsIn, 1 ether, "Should receive correct collateral assets");
        assertEq(cstSharesOut, 1 ether, "Should receive correct cST shares");
        assertEq(fee, 0, "Should have exact fee");
    }

    function test_previewUnwindExerciseOther_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        uint256 assets = 1 ether;

        (uint256 poolManagerCaAssetsIn, uint256 poolManagerCstSharesOut, uint256 poolManagerFee) =
            corkPoolManager.previewUnwindExerciseOther(defaultPoolId, assets);
        (uint256 poolShareCaAssetsIn, uint256 poolShareCstSharesOut, uint256 poolShareFee) =
            swapToken.previewUnwindExerciseOther(assets);

        assertEq(
            poolShareCaAssetsIn,
            poolManagerCaAssetsIn,
            "PoolShare previewUnwindExerciseOther sharesIn should match PoolManager previewUnwindExerciseOther"
        );
        assertEq(
            poolShareCstSharesOut,
            poolManagerCstSharesOut,
            "PoolShare previewUnwindExerciseOther cstSharesOut should match PoolManager previewUnwindExerciseOther"
        );
        assertEq(
            poolShareFee,
            poolManagerFee,
            "PoolShare previewUnwindExerciseOther fee should match PoolManager previewUnwindExerciseOther"
        );
    }

    function test_previewUnwindExercise_ShouldReturnZero_AfterExpiry()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.previewUnwindExercise(defaultPoolId, 100 ether);
        assertEq(collateralAssetsIn, 0, "Should return zero collateralAssetsIn");
        assertEq(cstSharesOut, 0, "Should return zero cstSharesOut");
        assertEq(fee, 0, "Should return zero fee");
    }

    function test_previewUnwindExercise_ShouldReturnZero_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.previewUnwindExercise(defaultPoolId, 100 ether);
        assertEq(collateralAssetsIn, 0, "Should return zero collateralAssetsIn");
        assertEq(cstSharesOut, 0, "Should return zero cstSharesOut");
        assertEq(fee, 0, "Should return zero fee");
    }

    // ================================ Max Unwind Exercise Tests ================================ //

    function test_maxUnwindExerciseOther_ShouldReturnCorrectAmount_WhenLessCstThanRespctiveReferenceAsset() external {
        overridePrank(bravo);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        _deposit(defaultPoolId, 500 ether, alice);
        _swap(defaultPoolId, 100 ether, alice);

        testOracle.setRate(defaultPoolId, 1.1 ether); // 110%

        uint256 maxReferenceAssetsOut = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, alice);
        uint256 expectedReferenceAssets = MathHelper.calculateDepositAmountWithSwapRate(100 ether, 1.1 ether, false);
        assertEq(maxReferenceAssetsOut, expectedReferenceAssets, "Should return max shares");
    }

    function test_maxUnwindExerciseOther_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        uint256 poolManagerResult = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxUnwindExerciseOther(alice);

        assertEq(
            poolShareResult,
            poolManagerResult,
            "PoolShare maxUnwindExerciseOther should match PoolManager maxUnwindExerciseOther"
        );
    }

    function test_maxUnwindExerciseOther_ShouldReturnZero_AfterExpiry()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 maxCstSharesOut) = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, alice);
        assertEq(maxCstSharesOut, 0, "Should return zero maxCstSharesOut");
    }

    function test_maxUnwindExerciseOther_ShouldReturnZero_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        (uint256 maxReferenceAssetsOut) = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, alice);
        assertEq(maxReferenceAssetsOut, 0, "Should return zero maxReferenceAssetsOut");
    }

    function test_maxUnwindExerciseOther_ShouldReturnZero_WhenZeroReferenceAsset()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        uint256 maxReferenceAssets = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, alice);
        assertEq(maxReferenceAssets, 0, "Should return 0 when pool has zero reference asset balance");
    }

    function test_maxUnwindExerciseOther_ShouldReturnZero_WhenZeroCST()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        (, address swapTokenAddress) = corkPoolManager.shares(defaultPoolId);
        IERC20 swapTokenERC20 = IERC20(swapTokenAddress);

        uint256 poolSwapBalance = swapTokenERC20.balanceOf(address(corkPoolManager));

        overridePrank(address(corkPoolManager));
        swapTokenERC20.transfer(alice, poolSwapBalance);

        overridePrank(alice);
        uint256 maxReferenceAssets = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, alice);
        assertEq(maxReferenceAssets, 0, "Should return 0 when pool has zero cST balance");
    }

    // ================================ Negative Test Cases ================================ //

    function test_unwindExerciseOther_ShouldRevert_WhenInsufficientReferenceAssetLiquidity()
        external
        __as(alice)
        __depositAndSwap(400 ether, 200 ether, alice)
    {
        // Setup: We need swapAssetOut <= swapTokenBalance
        // but compensationOut > referenceAssetBalance to ensure correct edge case is tested

        overridePrank(bravo);
        testOracle.setRate(defaultPoolId, 0.5 ether);

        // Get reference asset balance of pool
        (, uint256 referenceAssets) = corkPoolManager.assets(defaultPoolId);

        (, address swapToken) = corkPoolManager.shares(defaultPoolId);
        // Get the swap token balance in pool
        uint256 cstInPool = IERC20(swapToken).balanceOf(address(corkPoolManager));

        uint256 unwindAmount = 220 ether;
        (, uint256 previewCstShares,) = corkPoolManager.previewUnwindExerciseOther(defaultPoolId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut > referenceAssets balance of pool)
        assertGt(unwindAmount, referenceAssets, "Reference asset check MUST exceed available");

        // 2. Swap token check (swapAssetOut <= available swap tokens balance of pool)
        assertLe(previewCstShares, cstInPool, "Swap asset required MUST be less than available");

        overridePrank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", referenceAssets, unwindAmount)
        );
        corkPoolManager.unwindExerciseOther(defaultPoolId, unwindAmount, alice);
    }

    function test_unwindExerciseOther_ShouldRevert_WhenInsufficientSwapTokenLiquidity()
        external
        __as(alice)
        __depositAndSwap(400 ether, 200 ether, alice)
    {
        // Setup: We need referenceAssetOut <= referenceAssetBalance
        // but swapAssetOut > swapTokenBalance to ensure correct edge case is tested
        overridePrank(bravo);
        testOracle.setRate(defaultPoolId, 1.1 ether);

        // Get reference asset balance of pool
        (, uint256 referenceAssets) = corkPoolManager.assets(defaultPoolId);

        (, address swapToken) = corkPoolManager.shares(defaultPoolId);
        // Get the swap token balance in pool
        uint256 cstInPool = IERC20(swapToken).balanceOf(address(corkPoolManager));

        uint256 unwindAmount = 200 ether;
        (, uint256 previewCstShares,) = corkPoolManager.previewUnwindExerciseOther(defaultPoolId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut <= referenceAssets balance of pool)
        assertLe(unwindAmount, referenceAssets, "Reference asset check MUST less than available");

        // 2. Swap token check (swapAssetOut > available swap tokens balance of pool)
        assertGt(previewCstShares, cstInPool, "Swap asset required MUST exceed available");

        overridePrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", cstInPool, previewCstShares));
        corkPoolManager.unwindExerciseOther(defaultPoolId, unwindAmount, alice);
    }

    function test_unwindExerciseOther_ShouldRevertAfterExpiry()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        vm.expectRevert(IErrors.Expired.selector);
        corkPoolManager.unwindExerciseOther(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindExerciseOther_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindExerciseOther(defaultPoolId, 0, alice);
    }

    function test_unwindExercise_ShouldRevert_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExerciseOther(defaultPoolId, 100 ether, alice);
    }

    function test_previewUnwindExerciseOther_ShouldReturnZeroZeroZero_WhenZeroReferenceAsset()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        (uint256 assetIn, uint256 fee, uint256 sharesOut) = corkPoolManager.previewUnwindExerciseOther(defaultPoolId, 0);

        assertEq(assetIn, 0, "Should return 0 asset in for zero reference asset");
        assertEq(fee, 0, "Should return 0 fee for zero reference asset");
        assertEq(sharesOut, 0, "Should return 0 shares out for zero reference asset");
    }

    function test_previewUnwindExerciseOther_ShouldReturnZeroZeroZero_WhenUnwindSwapPaused()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4); // 10000 = unwind swap paused

        overridePrank(alice);
        (uint256 assetIn, uint256 fee, uint256 sharesOut) =
            corkPoolManager.previewUnwindExerciseOther(defaultPoolId, 100 ether);

        assertEq(assetIn, 0, "Should return 0 asset in when unwind swap paused");
        assertEq(fee, 0, "Should return 0 fee when unwind swap paused");
        assertEq(sharesOut, 0, "Should return 0 shares out when unwind swap paused");
    }

    function test_previewUnwindExerciseOther_ShouldReturnZeroZeroZero_WhenExpired()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        vm.warp(block.timestamp + 2 days);

        (uint256 assetIn, uint256 fee, uint256 sharesOut) =
            corkPoolManager.previewUnwindExerciseOther(defaultPoolId, 100 ether);

        assertEq(assetIn, 0, "Should return 0 asset in when expired");
        assertEq(fee, 0, "Should return 0 fee when expired");
        assertEq(sharesOut, 0, "Should return 0 shares out when expired");
    }

    function test_unwindExerciseOther_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.unwindExerciseOther(fakePoolId, 1 ether, alice);
    }

    function test_unwindExerciseOther_ShouldRevert_WhenGloballyPaused()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        // Pause the entire contract (not just swaps for a specific pool)
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExerciseOther(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindExerciseOther_ShouldRevert_WhenInsufficientCollateralAssetBalance()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        // Transfer away all collateral assets so user has none for unwindExerciseOther
        collateralAsset.transfer(bob, referenceAsset.balanceOf(alice));

        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)",
                alice,
                10_101_010_101_010_102,
                505_050_446_004_455_252
            )
        );
        corkPoolManager.unwindExerciseOther(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindExerciseOther_ShouldRevert_WhenReceiverIsZeroAddress()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        corkPoolManager.unwindExerciseOther(defaultPoolId, 0.5 ether, address(0));
    }

    function test_previewUnwindExerciseOther_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.previewUnwindExerciseOther(fakePoolId, 1 ether);
    }

    function test_maxUnwindExerciseOther_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxUnwindExerciseOther(fakePoolId, address(0));
    }

    // ================================ Fuzz Tests ================================ //

    function testFuzz_unwindExerciseOther_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals)
        external
    {
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

        uint256 desiredReferenceAssetsOut =
            TransferHelper.fixedToTokenNativeDecimals(0.5 ether, referenceAsset.decimals());

        // Take snapshots before unwindExerciseOther
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedCollateralAssetsIn, uint256 expectedCstSharesOut, uint256 expectedFee) =
            corkPoolManager.previewUnwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut);

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut, alice);

        // Take snapshots after unwindExerciseOther
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(collateralAssetsIn, expectedCollateralAssetsIn, "collateralAssetsIn should match preview");
        assertEq(cstSharesOut, expectedCstSharesOut, "RefAssetsOut should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // ================================ User State Changes ================================ //
        assertEq(
            afterSnapshot.userCollateral,
            beforeSnapshot.userCollateral - collateralAssetsIn,
            "User should spend correct collateral amount"
        );
        assertEq(
            afterSnapshot.userRef,
            beforeSnapshot.userRef + desiredReferenceAssetsOut,
            "User should receive correct amount of reference asset compensation"
        );
        assertEq(
            afterSnapshot.userSwapToken,
            beforeSnapshot.userSwapToken + cstSharesOut,
            "User should receive correct amount of cST shares"
        );
        assertEq(
            afterSnapshot.userPrincipalToken,
            beforeSnapshot.userPrincipalToken,
            "User principal token balance should remain unchanged"
        );

        // ================================ Contract State Changes ================================ //
        assertEq(
            afterSnapshot.contractCollateral,
            beforeSnapshot.contractCollateral + collateralAssetsIn - fee,
            "Contract collateral balance should increase by assets collateralAssetsIn excluding fee"
        );
        assertEq(
            afterSnapshot.contractRef,
            beforeSnapshot.contractRef - desiredReferenceAssetsOut,
            "Contract should send reference asset desiredReferenceAssetsOut"
        );

        // ================================ Pool Internal State Changes ================================ //
        assertEq(
            afterSnapshot.poolCollateral,
            beforeSnapshot.poolCollateral + (collateralAssetsIn - fee),
            "Pool collateral should increase by assets In minus fee"
        );
        assertEq(
            afterSnapshot.poolRef,
            beforeSnapshot.poolRef - desiredReferenceAssetsOut,
            "Pool reference assets should decrease by desiredReferenceAssetsOut"
        );

        // ================================ Internal State Consistency ================================ //
        assertEq(
            afterSnapshot.internalState.pool.balances.collateralAsset.locked,
            beforeSnapshot.internalState.pool.balances.collateralAsset.locked + (collateralAssetsIn - fee),
            "Locked collateral should increase by assets In minus fee"
        );
        assertEq(
            afterSnapshot.internalState.pool.balances.referenceAssetBalance,
            beforeSnapshot.internalState.pool.balances.referenceAssetBalance - desiredReferenceAssetsOut,
            "Reference asset balance should decrease by refAssetsOut"
        );
        assertEq(
            afterSnapshot.internalState.pool.balances.swapTokenBalance,
            beforeSnapshot.internalState.pool.balances.swapTokenBalance - cstSharesOut,
            "Swap token balance should decrease by shares spent"
        );

        // ================================ Treasury State Changes ================================ //
        assertEq(
            afterSnapshot.treasuryCollateral, beforeSnapshot.treasuryCollateral + fee, "Treasury should receive fee"
        );

        // ================================ Token Supply Consistency ================================ //
        assertEq(
            afterSnapshot.swapTokenTotalSupply,
            beforeSnapshot.swapTokenTotalSupply,
            "Swap token total supply should remain unchanged"
        );
        assertEq(
            afterSnapshot.principalTokenTotalSupply,
            beforeSnapshot.principalTokenTotalSupply,
            "Principal token total supply should remain unchanged"
        );
    }

    function testFuzz_previewUnwindExerciseOther_WithDifferentDecimals(
        uint8 collateralDecimals,
        uint8 referenceDecimals
    ) external {
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

        uint256 desiredReferenceAssetsOut =
            TransferHelper.fixedToTokenNativeDecimals(0.5 ether, referenceAsset.decimals());

        // Preview unwind exercise other
        (uint256 previewCollateralAssetsIn, uint256 previewCstSharesOut, uint256 previewFee) =
            corkPoolManager.previewUnwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut);

        // Execute actual unwind exercise other
        (uint256 actualCollateralAssetsIn, uint256 actualRefAssetsOut, uint256 actualFee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut, alice);

        // Verify preview matches actual
        assertEq(
            previewCollateralAssetsIn,
            actualCollateralAssetsIn,
            "Preview collateral assets in should match actual collateral assets in"
        );
        assertEq(previewCstSharesOut, actualRefAssetsOut, "Preview cST shares out should match actual ref assets out");
        assertEq(previewFee, actualFee, "Preview fee should match actual fee");
    }

    function testFuzz_unwindExerciseOther_ShouldRequireMoreAsset_WhenDustAmount(uint256 rate)
        external
        __createPoolBounded(1 days, 6, 18)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        rate = bound(rate, 0.5 ether, 0.99 ether);
        testOracle.setRate(rate);

        StateSnapshot memory initialSnapshot = _getStateSnapshot(alice, defaultPoolId);

        uint256 desiredReferenceAssetsOut = 1;

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, desiredReferenceAssetsOut, alice);

        StateSnapshot memory finalSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // should at least cost something
        // NOTE : currently it does 2 ceil div, thus requiring 2 collateral assetIn in edgecase like this
        assertEq(collateralAssetsIn, 2);
        assertEq(finalSnapshot.userRef - initialSnapshot.userRef, desiredReferenceAssetsOut);
        assertEq(cstSharesOut, 0);
        assertEq(finalSnapshot.userSwapToken - initialSnapshot.userSwapToken, 0);
    }
}
