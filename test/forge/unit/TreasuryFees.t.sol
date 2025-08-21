// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {ERC20Burnable, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract TreasuryFeesTest is Helper {
    ERC20Mock private collateralAsset;
    ERC20Mock private referenceAsset;
    MarketId private marketId;
    address private user;
    address private treasury;

    uint256 private constant TEST_AMOUNT = 1 ether;
    uint256 private constant FEE_PERCENTAGE = 5 ether; // 5%

    function setUp() public {
        user = address(0x1234);
        treasury = address(0x5678);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, marketId) = createMarket(1 days);

        // Set treasury address
        corkConfig.setTreasury(treasury);

        // Set fees for testing
        corkConfig.updateUnwindSwapFeeRate(marketId, FEE_PERCENTAGE);
        corkConfig.updateBaseRedemptionFeePercentage(marketId, FEE_PERCENTAGE);

        vm.deal(user, type(uint256).max);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        vm.startPrank(user);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();
        vm.stopPrank();
    }

    function setupDifferentDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (uint8, uint8) {
        vm.startPrank(DEFAULT_ADDRESS);

        raDecimals = uint8(bound(raDecimals, 6, 18));
        paDecimals = uint8(bound(paDecimals, 6, 18));

        (collateralAsset, referenceAsset, marketId) = createMarket(1 days, raDecimals, paDecimals);

        // Set treasury address
        corkConfig.setTreasury(treasury);

        // Set fees for testing
        corkConfig.updateUnwindSwapFeeRate(marketId, FEE_PERCENTAGE);
        corkConfig.updateBaseRedemptionFeePercentage(marketId, FEE_PERCENTAGE);

        vm.deal(user, type(uint256).max);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        vm.startPrank(user);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);

        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);

        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);

        vm.stopPrank();

        return (raDecimals, paDecimals);
    }

    function test_unwindSwap_ShouldSendFeesToTreasury() external {
        // Setup: deposit and create liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        corkPool.swap(marketId, 200 ether, user); // Create pool liquidity
        vm.stopPrank();

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);

        // Use a larger amount for testing
        uint256 unwindAmount = 10.52631579 ether;

        // Preview to get expected fee
        (,, uint256 expectedFeePercentage, uint256 expectedFee,) = corkPool.previewUnwindSwap(marketId, unwindAmount);

        vm.startPrank(user);
        (,, uint256 actualFeePercentage, uint256 actualFee,) = corkPool.unwindSwap(marketId, unwindAmount, user);
        vm.stopPrank();

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        assertEq(treasuryFeesReceived, actualFee, "Treasury should receive the exact fee amount");
        assertApproxEqAbs(treasuryFeesReceived, 0.52631579 ether, 0.0001 ether, "Treasury should receive the exact fee amount");
    }

    function test_unwindExercise_ShouldSendFeesToTreasury() external {
        // Setup: create pool liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        corkPool.swap(marketId, 200 ether, user); // Create liquidity

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);
        uint256 shares = 50 ether;

        (uint256 assetIn, uint256 compensationOut) = corkPool.unwindExercise(marketId, shares, user, 0, type(uint256).max);

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;
        // this tests depends on https://github.com/Cork-Technology/Depeg-Swap-Private/pull/51 to succeed
        assertApproxEqAbs(treasuryFeesReceived, 2.63157895 ether, 0.001 ether, "this tests depends on https://github.com/Cork-Technology/Depeg-Swap-Private/pull/51 to succeed");
    }

    function test_exercise_ShouldSendFeesToTreasury() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);
        vm.stopPrank();

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);
        uint256 exerciseShares = 100 ether;

        vm.startPrank(user);
        (,, uint256 fee) = corkPool.exercise(marketId, exerciseShares, 0, user, 0, type(uint256).max);
        vm.stopPrank();

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        assertEq(treasuryFeesReceived, 5 ether, "Treasury should receive the exact fee amount");
        assertEq(fee, 5 ether, "Treasury should receive the exact fee amount");
    }

    function test_swap_ShouldSendFeesToTreasury() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);
        vm.stopPrank();

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);
        uint256 assets = 100 ether;

        vm.startPrank(user);

        (uint256 shares, uint256 compensation) = corkPool.swap(marketId, assets, address(44));
        vm.stopPrank();

        assertApproxEqAbs(shares, 105.2631579 ether, 0.001 ether);
        assertApproxEqAbs(compensation, 105.2631579 ether, 0.001 ether);

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;
        assertApproxEqAbs(treasuryFeesReceived, 5.2631579 ether, 0.0001 ether);
    }

    function testFuzz_unwindSwap_ShouldSendFeesToTreasury(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        // Setup: deposit and create liquidity first
        vm.startPrank(user);
        uint256 depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, raDecimals);
        uint256 swapAmount = TransferHelper.normalizeDecimals(200 ether, TARGET_DECIMALS, raDecimals);

        corkPool.deposit(marketId, depositAmount, currentCaller());
        corkPool.swap(marketId, swapAmount, user); // Create pool liquidity

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);

        // Use a larger amount for testing
        uint256 unwindAmount = TransferHelper.normalizeDecimals(10.52631579 ether, TARGET_DECIMALS, raDecimals);

        // Preview to get expected fee
        (,,, uint256 actualFee,) = corkPool.unwindSwap(marketId, unwindAmount, user);

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        assertEq(treasuryFeesReceived, actualFee, "Treasury should receive the exact fee amount");
        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.52631579 ether, TARGET_DECIMALS, raDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(0.0001 ether, TARGET_DECIMALS, raDecimals);
        assertApproxEqAbs(treasuryFeesReceived, expectedAmount, acceptableDelta, "Treasury should receive the exact fee amount");
    }

    function testFuzz_unwindExercise_ShouldSendFeesToTreasury(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        // Setup: create pool liquidity
        vm.startPrank(user);
        uint256 depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, raDecimals);
        uint256 swapAmount = TransferHelper.normalizeDecimals(200 ether, TARGET_DECIMALS, raDecimals);
        corkPool.deposit(marketId, depositAmount, currentCaller());
        corkPool.swap(marketId, swapAmount, user); // Create liquidity

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);
        uint256 shares = 50 ether;

        corkPool.unwindExercise(marketId, shares, user, 0, type(uint256).max);

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;
        // this tests depends on https://github.com/Cork-Technology/Depeg-Swap-Private/pull/51 to succeed
        uint256 expectedAmount = TransferHelper.normalizeDecimals(2.63157895 ether, TARGET_DECIMALS, raDecimals);
        assertApproxEqAbs(treasuryFeesReceived, expectedAmount, 0.001 ether, "this tests depends on https://github.com/Cork-Technology/Depeg-Swap-Private/pull/51 to succeed");
    }

    function testFuzz_exercise_ShouldSendFeesToTreasury(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        // Setup: deposit first
        vm.startPrank(user);
        uint256 depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, raDecimals);
        corkPool.deposit(marketId, depositAmount, currentCaller());

        (, address swapToken) = corkPool.shares(marketId);
        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);
        uint256 exerciseShares = 1 ether;

        (,, uint256 fee) = corkPool.exercise(marketId, exerciseShares, 0, user, 0, type(uint256).max);

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.05 ether, TARGET_DECIMALS, raDecimals);
        assertEq(treasuryFeesReceived, expectedAmount, "Treasury should receive the exact fee amount");
        assertEq(fee, expectedAmount, "Treasury should receive the exact fee amount");
    }

    function testFuzz_swap_ShouldSendFeesToTreasury(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        // Setup: deposit first
        vm.startPrank(user);
        uint256 depositAmount = TransferHelper.normalizeDecimals(1000 ether, TARGET_DECIMALS, raDecimals);
        corkPool.deposit(marketId, depositAmount, currentCaller());

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);

        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);
        uint256 assets = TransferHelper.normalizeDecimals(100 ether, TARGET_DECIMALS, raDecimals);

        (uint256 shares, uint256 compensation) = corkPool.swap(marketId, assets, address(44));

        {
            uint256 expectedShares = 105.2631579 ether;
            uint256 expectedCompensation = TransferHelper.normalizeDecimals(105.2631579 ether, TARGET_DECIMALS, paDecimals);
            uint256 acceptableDelta = 0.001 ether;
            uint256 acceptableDeltaCompensation = TransferHelper.normalizeDecimals(0.001 ether, TARGET_DECIMALS, paDecimals);
            assertApproxEqAbs(shares, expectedShares, acceptableDelta);
            assertApproxEqAbs(compensation, expectedCompensation, acceptableDeltaCompensation);
        }

        uint256 treasuryBalanceAfter = collateralAsset.balanceOf(treasury);
        uint256 treasuryFeesReceived = treasuryBalanceAfter - treasuryBalanceBefore;
        uint256 expectedFeeAmount = TransferHelper.normalizeDecimals(5.2631579 ether, TARGET_DECIMALS, raDecimals);
        uint256 acceptableFeesDelta = TransferHelper.normalizeDecimals(0.0001 ether, TARGET_DECIMALS, raDecimals);
        assertApproxEqAbs(treasuryFeesReceived, expectedFeeAmount, acceptableFeesDelta);
    }
}
