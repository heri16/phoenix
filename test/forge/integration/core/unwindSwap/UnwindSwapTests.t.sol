// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnwindSwapTests is BaseTest {
    uint256 internal constant EXPIRY = 1 days;
    uint256 internal depositAmount = 2000 ether;
    uint256 internal swapAmount = 1000 ether;

    // ================================ UnwindSwap Tests ================================ //

    function test_unwindSwapBasic_ShouldWorkCorrectly() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        uint256 desiredAssetsIn = 0.5 ether;

        // Take state snapshot before unwindSwap
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedCstSharesOut, uint256 expectedRefAssetsOut, uint256 expectedFee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, desiredAssetsIn);

        (uint256 cstSharesOut, uint256 refAssetsOut, uint256 fee) =
            corkPoolManager.unwindSwap(defaultPoolId, desiredAssetsIn, alice);

        // Take state snapshot after unwindSwap
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Assert unwindSwap return values match preview
        assertEq(cstSharesOut, expectedCstSharesOut, "CstSharesOut should match preview");
        assertEq(refAssetsOut, expectedRefAssetsOut, "RefAssetsOut should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // Assert alice balance changes
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral - desiredAssetsIn,
            "User should spend exact collateral amount"
        );
        assertEq(
            stateAfter.userRef,
            stateBefore.userRef + refAssetsOut,
            "User should recieve correct amount of reference asset compensation"
        );
        assertEq(
            stateAfter.userSwapToken,
            stateBefore.userSwapToken + cstSharesOut,
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
            stateBefore.contractCollateral + desiredAssetsIn - fee,
            "Contract collateral balance should increase by assets out excluding fee"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef - refAssetsOut,
            "Contract should sent reference asset refAssetsOut"
        );

        // Assert pool asset tracking
        assertEq(
            stateAfter.poolCollateral,
            stateBefore.poolCollateral + (desiredAssetsIn - fee),
            "Pool collateral should increase by assets out minus fee"
        );
        assertEq(
            stateAfter.poolRef,
            stateBefore.poolRef - refAssetsOut,
            "Pool reference assets should decrease by refAssetsOut"
        );

        // Assert internal state changes
        assertEq(
            stateAfter.internalState.pool.balances.collateralAsset.locked,
            stateBefore.internalState.pool.balances.collateralAsset.locked + (desiredAssetsIn - fee),
            "Locked collateral should increase by assets out minus fee"
        );
        assertEq(
            stateAfter.internalState.pool.balances.referenceAssetBalance,
            stateBefore.internalState.pool.balances.referenceAssetBalance - refAssetsOut,
            "Reference asset balance should decrease by refAssetsOut"
        );
        assertEq(
            stateAfter.internalState.pool.balances.swapTokenBalance,
            stateBefore.internalState.pool.balances.swapTokenBalance - cstSharesOut,
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

    function test_unwindSwap_ShouldEmitcorrectEvents()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        uint256 assetAmount = 100 ether;
        uint256 expectedCompensation = 99_000_011_574_208_034_816;
        uint256 expectedShares = 99_000_011_574_208_034_816;
        uint256 expectedFee = 100 ether - expectedCompensation;

        (address principalToken,) = corkPoolManager.shares(defaultPoolId);

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(defaultPoolId, alice, alice, assetAmount, expectedCompensation, 0, 0, true);
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(defaultPoolId, alice, expectedFee, 0, true);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Deposit(alice, alice, assetAmount - expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(alice, alice, alice, address(referenceAsset), expectedCompensation, 0);
        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.unwindSwap(defaultPoolId, assetAmount, alice);

        assertEq(shares, expectedShares, "Should show correct cST shares");
        assertEq(compensation, expectedCompensation, "Should show correct reference asset compensation");
    }

    function test_unwindSwap_ShouldWorkWithDifferentOwnerReceiver()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        overridePrank(bob);
        _deposit(defaultPoolId, depositAmount, currentCaller());
        _swap(defaultPoolId, swapAmount, currentCaller());

        uint256 desiredAssetsIn = 0.3 ether;

        uint256 bobCaBefore = collateralAsset.balanceOf(bob);
        uint256 bobRaBefore = referenceAsset.balanceOf(bob);
        uint256 bobCstBefore = swapToken.balanceOf(bob);
        uint256 aliceCaBefore = collateralAsset.balanceOf(alice);

        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.unwindSwap(defaultPoolId, desiredAssetsIn, alice);

        uint256 bobCaAfter = collateralAsset.balanceOf(bob);
        uint256 bobRaAfter = referenceAsset.balanceOf(bob);
        uint256 bobCstAfter = swapToken.balanceOf(bob);
        uint256 aliceCaAfter = collateralAsset.balanceOf(alice);

        assertGt(shares, 0, "Should unlock cST shares");
        assertGt(compensation, 0, "Should unlock reference asset compensation");
        assertEq(bobCaBefore - bobCaAfter, desiredAssetsIn, "bob should spend collateral assets");
        assertEq(bobCstAfter, bobCstBefore, "bob should not receive cST shares");
        assertEq(bobRaAfter, bobRaBefore, "bob should not receive reference assets");
    }

    // ================================ Preview Unwind Swap Tests ================================ //

    function test_previewUnwindSwap_ShouldReturnCorrectAmounts() external {
        overridePrank(bravo);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        uint256 assets = 1 ether;
        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.previewUnwindSwap(defaultPoolId, assets);

        assertEq(shares, 1 ether, "Should receive correct cST shares");
        assertEq(compensation, 1 ether, "Should receive correct reference assets");
        assertEq(fee, 0, "Should have exact fee");
    }

    function test_previewUnwindSwap_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        uint256 assets = 1 ether;

        (uint256 poolManagerSharesIn, uint256 poolManagerCompensation, uint256 poolManagerFee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, assets);
        (uint256 poolShareSharesIn, uint256 poolShareCompensation, uint256 poolShareFee) =
            swapToken.previewUnwindSwap(assets);

        assertEq(
            poolShareSharesIn,
            poolManagerSharesIn,
            "PoolShare previewUnwindSwap sharesIn should match PoolManager previewUnwindSwap"
        );
        assertEq(
            poolShareCompensation,
            poolManagerCompensation,
            "PoolShare previewUnwindSwap compensation should match PoolManager previewUnwindSwap"
        );
        assertEq(
            poolShareFee, poolManagerFee, "PoolShare previewUnwindSwap fee should match PoolManager previewUnwindSwap"
        );
    }

    function test_previewUnwindSwap_ShouldReturnZero_AfterExpiry()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, 0.5 ether);
        assertEq(shares, 0, "Should return zero shares");
        assertEq(compensation, 0, "Should return zero compensation");
        assertEq(fee, 0, "Should return zero fee");
    }

    function test_previewUnwindSwap_ShouldReturnZero_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, 100 ether);
        assertEq(shares, 0, "Should return zero shares");
        assertEq(compensation, 0, "Should return zero compensation");
        assertEq(fee, 0, "Should return zero fee");
    }

    // ================================ Max Unwind Swap Tests ================================ //

    function test_maxUnwindSwap_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        uint256 poolManagerResult = corkPoolManager.maxUnwindSwap(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxUnwindSwap(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindSwap should match PoolManager maxUnwindSwap");
    }

    function test_maxUnwindSwap_ShouldReturnZero_AfterExpiry()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 maxCollateralAssetsIn) = corkPoolManager.maxUnwindSwap(defaultPoolId, alice);
        assertEq(maxCollateralAssetsIn, 0, "Should return zero maxCollateralAssetsIn");
    }

    function test_maxUnwindSwap_ShouldReturnZero_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        (uint256 maxCollateralAssetsIn) = corkPoolManager.maxUnwindSwap(defaultPoolId, alice);
        assertEq(maxCollateralAssetsIn, 0, "Should return zero maxCollateralAssetsIn");
    }

    // ================================ Negative Test Cases ================================ //

    function test_unwindSwap_ShouldRevert_WhenInsufficientReferenceAssetLiquidity()
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

        uint256 unwindAmount = 200 ether;
        (uint256 previewSwapAsset, uint256 previewReferenceAsset,) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut > referenceAssets balance of pool)
        assertGt(previewReferenceAsset, referenceAssets, "Reference asset check MUST exceed available");

        // 2. Swap token check (swapAssetOut <= available swap tokens balance of pool)
        assertLe(previewSwapAsset, cstInPool, "Swap asset required MUST be less than available");

        overridePrank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", referenceAssets, previewReferenceAsset)
        );
        corkPoolManager.unwindSwap(defaultPoolId, unwindAmount, alice);
    }

    function test_unwindSwap_ShouldRevert_WhenInsufficientSwapTokenLiquidity()
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

        uint256 unwindAmount = 220 ether;
        (uint256 previewSwapAsset, uint256 previewReferenceAsset,) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut <= referenceAssets balance of pool)
        assertLe(previewReferenceAsset, referenceAssets, "Reference asset check MUST less than available");

        // 2. Swap token check (swapAssetOut > available swap tokens balance of pool)
        assertGt(previewSwapAsset, cstInPool, "Swap asset required MUST exceed available");

        overridePrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", cstInPool, previewSwapAsset));
        corkPoolManager.unwindSwap(defaultPoolId, unwindAmount, alice);
    }

    function test_unwindSwap_ShouldRevertAfterExpiry() external __as(alice) __depositAndSwap(2 ether, 1 ether, alice) {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        vm.expectRevert(IErrors.Expired.selector);
        corkPoolManager.unwindSwap(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindSwap_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindSwap(defaultPoolId, 0, alice);
    }

    function test_unwindSwap_ShouldRevert_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4);
        overridePrank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(defaultPoolId, 100 ether, alice);
    }

    function test_previewUnwindSwap_ShouldReturnZeroZeroZero_WhenZeroAmount()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        (uint256 swapAssetOut, uint256 compensationOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, 0);

        assertEq(swapAssetOut, 0, "Should return 0 swap asset out for zero amount");
        assertEq(compensationOut, 0, "Should return 0 compensation out for zero amount");
        assertEq(fee, 0, "Should return 0 fee for zero amount");
    }

    function test_previewUnwindSwap_ShouldReturnZeroZeroZero_WhenUnwindSwapPaused()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4); // 10000 = unwind swap paused

        overridePrank(alice);
        (uint256 swapAssetOut, uint256 compensationOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, 100 ether);

        assertEq(swapAssetOut, 0, "Should return 0 swap asset out when unwind swap paused");
        assertEq(compensationOut, 0, "Should return 0 compensation out when unwind swap paused");
        assertEq(fee, 0, "Should return 0 fee when unwind swap paused");
    }

    function test_previewUnwindSwap_ShouldReturnZeroZeroZero_WhenExpired()
        external
        __as(alice)
        __depositAndSwap(depositAmount, swapAmount, alice)
    {
        vm.warp(block.timestamp + 2 days);

        (uint256 swapAssetOut, uint256 compensationOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, 100 ether);

        assertEq(swapAssetOut, 0, "Should return 0 swap asset out when expired");
        assertEq(compensationOut, 0, "Should return 0 compensation out when expired");
        assertEq(fee, 0, "Should return 0 fee when expired");
    }

    function test_unwindSwap_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.unwindSwap(fakePoolId, 1 ether, alice);
    }

    function test_unwindSwap_ShouldRevert_WhenGloballyPaused()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        // Pause the entire contract (not just swaps for a specific pool)
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindSwap_ShouldRevert_WhenInsufficientCollateralAssetBalance()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        // Transfer away all collateral assets so user has none for unwindSwap
        collateralAsset.transfer(bob, referenceAsset.balanceOf(alice));

        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)", alice, 10_101_010_101_010_102, 0.5 ether
            )
        );
        corkPoolManager.unwindSwap(defaultPoolId, 0.5 ether, alice);
    }

    function test_unwindSwap_ShouldRevert_WhenReceiverIsZeroAddress()
        external
        __as(alice)
        __depositAndSwap(2 ether, 1 ether, alice)
    {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        corkPoolManager.unwindSwap(defaultPoolId, 0.5 ether, address(0));
    }

    function test_previewUnwindSwap_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.previewUnwindSwap(fakePoolId, 1 ether);
    }

    function test_maxUnwindSwap_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxUnwindSwap(fakePoolId, alice);
    }

    // ================================ Fuzz Tests ================================ //

    function testFuzz_unwindSwap_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
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

        uint256 desiredAssetsIn = TransferHelper.fixedToTokenNativeDecimals(0.5 ether, collateralAsset.decimals());

        // Take snapshots before unwindSwap
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedCstSharesOut, uint256 expectedRefAssetsOut, uint256 expectedFee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, desiredAssetsIn);

        (uint256 cstSharesOut, uint256 refAssetsOut, uint256 fee) =
            corkPoolManager.unwindSwap(defaultPoolId, desiredAssetsIn, alice);

        // Take snapshots after unwindSwap
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(cstSharesOut, expectedCstSharesOut, "CstSharesOut should match preview");
        assertEq(refAssetsOut, expectedRefAssetsOut, "RefAssetsOut should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // ================================ User State Changes ================================ //
        assertEq(
            afterSnapshot.userCollateral,
            beforeSnapshot.userCollateral - desiredAssetsIn,
            "User should spend exact collateral amount"
        );
        assertEq(
            afterSnapshot.userRef,
            beforeSnapshot.userRef + refAssetsOut,
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
            beforeSnapshot.contractCollateral + desiredAssetsIn - fee,
            "Contract collateral balance should increase by assets in excluding fee"
        );
        assertEq(
            afterSnapshot.contractRef,
            beforeSnapshot.contractRef - refAssetsOut,
            "Contract should send reference asset refAssetsOut"
        );

        // ================================ Pool Internal State Changes ================================ //
        assertEq(
            afterSnapshot.poolCollateral,
            beforeSnapshot.poolCollateral + (desiredAssetsIn - fee),
            "Pool collateral should increase by assets in minus fee"
        );
        assertEq(
            afterSnapshot.poolRef,
            beforeSnapshot.poolRef - refAssetsOut,
            "Pool reference assets should decrease by refAssetsOut"
        );

        // ================================ Internal State Consistency ================================ //
        assertEq(
            afterSnapshot.internalState.pool.balances.collateralAsset.locked,
            beforeSnapshot.internalState.pool.balances.collateralAsset.locked + (desiredAssetsIn - fee),
            "Locked collateral should increase by assets in minus fee"
        );
        assertEq(
            afterSnapshot.internalState.pool.balances.referenceAssetBalance,
            beforeSnapshot.internalState.pool.balances.referenceAssetBalance - refAssetsOut,
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

    function testFuzz_previewUnwindSwap_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals)
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

        uint256 desiredAssetsIn = TransferHelper.fixedToTokenNativeDecimals(0.5 ether, collateralAsset.decimals());

        // Preview unwind swap
        (uint256 previewCstSharesOut, uint256 previewRefAssetsOut, uint256 previewFee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, desiredAssetsIn);

        // Execute actual unwind swap
        (uint256 actualCstSharesOut, uint256 actualRefAssetsOut, uint256 actualFee) =
            corkPoolManager.unwindSwap(defaultPoolId, desiredAssetsIn, alice);

        // Verify preview matches actual
        assertEq(previewCstSharesOut, actualCstSharesOut, "Preview cST shares out should match actual cST shares out");
        assertEq(previewRefAssetsOut, actualRefAssetsOut, "Preview ref assets out should match actual ref assets out");
        assertEq(previewFee, actualFee, "Preview fee should match actual fee");
    }

    // ================================ maxUnwindSwap Branch Coverage Tests ================================ //

    function test_maxUnwindSwap_ShouldReturnZero_WhenNotInitialized() external __as(alice) {
        MarketId uninitializedPoolId = MarketId.wrap(bytes32("0x123"));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxUnwindSwap(uninitializedPoolId, alice);
    }

    function test_maxUnwindSwap_ShouldReturnZero_WhenPoolHasZeroReferenceAsset() external __as(alice) {
        // Create a pool but drain all reference assets
        _deposit(defaultPoolId, depositAmount, alice);

        // Drain all reference assets from the pool
        uint256 poolRefBalance = referenceAsset.balanceOf(address(corkPoolManager));

        overridePrank(address(corkPoolManager));
        referenceAsset.transfer(bob, poolRefBalance);

        overridePrank(alice);
        uint256 maxAmount = corkPoolManager.maxUnwindSwap(defaultPoolId, alice);
        assertEq(maxAmount, 0, "Should return 0 when pool has zero reference asset balance");
    }

    function test_maxUnwindSwap_ShouldReturnZero_WhenPoolHasZeroSwapToken() external __as(alice) {
        // Create a pool but drain all cST
        _deposit(defaultPoolId, depositAmount, alice);

        // Drain all cST from the pool
        (, address swapTokenAddress) = corkPoolManager.shares(defaultPoolId);
        IERC20 swapTokenERC20 = IERC20(swapTokenAddress);
        uint256 poolSwapBalance = swapTokenERC20.balanceOf(address(corkPoolManager));

        overridePrank(address(corkPoolManager));
        swapTokenERC20.transfer(bob, poolSwapBalance);

        overridePrank(alice);
        uint256 maxAmount = corkPoolManager.maxUnwindSwap(defaultPoolId, alice);
        assertEq(maxAmount, 0, "Should return 0 when pool has zero swap token balance");
    }

    function testFuzz_unwindSwapShouldNotRevert_WhenUsingMaxUnwindSwapInput(
        uint8 _collateralDecimal,
        uint8 _referenceDecimal,
        uint256 depositAmount
    )
        external
        __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
    {
        // Bound deposit amount to reasonable values
        depositAmount = bound(depositAmount, 10 ether, type(uint64).max);

        // Deposit to get cST shares
        _deposit(defaultPoolId, depositAmount, alice);

        // Swap to create locked positions
        uint256 maxSwap = corkPoolManager.maxSwap(defaultPoolId, alice);
        uint256 swapAmount = maxSwap / 2;
        corkPoolManager.swap(defaultPoolId, swapAmount, alice);

        // Get max unwindable collateral assets
        uint256 collateralAssetsIn = corkPoolManager.maxUnwindSwap(defaultPoolId, alice);

        // should not revert
        corkPoolManager.unwindSwap(defaultPoolId, collateralAssetsIn, alice);
    }
}
