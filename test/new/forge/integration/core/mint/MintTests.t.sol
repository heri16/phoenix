// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

/**
 * @title MintTests
 * @notice Unified test suite for all mint-related functionality
 * @dev This file contains all tests related to:
 *      - mint() function
 *      - maxMint() function
 *      - previewMint() function
 */
contract MintTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal tokensOut = 500 ether;

    // ================================ BASIC MINT TESTS ================================ //

    function test_mint() public __as(alice) {
        // Store initial pool balances
        (uint256 initialCollateralLocked, uint256 initialSwapTokenBalance, uint256 initialReferenceAssetBalance) = corkPoolManager.getPoolBalances(defaultPoolId);

        {
            // Store initial state
            uint256 initialCollateralBalance = collateralAsset.balanceOf(alice);
            uint256 initialCorkPoolBalance = collateralAsset.balanceOf(address(corkPoolManager));
            uint256 initialPrincipalBalance = principalToken.balanceOf(alice);
            uint256 initialSwapBalance = swapToken.balanceOf(alice);
            uint256 initialPrincipalSupply = principalToken.totalSupply();
            uint256 initialSwapSupply = swapToken.totalSupply();
            uint256 initialAllowance = collateralAsset.allowance(alice, address(corkPoolManager));

            uint256 collateralIn = corkPoolManager.mint(defaultPoolId, tokensOut, alice);

            // Verify return value
            assertEq(collateralIn, tokensOut);

            // Verify collateral asset transfers
            assertEq(collateralAsset.balanceOf(alice), initialCollateralBalance - tokensOut, "Minter collateral balance should decrease");
            assertEq(collateralAsset.balanceOf(address(corkPoolManager)), initialCorkPoolBalance + tokensOut, "CorkPoolManager collateral balance should increase");

            // Verify token minting
            assertEq(principalToken.balanceOf(alice), initialPrincipalBalance + tokensOut, "Principal token balance should increase");
            assertEq(swapToken.balanceOf(alice), initialSwapBalance + tokensOut, "Swap token balance should increase");
            assertEq(principalToken.totalSupply(), initialPrincipalSupply + tokensOut, "Principal token supply should increase");
            assertEq(swapToken.totalSupply(), initialSwapSupply + tokensOut, "Swap token supply should increase");

            // Verify allowance was consumed
            assertEq(collateralAsset.allowance(alice, address(corkPoolManager)), initialAllowance - tokensOut, "Allowance should be consumed");
        }

        // Verify pool internal balances
        (uint256 finalCollateralLocked, uint256 finalSwapTokenBalance, uint256 finalReferenceAssetBalance) = corkPoolManager.getPoolBalances(defaultPoolId);

        assertEq(finalCollateralLocked, initialCollateralLocked + tokensOut, "Pool collateral locked should increase");
        assertEq(finalSwapTokenBalance, initialSwapTokenBalance, "Pool swap token balance should remain unchanged");
        assertEq(finalReferenceAssetBalance, initialReferenceAssetBalance, "Pool reference asset balance should remain unchanged");
    }

    function test_mint_ShouldCalculateCorrectCollateralIn() external __as(alice) {
        // Expect both Pool Manager and ERC4626-compatible events
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, tokensOut, 0, false);

        vm.expectEmit(true, true, false, true, address(principalToken));
        emit IPoolShare.Deposit(alice, alice, tokensOut, tokensOut);

        uint256 collateralIn = corkPoolManager.mint(defaultPoolId, tokensOut, currentCaller());

        assertEq(collateralIn, tokensOut, "Should require equal collateral amount");
        assertEq(principalToken.balanceOf(alice), tokensOut, "Should have principal tokens");
        assertEq(swapToken.balanceOf(alice), tokensOut, "Should have swap tokens");
    }

    // ================================ MINT ERROR TESTS ================================ //

    function test_mint_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InsufficientAmount.selector);
        corkPoolManager.mint(defaultPoolId, 0, currentCaller());
    }

    function test_mint_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkPoolManager.mint(defaultPoolId, 1000 ether, alice);
    }

    function test_mint_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // 00001 = deposit/mint paused
        vm.stopPrank();

        overridePrank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.mint(defaultPoolId, 1000 ether, currentCaller());

        vm.stopPrank();
    }

    function test_pauseMintStatus_blocksMint() public __as(pauser) {
        defaultCorkController.pauseDeposits(defaultPoolId); // This pauses both deposits and mints

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.mint(defaultPoolId, 1 ether, currentCaller());
    }

    function test_mint_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        MarketId invalidPoolId = MarketId.wrap(bytes32(uint256(999)));
        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.mint(invalidPoolId, 1000 ether, currentCaller());
    }

    function test_mint_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);
        vm.stopPrank();

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.mint(defaultPoolId, 1000 ether, currentCaller());
        vm.stopPrank();
    }

    function test_mint_ShouldRevert_WhenInsufficientAllowance() external __as(alice) {
        // Approve less than required
        collateralAsset.approve(address(corkPoolManager), 500 ether);

        vm.expectRevert(); // ERC20InsufficientAllowance
        corkPoolManager.mint(defaultPoolId, 1000 ether, currentCaller());
    }

    function test_mint_ShouldRevert_WhenInsufficientBalance() external __as(alice) {
        // Give alice less collateral than needed
        uint256 aliceBalance = collateralAsset.balanceOf(alice);

        overridePrank(alice);
        collateralAsset.transfer(bob, aliceBalance - 500 ether); // Leave only 500 ether
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        vm.stopPrank();

        overridePrank(alice);

        vm.expectRevert(); // ERC20InsufficientBalance
        corkPoolManager.mint(defaultPoolId, 1000 ether, currentCaller());
        vm.stopPrank();
    }

    function test_mintShouldRevertWhenCollateralInIsZero() external __createPool(1 days, 6, 18) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        // this should fail, max amount to be accepted is 1e12
        uint256 depositAmount = 1e11;

        uint256 collateralAmountIn = corkPoolManager.previewMint(defaultPoolId, depositAmount);

        // atleast 1 wei of collateral
        assertEq(collateralAmountIn, 1);

        collateralAmountIn = corkPoolManager.mint(defaultPoolId, depositAmount, DEFAULT_ADDRESS);

        // atleast 1 wei of collateral
        assertEq(collateralAmountIn, 1);
    }

    // ================================ PREVIEW MINT TESTS ================================ //

    function test_previewMint() external __as(DEFAULT_ADDRESS) {
        uint256 out = corkPoolManager.previewMint(defaultPoolId, 1 ether);

        assertEq(out, 1 ether);
    }

    function test_previewMint_ShouldReturnCorrectAmount() external {
        uint256 tokensOutTest = 500 ether;
        uint256 collateralIn = corkPoolManager.previewMint(defaultPoolId, tokensOutTest);
        assertEq(collateralIn, tokensOutTest, "Should require equal collateral");
    }

    function test_previewMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 swapAndPricipalTokenAmountOut = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewMint(defaultPoolId, swapAndPricipalTokenAmountOut);
        uint256 poolShareResult = principalToken.previewMint(swapAndPricipalTokenAmountOut);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewMint should match PoolManager previewMint");
    }

    function test_previewMint_ShouldReturnZero_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // Pause deposits/mints
        vm.stopPrank();

        uint256 result = corkPoolManager.previewMint(defaultPoolId, 1000 ether);
        assertEq(result, 0, "Preview should return 0 when paused");
    }

    function test_previewMint_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days); // Past expiry

        uint256 result = corkPoolManager.previewMint(defaultPoolId, 1000 ether);
        assertEq(result, 0, "Preview should return 0 when expired");
    }

    // ================================ MAX MINT TESTS ================================ //

    function test_maxMint_ShouldReturnMaxUint() external {
        uint256 maxAmount = corkPoolManager.maxMint(defaultPoolId, alice);
        assertEq(maxAmount, type(uint256).max, "Should return max uint256");
    }

    function test_maxMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxMint(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxMint(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxMint should match PoolManager maxMint");
    }

    function test_maxMint_ShouldReturnZero_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // Pause deposits/mints
        vm.stopPrank();

        uint256 result = corkPoolManager.maxMint(defaultPoolId, alice);
        assertEq(result, 0, "Max mint should return 0 when paused");
    }

    function test_maxMint_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days); // Past expiry

        uint256 result = corkPoolManager.maxMint(defaultPoolId, alice);
        assertEq(result, 0, "Max mint should return 0 when expired");
    }

    // ================================ FUZZ MINT TESTS ================================ //

    function testFuzz_mint(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        uint256 mintAmountNormalized = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

        // Store initial pool balances
        (uint256 initialCollateralLocked, uint256 initialSwapTokenBalance, uint256 initialReferenceAssetBalance) = corkPoolManager.getPoolBalances(defaultPoolId);

        {
            // Store initial state
            uint256 initialCollateralBalance = collateralAsset.balanceOf(currentCaller());
            uint256 initialCorkPoolBalance = collateralAsset.balanceOf(address(corkPoolManager));
            uint256 initialPrincipalBalance = principalToken.balanceOf(currentCaller());
            uint256 initialSwapBalance = swapToken.balanceOf(currentCaller());
            uint256 initialPrincipalSupply = principalToken.totalSupply();
            uint256 initialSwapSupply = swapToken.totalSupply();
            uint256 initialAllowance = collateralAsset.allowance(currentCaller(), address(corkPoolManager));

            uint256 inAmount = corkPoolManager.mint(defaultPoolId, 1 ether, currentCaller());

            // Verify return value - regardless of the amount, the received amount would be in 18 decimals
            assertEq(inAmount, mintAmountNormalized);

            // Verify collateral asset transfers
            assertEq(collateralAsset.balanceOf(currentCaller()), initialCollateralBalance - mintAmountNormalized, "Minter collateral balance should decrease");
            assertEq(collateralAsset.balanceOf(address(corkPoolManager)), initialCorkPoolBalance + mintAmountNormalized, "CorkPoolManager collateral balance should increase");

            // Verify token minting
            assertEq(principalToken.balanceOf(currentCaller()), initialPrincipalBalance + 1 ether, "Principal token balance should increase");
            assertEq(swapToken.balanceOf(currentCaller()), initialSwapBalance + 1 ether, "Swap token balance should increase");
            assertEq(principalToken.totalSupply(), initialPrincipalSupply + 1 ether, "Principal token supply should increase");
            assertEq(swapToken.totalSupply(), initialSwapSupply + 1 ether, "Swap token supply should increase");

            // Verify allowance was consumed
            assertEq(collateralAsset.allowance(currentCaller(), address(corkPoolManager)), initialAllowance - mintAmountNormalized, "Allowance should be consumed");
        }

        // Verify pool internal balances
        (uint256 finalCollateralLocked, uint256 finalSwapTokenBalance, uint256 finalReferenceAssetBalance) = corkPoolManager.getPoolBalances(defaultPoolId);

        assertEq(finalCollateralLocked, initialCollateralLocked + mintAmountNormalized, "Pool collateral locked should increase");
        assertEq(finalSwapTokenBalance, initialSwapTokenBalance, "Pool swap token balance should remain unchanged");
        assertEq(finalReferenceAssetBalance, initialReferenceAssetBalance, "Pool reference asset balance should remain unchanged");
    }

    function testFuzz_previewMint(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        uint256 expectedInAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralDecimal);

        // Preview mint
        uint256 previewInAmount = corkPoolManager.previewMint(defaultPoolId, 1 ether);

        // Execute actual mint
        uint256 actualInAmount = corkPoolManager.mint(defaultPoolId, 1 ether, currentCaller());

        // Verify preview matches actual
        assertEq(previewInAmount, actualInAmount, "Preview mint should match actual mint");

        // Also verify expected value
        assertEq(actualInAmount, expectedInAmount, "Should require correct collateral amount based on decimals");
    }

    // ================================ INTEGRATION MINT TESTS ================================ //

    function test_mint_WithDifferentDecimals() external __createPool(1 days, 6, 18) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        // Test mint with different decimal configurations
        uint256 tokensOutNormalized = 1 ether; // This is in 18 decimals (target decimals)
        uint256 expectedCollateralIn = TransferHelper.normalizeDecimals(tokensOutNormalized, TARGET_DECIMALS, 6);

        uint256 collateralIn = corkPoolManager.mint(defaultPoolId, tokensOutNormalized, currentCaller());

        // Should require normalized collateral amount
        assertEq(collateralIn, expectedCollateralIn);
    }

    function test_mint_MultipleUsers() external {
        // Test mints from multiple users
        overridePrank(bob);
        uint256 collateralIn1 = corkPoolManager.mint(defaultPoolId, 500 ether, currentCaller());
        vm.stopPrank();

        overridePrank(charlie);
        uint256 collateralIn2 = corkPoolManager.mint(defaultPoolId, 300 ether, currentCaller());
        vm.stopPrank();

        assertEq(collateralIn1, 500 ether);
        assertEq(collateralIn2, 300 ether);

        // Check balances
        assertEq(principalToken.balanceOf(bob), 500 ether);
        assertEq(principalToken.balanceOf(charlie), 300 ether);
        assertEq(swapToken.balanceOf(bob), 500 ether);
        assertEq(swapToken.balanceOf(charlie), 300 ether);
    }
}
