// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract RedeemTests is BaseTest {
    uint256 constant EXPIRY = 1 days;
    uint256 redeemAmount = 100 ether;
    uint256 depositAmount = 1000 ether;

    // ================================ Basic Redeem Tests ================================ //

    function test_redeem() external __as(alice) __deposit(depositAmount, alice) {
        vm.warp(block.timestamp + 2 days); // Expire

        // Get state before redeem
        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        // Execute redeem
        (uint256 accruedRef, uint256 accruedCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, alice);

        // Get state after redeem
        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        // Verify user asset balances
        assertGt(accruedCollateral, 0, "Should receive collateral");
        assertEq(_after.userRef - before.userRef, accruedRef, "User should receive reference assets");
        assertEq(_after.userCollateral - before.userCollateral, accruedCollateral, "User should receive collateral assets");

        // Verify principal token state changes
        assertEq(before.userPrincipalToken - _after.userPrincipalToken, redeemAmount, "User principal tokens should be burned");
        assertEq(before.principalTokenTotalSupply - _after.principalTokenTotalSupply, redeemAmount, "Principal token total supply should decrease");

        // Verify contract asset balances
        assertEq(before.contractRef - _after.contractRef, accruedRef, "Contract reference asset balance should decrease");
        assertEq(before.contractCollateral - _after.contractCollateral, accruedCollateral, "Contract collateral asset balance should decrease");

        // Verify pool state changes (balances should be the same regardless of  liquidity separation)
        assertEq(_after.poolCollateral, 900 ether, "Pool collateral balance be the same regardless of liquidity separation");
        assertEq(_after.poolRef, 0, "Pool reference balance be the same regardless of liquidity separation");

        // Verify internal state changes
        assertTrue(_after.internalState.pool.liquiditySeparated, "Liquidity should be separated after first redeem");
        assertEq(_after.internalState.shares.withdrawn, redeemAmount, "Withdrawn shares should be tracked");
        assertEq(_after.internalState.pool.balances.collateralAsset.locked, 0, "Internal collateral balance should be 0 after liquidity separation");
        assertEq(_after.internalState.pool.balances.referenceAssetBalance, 0, "Internal reference balance should be 0 after liquidity separation");
        assertEq(_after.internalState.pool.poolArchive.collateralAssetAccrued, 900 ether, "Pool archive collateral should decrease by redeemed amount");
        assertEq(_after.internalState.pool.poolArchive.referenceAssetAccrued, 0, "Pool archive reference should decrease by redeemed amount");
    }

    function test_redeem_ShouldWork() external __as(alice) __deposit(depositAmount, alice) {
        vm.warp(block.timestamp + 2 days); // Expire

        // Preview to get expected values
        (uint256 expectedRef, uint256 expectedCollateral) = corkPoolManager.previewRedeem(defaultPoolId, redeemAmount);

        (address principalToken,) = corkPoolManager.shares(defaultPoolId);

        // Expect both PoolModifyLiquidity and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, expectedCollateral, expectedRef, true);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Withdraw(alice, alice, alice, expectedCollateral, redeemAmount);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(alice, alice, alice, address(referenceAsset), expectedRef, redeemAmount);

        (uint256 accruedRef, uint256 accruedCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, alice);

        assertEq(accruedCollateral, redeemAmount, "Should receive collateral");
    }

    function test_previewRedeem() external __as(alice) __deposit(1 ether, alice) {
        // Forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 withdrawAmount = 1 ether;

        // Get balances before
        uint256 userPaBefore = referenceAsset.balanceOf(alice);
        uint256 userRaBefore = collateralAsset.balanceOf(alice);

        // Preview redeem
        (uint256 previewPa, uint256 previewRa) = corkPoolManager.previewRedeem(defaultPoolId, withdrawAmount);

        // Execute actual redeem
        (uint256 actualPa, uint256 actualRa) = corkPoolManager.redeem(defaultPoolId, withdrawAmount, alice, alice);

        // Get balances after
        uint256 userPaAfter = referenceAsset.balanceOf(alice);
        uint256 userRaAfter = collateralAsset.balanceOf(alice);

        // Assert preview matches actual
        assertEq(previewPa, actualPa);
        assertEq(previewRa, actualRa);

        // Assert balances changed correctly
        assertEq(userPaAfter - userPaBefore, actualPa); // User received Reference Asset
        assertEq(userRaAfter - userRaBefore, actualRa); // User received Collateral Asset
    }

    function test_previewRedeem_ShouldReturnCorrectAmounts_WhenExpired() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 amount = 100 ether;
        (uint256 accruedCollateral, uint256 accruedRef) = corkPoolManager.previewRedeem(defaultPoolId, amount);

        assertEq(accruedCollateral, 0, "Should calculate collateral amount correctly");
        assertEq(accruedRef, 100 ether, "Should calculate reference amount correctly");
    }

    // ================================ Error Condition Tests ================================ //

    function test_redeem_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.redeem(defaultPoolId, 0, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenNotExpired() external __as(alice) {
        _deposit(defaultPoolId, depositAmount, alice);

        vm.expectRevert(IErrors.NotExpired.selector);
        corkPoolManager.redeem(defaultPoolId, 100 ether, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2); // 00100 = withdrawal paused

        overridePrank(alice);
        _deposit(defaultPoolId, depositAmount, alice);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.redeem(defaultPoolId, 100 ether, alice, alice);
    }

    function test_redeemWithZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.redeem(defaultPoolId, 0, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenNotInitialized() external __as(alice) {
        MarketId uninitializedPoolId = MarketId.wrap(bytes32("0x123"));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.redeem(uninitializedPoolId, 100 ether, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenInsufficientShares() external __as(alice) __deposit(depositAmount, alice) __deposit(depositAmount, bob) {
        vm.warp(block.timestamp + 2 days);

        // Try to redeem more than user has
        uint256 userBalance = principalToken.balanceOf(alice);
        uint256 excessiveAmount = userBalance + 1 ether;

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        corkPoolManager.redeem(defaultPoolId, excessiveAmount, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenInsufficientSharesAmount() external __createPool(1 days, 6, 18) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __as(alice) {
        uint256 smallAmount = 1; // Less than minimum required for 6-decimal token

        _deposit(defaultPoolId, 1000e6, alice);

        vm.warp(block.timestamp + 2 days);

        uint256 minimumShares = 10 ** (18 - 6); // 10^12 for 6-decimal token
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientSharesAmount.selector, minimumShares, smallAmount));
        corkPoolManager.redeem(defaultPoolId, smallAmount, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenAllowanceInsufficient() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 redeemAmount = 0.5 ether;

        // Bob tries to redeem alice's tokens without allowance
        overridePrank(bob);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, bob);
    }

    function test_redeem_ShouldRevert_WhenUserHasNoTokenBalance() external __as(alice) __deposit(depositAmount, bob) {
        // Don't deposit anything for alice
        vm.warp(block.timestamp + 2 days);

        uint256 userShares = principalToken.balanceOf(alice);
        assertEq(userShares, 0, "User should have no shares");

        // Try to redeem when user has no tokens
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        corkPoolManager.redeem(defaultPoolId, 1 ether, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenGloballyPaused() external __as(alice) __deposit(depositAmount, alice) {
        vm.warp(block.timestamp + 2 days);

        // Pause globally
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.redeem(defaultPoolId, 100 ether, alice, alice);
    }

    function test_redeem_ShouldRevert_WhenTryingToRedeemZeroShares() external __as(alice) {
        // Don't deposit anything for alice
        vm.warp(block.timestamp + 2 days);

        uint256 userShares = principalToken.balanceOf(alice);
        assertEq(userShares, 0, "User should have no shares");

        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.redeem(defaultPoolId, 0, alice, alice);
    }

    // ================================ MaxRedeem Tests ================================ //

    function test_maxRedeem_ShouldRevert_WhenNotInitialized() external {
        MarketId uninitializedId = MarketId.wrap(bytes32(uint256(3)));

        vm.expectPartialRevert(IErrors.NotInitialized.selector);
        corkPoolManager.maxRedeem(uninitializedId, alice);
    }

    function test_maxRedeem_ShouldReturnZero_WhenWithdrawalPaused() external __as(alice) __deposit(1000 ether, alice) {
        // Pause withdrawals
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2); // 00100 = withdrawal paused

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        uint256 maxShares = corkPoolManager.maxRedeem(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when withdrawal is paused");
    }

    function test_maxRedeem_ShouldReturnZero_WhenNotExpired() external __as(alice) __deposit(1000 ether, alice) {
        // Don't warp time - market not expired
        uint256 maxShares = corkPoolManager.maxRedeem(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when market not expired");
    }

    function test_maxRedeem_ShouldReturnZero_WhenUserHasNoShares() external {
        // Setup: don't deposit anything for user
        vm.warp(block.timestamp + 2 days); // Expire

        uint256 maxShares = corkPoolManager.maxRedeem(defaultPoolId, alice);
        assertEq(maxShares, 0, "Should return 0 when user has no shares");
    }

    function test_maxRedeem_ShouldReturnUserBalance_WhenMarketExpiredAndUserHasShares() external __as(alice) {
        uint256 receivedShares = _deposit(defaultPoolId, 1000 ether, alice);

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Get user's CPT balance
        uint256 userBalance = principalToken.balanceOf(alice);

        uint256 maxShares = corkPoolManager.maxRedeem(defaultPoolId, alice);
        assertEq(maxShares, userBalance, "Should return user's CPT balance");
        assertEq(maxShares, receivedShares, "Should equal received shares from deposit");
    }

    function test_maxRedeem_ShouldReturnCorrectAmount_WhenMultipleUsers() external {
        // Setup: multiple users deposit
        overridePrank(alice);
        uint256 aliceShares = _deposit(defaultPoolId, 1000 ether, alice);

        overridePrank(bob);
        uint256 bobShares = _deposit(defaultPoolId, 500 ether, bob);

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Check both users get their correct max redeemable amounts
        uint256 maxShares1 = corkPoolManager.maxRedeem(defaultPoolId, alice);
        uint256 maxShares2 = corkPoolManager.maxRedeem(defaultPoolId, bob);

        assertEq(maxShares1, aliceShares, "alice should get their deposit amount");
        assertEq(maxShares2, bobShares, "bob should get their deposit amount");
    }

    function test_maxRedeem_ShouldReturnCorrectAmount_AfterPartialRedemption() external {
        // Setup: deposit and expire
        overridePrank(alice);
        uint256 initialShares = _deposit(defaultPoolId, 1000 ether, alice);

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Redeem part of the shares
        overridePrank(alice);
        uint256 redeemAmount = 300 ether;
        corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, alice);

        // Check remaining max redeemable amount
        uint256 maxShares = corkPoolManager.maxRedeem(defaultPoolId, alice);
        uint256 expectedRemaining = initialShares - redeemAmount;
        assertEq(maxShares, expectedRemaining, "Should return remaining shares after partial redemption");
    }

    // ================================ Allowance Tests ================================ //

    function test_redeemWithSameOwnerSender() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 redeemAmount = 0.5 ether;
        uint256 ownerCollateralBalanceBefore = collateralAsset.balanceOf(alice);
        uint256 ownerReferenceBalanceBefore = referenceAsset.balanceOf(alice);
        uint256 receiverCollateralBalanceBefore = collateralAsset.balanceOf(bob);
        uint256 receiverReferenceBalanceBefore = referenceAsset.balanceOf(bob);

        (uint256 actualReference, uint256 actualCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, bob);

        uint256 receiverCollateralBalanceAfter = collateralAsset.balanceOf(bob);
        uint256 receiverReferenceBalanceAfter = referenceAsset.balanceOf(bob);

        assertEq(receiverCollateralBalanceAfter - receiverCollateralBalanceBefore, actualCollateral, "Receiver should receive collateral assets");
        assertEq(receiverReferenceBalanceAfter - receiverReferenceBalanceBefore, actualReference, "Receiver should receive reference assets");

        uint256 ownerCollateralBalanceAfter = collateralAsset.balanceOf(alice);
        uint256 ownerReferenceBalanceAfter = referenceAsset.balanceOf(alice);

        assertEq(ownerCollateralBalanceAfter, ownerCollateralBalanceBefore, "Owner should not receive collateral assets");
        assertEq(ownerReferenceBalanceAfter, ownerReferenceBalanceBefore, "Owner should not receive reference assets");
    }

    function test_redeemWithDifferentSenderOwner() external {
        overridePrank(alice);
        _deposit(defaultPoolId, 1 ether, alice);

        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 redeemAmount = 0.5 ether;

        principalToken.approve(bob, redeemAmount);
        principalToken.approve(address(corkPoolManager), redeemAmount);

        uint256 allowanceBefore = principalToken.allowance(alice, bob);
        assertEq(allowanceBefore, redeemAmount, "Allowance should be set correctly");

        uint256 receiverCollateralBalanceBefore = collateralAsset.balanceOf(bob);
        uint256 receiverReferenceBalanceBefore = referenceAsset.balanceOf(bob);

        overridePrank(bob);

        (uint256 actualReference, uint256 actualCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, bob);

        uint256 receiverCollateralBalanceAfter = collateralAsset.balanceOf(bob);
        uint256 receiverReferenceBalanceAfter = referenceAsset.balanceOf(bob);

        assertEq(receiverCollateralBalanceAfter - receiverCollateralBalanceBefore, actualCollateral, "Receiver should receive collateral assets");
        assertEq(receiverReferenceBalanceAfter - receiverReferenceBalanceBefore, actualReference, "Receiver should receive reference assets");

        uint256 allowanceAfter = principalToken.allowance(alice, bob);
        assertEq(allowanceAfter, 0, "Allowance should be fully spent");
    }

    function test_redeemWithInsufficientAllowance() external __as(alice) {
        _deposit(defaultPoolId, 1 ether, alice);

        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 redeemAmount = 0.5 ether;
        overridePrank(bob);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, bob);
    }

    function test_redeemWithExactAllowance() external {
        overridePrank(alice);
        _deposit(defaultPoolId, 1 ether, alice);

        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 redeemAmount = 0.5 ether;
        principalToken.approve(bob, redeemAmount);

        uint256 receiverCollateralBalanceBefore = collateralAsset.balanceOf(bob);
        uint256 receiverReferenceBalanceBefore = referenceAsset.balanceOf(bob);

        overridePrank(bob);
        (uint256 actualReference, uint256 actualCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, bob);

        uint256 receiverCollateralBalanceAfter = collateralAsset.balanceOf(bob);
        uint256 receiverReferenceBalanceAfter = referenceAsset.balanceOf(bob);

        assertEq(receiverCollateralBalanceAfter - receiverCollateralBalanceBefore, actualCollateral, "Receiver should receive collateral assets");
        assertEq(receiverReferenceBalanceAfter - receiverReferenceBalanceBefore, actualReference, "Receiver should receive reference assets");

        uint256 allowanceAfter = principalToken.allowance(alice, bob);
        assertEq(allowanceAfter, 0, "Allowance should be fully spent");
    }

    function test_redeemMultipleReceivers() external __as(alice) __deposit(1 ether, alice) {
        address receiver2 = address(0x4);

        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 redeemAmount = 0.5 ether;

        uint256 receiver1CollateralBalanceBefore = collateralAsset.balanceOf(bob);
        uint256 receiver2CollateralBalanceBefore = collateralAsset.balanceOf(receiver2);

        (uint256 actualReference1, uint256 actualCollateral1) = corkPoolManager.redeem(defaultPoolId, redeemAmount / 2, alice, bob);
        (uint256 actualReference2, uint256 actualCollateral2) = corkPoolManager.redeem(defaultPoolId, redeemAmount / 2, alice, receiver2);

        uint256 receiver1CollateralBalanceAfter = collateralAsset.balanceOf(bob);
        uint256 receiver2CollateralBalanceAfter = collateralAsset.balanceOf(receiver2);

        assertEq(receiver1CollateralBalanceAfter - receiver1CollateralBalanceBefore, actualCollateral1, "Receiver1 should receive collateral assets");
        assertEq(receiver2CollateralBalanceAfter - receiver2CollateralBalanceBefore, actualCollateral2, "Receiver2 should receive collateral assets");
    }

    function test_redeemPreviewConsistency() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 redeemAmount = 0.5 ether;

        (uint256 previewReference, uint256 previewCollateral) = corkPoolManager.previewRedeem(defaultPoolId, redeemAmount);

        (uint256 actualReference, uint256 actualCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmount, alice, bob);

        assertEq(actualReference, previewReference, "Actual reference asset should match preview");
        assertEq(actualCollateral, previewCollateral, "Actual collateral asset should match preview");
    }

    // ================================ Fuzz Tests ================================ //

    function testFuzz_redeem(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(EXPIRY, _collateralDecimal, _referenceDecimal) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __as(alice) {
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, collateralDecimal);
        uint256 redeemAmountNormalized = 100 ether; // Always in 18 decimals

        uint256 received = _deposit(defaultPoolId, depositAmountNormalized, alice);

        // Forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Get state before redeem
        StateSnapshot memory before = _getStateSnapshot(alice, defaultPoolId);

        // Execute redeem
        (uint256 accruedRef, uint256 accruedCollateral) = corkPoolManager.redeem(defaultPoolId, redeemAmountNormalized, alice, alice);

        // Get state after redeem
        StateSnapshot memory _after = _getStateSnapshot(alice, defaultPoolId);

        // Verify user asset balances
        assertGt(accruedCollateral, 0, "Should receive collateral");
        assertEq(_after.userRef - before.userRef, accruedRef, "User should receive reference assets");
        assertEq(_after.userCollateral - before.userCollateral, accruedCollateral, "User should receive collateral assets");

        // Verify principal token state changes
        assertEq(before.userPrincipalToken - _after.userPrincipalToken, redeemAmountNormalized, "User principal tokens should be burned");
        assertEq(before.principalTokenTotalSupply - _after.principalTokenTotalSupply, redeemAmountNormalized, "Principal token total supply should decrease");

        // Verify contract asset balances
        assertEq(before.contractRef - _after.contractRef, accruedRef, "Contract reference asset balance should decrease");
        assertEq(before.contractCollateral - _after.contractCollateral, accruedCollateral, "Contract collateral asset balance should decrease");

        // Verify pool state changes (balances should be the same regardless of liquidity separation)
        uint256 expectedPoolCollateral = TransferHelper.normalizeDecimals(900 ether, TARGET_DECIMALS, collateralDecimal);
        assertEq(_after.poolCollateral, expectedPoolCollateral, "Pool collateral balance be the same regardless of liquidity separation");
        assertEq(_after.poolRef, 0, "Pool reference balance be the same regardless of liquidity separation");

        // Verify internal state changes
        assertTrue(_after.internalState.pool.liquiditySeparated, "Liquidity should be separated after first redeem");
        assertEq(_after.internalState.shares.withdrawn, redeemAmountNormalized, "Withdrawn shares should be tracked");
        assertEq(_after.internalState.pool.balances.collateralAsset.locked, 0, "Internal collateral balance should be 0 after liquidity separation");
        assertEq(_after.internalState.pool.balances.referenceAssetBalance, 0, "Internal reference balance should be 0 after liquidity separation");
        assertEq(_after.internalState.pool.poolArchive.collateralAssetAccrued, expectedPoolCollateral, "Pool archive collateral should decrease by redeemed amount");
        assertEq(_after.internalState.pool.poolArchive.referenceAssetAccrued, 0, "Pool archive reference should decrease by redeemed amount");
    }

    function testFuzz_previewRedeem(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(EXPIRY, _collateralDecimal, _referenceDecimal) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __as(alice) {
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, collateralDecimal);
        uint256 withdrawAmount = 100 ether; // Always in 18 decimals

        // First deposit to have something to redeem
        _deposit(defaultPoolId, depositAmountNormalized, alice);

        // Forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Preview redeem
        (uint256 previewRef, uint256 previewCollateral) = corkPoolManager.previewRedeem(defaultPoolId, withdrawAmount);

        // Execute actual redeem
        (uint256 actualRef, uint256 actualCollateral) = corkPoolManager.redeem(defaultPoolId, withdrawAmount, alice, alice);

        // Assert preview matches actual
        assertEq(previewRef, actualRef, "Preview reference should match actual");
        assertEq(previewCollateral, actualCollateral, "Preview collateral should match actual");

        // Verify expected values based on decimal normalization
        // When expired, user gets remaining collateral proportionally
        uint256 expectedCollateral = TransferHelper.normalizeDecimals(withdrawAmount, TARGET_DECIMALS, collateralDecimal);
        assertEq(actualCollateral, expectedCollateral, "Should receive correct normalized collateral amount");
        assertEq(actualRef, 0, "Should receive no reference assets when expired");
    }

    // ================================ Integration Tests ================================ //

    function test_fullLifecycle_DepositExerciseRedeem() external __as(alice) {
        // 1. Deposit
        uint256 deposited = _deposit(defaultPoolId, depositAmount, alice);

        // 2. Exercise part of the tokens
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exercise(defaultPoolId, 100 ether, alice);

        // 3. Move to expiry
        vm.warp(block.timestamp + 2 days);

        // 4. Redeem remaining tokens
        uint256 remainingBalance = principalToken.balanceOf(alice);

        uint256 userCollateralBefore = collateralAsset.balanceOf(alice);
        uint256 userRefBefore = referenceAsset.balanceOf(alice);

        (uint256 accruedRef, uint256 accruedCollateral) = corkPoolManager.redeem(defaultPoolId, remainingBalance, alice, alice);

        uint256 userCollateralAfter = collateralAsset.balanceOf(alice);
        uint256 userRefAfter = referenceAsset.balanceOf(alice);

        // Verify final state
        assertEq(userCollateralAfter - userCollateralBefore, accruedCollateral);
        assertEq(userRefAfter - userRefBefore, accruedRef);
        assertEq(principalToken.balanceOf(alice), 0, "Should have no tokens remaining");
    }
}
