// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

/**
 * @title DepositTests
 * @notice Unified test suite for all deposit-related functionality
 * @dev This file contains all tests related to:
 *      - deposit() function
 *      - maxDeposit() function
 *      - previewDeposit() function
 */
contract DepositTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal depositAmount = 1000 ether;

    // ================================ BASIC DEPOSIT TESTS ================================ //

    function test_deposit_ShouldMintTokens() external __as(alice) {
        uint256 depositAmountTest = 1000 ether;

        // Expect both Pool Manager and ERC4626-compatible events
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, depositAmountTest, 0, false);

        (address principalTokenAddr, address swapTokenAddr) = corkPoolManager.shares(defaultPoolId);
        vm.expectEmit(true, true, false, true, principalTokenAddr);
        emit IPoolShare.Deposit(alice, alice, depositAmountTest, depositAmountTest);

        uint256 received = corkPoolManager.deposit(defaultPoolId, depositAmountTest, currentCaller());

        assertEq(received, depositAmountTest, "Should receive equal amount in 18 decimals");
        assertEq(IERC20(principalTokenAddr).balanceOf(alice), depositAmountTest, "Should have principal tokens");
        assertEq(IERC20(swapTokenAddr).balanceOf(alice), depositAmountTest, "Should have swap tokens");
    }

    // TODO use the snapshot function in BaseTest for cleaner snapshotting
    // TODO removeoverridePrank and use overridePrank
    function test_deposit() public __as(alice) {
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

            uint256 received = corkPoolManager.deposit(defaultPoolId, depositAmount, alice);

            // Verify return value
            assertEq(received, depositAmount);

            // Verify collateral asset transfers
            assertEq(collateralAsset.balanceOf(alice), initialCollateralBalance - depositAmount, "Depositor collateral balance should decrease");
            assertEq(collateralAsset.balanceOf(address(corkPoolManager)), initialCorkPoolBalance + depositAmount, "CorkPoolManager collateral balance should increase");

            // Verify token minting
            assertEq(principalToken.balanceOf(alice), initialPrincipalBalance + depositAmount, "Principal token balance should increase");
            assertEq(swapToken.balanceOf(alice), initialSwapBalance + depositAmount, "Swap token balance should increase");
            assertEq(principalToken.totalSupply(), initialPrincipalSupply + depositAmount, "Principal token supply should increase");
            assertEq(swapToken.totalSupply(), initialSwapSupply + depositAmount, "Swap token supply should increase");

            // Verify allowance was consumed
            assertEq(collateralAsset.allowance(alice, address(corkPoolManager)), initialAllowance - depositAmount, "Allowance should be consumed");
        }

        // Verify pool internal balances
        (uint256 finalCollateralLocked, uint256 finalSwapTokenBalance, uint256 finalReferenceAssetBalance) = corkPoolManager.getPoolBalances(defaultPoolId);

        assertEq(finalCollateralLocked, initialCollateralLocked + depositAmount, "Pool collateral locked should increase");
        assertEq(finalSwapTokenBalance, initialSwapTokenBalance, "Pool swap token balance should remain unchanged");
        assertEq(finalReferenceAssetBalance, initialReferenceAssetBalance, "Pool reference asset balance should remain unchanged");
    }

    // ================================ DEPOSIT ERROR TESTS ================================ //

    function test_deposit_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPoolManager.deposit(defaultPoolId, 0, currentCaller());
    }

    function test_deposit_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.deposit(defaultPoolId, 1000 ether, currentCaller());
    }

    function test_deposit_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // 00001 = deposit paused
        vm.stopPrank();

        overridePrank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(defaultPoolId, 1000 ether, currentCaller());

        vm.stopPrank();
    }

    function test_pauseDepositStatus_blocksDeposit() public __as(pauser) {
        defaultCorkController.pauseDeposits(defaultPoolId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(defaultPoolId, 1 ether, currentCaller());
    }

    function test_deposit_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        MarketId invalidPoolId = MarketId.wrap(bytes32(uint256(999)));
        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.deposit(invalidPoolId, 1000 ether, currentCaller());
    }

    function test_deposit_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);
        vm.stopPrank();

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(defaultPoolId, 1000 ether, currentCaller());
        vm.stopPrank();
    }

    // ================================ PREVIEW DEPOSIT TESTS ================================ //

    function test_previewDeposit_ShouldReturnCorrectAmount() external {
        uint256 amount = 1000 ether;
        uint256 expected = corkPoolManager.previewDeposit(defaultPoolId, amount);
        assertEq(expected, amount, "Should return 1:1 ratio");
    }

    function test_previewDeposit() public __as(DEFAULT_ADDRESS) {
        uint256 received = corkPoolManager.previewDeposit(defaultPoolId, 1 ether);

        assertEq(received, 1 ether);
    }

    function test_previewDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 collateralAssetIn = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewDeposit(defaultPoolId, collateralAssetIn);
        uint256 poolShareResult = principalToken.previewDeposit(collateralAssetIn);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewDeposit should match PoolManager previewDeposit");
    }

    function test_previewDeposit_ShouldReturnZero_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // Pause deposits
        vm.stopPrank();

        uint256 result = corkPoolManager.previewDeposit(defaultPoolId, 1000 ether);
        assertEq(result, 0, "Preview should return 0 when paused");
    }

    function test_previewDeposit_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days); // Past expiry

        uint256 result = corkPoolManager.previewDeposit(defaultPoolId, 1000 ether);
        assertEq(result, 0, "Preview should return 0 when expired");
    }

    // ================================ MAX DEPOSIT TESTS ================================ //

    function test_maxDeposit_ShouldReturnMaxUint() external {
        uint256 maxAmount = corkPoolManager.maxDeposit(defaultPoolId, alice);
        assertEq(maxAmount, type(uint256).max, "Should return max uint256");
    }

    function test_maxDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxDeposit(defaultPoolId, bob);
        uint256 poolShareResult = principalToken.maxDeposit(bob);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxDeposit should match PoolManager maxDeposit");
    }

    function test_maxDeposit_ShouldReturnZero_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // Pause deposits
        vm.stopPrank();

        uint256 result = corkPoolManager.maxDeposit(defaultPoolId, alice);
        assertEq(result, 0, "Max deposit should return 0 when paused");
    }

    function test_maxDeposit_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days); // Past expiry

        uint256 result = corkPoolManager.maxDeposit(defaultPoolId, alice);
        assertEq(result, 0, "Max deposit should return 0 when expired");
    }

    // ================================ FUZZ DEPOSIT TESTS ================================ //

    function testFuzz_deposit(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

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

            uint256 received = corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

            // Verify return value - regardless of the amount, the received amount would be in 18 decimals
            assertEq(received, 1 ether);

            // Verify collateral asset transfers
            assertEq(collateralAsset.balanceOf(currentCaller()), initialCollateralBalance - depositAmountNormalized, "Depositor collateral balance should decrease");
            assertEq(collateralAsset.balanceOf(address(corkPoolManager)), initialCorkPoolBalance + depositAmountNormalized, "CorkPoolManager collateral balance should increase");

            // Verify token minting
            assertEq(principalToken.balanceOf(currentCaller()), initialPrincipalBalance + 1 ether, "Principal token balance should increase");
            assertEq(swapToken.balanceOf(currentCaller()), initialSwapBalance + 1 ether, "Swap token balance should increase");
            assertEq(principalToken.totalSupply(), initialPrincipalSupply + 1 ether, "Principal token supply should increase");
            assertEq(swapToken.totalSupply(), initialSwapSupply + 1 ether, "Swap token supply should increase");

            // Verify allowance was consumed
            assertEq(collateralAsset.allowance(currentCaller(), address(corkPoolManager)), initialAllowance - depositAmountNormalized, "Allowance should be consumed");
        }

        // Verify pool internal balances
        (uint256 finalCollateralLocked, uint256 finalSwapTokenBalance, uint256 finalReferenceAssetBalance) = corkPoolManager.getPoolBalances(defaultPoolId);

        assertEq(finalCollateralLocked, initialCollateralLocked + depositAmountNormalized, "Pool collateral locked should increase");
        assertEq(finalSwapTokenBalance, initialSwapTokenBalance, "Pool swap token balance should remain unchanged");
        assertEq(finalReferenceAssetBalance, initialReferenceAssetBalance, "Pool reference asset balance should remain unchanged");
    }

    function testFuzz_previewDeposit(uint8 _collateralDecimal, uint8 _referenceDecimal) external __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, collateralDecimal);

        // Preview deposit
        uint256 previewReceived = corkPoolManager.previewDeposit(defaultPoolId, depositAmountNormalized);

        // Execute actual deposit
        uint256 actualReceived = corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Verify preview matches actual
        assertEq(previewReceived, actualReceived, "Preview deposit should match actual deposit");

        // Also verify expected value - regardless of the amount, the received amount would be in 18 decimals
        assertEq(actualReceived, 1 ether, "Should receive 1 ether in 18 decimals");
    }

    // ================================ INTEGRATION DEPOSIT TESTS ================================ //

    function test_deposit_WithDifferentDecimals() external __createPool(1 days, 6, 18) __giveAssets(DEFAULT_ADDRESS) __approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager)) {
        // Test deposit with different decimal configurations
        // Create market with different decimals
        uint256 depositAmountNormalized = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, 6);
        uint256 received = corkPoolManager.deposit(defaultPoolId, depositAmountNormalized, currentCaller());

        // Should still receive 1 ether in 18 decimals
        assertEq(received, 1 ether);
    }

    function test_deposit_MultipleUsers() external {
        // Test deposits from multiple users
        overridePrank(bob);
        uint256 received1 = corkPoolManager.deposit(defaultPoolId, 500 ether, currentCaller());
        vm.stopPrank();

        overridePrank(charlie);
        uint256 received2 = corkPoolManager.deposit(defaultPoolId, 300 ether, currentCaller());
        vm.stopPrank();

        assertEq(received1, 500 ether);
        assertEq(received2, 300 ether);

        // Check balances
        assertEq(principalToken.balanceOf(bob), 500 ether);
        assertEq(principalToken.balanceOf(charlie), 300 ether);
        assertEq(swapToken.balanceOf(bob), 500 ether);
        assertEq(swapToken.balanceOf(charlie), 300 ether);
    }
}
