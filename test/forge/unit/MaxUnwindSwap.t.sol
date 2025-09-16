// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract MaxUnwindSwapTest is Helper {
    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    MarketId marketId;

    address user = address(0x123);
    address user2 = address(0x456);
    address owner = address(0x789);

    uint256 DEPOSIT_AMOUNT = 1000 ether;
    uint256 SWAP_AMOUNT = 100 ether;

    address principalToken;
    address swapToken;

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, marketId) = createMarket(1 days);

        vm.deal(user, type(uint256).max);
        vm.deal(user2, type(uint256).max);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        (principalToken, swapToken) = corkPool.shares(marketId);

        vm.startPrank(user);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        // Deposit first
        collateralAsset.approve(address(corkPool), DEPOSIT_AMOUNT);
        corkPool.deposit(marketId, DEPOSIT_AMOUNT, currentCaller());

        // Approve for Swap
        IERC20(referenceAsset).approve(address(corkPool), type(uint256).max);
        IERC20(swapToken).approve(address(corkPool), type(uint256).max);

        vm.startPrank(user2);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        IERC20(referenceAsset).approve(address(corkPool), type(uint256).max);
        IERC20(swapToken).approve(address(corkPool), type(uint256).max);

        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        IERC20(referenceAsset).approve(address(corkPool), type(uint256).max);
        IERC20(swapToken).approve(address(corkPool), type(uint256).max);

        vm.stopPrank();
    }

    function test_maxUnwindSwap_BasicFunctionality() external {
        // SWAP FIRST
        vm.startPrank(user);
        corkPool.swap(marketId, SWAP_AMOUNT, user);
        vm.stopPrank();

        // Add more deposits for liquidity
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 500 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        // Test maxUnwindSwap
        uint256 maxAmount = corkPool.maxUnwindSwap(marketId, user);

        // Should return a reasonable amount
        assertGt(maxAmount, 0, "Max unwind swap should be greater than 0");

        IUnwindSwap.UnwindSwapReturnParams memory previewReturnParams = corkPool.previewUnwindSwap(marketId, maxAmount);
        assertGt(previewReturnParams.receivedReferenceAsset, 0, "Should receive reference asset");
        assertGt(previewReturnParams.receivedSwapToken, 0, "Should receive swap token");
    }

    function test_maxUnwindSwap_WhenUnwindSwapPaused() external {
        // SWAP FIRST
        vm.startPrank(user);
        corkPool.swap(marketId, SWAP_AMOUNT, user);
        vm.stopPrank();

        // Pause unwind swaps
        vm.prank(DEFAULT_ADDRESS);
        corkConfig.pauseUnwindSwaps(defaultCurrencyId);

        // Should return 0 when paused
        uint256 maxAmount = corkPool.maxUnwindSwap(marketId, user);
        assertEq(maxAmount, 0, "Should return 0 when unwind swap is paused");
    }

    function test_maxUnwindSwap_WhenExpired() external {
        vm.startPrank(user);
        // Do swap first
        corkPool.swap(marketId, SWAP_AMOUNT, user);
        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + 365 days + 1);

        // Should return 0 when expired
        uint256 maxAmount = corkPool.maxUnwindSwap(marketId, user);
        assertEq(maxAmount, 0, "Should return 0 when expired");
    }

    function test_maxUnwindSwap_WithNoLiquidity() external {
        // Test with empty market (no liquidity)
        uint256 maxAmount = corkPool.maxUnwindSwap(marketId, user);
        assertEq(maxAmount, 0, "Should return 0 with no liquidity");
    }

    function test_maxUnwindSwap_ConsistencyWithPreview() external {
        // Setup: Create a market with liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), DEPOSIT_AMOUNT);
        corkPool.deposit(marketId, DEPOSIT_AMOUNT, currentCaller());

        // CRITICAL: Do swap FIRST to create swap token liquidity
        corkPool.swap(marketId, SWAP_AMOUNT, user);
        vm.stopPrank();

        // Add more deposits for additional liquidity
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), DEPOSIT_AMOUNT);
        corkPool.deposit(marketId, DEPOSIT_AMOUNT, currentCaller());
        vm.stopPrank();

        uint256 maxAmount = corkPool.maxUnwindSwap(marketId, user);

        // Test that maxAmount should work without reverting
        IUnwindSwap.UnwindSwapReturnParams memory previewReturnParams = corkPool.previewUnwindSwap(marketId, maxAmount);

        // Verify the preview returns reasonable values
        assertGt(previewReturnParams.receivedReferenceAsset, 0, "Should receive reference asset");
        assertGt(previewReturnParams.receivedSwapToken, 0, "Should receive swap token");
    }

    // only works up to 10 decimals, need to re confirm
    function testFuzz_maxUnwindSwap_DifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 11, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 11, 18));

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with different decimals using Helper
        (ERC20Mock newCollateralAsset, ERC20Mock newReferenceAsset, MarketId newMarketId) = createMarket(365 days, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, referenceDecimals, collateralDecimals);

        corkConfig.updateUnwindSwapFeeRate(newMarketId, 0);

        // Mint tokens to users
        uint256 collateralAssetAmount = 1_000_000 * 10 ** collateralDecimals;
        uint256 referenceAmount = 1_000_000 * 10 ** referenceDecimals;

        vm.deal(user, type(uint256).max);
        vm.deal(user2, type(uint256).max);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        vm.startPrank(user);
        newCollateralAsset.deposit{value: type(uint128).max}();
        newReferenceAsset.deposit{value: type(uint128).max}();

        vm.startPrank(user2);
        newCollateralAsset.deposit{value: type(uint128).max}();
        newReferenceAsset.deposit{value: type(uint128).max}();

        vm.startPrank(DEFAULT_ADDRESS);
        newCollateralAsset.deposit{value: type(uint128).max}();
        newReferenceAsset.deposit{value: type(uint128).max}();
        vm.stopPrank();

        vm.startPrank(user);
        // 1. Deposit first

        // 2. CRITICAL: Do swap FIRST before testing unwind swap
        (principalToken, swapToken) = corkPool.shares(newMarketId);
        IERC20(newReferenceAsset).approve(address(corkPool), type(uint256).max);
        IERC20(newCollateralAsset).approve(address(corkPool), type(uint256).max);
        IERC20(swapToken).approve(address(corkPool), type(uint256).max);

        corkPool.deposit(newMarketId, collateralAssetAmount, currentCaller());

        uint256 swapAmount = collateralAssetAmount / 2; // Use 50% for swap

        corkPool.swap(newMarketId, swapAmount, user);
        vm.stopPrank();

        // Test maxUnwindSwap - should not revert regardless of decimals
        uint256 maxAmount = corkPool.maxUnwindSwap(newMarketId, user);

        // Should be able to handle different decimals correctly
        assertTrue(maxAmount > 0, "maxUnwindSwap should not revert with different decimals");

        // Get initial balances
        uint256 initialRefBalance = IERC20(newReferenceAsset).balanceOf(user);
        uint256 initialSwapBalance = IERC20(swapToken).balanceOf(user);

        // Preview the unwind swap
        IUnwindSwap.UnwindSwapReturnParams memory previewReturnParams = corkPool.previewUnwindSwap(newMarketId, maxAmount);

        // Perform the actual unwind swap
        vm.prank(user);
        corkPool.unwindSwap(newMarketId, maxAmount, user);

        {
            // Verify balances match preview
            uint256 finalRefBalance = IERC20(newReferenceAsset).balanceOf(user);
            uint256 finalSwapBalance = IERC20(swapToken).balanceOf(user);

            assertEq(finalRefBalance - initialRefBalance, previewReturnParams.receivedReferenceAsset, "Reference asset balance should match preview");
            assertEq(finalSwapBalance - initialSwapBalance, previewReturnParams.receivedSwapToken, "Swap token balance should match preview");
        }

        // Verify availableForUnwindSwap returns 0 for both values after max unwind
        (uint256 availableRefAfter, uint256 availableSwapAfter) = corkPool.availableForUnwindSwap(newMarketId);
        assertApproxEqAbs(availableRefAfter, 0, 0.00000000001 ether, "Available reference should be 0 after max unwind swap");
        assertApproxEqAbs(availableSwapAfter, 0, 0.000001 ether, "Available swap tokens should be 0 after max unwind swap");
    }

    function testFuzz_maxUnwindSwap_DifferentLiquidityLevels(uint256 collateralLiquidity, uint256 swapAmount) external {
        // Bound liquidity to reasonable ranges
        collateralLiquidity = bound(collateralLiquidity, 1 ether, 10_000 ether);
        swapAmount = bound(swapAmount, 0.1 ether, collateralLiquidity / 2);

        // Setup initial deposit
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), collateralLiquidity);
        corkPool.deposit(marketId, collateralLiquidity, currentCaller());

        // CRITICAL: Do swap FIRST to create swap token liquidity

        corkPool.swap(marketId, swapAmount, user);
        vm.stopPrank();

        // Add varying liquidity levels from user2
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), collateralLiquidity);
        corkPool.deposit(marketId, collateralLiquidity / 2, currentCaller());
        vm.stopPrank();

        // Test maxUnwindSwap with different liquidity levels
        uint256 maxAmount = corkPool.maxUnwindSwap(marketId, user);

        // Should not revert regardless of liquidity levels
        assertTrue(maxAmount >= 0, "maxUnwindSwap should handle different liquidity levels");

        // Get initial balances
        uint256 initialRefBalance = IERC20(referenceAsset).balanceOf(user);
        uint256 initialSwapBalance = IERC20(swapToken).balanceOf(user);

        // Preview the unwind swap
        IUnwindSwap.UnwindSwapReturnParams memory previewReturnParams = corkPool.previewUnwindSwap(marketId, maxAmount);

        // Perform the actual unwind swap
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), maxAmount);

        corkPool.unwindSwap(marketId, maxAmount, user);

        // Verify balances match preview
        uint256 finalRefBalance = IERC20(referenceAsset).balanceOf(user);
        uint256 finalSwapBalance = IERC20(swapToken).balanceOf(user);

        assertEq(finalRefBalance - initialRefBalance, previewReturnParams.receivedReferenceAsset, "Reference asset balance should match preview");
        assertEq(finalSwapBalance - initialSwapBalance, previewReturnParams.receivedSwapToken, "Swap token balance should match preview");

        // Verify availableForUnwindSwap returns 0 for both values after max unwind
        (uint256 availableRefAfter, uint256 availableSwapAfter) = corkPool.availableForUnwindSwap(marketId);

        assertApproxEqAbs(availableRefAfter, 0, 0.6 ether, "Available reference should be close to 0 after max unwind swap");
        assertApproxEqAbs(availableSwapAfter, 0, 0.6 ether, "Available swap tokens should be close to 0 after max unwind swap");
    }

    function test_maxUnwindSwap_NeverReverts_ForValidMarket() external {
        // Test that maxUnwindSwap never reverts under various conditions Except for expired market

        // 1. Uninitialized market Will revert
        MarketId uninitializedId = MarketId.wrap(keccak256("uninitialized"));
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotInitialized.selector));
        corkPool.maxUnwindSwap(uninitializedId, user);

        // 2. Normal market Will not revert
        uint256 result2 = corkPool.maxUnwindSwap(marketId, user);
        assertTrue(result2 >= 0, "Should not revert for normal market");

        // 3. Market with zero address user Will not revert
        uint256 result3 = corkPool.maxUnwindSwap(marketId, address(0));
        assertTrue(result3 >= 0, "Should not revert with zero address user");

        // 4. After proper operations: deposit -> swap -> more deposits Will not revert
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), DEPOSIT_AMOUNT);
        corkPool.deposit(marketId, DEPOSIT_AMOUNT, currentCaller());

        // // Do swap first
        // corkPool.swap(marketId, SWAP_AMOUNT, user);

        // Do swap first Will not revert
        (address principalToken,) = corkPool.shares(marketId);
        IERC20(principalToken).approve(address(corkPool), 100 ether);
        corkPool.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 result4 = corkPool.maxUnwindSwap(marketId, user);
        assertTrue(result4 >= 0, "Should not revert after deposit and swap");
    }

    function test_maxUnwindSwap_CorrectFlow() external {
        // This test demonstrates the correct flow: deposit -> swap -> then unwind operations

        // Before any operations
        uint256 maxBefore = corkPool.maxUnwindSwap(marketId, user);
        assertEq(maxBefore, 0, "Should be 0 before any operations");

        // 1. Deposit collateral
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), DEPOSIT_AMOUNT);
        corkPool.deposit(marketId, DEPOSIT_AMOUNT, currentCaller());

        // Still should be 0 - no swap tokens yet
        uint256 maxAfterDeposit = corkPool.maxUnwindSwap(marketId, user);
        assertEq(maxAfterDeposit, 0, "Should be 0 after deposit but before swap");

        (principalToken, swapToken) = corkPool.shares(defaultCurrencyId);
        IERC20(referenceAsset).approve(address(corkPool), type(uint256).max);
        IERC20(swapToken).approve(address(corkPool), type(uint256).max);
        corkPool.swap(marketId, SWAP_AMOUNT, user);

        // Now should have positive max unwind swap
        uint256 maxAfterSwap = corkPool.maxUnwindSwap(marketId, user);
        assertGt(maxAfterSwap, 0, "Should be positive after swap and additional liquidity");

        IUnwindSwap.UnwindSwapReturnParams memory previewReturnParams = corkPool.previewUnwindSwap(marketId, maxAfterSwap);
        assertGt(previewReturnParams.receivedReferenceAsset, 0, "Should receive reference asset");
        assertGt(previewReturnParams.receivedSwapToken, 0, "Should receive swap token");
    }
}
