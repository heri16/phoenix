// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {CorkPoolAdapter} from "contracts/periphery/CorkPoolAdapter.sol";
import "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract CorkPoolAdapterUnwindExerciseTest is Helper {
    address constant RECEIVER = address(0x123);
    address constant OWNER = address(0x456);
    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant EXPIRY = 30 days;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare swapToken;
    PoolShare principalToken;

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        deployPeriphery();
        vm.stopPrank();
    }

    function setupUnwindExerciseTest() internal {
        vm.startPrank(DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY);

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        collateralAsset.deposit{value: type(uint256).max}();

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        referenceAsset.deposit{value: type(uint256).max}();

        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        swapToken.approve(address(corkPool), type(uint256).max);
        principalToken.approve(address(corkPool), type(uint256).max);

        // Deposit some collateral to get CST and CPT tokens
        uint256 depositAmount = 1000e18;
        corkPool.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        // Perform a swap to create liquidity for unwind exercise
        uint256 swapAmount = 500e18;
        corkPool.swap(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_success_basicTest() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        // Set 1% base redemption fee
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 1 ether);

        uint256 shares = 100e18;
        uint256 minCompensationOut = 50e18;
        uint256 maxAssetsIn = 200e18;

        // Hardcoded expected amounts based on 1% fee
        uint256 expectedAssetIn = 101_010_100_616_465_037_754; // ~101.01e18 (100e18 + 1% fee)
        uint256 expectedCompensationOut = 100e18; // Should receive 100e18 compensation

        // Get preview of the unwind exercise for reference
        (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        // Record initial balances
        uint256 receiverRefAssetBefore = referenceAsset.balanceOf(RECEIVER);
        uint256 receiverSwapTokenBefore = swapToken.balanceOf(RECEIVER);

        // Transfer collateral to adapter and record balances
        collateralAsset.transfer(address(corkPoolAdapter), maxAssetsIn);

        uint256 adapterCollateralBefore = collateralAsset.balanceOf(address(corkPoolAdapter));

        // Execute unwind exercise
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        // Verify results
        uint256 actualCollateralUsed = adapterCollateralBefore - collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 actualCompensationReceived = referenceAsset.balanceOf(RECEIVER) - receiverRefAssetBefore;
        uint256 actualSharesReceived = swapToken.balanceOf(RECEIVER) - receiverSwapTokenBefore;

        // Compare with hardcoded expected amounts
        assertEq(actualCollateralUsed, expectedAssetIn, "Should use expected asset amount with 1% fee");
        assertEq(actualCompensationReceived, expectedCompensationOut, "Should receive expected compensation amount");
        assertEq(actualSharesReceived, shares, "Should receive the specified shares amount");

        // Verify preview matches actual
        assertEq(actualCollateralUsed, previewAssetIn, "Should use preview asset amount");
        assertEq(actualCompensationReceived, previewCompensationOut, "Should receive preview compensation amount");

        // Verify slippage protection
        assertGe(actualCompensationReceived, minCompensationOut, "Should receive at least minimum compensation");
        assertLe(actualCollateralUsed, maxAssetsIn, "Should not exceed maximum asset input");

        vm.stopPrank();
    }

    function test_safeUnwindExercise_success_exactLimits() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 shares = 100e18;

        // Get preview to set exact limits
        (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        uint256 minCompensationOut = previewCompensationOut;
        uint256 maxAssetsIn = previewAssetIn;

        // Transfer exact collateral needed to adapter
        collateralAsset.transfer(address(corkPoolAdapter), maxAssetsIn);

        // Execute unwind exercise with exact limits
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        // Verify the transaction succeeded with exact limits
        uint256 receiverRefAssetAfter = referenceAsset.balanceOf(RECEIVER);
        uint256 receiverSwapTokenAfter = swapToken.balanceOf(RECEIVER);

        assertEq(receiverRefAssetAfter, previewCompensationOut, "Should receive exact compensation amount");
        assertEq(receiverSwapTokenAfter, shares, "Should receive exact shares amount");

        vm.stopPrank();
    }

    function test_safeUnwindExercise_revertsOnDeadlineExceeded() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 shares = 100e18;
        uint256 minCompensationOut = 50e18;
        uint256 maxAssetsIn = 200e18;

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp - 1);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_revertsOnZeroReceiver() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 shares = 100e18;
        uint256 minCompensationOut = 50e18;
        uint256 maxAssetsIn = 200e18;

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, address(0), minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_revertsOnZeroShares() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 minCompensationOut = 50e18;
        uint256 maxAssetsIn = 200e18;

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, 0, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_revertsOnSlippageExceeded_minCompensationOut() public {
        setupUnwindExerciseTest();

        uint256 shares = 100e18;
        uint256 minCompensationOut = type(uint256).max; // Very high minimum to trigger slippage
        uint256 maxAssetsIn = 200e18;

        // Transfer collateral to adapter
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.transfer(address(corkPoolAdapter), maxAssetsIn);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        // Expect InsufficientOutputAmount error from the underlying unwindExercise call
        vm.expectRevert();
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_revertsOnSlippageExceeded_maxAssetsIn() public {
        setupUnwindExerciseTest();

        uint256 shares = 100e18;
        uint256 minCompensationOut = 1;
        uint256 maxAssetsIn = 1; // Very low maximum to trigger slippage

        // Transfer collateral to adapter
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.transfer(address(corkPoolAdapter), 200e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        // Expect ExcessiveInput error from the underlying unwindExercise call
        vm.expectRevert();
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_revertsOnUnauthorizedCaller() public {
        setupUnwindExerciseTest();

        uint256 shares = 100e18;
        uint256 minCompensationOut = 50e18;
        uint256 maxAssetsIn = 200e18;

        vm.prank(address(0x999));
        vm.expectRevert(IErrors.UnauthorizedSender.selector);
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);
    }

    function test_safeUnwindExercise_revertsOnInsufficientCollateral() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 shares = 100e18;
        uint256 minCompensationOut = 1;
        uint256 maxAssetsIn = 200e18;

        // Don't transfer enough collateral to adapter
        collateralAsset.transfer(address(corkPoolAdapter), 10e18);

        vm.expectRevert();
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeUnwindExercise_success_multipleOperations() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 shares1 = 50e18;
        uint256 shares2 = 75e18;
        uint256 minCompensationOut = 25e18;
        uint256 maxAssetsIn = 150e18;

        // Transfer sufficient collateral for multiple operations
        collateralAsset.transfer(address(corkPoolAdapter), 500e18);

        // Record initial balances
        uint256 receiverRefAssetBefore = referenceAsset.balanceOf(RECEIVER);
        uint256 receiverSwapTokenBefore = swapToken.balanceOf(RECEIVER);

        // Execute first unwind exercise
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares1, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        // Execute second unwind exercise
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares2, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        // Verify total results
        uint256 receiverRefAssetAfter = referenceAsset.balanceOf(RECEIVER);
        uint256 receiverSwapTokenAfter = swapToken.balanceOf(RECEIVER);

        uint256 totalCompensationReceived = receiverRefAssetAfter - receiverRefAssetBefore;
        uint256 totalSharesReceived = receiverSwapTokenAfter - receiverSwapTokenBefore;

        assertEq(totalSharesReceived, shares1 + shares2, "Should receive total shares from both operations");
        assertGt(totalCompensationReceived, 0, "Should receive some compensation");

        vm.stopPrank();
    }

    function test_safeUnwindExercise_success_largeAmounts() public {
        setupUnwindExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 shares = 500e18; // Large amount
        uint256 minCompensationOut = 100e18;
        uint256 maxAssetsIn = 1000e18;

        // Transfer large amount of collateral to adapter
        collateralAsset.transfer(address(corkPoolAdapter), maxAssetsIn);

        // Execute unwind exercise with large amounts
        corkPoolAdapter.safeUnwindExercise(defaultCurrencyId, shares, RECEIVER, minCompensationOut, maxAssetsIn, block.timestamp + 1 hours);

        // Verify the transaction succeeded
        uint256 receiverSwapTokenAfter = swapToken.balanceOf(RECEIVER);
        assertEq(receiverSwapTokenAfter, shares, "Should receive the large shares amount");

        vm.stopPrank();
    }
}
