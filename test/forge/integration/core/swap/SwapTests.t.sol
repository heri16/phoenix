// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SwapTests is BaseTest {
    uint256 internal constant EXPIRY = 1 days;
    uint256 internal depositAmount = 1000 ether;

    struct PreviewswapVars {
        uint256 collateralAsset;
        uint256 swapToken;
        uint256 fee;
        uint256 rate;
    }

    struct BalanceSnapshot {
        uint256 collateralAsset;
        uint256 referenceAsset;
        uint256 swapToken;
        uint256 principalToken;
    }

    function defaultSwapRate() internal pure returns (uint256) {
        return 1.0 ether;
    }

    // ================================ Swap Tests ================================ //

    function test_swapRate() public {
        uint256 rate = corkPoolManager.swapRate(defaultPoolId);
        assertEq(rate, defaultSwapRate(), "Swap rate should match default");
    }

    function test_swapBasic() external __as(alice) __deposit(1 ether, alice) {
        uint256 desiredAssets = 0.5 ether;

        // Take state snapshot before swap
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedShares, uint256 expectedCompensation, uint256 expectedFee) =
            corkPoolManager.previewSwap(defaultPoolId, desiredAssets);

        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultPoolId, desiredAssets, alice);

        // Take state snapshot after swap
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Assert swap return values match preview
        assertEq(shares, expectedShares, "Shares should match preview");
        assertEq(compensation, expectedCompensation, "Compensation should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // Assert user balance changes
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + desiredAssets,
            "User should receive exact collateral amount"
        );
        assertEq(
            stateAfter.userRef, stateBefore.userRef - compensation, "User should spend reference asset compensation"
        );
        assertEq(
            stateAfter.userPrincipalToken,
            stateBefore.userPrincipalToken,
            "User principal token balance should remain unchanged"
        );

        // Assert contract balance changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral - (desiredAssets + fee),
            "Contract collateral balance should decrease by assets out plus fee"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef + compensation,
            "Contract should receive reference asset compensation"
        );

        // Assert pool asset tracking
        assertEq(
            stateAfter.poolCollateral,
            stateBefore.poolCollateral - (desiredAssets + fee),
            "Pool collateral should decrease by assets out plus fee"
        );
        assertEq(
            stateAfter.poolRef,
            stateBefore.poolRef + compensation,
            "Pool reference assets should increase by compensation"
        );

        // Assert internal state changes
        assertEq(
            stateAfter.internalState.pool.balances.collateralAsset.locked,
            stateBefore.internalState.pool.balances.collateralAsset.locked - (desiredAssets + fee),
            "Locked collateral should decrease by assets out plus fee"
        );
        assertEq(
            stateAfter.internalState.pool.balances.referenceAssetBalance,
            stateBefore.internalState.pool.balances.referenceAssetBalance + compensation,
            "Reference asset balance should increase by compensation"
        );
        assertEq(
            stateAfter.internalState.pool.balances.swapTokenBalance,
            stateBefore.internalState.pool.balances.swapTokenBalance + shares,
            "Swap token balance should increase by shares received"
        );
    }

    function test_swap_shouldNotReleaseFreeCollateral()
        external
        __createPool(1 days, 6, 18)
        __giveAssets(bravo)
        __approveAllTokens(bravo, address(corkPoolManager))
        __as(bravo)
    {
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 99_999_900_001_000);

        corkPoolManager.mint(defaultPoolId, 100 ether, bravo);

        uint256 collateralOut = 1e6;

        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultPoolId, collateralOut, bravo);

        assertEq(shares, collateralOut * 10 ** 12 + fee * 10 ** 12);

        (uint256 collateralLocked, uint256 referenceLocked) = corkPoolManager.assets(defaultPoolId);

        uint256 collateralNormalized = TransferHelper.normalizeDecimals(collateralLocked, 6, 18);

        uint256 sharesTotalSupply = swapToken.totalSupply();

        assertEq(referenceLocked + collateralNormalized, sharesTotalSupply);
    }

    function test_swap_ShouldEmitcorrectEvents() external __as(alice) __deposit(depositAmount, alice) {
        uint256 assetAmount = 100 ether;
        uint256 expectedCompensation = 101_010_101_010_101_010_102;
        uint256 expectedShares = 101_010_101_010_101_010_102;
        uint256 expectedFee = 1_010_101_010_101_010_102;

        (address _principalToken,) = corkPoolManager.shares(defaultPoolId);
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(defaultPoolId, alice, alice, assetAmount, expectedCompensation, 0, 0, false);
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(defaultPoolId, alice, expectedFee, 0, false);
        vm.expectEmit(true, true, true, true, _principalToken);
        emit IPoolShare.Withdraw(alice, alice, alice, assetAmount + expectedFee, 0);
        vm.expectEmit(true, true, true, true, _principalToken);
        emit IPoolShare.DepositOther(alice, alice, address(referenceAsset), expectedCompensation, 0);
        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultPoolId, assetAmount, alice);

        assertEq(shares, expectedShares, "Should provide cST shares");
        assertEq(compensation, expectedCompensation, "Should require reference asset compensation");
    }

    function test_swapWithDifferentOwnerReceiver() external __as(alice) __deposit(1 ether, alice) {
        overridePrank(bob);
        _deposit(defaultPoolId, 1 ether, currentCaller());

        uint256 desiredAssets = 0.3 ether;

        uint256 bobCaBefore = collateralAsset.balanceOf(bob);
        uint256 bobRaBefore = referenceAsset.balanceOf(bob);
        uint256 bobCstBefore = swapToken.balanceOf(bob);
        uint256 aliceCaBefore = collateralAsset.balanceOf(alice);

        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultPoolId, desiredAssets, alice);

        uint256 bobCaAfter = collateralAsset.balanceOf(bob);
        uint256 bobRaAfter = referenceAsset.balanceOf(bob);
        uint256 bobCstAfter = swapToken.balanceOf(bob);
        uint256 aliceCaAfter = collateralAsset.balanceOf(alice);

        assertGt(shares, 0, "Should lock cST shares");
        assertGt(compensation, 0, "Should lock reference asset compensation");
        assertEq(aliceCaAfter - aliceCaBefore, desiredAssets, "Receiver should get exact collateral amount");
        assertEq(bobCstBefore - bobCstAfter, shares, "bob should spend cST shares");
        assertEq(bobRaBefore - bobRaAfter, compensation, "bob should spend reference asset compensation");
        assertEq(bobCaAfter, bobCaBefore, "bob should not receive collateral assets");
    }

    function test_previewSwapWithSwapToken() external __as(alice) __deposit(1 ether, alice) {
        uint256 swapAmount = 0.5 ether;

        BalanceSnapshot memory beforeBalances = BalanceSnapshot({
            collateralAsset: collateralAsset.balanceOf(alice),
            referenceAsset: referenceAsset.balanceOf(alice),
            swapToken: swapToken.balanceOf(alice),
            principalToken: principalToken.balanceOf(alice)
        });

        PreviewswapVars memory preview;
        (preview.collateralAsset, preview.swapToken, preview.fee) =
            corkPoolManager.previewExercise(defaultPoolId, swapAmount);
        preview.rate = corkPoolManager.swapRate(defaultPoolId);

        PreviewswapVars memory actual;
        (actual.collateralAsset, actual.swapToken, actual.fee) =
            corkPoolManager.exerciseOther(defaultPoolId, swapAmount, alice);
        actual.rate = corkPoolManager.swapRate(defaultPoolId);

        BalanceSnapshot memory afterBalances = BalanceSnapshot({
            collateralAsset: collateralAsset.balanceOf(alice),
            referenceAsset: referenceAsset.balanceOf(alice),
            swapToken: swapToken.balanceOf(alice),
            principalToken: principalToken.balanceOf(alice)
        });

        assertEq(preview.collateralAsset, actual.collateralAsset);
        assertEq(preview.swapToken, actual.swapToken);
        assertEq(preview.fee, actual.fee);
        assertEq(preview.rate, actual.rate);

        assertEq(afterBalances.collateralAsset - beforeBalances.collateralAsset, actual.collateralAsset);
        assertEq(beforeBalances.swapToken - afterBalances.swapToken, actual.swapToken);
    }

    // ================================ Rate Update Tests ================================ //

    function testFuzz_swap(uint8 _collateralDecimal, uint8 _referenceDecimal)
        external
        __createPoolBounded(EXPIRY, _collateralDecimal, _referenceDecimal)
        __giveAssets(bravo)
        __approveAllTokens(bravo, address(corkPoolManager))
    {
        uint256 depositAmountNormalized =
            TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 desiredAssets = TransferHelper.normalizeDecimals(0.5 ether, TARGET_DECIMALS, collateralDecimal);

        // First deposit to have liquidity for swap
        corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Take state snapshot before swap
        StateSnapshot memory stateBefore = _getStateSnapshot(currentCaller(), defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedShares, uint256 expectedCompensation, uint256 expectedFee) =
            corkPoolManager.previewSwap(defaultPoolId, desiredAssets);

        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.swap(defaultPoolId, desiredAssets, currentCaller());

        // Take state snapshot after swap
        StateSnapshot memory stateAfter = _getStateSnapshot(currentCaller(), defaultPoolId);

        // Assert swap return values match preview
        assertEq(shares, expectedShares, "Shares should match preview");
        assertEq(compensation, expectedCompensation, "Compensation should match preview");
        assertEq(fee, expectedFee, "Fee should match preview");

        // Assert user balance changes
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + desiredAssets,
            "User should receive exact collateral amount"
        );
        assertEq(
            stateAfter.userRef, stateBefore.userRef - compensation, "User should spend reference asset compensation"
        );
        assertEq(
            stateAfter.userPrincipalToken,
            stateBefore.userPrincipalToken,
            "User principal token balance should remain unchanged"
        );

        // Assert contract balance changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral - (desiredAssets + fee),
            "Contract collateral balance should decrease by assets out plus fee"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef + compensation,
            "Contract should receive reference asset compensation"
        );

        // Assert pool asset tracking
        assertEq(
            stateAfter.poolCollateral,
            stateBefore.poolCollateral - (desiredAssets + fee),
            "Pool collateral should decrease by assets out plus fee"
        );
        assertEq(
            stateAfter.poolRef,
            stateBefore.poolRef + compensation,
            "Pool reference assets should increase by compensation"
        );

        // Assert internal state changes
        assertEq(
            stateAfter.internalState.pool.balances.collateralAsset.locked,
            stateBefore.internalState.pool.balances.collateralAsset.locked - (desiredAssets + fee),
            "Locked collateral should decrease by assets out plus fee"
        );
        assertEq(
            stateAfter.internalState.pool.balances.referenceAssetBalance,
            stateBefore.internalState.pool.balances.referenceAssetBalance + compensation,
            "Reference asset balance should increase by compensation"
        );
        assertEq(
            stateAfter.internalState.pool.balances.swapTokenBalance,
            stateBefore.internalState.pool.balances.swapTokenBalance + shares,
            "Swap token balance should increase by shares received"
        );
    }

    function testFuzz_previewSwap(uint8 _collateralDecimal, uint8 _referenceDecimal)
        external
        __createPoolBounded(EXPIRY, _collateralDecimal, _referenceDecimal)
        __giveAssets(bravo)
        __approveAllTokens(bravo, address(corkPoolManager))
    {
        uint256 depositAmountNormalized =
            TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, collateralDecimal);
        uint256 desiredAssets = TransferHelper.normalizeDecimals(0.5 ether, TARGET_DECIMALS, collateralDecimal);

        // First deposit to have liquidity for swap
        corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Preview swap
        (uint256 previewShares, uint256 previewCompensation, uint256 previewFee) =
            corkPoolManager.previewSwap(defaultPoolId, desiredAssets);

        // Execute actual swap
        (uint256 actualShares, uint256 actualCompensation, uint256 actualFee) =
            corkPoolManager.swap(defaultPoolId, desiredAssets, currentCaller());

        // Verify preview matches actual
        assertEq(previewShares, actualShares, "Preview shares should match actual shares");
        assertEq(previewCompensation, actualCompensation, "Preview compensation should match actual compensation");
        assertEq(previewFee, actualFee, "Preview fee should match actual fee");

        // Verify that the swap functioned correctly with decimal normalization
        assertGt(actualShares, 0, "Should receive some shares");
        assertGt(actualCompensation, 0, "Should require some compensation");
    }

    // ================================ Interface Consistency Tests ================================ //

    function test_maxSwap_ShouldReturnSameValueAsPoolManager() external __as(alice) __deposit(depositAmount, alice) {
        uint256 poolManagerResult = corkPoolManager.maxSwap(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxSwap(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxSwap should match PoolManager maxSwap");
    }

    function test_previewSwap_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        uint256 assets = 1 ether;

        (uint256 poolManagerSharesOut, uint256 poolManagerCompensation, uint256 poolManagerFee) =
            corkPoolManager.previewSwap(defaultPoolId, assets);
        (uint256 poolShareSharesOut, uint256 poolShareCompensation, uint256 poolShareFee) =
            swapToken.previewSwap(assets);

        assertEq(
            poolShareSharesOut,
            poolManagerSharesOut,
            "PoolShare previewSwap sharesOut should match PoolManager previewSwap"
        );
        assertEq(
            poolShareCompensation,
            poolManagerCompensation,
            "PoolShare previewSwap compensation should match PoolManager previewSwap"
        );
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewSwap fee should match PoolManager previewSwap");
    }

    // ================================ Negative Test Cases ================================ //

    function test_swapInsufficientLiquidity() external __as(alice) __deposit(0.1 ether, alice) {
        uint256 desiredAssets = 1 ether;

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.swap(defaultPoolId, desiredAssets, alice);
    }

    function test_swapAfterExpiry() external __as(alice) __deposit(1 ether, alice) {
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        vm.expectPartialRevert(IErrors.Expired.selector);
        corkPoolManager.swap(defaultPoolId, 0.5 ether, alice);
    }

    function test_swap_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectPartialRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.swap(defaultPoolId, 0, alice);
    }

    function test_swap_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectPartialRevert(IErrors.Expired.selector);
        corkPoolManager.swap(defaultPoolId, 100 ether, alice);
    }

    function test_swap_ShouldRevert_WhenPaused() external __as(address(defaultCorkController)) {
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1);
        overridePrank(alice);

        vm.expectPartialRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.swap(defaultPoolId, 100 ether, alice);
    }

    function test_previewSwap_ShouldReturnZeroZeroZero_WhenZeroAssets()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        (uint256 sharesOut, uint256 compensation, uint256 fee) = corkPoolManager.previewSwap(defaultPoolId, 0);

        assertEq(sharesOut, 0, "Should return 0 shares out for zero assets");
        assertEq(compensation, 0, "Should return 0 compensation for zero assets");
        assertEq(fee, 0, "Should return 0 fee for zero assets");
    }

    function test_previewSwap_ShouldReturnZeroZeroZero_WhenSwapPaused()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        overridePrank(alice);
        (uint256 sharesOut, uint256 compensation, uint256 fee) = corkPoolManager.previewSwap(defaultPoolId, 100 ether);

        assertEq(sharesOut, 0, "Should return 0 shares out when swap paused");
        assertEq(compensation, 0, "Should return 0 compensation when swap paused");
        assertEq(fee, 0, "Should return 0 fee when swap paused");
    }

    function test_previewSwap_ShouldReturnZeroZeroZero_WhenExpired()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        vm.warp(block.timestamp + 2 days);

        (uint256 sharesOut, uint256 compensation, uint256 fee) = corkPoolManager.previewSwap(defaultPoolId, 100 ether);

        assertEq(sharesOut, 0, "Should return 0 shares out when expired");
        assertEq(compensation, 0, "Should return 0 compensation when expired");
        assertEq(fee, 0, "Should return 0 fee when expired");
    }

    function test_swap_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a non-existent pool ID
        MarketId fakePoolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.swap(fakePoolId, 1 ether, alice);
    }

    function test_swap_ShouldRevert_WhenGloballyPaused() external __as(alice) __deposit(1 ether, alice) {
        // Pause the entire contract (not just swaps for a specific pool)
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectPartialRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.swap(defaultPoolId, 0.5 ether, alice);
    }

    function test_swap_ShouldRevert_WhenInsufficientSwapTokenBalance() external __as(alice) __deposit(1 ether, alice) {
        // Transfer away all swap tokens so user has none
        swapToken.transfer(bob, swapToken.balanceOf(alice));

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        corkPoolManager.swap(defaultPoolId, 0.5 ether, alice);
    }

    function test_swap_ShouldRevert_WhenInsufficientReferenceAssetBalance()
        external
        __as(alice)
        __deposit(1 ether, alice)
    {
        // Transfer away all reference assets so user has none for compensation
        referenceAsset.transfer(bob, referenceAsset.balanceOf(alice));

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        corkPoolManager.swap(defaultPoolId, 0.5 ether, alice);
    }

    function test_swap_ShouldRevert_WhenReceiverIsZeroAddress() external __as(alice) __deposit(1 ether, alice) {
        vm.expectPartialRevert(IERC20Errors.ERC20InvalidReceiver.selector);
        corkPoolManager.swap(defaultPoolId, 0.5 ether, address(0));
    }

    function test_swap_ShouldRevert_WhenRateOracleReturnsInvalidData() external __as(alice) __deposit(10 ether, alice) {
        // Set oracle to return 0 rate (invalid)
        testOracle.setRate(defaultPoolId, 0);

        overridePrank(bravo);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee) =
            corkPoolManager.swap(defaultPoolId, 1 ether, alice);

        // should be capped at 0.9 rate
        // refIn = amount / rate + 1 (if appropriate for rounding)
        assertEq(referenceAssetsIn, 1_111_111_111_111_111_112);
    }

    function test_swap_EdgeCase_VerySmallAmount() external __as(alice) __deposit(1 ether, alice) {
        overridePrank(bravo);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        // Test with 1 wei
        uint256 verySmallAmount = 1;

        overridePrank(alice);
        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.swap(defaultPoolId, verySmallAmount, alice);

        // should atleast costs something
        assertEq(shares, 1);
        assertEq(compensation, 1);
    }

    // ================================ maxSwap Branch Coverage Tests ================================ //

    function test_maxSwap_ShouldReturnZero_WhenNotInitialized() external __as(alice) {
        MarketId uninitializedPoolId = MarketId.wrap(bytes32("0x123"));

        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxSwap(uninitializedPoolId, alice);
    }

    function test_maxSwap_ShouldReturnZero_WhenExpired() external __as(alice) __deposit(depositAmount, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 maxAssets = corkPoolManager.maxSwap(defaultPoolId, alice);
        assertEq(maxAssets, 0, "Should return 0 when expired");
    }

    function test_maxSwap_ShouldReturnZero_WhenSwapPaused() external __as(alice) __deposit(depositAmount, alice) {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 1); // 00010 = swap paused

        overridePrank(alice);
        uint256 maxAssets = corkPoolManager.maxSwap(defaultPoolId, alice);
        assertEq(maxAssets, 0, "Should return 0 when swap paused");
    }

    function test_maxSwap_ShouldReturnZero_WhenUserHasZeroCST() external __as(alice) __deposit(depositAmount, alice) {
        // Transfer away all cST from user
        swapToken.transfer(bob, swapToken.balanceOf(alice));

        uint256 maxAssets = corkPoolManager.maxSwap(defaultPoolId, alice);
        assertEq(maxAssets, 0, "Should return 0 when user has no cST balance");
    }

    function test_maxSwap_ShouldReturnZero_WhenUserHasZeroReferenceAsset()
        external
        __as(alice)
        __deposit(depositAmount, alice)
    {
        // Transfer away all reference assets from user
        referenceAsset.transfer(bob, referenceAsset.balanceOf(alice));

        uint256 maxAssets = corkPoolManager.maxSwap(defaultPoolId, alice);
        assertEq(maxAssets, 0, "Should return 0 when user has no reference asset balance");
    }

    function testFuzz_swapShouldNotRevert_WhenUsingMaxSwapInput(
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

        uint256 collateralAssetsOut = corkPoolManager.maxSwap(defaultPoolId, alice);

        // should not revert
        corkPoolManager.swap(defaultPoolId, collateralAssetsOut, alice);
    }
}
