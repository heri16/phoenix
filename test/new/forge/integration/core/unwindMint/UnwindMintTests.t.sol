// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract UnwindMintTests is BaseTest {
    uint256 amount = 500 ether;
    uint256 unwindAmount = 100 ether;

    // ================================ Core UnwindMint Tests ================================ //

    function test_unwindMint_ShouldWork() external __as(alice) __deposit(amount, alice) {
        // Take snapshots before unwindMint
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Execute unwindMint
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, unwindAmount, 0, true);
        uint256 collateralReceived = corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, alice);

        // Take snapshots after unwindMint
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(collateralReceived, unwindAmount, "Should receive equal collateral amount");

        // ================================ User State Changes ================================ //
        assertEq(afterSnapshot.userCollateral, beforeSnapshot.userCollateral + unwindAmount, "User collateral balance should increase by unwindAmount");
        assertEq(afterSnapshot.userPrincipalToken, beforeSnapshot.userPrincipalToken - unwindAmount, "User principal token balance should decrease by unwindAmount");
        assertEq(afterSnapshot.userSwapToken, beforeSnapshot.userSwapToken - unwindAmount, "User swap token balance should decrease by unwindAmount");
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef, "User reference asset balance should remain unchanged");

        // ================================ Contract State Changes ================================ //
        assertEq(afterSnapshot.contractCollateral, beforeSnapshot.contractCollateral - unwindAmount, "Contract collateral balance should decrease by unwindAmount");
        assertEq(afterSnapshot.contractRef, beforeSnapshot.contractRef, "Contract reference asset balance should remain unchanged");

        // ================================ Token Supply Changes ================================ //
        assertEq(afterSnapshot.principalTokenTotalSupply, beforeSnapshot.principalTokenTotalSupply - unwindAmount, "Principal token total supply should decrease by unwindAmount");
        assertEq(afterSnapshot.swapTokenTotalSupply, beforeSnapshot.swapTokenTotalSupply - unwindAmount, "Swap token total supply should decrease by unwindAmount");

        // ================================ Pool Internal State Changes ================================ //
        assertEq(afterSnapshot.poolCollateral, beforeSnapshot.poolCollateral - unwindAmount, "Pool locked collateral should decrease by unwindAmount");
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef, "Pool reference asset should remain unchanged");

        // ================================ Internal State Consistency ================================ //
        assertEq(afterSnapshot.internalState.pool.balances.collateralAsset.locked, beforeSnapshot.internalState.pool.balances.collateralAsset.locked - unwindAmount, "Internal state locked collateral should decrease by unwindAmount");
        assertEq(afterSnapshot.internalState.pool.balances.referenceAssetBalance, beforeSnapshot.internalState.pool.balances.referenceAssetBalance, "Internal state locked reference asset should remain unchanged");
    }

    function test_unwindMint_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindMint(defaultPoolId, 0, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 3); // 01000 = unwind deposit paused

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, alice);
    }

    // ================================ Preview Function Tests ================================ //

    function test_previewUnwindMint_ShouldReturnCorrectAmount() external {
        uint256 tokensIn = amount;
        uint256 collateralOut = corkPoolManager.previewUnwindMint(defaultPoolId, tokensIn);
        assertEq(collateralOut, tokensIn, "Should return 1:1 ratio");
    }

    // ================================ Max Function Tests ================================ //

    function test_maxUnwindMint_ShouldReturnUserBalance() external __as(alice) {
        _deposit(defaultPoolId, amount, currentCaller());

        uint256 maxAmount = corkPoolManager.maxUnwindMint(defaultPoolId, alice);
        assertEq(maxAmount, amount, "Should return alice's minimum token balance");
    }

    function test_maxUnwindMint_ShouldReturnSameAmount_WhenBalancesAreEqual() external __as(alice) __deposit(1000 ether, alice) {
        uint256 swapBalance = swapToken.balanceOf(alice);
        uint256 principalBalance = principalToken.balanceOf(alice);

        // Verify balances are equal
        assertEq(swapBalance, principalBalance, "Balances should be equal after deposit");

        uint256 maxAmount = corkPoolManager.maxUnwindMint(defaultPoolId, alice);

        // Should return either balance (they're equal)
        assertEq(maxAmount, swapBalance, "Should return the balance when both are equal");
        assertEq(maxAmount, principalBalance, "Should equal both balances when they're the same");
    }

    function test_maxUnwindMint_ShouldReturnZero_WhenUserHasNoTokens() external {
        // Test edge case where alice has no tokens at all
        address delta = makeAddr("delta");

        uint256 maxAmount = corkPoolManager.maxUnwindMint(defaultPoolId, delta);
        assertEq(maxAmount, 0, "Should return 0 when alice has no tokens");
    }

    // ================================ PoolShare Wrapper Tests ================================ //

    function test_maxUnwindMint_ShouldReturnSameValueAsPoolManager() external __as(alice) __deposit(1000 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxUnwindMint(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxUnwindMint(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindMint should match PoolManager maxUnwindMint");
    }

    function test_previewUnwindMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 cptAndCstSharesIn = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewUnwindMint(defaultPoolId, cptAndCstSharesIn);
        uint256 poolShareResult = principalToken.previewUnwindMint(cptAndCstSharesIn);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewUnwindMint should match PoolManager previewUnwindMint");
    }

    // ================================  Integration Tests ================================ //

    function test_unwindMint_ShouldNotUseExtra() external __createPool(1 days, 6, 18) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __deposit(amount, alice) {
        uint256 principalBalanceBefore = principalToken.balanceOf(alice);
        uint256 swapBalanceBefore = swapToken.balanceOf(alice);

        // extra 1 wei
        uint256 unwindAmount = 1e12 + 1;

        corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, alice);

        uint256 principalBalanceAfter = principalToken.balanceOf(alice);
        uint256 swapBalanceAfter = swapToken.balanceOf(alice);

        // atlee(shares decimal - collateral decimals : 18 - 6 = 12) wei of unused shares
        assertGe(principalBalanceBefore - principalBalanceAfter, 1e12, "Should not use extra principal shares beyond required amount");
        assertGe(swapBalanceBefore - swapBalanceAfter, 1e12, "Should not use extra swap shares beyond required amount");
    }

    // ================================ Additional Negative Test Cases ================================ //

    function test_unwindMint_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a random market ID that doesn't exist
        MarketId nonExistentPoolId = MarketId.wrap(bytes32("1"));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.unwindMint(nonExistentPoolId, unwindAmount, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenInsufficientPrincipalTokenBalance() external __as(alice) __deposit(amount, alice) {
        // Try to unwind more than alice has
        uint256 excessiveAmount = amount + 1 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                amount, // alice's actual balance
                excessiveAmount // amount needed
            )
        );
        corkPoolManager.unwindMint(defaultPoolId, excessiveAmount, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenInsufficientSwapTokenBalance() external __as(alice) __deposit(amount, alice) {
        // Transfer some swap tokens away to create imbalance
        swapToken.transfer(bob, 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                amount - 50 ether, // alice's remaining swap token balance
                amount // amount needed for full unwind
            )
        );
        corkPoolManager.unwindMint(defaultPoolId, amount, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenInsufficientAllowance() external __as(alice) __deposit(amount, alice) {
        overridePrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                bob,
                0, // current allowance
                unwindAmount // amount needed
            )
        );
        corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenBelowMinimumShares() external __createPool(1 days, 6, 18) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __deposit(amount, alice) {
        // For 6-decimal collateral, minimum shares = 10^(18-6) = 10^12
        uint256 minimumShares = 10 ** (18 - 6);
        uint256 belowMinimum = minimumShares - 1;

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientSharesAmount.selector, minimumShares, belowMinimum));
        corkPoolManager.unwindMint(defaultPoolId, belowMinimum, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenZeroAddressOwner() external __as(alice) __deposit(amount, alice) {
        vm.expectRevert(); // Should revert with some error for zero address
        corkPoolManager.unwindMint(defaultPoolId, unwindAmount, address(0), alice);
    }

    function test_unwindMint_ShouldRevert_WhenZeroAddressReceiver() external __as(alice) __deposit(amount, alice) {
        vm.expectRevert(); // Should revert with some error for zero address
        corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, address(0));
    }

    function test_unwindMint_ShouldWorkWithDifferentDecimalCombinations() external {
        // Test 8-18 decimal combination
        createMarket(1 days, 8, 18, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);
        _deposit(defaultPoolId, amount, alice);

        uint256 collateralReceived = corkPoolManager.unwindMint(defaultPoolId, unwindAmount, alice, alice);
        assertEq(collateralReceived, TransferHelper.normalizeDecimals(unwindAmount, TARGET_DECIMALS, 8), "Should work with 8-18 decimal combination");
    }

    function test_unwindMint_ShouldRevert_WhenRoundingToZero() external __createPool(1 days, 6, 18) __giveAssets(alice) __approveAllTokens(alice, address(corkPoolManager)) __deposit(amount, alice) {
        // Try unwinding an amount so small it would round to zero in collateral terms
        uint256 tinyAmount = 1; // 1 wei in 18 decimals

        // This should be caught by the minimum shares requirement
        uint256 minimumShares = 10 ** (18 - 6);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientSharesAmount.selector, minimumShares, tinyAmount));
        corkPoolManager.unwindMint(defaultPoolId, tinyAmount, alice, alice);
    }

    function test_unwindMint_ShouldRevert_WhenMismatchedTokenBalances() external __as(alice) __deposit(amount, alice) {
        // Create scenario where user has different amounts of principal vs swap tokens
        // Transfer away half of the swap tokens
        uint256 transferAmount = amount / 2;
        swapToken.transfer(bob, transferAmount);

        // Now alice has `amount` principal tokens but only `amount - transferAmount` swap tokens
        // Trying to unwind `amount` should fail on swap token balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                amount - transferAmount, // actual swap token balance
                amount // required amount
            )
        );
        corkPoolManager.unwindMint(defaultPoolId, amount, alice, alice);
    }

    // ================================ Fuzz Tests ================================ //

    function testFuzz_unwindMint_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(500 ether, collateralAsset.decimals());
        uint256 normalizedUnwindAmount = TransferHelper.fixedToTokenNativeDecimals(100 ether, collateralAsset.decimals());

        // First deposit to have tokens for unwinding
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());

        // Take snapshots before unwindMint
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        uint256 expectedCollateralReceived = corkPoolManager.previewUnwindMint(defaultPoolId, 100 ether);

        uint256 collateralReceived = corkPoolManager.unwindMint(defaultPoolId, 100 ether, alice, alice);

        // Take snapshots after unwindMint
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(collateralReceived, expectedCollateralReceived, "Should receive expected collateral amount");

        // ================================ User State Changes ================================ //
        assertEq(afterSnapshot.userCollateral, beforeSnapshot.userCollateral + normalizedUnwindAmount, "User collateral balance should increase by unwindAmount");
        assertEq(afterSnapshot.userPrincipalToken, beforeSnapshot.userPrincipalToken - 100 ether, "User principal token balance should decrease by unwindAmount");
        assertEq(afterSnapshot.userSwapToken, beforeSnapshot.userSwapToken - 100 ether, "User swap token balance should decrease by unwindAmount");
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef, "User reference asset balance should remain unchanged");

        // ================================ Contract State Changes ================================ //
        assertEq(afterSnapshot.contractCollateral, beforeSnapshot.contractCollateral - normalizedUnwindAmount, "Contract collateral balance should decrease by unwindAmount");
        assertEq(afterSnapshot.contractRef, beforeSnapshot.contractRef, "Contract reference asset balance should remain unchanged");

        // ================================ Token Supply Changes ================================ //
        assertEq(afterSnapshot.principalTokenTotalSupply, beforeSnapshot.principalTokenTotalSupply - 100 ether, "Principal token total supply should decrease by unwindAmount");
        assertEq(afterSnapshot.swapTokenTotalSupply, beforeSnapshot.swapTokenTotalSupply - 100 ether, "Swap token total supply should decrease by unwindAmount");

        // ================================ Pool Internal State Changes ================================ //
        assertEq(afterSnapshot.poolCollateral, beforeSnapshot.poolCollateral - normalizedUnwindAmount, "Pool locked collateral should decrease by unwindAmount");
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef, "Pool reference asset should remain unchanged");

        // ================================ Internal State Consistency ================================ //
        assertEq(afterSnapshot.internalState.pool.balances.collateralAsset.locked, beforeSnapshot.internalState.pool.balances.collateralAsset.locked - normalizedUnwindAmount, "Internal state locked collateral should decrease by unwindAmount");
        assertEq(afterSnapshot.internalState.pool.balances.referenceAssetBalance, beforeSnapshot.internalState.pool.balances.referenceAssetBalance, "Internal state locked reference asset should remain unchanged");
    }

    function testFuzz_previewUnwindMint_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(500 ether, collateralAsset.decimals());

        // First deposit to have tokens for unwinding
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());

        uint256 tokensIn = 100 ether;

        // Preview unwind mint
        uint256 previewCollateralOut = corkPoolManager.previewUnwindMint(defaultPoolId, tokensIn);

        // Execute actual unwind mint
        uint256 actualCollateralOut = corkPoolManager.unwindMint(defaultPoolId, tokensIn, alice, alice);

        // Verify preview matches actual
        assertEq(previewCollateralOut, actualCollateralOut, "Preview collateral out should match actual collateral out");

        // Verify that the unwinding functioned correctly with decimal normalization
        uint256 expectedCollateralOut = TransferHelper.fixedToTokenNativeDecimals(tokensIn, collateralAsset.decimals());

        assertEq(actualCollateralOut, expectedCollateralOut, "Should return correct amount with decimal normalization");
    }
}
