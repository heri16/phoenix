// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract MaxExerciseOtherTest is Helper {
    ERC20Mock internal collateralAsset;
    ERC20Mock internal referenceAsset;
    PoolShare internal swapToken;
    PoolShare internal principalToken;

    uint256 public constant DEFAULT_DEPOSIT_AMOUNT = 10_000 ether;
    uint256 public constant EXPIRY = 30 days;

    address user2 = address(0x456);

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset,) = createMarket(EXPIRY, 1 ether);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        swapToken.approve(address(corkPoolManager), type(uint256).max);
        principalToken.approve(address(corkPoolManager), type(uint256).max);

        vm.stopPrank();

        // Setup user2
        vm.startPrank(user2);
        vm.deal(user2, type(uint256).max);

        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        swapToken.approve(address(corkPoolManager), type(uint256).max);
        principalToken.approve(address(corkPoolManager), type(uint256).max);

        vm.stopPrank();
    }

    function setupDifferentDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (uint8, uint8) {
        // bound decimals to minimum of TARGET_DECIMALS and max of MAX_DECIMALS
        raDecimals = uint8(bound(raDecimals, TARGET_DECIMALS, MAX_DECIMALS));
        paDecimals = uint8(bound(paDecimals, TARGET_DECIMALS, MAX_DECIMALS));

        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY, raDecimals, paDecimals);

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        collateralAsset.deposit{value: type(uint256).max}();

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        referenceAsset.deposit{value: type(uint256).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        swapToken.approve(address(corkPoolManager), type(uint256).max);
        principalToken.approve(address(corkPoolManager), type(uint256).max);

        return (raDecimals, paDecimals);
    }

    // ============ Basic Functionality Tests ============

    function test_maxExerciseOther_basicFunctionality() public {
        vm.startPrank(DEFAULT_ADDRESS);
        address user3 = address(99);

        // Setup - deposit to create pool liquidity
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        // Give user3 some reference assets AND some CST tokens for compensation mode
        referenceAsset.transfer(user3, 500 ether);
        swapToken.transfer(user3, 100 ether); // CST tokens needed for compensation mode

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user3);

        assertEq(maxReferenceAssets, 100 ether, "Should return valid result");
    }

    function test_maxExerciseOther_withZeroReferenceBalance() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Setup - deposit to create pool liquidity but don't give user2 reference assets
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        vm.stopPrank();

        // user2 has no reference assets
        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user2);

        // Should be 0 when user has no reference assets
        assertEq(maxReferenceAssets, 0, "Should return 0 when user has no reference assets");
    }

    // ============ Edge Case Tests ============

    function test_maxExerciseOther_whenSwapsPaused() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Setup - deposit to create pool liquidity
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        referenceAsset.transfer(user2, 500 ether);

        // Pause swaps
        defaultCorkController.pauseSwaps(defaultCurrencyId);

        vm.stopPrank();

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user2);

        // Should be 0 when swaps are paused
        assertEq(maxReferenceAssets, 0, "Should return 0 when swaps are paused");
    }

    function test_maxExerciseOther_afterExpiry() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Setup - deposit to create pool liquidity
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        referenceAsset.transfer(user2, 500 ether);

        vm.stopPrank();

        // Move past expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user2);

        // Should be 0 after expiry
        assertEq(maxReferenceAssets, 0, "Should return 0 after market expiry");
    }

    function test_maxExerciseOther_withZeroAddress() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Setup - deposit to create pool liquidity
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        vm.stopPrank();

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, address(0));

        // Should be 0 for zero address (has no assets)
        assertEq(maxReferenceAssets, 0, "Should return 0 for zero address");
    }

    function test_maxExerciseOther_withEmptyPool() public {
        // Don't deposit anything - empty pool

        vm.startPrank(DEFAULT_ADDRESS);
        referenceAsset.transfer(user2, 500 ether);
        vm.stopPrank();

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user2);

        // Should be 0 when pool is empty (no collateral to provide)
        assertEq(maxReferenceAssets, 0, "Should return 0 when pool is empty");
    }

    function test_maxExerciseOther_gasUsage() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Setup
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        referenceAsset.transfer(user2, 500 ether);

        vm.stopPrank();

        // Measure gas usage
        uint256 gasBefore = gasleft();
        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user2);
        uint256 gasUsed = gasBefore - gasleft();

        // Should be a view function with reasonable gas usage
        assertLt(gasUsed, 20_000, "Should use reasonable amount of gas");
        assertGe(maxReferenceAssets, 0, "Should return valid result");
    }

    // ============ Integration Tests ============

    function test_maxExerciseOther_integrationWithPreviewExercise() public {
        vm.startPrank(DEFAULT_ADDRESS);

        address user3 = address(99);

        // Setup
        uint256 depositAmount = 1000 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        referenceAsset.transfer(user3, 500 ether);
        swapToken.transfer(user3, 100 ether);

        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0);

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user3);

        // Should be able to preview exercise with the max amount
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.previewExerciseOther(
                defaultCurrencyId,
                maxReferenceAssets // compensation
            );

        assertEq(assets, 100 ether, "Should receive assets in preview");
        assertEq(otherAssetSpent, 100 ether, "Should spend other assets in preview");
    }

    // ============ Fuzz Test ============
    function testFuzz_maxExerciseOther_differentDecimals(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        address user3 = address(99);

        // Setup - deposit to create pool liquidity
        uint256 depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, raDecimals);
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);
        // Give user3 some reference assets AND some CST tokens for compensation mode
        referenceAsset.transfer(user3, TransferHelper.normalizeDecimals(500 ether, TARGET_DECIMALS, paDecimals));
        swapToken.transfer(user3, 100 ether); // CST tokens needed for compensation mode

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user3);

        assertEq(maxReferenceAssets, TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, paDecimals), "Should return valid result");
    }

    function testFuzz_maxExerciseOther_differentDecimals_differentRate(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        testOracle.setRate(0.8 ether);
        address user3 = address(99);

        // Setup - deposit to create pool liquidity
        uint256 depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, raDecimals);
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);
        // Give user3 some reference assets AND some CST tokens for compensation mode
        referenceAsset.transfer(user3, TransferHelper.normalizeDecimals(10 ether, TARGET_DECIMALS, paDecimals));
        swapToken.transfer(user3, 100 ether); // CST tokens needed for compensation mode

        uint256 maxReferenceAssets = corkPoolManager.maxExerciseOther(defaultCurrencyId, user3);

        assertEq(maxReferenceAssets, TransferHelper.normalizeDecimals(10 ether, TARGET_DECIMALS, paDecimals), "Should return valid result");
    }
}
