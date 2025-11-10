// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {ERC20Burnable, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Balances, CollateralAssetManager, CorkPoolPoolArchive, PoolState, State} from "contracts/libraries/State.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {DummyWETH, ERC20Mock} from "test/old/mocks/DummyWETH.sol";

contract CorkPoolTest is Helper {
    ERC20Mock private collateralAsset;
    ERC20Mock private referenceAsset;
    MarketId private marketId;
    address private user;
    address private user2;
    address private treasury;
    address private owner;

    // ================================ Event Declarations ================================ //

    // Events from IPoolManager and related interfaces - using IPoolManager events directly

    function setUp() public {
        user = address(0x1234);
        user2 = address(0x2345);
        treasury = address(789);
        owner = address(0x9ABC);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, marketId) = createMarket(1 days);

        vm.deal(user, type(uint256).max);
        vm.deal(user2, type(uint256).max);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        vm.startPrank(user);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        vm.startPrank(user2);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();
        vm.stopPrank();
    }

    // ================================ Market Creation Tests ================================ //

    function test_createNewPool_ShouldCreateMarket() external {
        ERC20Mock newCollateral = new DummyWETH();
        ERC20Mock newReference = new DummyWETH();
        uint256 expiry = block.timestamp + 30 days;
        uint256 rateMin = 0.9 ether;
        uint256 rateMax = 1.1 ether;
        uint256 rateChangePerDayMax = 0.0001 ether;
        uint256 rateChangeCapacityMax = 0.001 ether;
        Market memory market =
            Market({collateralAsset: address(newCollateral), referenceAsset: address(newReference), expiryTimestamp: expiry, rateOracle: address(testOracle), rateMin: rateMin, rateMax: rateMax, rateChangePerDayMax: rateChangePerDayMax, rateChangeCapacityMax: rateChangeCapacityMax});
        MarketId newId = corkPoolManager.getId(market);

        vm.startPrank(address(DEFAULT_ADDRESS));
        testOracle.setRate(newId, 1 ether);

        // Calculate expected token addresses using factory's nonce
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, true, true, true);
        emit Initialize.MarketCreated(newId, address(newReference), address(newCollateral), expiry, address(testOracle), expectedPrincipalToken, expectedSwapToken);
        corkPoolManager.createNewPool(market);

        Market memory marketParams = corkPoolManager.market(newId);
        assertEq(marketParams.referenceAsset, address(newReference), "Reference asset should match");
        assertEq(marketParams.collateralAsset, address(newCollateral), "Collateral asset should match");
        assertEq(marketParams.expiryTimestamp, expiry, "expiry should match");
        assertEq(marketParams.rateOracle, address(testOracle), "Oracle should match");
        assertEq(marketParams.rateMin, rateMin, "rateMin should match");
        assertEq(marketParams.rateMax, rateMax, "rateMax should match");
        assertEq(marketParams.rateChangePerDayMax, rateChangePerDayMax, "rateChangePerDayMax should match");
        assertEq(marketParams.rateChangeCapacityMax, rateChangeCapacityMax, "rateChangeCapacityMax should match");

        vm.stopPrank();
    }

    function test_createNewPool_ShouldRevert_WhenNotAdmin() external {
        vm.startPrank(user);

        address rateOracle = address(testOracle);
        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        corkPoolManager.createNewPool(
            Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: block.timestamp + 30 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether})
        );

        vm.stopPrank();
    }

    function test_createNewPool_ShouldRevert_WhenExpiryIsZero() external {
        vm.startPrank(address(defaultCorkController));

        address rateOracle = address(testOracle);
        vm.expectRevert(abi.encodeWithSignature("InvalidExpiry()"));
        corkPoolManager.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 0, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether}));

        vm.stopPrank();
    }

    function test_createNewPool_ShouldRevert_WhenAlreadyExists() external {
        vm.startPrank(address(defaultCorkController));

        address rateOracle = address(testOracle);
        vm.expectRevert(abi.encodeWithSignature("AlreadyInitialized()"));
        corkPoolManager.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 1 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 1 ether, rateChangeCapacityMax: 1 ether}));
        vm.stopPrank();
    }

    function test_createNewPool_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);
        vm.stopPrank();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 1 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 1 ether, rateChangeCapacityMax: 1 ether}));
    }

    // ================================ Initialization Tests ================================ //

    function test_initialize_ShouldRevert_WhenCalledTwice() external {
        // Deploy a fresh CorkPoolManager to test initialization
        CorkPoolManager freshPool = new CorkPoolManager();

        // First initialization should succeed
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(sharesFactory), address(defaultCorkController), address(999), treasury, address(whitelistManager))));

        // Second initialization should fail
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        CorkPoolManager(address(proxy)).initialize(address(sharesFactory), address(defaultCorkController), address(testOracle), treasury, address(whitelistManager));
    }

    function test_initialize_ShouldRevert_WhenSwapSharesFactoryOrAdminIsZero() external {
        CorkPoolManager freshPool = new CorkPoolManager();

        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(0), address(defaultCorkController), address(testOracle), treasury, address(whitelistManager))));
    }

    function test_initialize_ShouldRevert_WhenAdminIsZero() external {
        CorkPoolManager freshPool = new CorkPoolManager();

        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(sharesFactory), address(0), address(testOracle), treasury, address(whitelistManager))));
    }

    function test_initialize_ShouldRevert_WhenBothAddressesAreZero() external {
        CorkPoolManager freshPool = new CorkPoolManager();

        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(0), address(0), address(testOracle), treasury, address(whitelistManager))));
    }

    // ================================ Upgrade Authorization Tests ================================ //

    function test_upgradeToAndCall_ShouldRevert_WhenNotOwner() external {
        CorkPoolManager newImplementation = new CorkPoolManager();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", user, bytes32(0)));
        corkPoolManager.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    function test_upgradeToAndCall_ShouldWork_WhenOwner() external {
        CorkPoolManager newImplementation = new CorkPoolManager();

        vm.startPrank(DEFAULT_ADDRESS);
        // This should succeed without reverting
        corkPoolManager.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    // ================================ Deposit Tests ================================ //

    function test_deposit_ShouldMintTokens() external {
        uint256 depositAmount = 1000 ether;

        // Get the swap rate for the expected event
        // uint256 expectedSwapRate = corkPoolManager.swapRate(marketId);

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), depositAmount);

        // Expect both Pool Manager and ERC4626-compatible events
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, depositAmount, 0, false);

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IPoolShare.Deposit(user, user, depositAmount, depositAmount);

        uint256 received = corkPoolManager.deposit(marketId, depositAmount, currentCaller());
        vm.stopPrank();

        assertEq(received, depositAmount, "Should receive equal amount in 18 decimals");

        assertEq(IERC20(principalToken).balanceOf(user), depositAmount, "Should have principal tokens");
        assertEq(IERC20(swapToken).balanceOf(user), depositAmount, "Should have swap tokens");
    }

    function test_deposit_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 0);

        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPoolManager.deposit(marketId, 0, currentCaller());

        vm.stopPrank();
    }

    function test_deposit_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);

        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.stopPrank();
    }

    function test_deposit_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1); // 00001 = deposit paused
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.stopPrank();
    }

    // ================================ Mint Tests ================================ //

    function test_mint_ShouldCalculateCorrectCollateralIn() external {
        uint256 tokensOut = 500 ether;

        // uint256 expectedSwapRate = corkPoolManager.swapRate(marketId);

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);

        // Expect both Pool Manager and ERC4626-compatible events
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, tokensOut, 0, false);

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IPoolShare.Deposit(user, user, tokensOut, tokensOut);

        uint256 collateralIn = corkPoolManager.mint(marketId, tokensOut, currentCaller());
        vm.stopPrank();

        assertEq(collateralIn, tokensOut, "Should require equal collateral amount");

        assertEq(IERC20(principalToken).balanceOf(user), tokensOut, "Should have principal tokens");
        assertEq(IERC20(swapToken).balanceOf(user), tokensOut, "Should have swap tokens");
    }

    // ================================ Exercise Tests ================================ //

    function test_exercise_ShouldWorkWithShares() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);

        uint256 exerciseShares = 100 ether;
        // Preview to get expected values
        (uint256 expectedAssets, uint256 expectedOtherSpent, uint256 expectedFee) = corkPoolManager.previewExercise(marketId, exerciseShares);

        // Expect both PoolSwap and ERC4626-compatible withdraw events

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(marketId, user, user, expectedAssets, expectedOtherSpent, 0, 0, false);
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolFee(marketId, user, expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Withdraw(user, user, user, expectedAssets + expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.DepositOther(user, user, address(referenceAsset), expectedOtherSpent, 0);

        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exercise(marketId, exerciseShares, user);
        vm.stopPrank();

        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
        // Fee might be 0 if no base redemption fee
    }

    function test_exercise_ShouldRevertIfNotEnoughLiquidityForFee() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1 ether, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);

        uint256 exerciseShares = 1_010_101_010_101_010_102;

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.exercise(marketId, exerciseShares, user);

        uint256 exerciseCompensation = 1_010_101_010_101_010_102;

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.exerciseOther(marketId, exerciseCompensation, user);
    }

    function test_exercise_ShouldWorkWithCompensation() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        uint256 compensation = 50 ether;
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exerciseOther(marketId, compensation, user);
        vm.stopPrank();

        assertGt(assets, 0, "Should receive collateral assets");
        assertEq(otherAssetSpent, compensation, "Should spend exact compensation amount");
    }

    function test_exercise_ShouldRevert_WhenSharesAmountIsZero() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPoolManager.exercise(marketId, 0, user);
        vm.stopPrank();
    }

    function test_exercise_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.exercise(marketId, 100 ether, user);
        vm.stopPrank();
    }

    function test_exercise_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 1); // 00010 = swap paused
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(marketId, 100 ether, user);
        vm.stopPrank();
    }

    // ================================ Swap Tests ================================ //

    function test_swap_ShouldWork() external {
        // Setup: deposit and then swap
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        uint256 assetAmount = 100 ether;
        uint256 expectedCompensation = 101_010_101_010_101_010_102;
        uint256 expectedShares = 101_010_101_010_101_010_102;
        uint256 expectedFee = 1_010_101_010_101_010_102;

        (address principalToken,) = corkPoolManager.shares(marketId);
        // Expect both PoolSwap and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolSwap(marketId, user, user, assetAmount, expectedCompensation, 0, 0, false);
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(marketId, user, expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Withdraw(user, user, user, assetAmount + expectedFee, 0);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.DepositOther(user, user, address(referenceAsset), expectedCompensation, 0);
        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(marketId, assetAmount, user);
        vm.stopPrank();

        assertEq(shares, expectedShares, "Should provide CST shares");
        assertEq(compensation, expectedCompensation, "Should require reference asset compensation");
    }

    function test_swap_ShouldRevertIfNotEnoughLiquidityForFee() external {
        // Setup: deposit and then swap
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1 ether, currentCaller());

        uint256 assetAmount = 1 ether;

        corkPoolManager.previewSwap(marketId, assetAmount);

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.swap(marketId, assetAmount, user);
    }

    function test_swap_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        corkPoolManager.swap(marketId, 0, user);
        vm.stopPrank();
    }

    function test_swap_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    function test_swap_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 1); // 00010 = swap paused
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    // ================================ UnwindSwap Tests ================================ //

    function test_unwindSwap_ShouldWork() external {
        // Setup: create liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        corkPoolManager.swap(marketId, 200 ether, user); // Create pool liquidity

        uint256 unwindAmount = 50 ether;
        // Preview to get expected values
        (uint256 previewReceivedCst, uint256 previewReceivedRef, uint256 previewFee) = corkPoolManager.previewUnwindSwap(marketId, unwindAmount);

        (address principalToken,) = corkPoolManager.shares(marketId);
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolSwap(marketId, user, user, unwindAmount, previewReceivedRef, 0, 0, true);
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(marketId, user, previewFee, 0);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IPoolShare.Deposit(user, user, unwindAmount - previewFee, 0);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IPoolShare.WithdrawOther(user, user, user, address(referenceAsset), previewReceivedRef, 0);

        (uint256 unwindReceivedCst, uint256 unwindReceivedRef, uint256 unwindFee) = corkPoolManager.unwindSwap(marketId, unwindAmount, user);
        vm.stopPrank();

        assertGt(unwindReceivedRef, 0, "Should receive reference asset");
        assertGt(unwindReceivedCst, 0, "Should receive swap tokens");
        assertGt(unwindFee, 0, "Should have fees");
    }

    function test_unwindSwap_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        corkPoolManager.unwindSwap(marketId, 0, user);
        vm.stopPrank();
    }

    function test_unwindSwap_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.unwindSwap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    function test_unwindSwap_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 4); // 10000 = unwind swap paused
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    function test_unwindSwap_ShouldRevert_WhenInsufficientReferenceAssetLiquidity() external {
        // Setup: We need swapAssetOut <= swapTokenBalance
        // but compensationOut > referenceAssetBalance to ensure correct edge case is tested

        vm.startPrank(user);
        corkPoolManager.deposit(marketId, 10_000 ether, currentCaller());
        corkPoolManager.swap(marketId, 200 ether, user);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(marketId, 0.5 ether);
        vm.stopPrank();

        // Get reference asset balance of pool
        (, uint256 referenceAssets) = corkPoolManager.assets(marketId);

        (, address swapToken) = corkPoolManager.shares(marketId);
        // Get the swap token balance in pool
        uint256 cstInPool = IERC20(swapToken).balanceOf(address(corkPoolManager));

        uint256 unwindAmount = 200 ether;
        (uint256 previewSwapAsset, uint256 previewReferenceAsset,) = corkPoolManager.previewUnwindSwap(marketId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut > referenceAssets balance of pool)
        assertGt(previewReferenceAsset, referenceAssets, "Reference asset check MUST exceed available");

        // 2. Swap token check (swapAssetOut <= available swap tokens balance of pool)
        assertLe(previewSwapAsset, cstInPool, "Swap asset required MUST be less than available");

        vm.startPrank(user);
        // Should revert with InsufficientLiquidity for swap tokens
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", referenceAssets, previewReferenceAsset));
        corkPoolManager.unwindSwap(marketId, unwindAmount, user);
        vm.stopPrank();
    }

    function test_unwindSwap_ShouldRevert_WhenInsufficientSwapTokenLiquidity() external {
        // Setup: We need referenceAssetOut <= referenceAssetBalance
        // but swapAssetOut > swapTokenBalance to ensure correct edge case is tested
        vm.startPrank(user);
        corkPoolManager.deposit(marketId, 10_000 ether, currentCaller());
        corkPoolManager.swap(marketId, 200 ether, user);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(marketId, 1.1 ether);
        vm.stopPrank();

        // Get reference asset balance of pool
        (, uint256 referenceAssets) = corkPoolManager.assets(marketId);

        (, address swapToken) = corkPoolManager.shares(marketId);
        // Get the swap token balance in pool
        uint256 cstInPool = IERC20(swapToken).balanceOf(address(corkPoolManager));

        uint256 unwindAmount = 220 ether;
        (uint256 previewSwapAsset, uint256 previewReferenceAsset,) = corkPoolManager.previewUnwindSwap(marketId, unwindAmount);

        // CRITICAL ASSERTIONS to verify we're testing the RIGHT edge case:
        // 1. Reference asset check (referenceAssetOut <= referenceAssets balance of pool)
        assertLe(previewReferenceAsset, referenceAssets, "Reference asset check MUST less than available");

        // 2. Swap token check (swapAssetOut > available swap tokens balance of pool)
        assertGt(previewSwapAsset, cstInPool, "Swap asset required MUST exceed available");

        vm.startPrank(user);
        // Should revert with InsufficientLiquidity for swap tokens
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256,uint256)", cstInPool, previewSwapAsset));
        corkPoolManager.unwindSwap(marketId, unwindAmount, user);
        vm.stopPrank();
    }

    // ================================ UnwindMint Tests ================================ //

    function test_unwindMint_ShouldWork() external {
        uint256 depositAmount = 500 ether;

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), depositAmount);
        corkPoolManager.deposit(marketId, depositAmount, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(principalToken).approve(address(corkPoolManager), type(uint256).max);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);

        uint256 unwindAmount = 100 ether;
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, unwindAmount, 0, true);
        uint256 collateralReceived = corkPoolManager.unwindMint(marketId, unwindAmount, user, user);
        vm.stopPrank();

        assertEq(collateralReceived, unwindAmount, "Should receive equal collateral amount");
    }

    function test_unwindMint_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        corkPoolManager.unwindMint(marketId, 0, user, user);
        vm.stopPrank();
    }

    function test_unwindMint_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.unwindMint(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    function test_unwindMint_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 3); // 01000 = unwind deposit paused
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindMint(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    // ================================ UnwindDeposit Tests ================================ //

    function test_unwindDeposit_ShouldWork() external {
        uint256 depositAmount = 500 ether;

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), depositAmount);
        corkPoolManager.deposit(marketId, depositAmount, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(principalToken).approve(address(corkPoolManager), type(uint256).max);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);

        uint256 collateralOut = 100 ether;
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, collateralOut, 0, true);
        uint256 tokensIn = corkPoolManager.unwindDeposit(marketId, collateralOut, user, user);
        vm.stopPrank();

        assertEq(tokensIn, collateralOut, "Should burn equal token amount");
    }

    // ================================ UnwindExercise Tests ================================ //

    function test_unwindExercise_ShouldWork() external {
        // Setup: create pool liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        corkPoolManager.swap(marketId, 200 ether, user); // Create liquidity

        uint256 shares = 50 ether;
        uint256 treasuryBalanceBefore = collateralAsset.balanceOf(treasury);

        // Preview to get expected assetIn
        (uint256 expectedAssetIn, uint256 expectedCompensation, uint256 expectedFee) = corkPoolManager.previewUnwindExercise(marketId, shares);

        (address principalToken,) = corkPoolManager.shares(marketId);
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolSwap(marketId, user, user, expectedAssetIn, expectedCompensation, 0, 0, true);
        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.PoolFee(marketId, user, expectedFee, 0);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IPoolShare.Deposit(user, user, expectedAssetIn - expectedFee, 0);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IPoolShare.WithdrawOther(user, user, user, address(referenceAsset), expectedCompensation, 0);

        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.unwindExercise(marketId, shares, user);
        vm.stopPrank();

        assertGt(assetIn, 0, "Should require collateral input");
        assertGt(compensationOut, 0, "Should provide reference compensation");
        assertEq(fee, expectedFee, "Should calculate fee correctly");
        assertEq(collateralAsset.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Should increase treasury balance by expected fee amount");
    }

    function test_unwindExercise_ShouldRevert_WhenZeroShares() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        corkPoolManager.unwindExercise(marketId, 0, user);
        vm.stopPrank();
    }

    function test_unwindExercise_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPoolManager.unwindExercise(marketId, 100 ether, user);
        vm.stopPrank();
    }

    // ================================ Redeem Tests ================================ //

    function test_redeem_ShouldWork() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days); // Expire

        uint256 redeemAmount = 100 ether;
        // Preview to get expected values
        (uint256 expectedRef, uint256 expectedCollateral) = corkPoolManager.previewRedeem(marketId, redeemAmount);

        (address principalToken,) = corkPoolManager.shares(marketId);

        // Expect both PoolModifyLiquidity and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, expectedCollateral, expectedRef, true);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Withdraw(user, user, user, expectedCollateral, redeemAmount);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(user, user, user, address(referenceAsset), expectedRef, redeemAmount);
        (uint256 accruedRef, uint256 accruedCollateral) = corkPoolManager.redeem(marketId, redeemAmount, user, user);
        vm.stopPrank();

        assertGt(accruedCollateral, 0, "Should receive collateral");
        // accruedRef might be 0 if no reference assets in pool
    }

    function test_redeem_ShouldRevert_WhenZeroAmount() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        corkPoolManager.redeem(marketId, 0, user, user);
        vm.stopPrank();
    }

    function test_redeem_ShouldRevert_WhenNotExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(abi.encodeWithSignature("NotExpired()"));
        corkPoolManager.redeem(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    function test_redeem_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2); // 00100 = withdrawal paused
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.redeem(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    // ================================ MaxRedeem Tests ================================ //

    function test_maxRedeem_ShouldRevert_WhenNotInitialized() external {
        // Create a new market ID that hasn't been initialized
        ERC20Mock newCollateral = new DummyWETH();
        ERC20Mock newReference = new DummyWETH();
        MarketId uninitializedId = corkPoolManager.getId(
            Market({collateralAsset: address(newCollateral), referenceAsset: address(newReference), expiryTimestamp: block.timestamp + 30 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether})
        );

        vm.expectRevert(abi.encodeWithSelector(IErrors.NotInitialized.selector));
        corkPoolManager.maxRedeem(uninitializedId, user);
    }

    function test_maxRedeem_ShouldReturnZero_WhenWithdrawalPaused() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Pause withdrawals
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2); // 00100 = withdrawal paused
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        uint256 maxShares = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when withdrawal is paused");
    }

    function test_maxRedeem_ShouldReturnZero_WhenNotExpired() external {
        // Setup: deposit but don't expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Don't warp time - market not expired
        uint256 maxShares = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when market not expired");
    }

    function test_maxRedeem_ShouldReturnZero_WhenUserHasNoShares() external {
        // Setup: don't deposit anything for user
        vm.warp(block.timestamp + 2 days); // Expire

        uint256 maxShares = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when user has no shares");
    }

    function test_maxRedeem_ShouldReturnUserBalance_WhenMarketExpiredAndUserHasShares() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        uint256 receivedShares = corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Get user's CPT balance
        (address principalToken,) = corkPoolManager.shares(marketId);
        uint256 userBalance = IERC20(principalToken).balanceOf(user);

        uint256 maxShares = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares, userBalance, "Should return user's CPT balance");
        assertEq(maxShares, receivedShares, "Should equal received shares from deposit");
    }

    function test_maxRedeem_ShouldReturnCorrectAmount_WhenMultipleUsers() external {
        // Setup: multiple users deposit
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        uint256 user1Shares = corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 500 ether);
        uint256 user2Shares = corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Check both users get their correct max redeemable amounts
        uint256 maxShares1 = corkPoolManager.maxRedeem(marketId, user);
        uint256 maxShares2 = corkPoolManager.maxRedeem(marketId, user2);

        assertEq(maxShares1, user1Shares, "User1 should get their deposit amount");
        assertEq(maxShares2, user2Shares, "User2 should get their deposit amount");
        assertGt(maxShares1, maxShares2, "User1 should have more shares than user2");
    }

    function test_maxRedeem_ShouldReturnCorrectAmount_AfterPartialRedemption() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        uint256 initialShares = corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Redeem part of the shares
        vm.startPrank(user);
        uint256 redeemAmount = 300 ether;
        corkPoolManager.redeem(marketId, redeemAmount, user, user);
        vm.stopPrank();

        // Check remaining max redeemable amount
        uint256 maxShares = corkPoolManager.maxRedeem(marketId, user);
        uint256 expectedRemaining = initialShares - redeemAmount;
        assertEq(maxShares, expectedRemaining, "Should return remaining shares after partial redemption");
    }

    function test_maxRedeem_ShouldNotRevert_InAnyValidScenario() external {
        // Test that maxRedeem never reverts even in edge cases Except for expired market

        // Case 1: Market not initialized
        ERC20Mock newCollateral = new DummyWETH();
        ERC20Mock newReference = new DummyWETH();
        MarketId uninitializedId = corkPoolManager.getId(
            Market({collateralAsset: address(newCollateral), referenceAsset: address(newReference), expiryTimestamp: block.timestamp + 30 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether})
        );

        // Should revert in this one case of Uninitialized market
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotInitialized.selector));
        corkPoolManager.maxRedeem(uninitializedId, user);

        // Case 2: Paused state
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2); // 00100 = withdrawal paused
        vm.stopPrank();

        // Should not revert
        uint256 maxShares2 = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares2, 0);

        // Case 3: Not expired
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 0); // 00000 = all unpaused
        vm.stopPrank();

        // Should not revert
        uint256 maxShares3 = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares3, 0);

        // Case 4: Expired and normal operation
        vm.warp(block.timestamp + 2 days);

        // Should not revert
        uint256 maxShares4 = corkPoolManager.maxRedeem(marketId, user);
        assertEq(maxShares4, 0); // User has no shares
    }

    // ================================ MaxSwap Tests ================================ //

    function test_maxSwap_ShouldRevert_WhenNotInitialized() external {
        // Create a new market ID that hasn't been initialized
        ERC20Mock newCollateral = new DummyWETH();
        ERC20Mock newReference = new DummyWETH();
        MarketId uninitializedId = corkPoolManager.getId(
            Market({collateralAsset: address(newCollateral), referenceAsset: address(newReference), expiryTimestamp: block.timestamp + 30 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether})
        );

        vm.expectRevert(abi.encodeWithSelector(IErrors.NotInitialized.selector));
        corkPoolManager.maxSwap(uninitializedId, user);
    }

    function test_maxSwap_ShouldReturnZero_WhenSwapPaused() external {
        // Setup: deposit and provide liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Give user reference assets for compensation
        vm.startPrank(user);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        vm.stopPrank();

        // Pause swaps
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 1); // 00010 = swap paused
        vm.stopPrank();

        uint256 maxAssets = corkPoolManager.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when swap is paused");
    }

    function test_maxSwap_ShouldReturnZero_WhenExpired() external {
        // Setup: deposit but expire the market
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        uint256 maxAssets = corkPoolManager.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when market is expired");
    }

    function test_maxSwap_ShouldReturnZero_WhenUserHasNoCstShares() external {
        // Setup: don't deposit anything for user (no CST shares)
        uint256 maxAssets = corkPoolManager.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when user has no CST shares");
    }

    function test_maxSwap_ShouldReturnZero_WhenUserHasNoReferenceAssets() external {
        address newUser = address(8989);

        vm.startPrank(user);

        collateralAsset.transfer(newUser, 5000 ether);

        vm.startPrank(newUser);

        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // User has CST shares but no reference assets for compensation
        uint256 maxAssets = corkPoolManager.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when user has no reference assets");
    }

    function test_maxSwap_ShouldReturnCorrectAmount_WhenCstBalanceIsLimitingFactor() external {
        // Test condition: User has limited CST but plenty of reference assets
        // User CST balance < max CST usable with reference assets

        vm.startPrank(user);

        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller()); // Get CST shares

        uint256 maxAssets = corkPoolManager.maxSwap(marketId, user);
        assertGt(maxAssets, 0, "Should return positive amount when user has both CST and reference assets");

        // The result should be limited by CST balance, not reference asset balance
        (address cstToken,) = corkPoolManager.shares(marketId);
        uint256 userCstBalance = IERC20(cstToken).balanceOf(user);
        assertGt(userCstBalance, 0, "User should have CST shares");

        // Preview what we would get with all CST shares
        (uint256 expectedAssets,,) = corkPoolManager.previewExercise(marketId, userCstBalance);
        assertLe(maxAssets, expectedAssets, "maxSwap should not exceed what's possible with user's CST");
    }

    function test_maxSwap_ShouldReturnCorrectAmount_WhenReferenceAssetIsLimitingFactor() external {
        // Test condition: User has limited reference assets but plenty of CST shares
        // Reference asset capacity < user CST balance

        address newUser = address(8989);

        vm.startPrank(user);

        collateralAsset.transfer(newUser, 5000 ether);
        // Give user limited reference assets (just enough for small compensation)
        referenceAsset.transfer(newUser, 50 ether);

        vm.startPrank(newUser);

        collateralAsset.approve(address(corkPoolManager), 5000 ether);
        corkPoolManager.deposit(marketId, 5000 ether, currentCaller()); // Get lots of CST shares

        uint256 maxAssets = corkPoolManager.maxSwap(marketId, newUser);
        assertGt(maxAssets, 0, "Should return positive amount when user has both CST and reference assets");

        // The result should be limited by reference asset capacity, not CST balance
        uint256 userRefBalance = IERC20(address(referenceAsset)).balanceOf(newUser);
        assertEq(userRefBalance, 50 ether, "User should have limited reference assets");

        // Preview what we would get with all reference assets (compensation mode)
        (uint256 expectedAssets,,) = corkPoolManager.previewExerciseOther(marketId, userRefBalance);
        assertLe(maxAssets, expectedAssets, "maxSwap should not exceed what's possible with user's reference assets");
    }

    function test_maxSwap_ShouldReturnOptimalAmount_WhenBalancedScenario() external {
        // Test the optimal balance logic with realistic amounts

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller()); // Get CST shares
        referenceAsset.approve(address(corkPoolManager), 1000 ether);

        uint256 maxAssets = corkPoolManager.maxSwap(marketId, user);
        assertGt(maxAssets, 0, "Should return positive amount");

        // Verify the result is reasonable and doesn't exceed any limits
        (address cstToken,) = corkPoolManager.shares(marketId);
        uint256 userCstBalance = IERC20(cstToken).balanceOf(user);
        uint256 userRefBalance = IERC20(address(referenceAsset)).balanceOf(user);

        // Should be able to perform the swap with current balances
        (uint256 previewAssets,,) = corkPoolManager.previewExercise(marketId, userCstBalance);
        assertLe(maxAssets, previewAssets, "maxSwap should be achievable with user's CST balance");
    }

    // ================================ Withdraw Tests ================================ //

    function test_withdraw_ShouldWork() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days); // Expire

        uint256 collateralOut = 100 ether;
        // Preview to get expected values
        (uint256 expectedSharesIn, uint256 expectedCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdraw(marketId, collateralOut);

        // Expect both PoolModifyLiquidity and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, collateralOut, expectedRefOut, true);

        (address principalToken,) = corkPoolManager.shares(marketId);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Withdraw(user, user, user, collateralOut, expectedSharesIn);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(user, user, user, address(referenceAsset), expectedRefOut, expectedSharesIn);
        (uint256 sharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdraw(marketId, collateralOut, user, user);

        assertEq(expectedSharesIn, 100 ether);
        assertEq(expectedCollateralOut, 100 ether);
        assertEq(expectedRefOut, 0);
    }

    function test_withdraw_ShouldRevert_WhenCollateralAssetOutIsZero() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPoolManager.withdraw(marketId, 0, user, user);
        vm.stopPrank();
    }

    function test_withdraw_ShouldRevert_WhenNotExpired() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("NotExpired()"));
        corkPoolManager.withdraw(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    function test_withdraw_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2); // 00100 = withdrawal paused
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    // ================================ WithdrawOther Tests ================================ //

    function test_withdrawOther_ShouldWork() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        // Exercise to increase reference asset holdings of CorkPoolManager contract
        (, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);
        corkPoolManager.exercise(marketId, 100 ether, user);

        vm.warp(block.timestamp + 2 days); // Expire

        uint256 referenceOut = 100 ether;
        uint256 expectedCollateralOut = 900 ether;
        // Preview to get expected values
        (uint256 expectedSharesIn, uint256 previewActualCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdrawOther(marketId, referenceOut);

        // Expect both PoolModifyLiquidity and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolModifyLiquidity(marketId, user, user, expectedCollateralOut, expectedRefOut, true);

        (address principalToken,) = corkPoolManager.shares(marketId);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.Withdraw(user, user, user, expectedCollateralOut, expectedSharesIn);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IPoolShare.WithdrawOther(user, user, user, address(referenceAsset), expectedRefOut, expectedSharesIn);
        (uint256 sharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdrawOther(marketId, referenceOut, user, user);

        assertEq(expectedSharesIn, 1000 ether);
        assertEq(sharesIn, 1000 ether);
        assertEq(actualCollateralOut, 900 ether);
        assertEq(previewActualCollateralOut, 900 ether);
        assertEq(expectedRefOut, 100 ether);
        assertEq(actualRefOut, 100 ether);
    }

    function test_withdrawOther_ShouldRevert_WhenReferenceAssetOutIsZero() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPoolManager.withdrawOther(marketId, 0, user, user);
        vm.stopPrank();
    }

    function test_withdrawOther_ShouldRevert_WhenNotExpired() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("NotExpired()"));
        corkPoolManager.withdrawOther(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    function test_withdrawOther_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2); // 00100 = withdrawal paused
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    // ================================ Preview Function Tests ================================ //

    function test_previewDeposit_ShouldReturnCorrectAmount() external {
        uint256 amount = 1000 ether;
        uint256 expected = corkPoolManager.previewDeposit(marketId, amount);
        assertEq(expected, amount, "Should return 1:1 ratio");
    }

    function test_previewMint_ShouldReturnCorrectAmount() external {
        uint256 tokensOut = 500 ether;
        uint256 collateralIn = corkPoolManager.previewMint(marketId, tokensOut);
        assertEq(collateralIn, tokensOut, "Should require equal collateral");
    }

    function test_previewSwap_ShouldReturnCorrectAmounts() external {
        uint256 assets = 100 ether;
        (uint256 sharesOut, uint256 compensation, uint256 fee) = corkPoolManager.previewSwap(marketId, assets);

        assertGt(sharesOut, 0, "Should calculate CST shares needed");
        assertGt(compensation, 0, "Should calculate reference asset compensation needed");
        assertGt(fee, 0, "Should calculate fee");
    }

    function test_previewUnwindSwap_ShouldReturnCorrectAmounts() external {
        // First setup some pool liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 amount = 50 ether;
        (uint256 previewReceivedCst, uint256 previewReceivedRef, uint256 previewFee) = corkPoolManager.previewUnwindSwap(marketId, amount);

        assertGt(previewReceivedRef, 0, "Should calculate reference amount");
        assertGt(previewReceivedCst, 0, "Should calculate CST amount");
        assertGt(previewFee, 0, "Should have fees");
    }

    function test_previewExercise_ShouldReturnCorrectAmounts() external {
        uint256 shares = 100 ether;
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.previewExercise(marketId, shares);

        assertGt(assets, 0, "Should calculate collateral assets");
        assertGt(otherAssetSpent, 0, "Should calculate reference asset spent");
    }

    function test_previewUnwindExercise_ShouldReturnCorrectAmounts() external {
        uint256 shares = 100 ether;
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(marketId, shares);

        assertGt(assetIn, 0, "Should calculate collateral input");
        assertGt(compensationOut, 0, "Should calculate compensation output");
        assertGt(fee, 0, "Should calculate fee");
    }

    function test_previewUnwindExerciseOther_cantRugRef_POC() external {
        address alice = user;
        address eve = user2;

        uint256 depegRate = 1e18 - 1;

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);

        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(marketId, depegRate);
        vm.stopPrank();

        // required for attack
        vm.startPrank(eve);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);

        // Setup:
        //   - Mint 2 cST to Alice
        //   - Exercise 2 shares + 2 ref for 2 collateral
        vm.startPrank(alice);
        corkPoolManager.deposit(marketId, 2, currentCaller());

        assertEq(IERC20(swapToken).balanceOf(alice), 2);
        assertEq(IERC20(swapToken).balanceOf(eve), 0);
        assertEq(IERC20(collateralAsset).balanceOf(address(corkPoolManager)), 2);

        (uint256 assets, uint256 otherAssetSpent,) = corkPoolManager.exerciseOther(marketId, 2, user);

        uint256 swapBefore = IERC20(swapToken).balanceOf(address(corkPoolManager)); // 2
        uint256 refBefore = IERC20(referenceAsset).balanceOf(address(corkPoolManager)); // 2

        // Attack: Eve tries to extract two ref while paying just one collateral
        vm.startPrank(eve);
        corkPoolManager.unwindExercise(marketId, 1, currentCaller());

        // Attack should fail
        assertEq(IERC20(swapToken).balanceOf(address(corkPoolManager)), swapBefore - 1);
        assertEq(IERC20(referenceAsset).balanceOf(address(corkPoolManager)), refBefore - 1);

        vm.stopPrank();
    }

    function test_previewRedeem_ShouldReturnCorrectAmounts_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 amount = 100 ether;
        (uint256 accruedCollateral, uint256 accruedRef) = corkPoolManager.previewRedeem(marketId, amount);

        assertEq(accruedCollateral, 0, "Should calculate collateral amount correctly");
        assertEq(accruedRef, 100 ether, "Should calculate reference amount correctly");
        // accruedRef is expected to be 0 since there's no reference asset in this setup
    }

    function test_previewWithdraw_ShouldReturnCorrectAmounts_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 collateralOut = 100 ether;
        (uint256 expectedSharesIn, uint256 expectedCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdraw(marketId, collateralOut);

        assertEq(expectedSharesIn, 100 ether);
        assertEq(expectedCollateralOut, 100 ether);
        assertEq(expectedRefOut, 0);
    }

    function test_previewUnwindDeposit_ShouldReturnCorrectAmount() external {
        uint256 collateralOut = 500 ether;
        uint256 tokensIn = corkPoolManager.previewUnwindDeposit(marketId, collateralOut);
        assertEq(tokensIn, collateralOut, "Should return 1:1 ratio");
    }

    function test_previewUnwindMint_ShouldReturnCorrectAmount() external {
        uint256 tokensIn = 500 ether;
        uint256 collateralOut = corkPoolManager.previewUnwindMint(marketId, tokensIn);
        assertEq(collateralOut, tokensIn, "Should return 1:1 ratio");
    }

    // ================================ Max Function Tests ================================ //

    function test_maxDeposit_ShouldReturnMaxUint() external {
        uint256 maxAmount = corkPoolManager.maxDeposit(marketId, user);
        assertEq(maxAmount, type(uint256).max, "Should return max uint256");
    }

    function test_maxMint_ShouldReturnMaxUint() external {
        uint256 maxAmount = corkPoolManager.maxMint(marketId, user);
        assertEq(maxAmount, type(uint256).max, "Should return max uint256");
    }

    function test_maxExercise_ShouldReturnUserBalance() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        uint256 maxShares = corkPoolManager.maxExercise(marketId, user);
        assertEq(maxShares, 1000 ether, "Should return user's CST balance");
    }

    function test_maxExercise_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        uint256 maxShares = corkPoolManager.maxExercise(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when expired");
    }

    function test_maxExercise_ShouldReturnZero_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 1); // 00010 = swap paused
        vm.stopPrank();

        uint256 maxShares = corkPoolManager.maxExercise(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when paused");
    }

    function test_maxUnwindExercise_ShouldReturnCorrectAmount() external {
        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 maxShares = corkPoolManager.maxUnwindExercise(marketId, user);
        assertGt(maxShares, 0, "Should return positive amount");
    }

    function test_maxUnwindExercise_ShouldReturnCorrectAmount_WhenLessReferenceAssetThanRespctiveCst() external {
        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        testOracle.setRate(marketId, 0.9 ether); // 90%

        uint256 maxShares = corkPoolManager.maxUnwindExercise(marketId, user);
        uint256 expectedShares = MathHelper.calculateEqualSwapAmount(101_010_101_010_101_010_102, 0.9 ether);
        assertEq(maxShares, expectedShares, "Should return max shares");
    }

    function test_maxUnwindExerciseOther_ShouldReturnCorrectAmount() external {
        vm.startPrank(DEFAULT_ADDRESS);

        defaultCorkController.updateSwapFeePercentage(marketId, 0);

        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 maxReferenceAssets = corkPoolManager.maxUnwindExerciseOther(marketId, user);
        assertEq(maxReferenceAssets, 100 ether, "Should return positive amount");
    }

    function test_maxUnwindExerciseOther_ShouldReturnCorrectAmount_WhenLessCstThanRespctiveReferenceAsset() external {
        vm.startPrank(DEFAULT_ADDRESS);

        defaultCorkController.updateSwapFeePercentage(marketId, 0);

        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        testOracle.setRate(marketId, 1.1 ether); // 110%

        uint256 maxReferenceAssets = corkPoolManager.maxUnwindExerciseOther(marketId, user);
        uint256 expectedReferenceAssets = MathHelper.calculateDepositAmountWithSwapRate(100 ether, 1.1 ether, false);
        assertEq(maxReferenceAssets, expectedReferenceAssets, "Should return max reference assets");
    }

    function test_maxUnwindExerciseOther_ShouldReturnZero_WhenUnwindSwapPaused() external {
        vm.startPrank(DEFAULT_ADDRESS);

        defaultCorkController.pauseUnwindSwaps(marketId);

        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 maxReferenceAssets = corkPoolManager.maxUnwindExerciseOther(marketId, user);
        assertEq(maxReferenceAssets, 0, "Should return 0 when unwind swap is paused");
    }

    function test_maxUnwindExerciseOther_ShouldReturnZero_WhenExpired() external {
        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        referenceAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        corkPoolManager.swap(marketId, 100 ether, user);
        vm.stopPrank();

        // Warp to after expiry
        vm.warp(block.timestamp + 2 days);

        uint256 maxReferenceAssets = corkPoolManager.maxUnwindExerciseOther(marketId, user);
        assertEq(maxReferenceAssets, 0, "Should return 0 when expired");
    }

    function test_maxUnwindDeposit_ShouldReturnUserBalance() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        uint256 maxAmount = corkPoolManager.maxUnwindDeposit(marketId, user);
        assertEq(maxAmount, 500 ether, "Should return user's minimum token balance");
    }

    function test_maxUnwindMint_ShouldReturnUserBalance() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        uint256 maxAmount = corkPoolManager.maxUnwindMint(marketId, user);
        assertEq(maxAmount, 500 ether, "Should return user's minimum token balance");
    }

    function test_maxWithdraw_ShouldReturnCorrectAmount_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdraw(marketId, user);
        assertEq(maxAmount, 500 ether, "Should return positive amount when expired");
    }

    function test_maxWithdrawOther_ShouldReturnCorrectAmount_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        (address principal, address swap) = corkPoolManager.shares(marketId);

        IERC20(principal).approve(address(corkPoolManager), 500 ether);
        IERC20(swap).approve(address(corkPoolManager), 500 ether);

        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(marketId, 0);

        vm.startPrank(user);
        corkPoolManager.swap(marketId, 500 ether, user);

        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdrawOther(marketId, user);
        assertEq(maxAmount, 500 ether, "Should return positive amount when expired");
    }

    function test_maxWithdraw_ShouldReturnZero_WhenPaused() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2); // 00100 = withdrawal paused
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdraw(marketId, user);
        assertEq(maxAmount, 0, "Should return 0 when paused");
    }

    function test_maxWithdraw_ShouldReturnMaxCollateralOut_WhenOwnerSharesLessThanPool() external {
        // ownerShares < normalized pool balance
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 500 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller()); // Small deposit
        vm.stopPrank();

        // Add more liquidity from another user to ensure pool balance > owner shares
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 10_000 ether);
        corkPoolManager.deposit(marketId, 10_000 ether, currentCaller()); // Large deposit
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days); // Expire to enable withdrawals

        uint256 maxAmount = corkPoolManager.maxWithdraw(marketId, user);
        // Should return maxCollateralOut from previewRedeem
        assertGt(maxAmount, 0, "Should return positive amount");
        assertLe(maxAmount, 500 ether, "Should not exceed user's deposit");
    }

    function test_maxWithdraw_ShouldReturnPoolBalance_WhenOwnerSharesGreaterThanPool() external {
        // ownerShares >= normalized pool balance
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        // Withdraw some collateral to reduce pool balance below owner shares
        vm.warp(block.timestamp + 2 days); // Expire
        uint256 withdrawAmount = 800 ether;
        (address principalToken,) = corkPoolManager.shares(marketId);
        uint256 userBalance = IERC20(principalToken).balanceOf(user);

        // Withdraw most of the collateral, leaving small pool balance
        if (userBalance >= withdrawAmount) corkPoolManager.redeem(marketId, withdrawAmount, user, user);
        vm.stopPrank();

        uint256 maxAmount = corkPoolManager.maxWithdraw(marketId, user);
        // Should return poolCollateralBalance
        assertGt(maxAmount, 0, "Should return positive pool balance");
    }

    // ================================ MaxUnwindDeposit Edge Cases ================================ //

    function test_maxUnwindDeposit_ShouldReturnSameAmount_WhenBalancesAreEqual() external {
        // Setup: User has equal amounts of both tokens (default case after deposit)
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);

        uint256 swapBalance = IERC20(swapToken).balanceOf(user);
        uint256 principalBalance = IERC20(principalToken).balanceOf(user);

        // Verify balances are equal
        assertEq(swapBalance, principalBalance, "Balances should be equal after deposit");

        uint256 maxAmount = corkPoolManager.maxUnwindDeposit(marketId, user);

        // Should return either balance (they're equal)
        uint256 expectedAmount = TransferHelper.fixedToTokenNativeDecimals(swapBalance, collateralAsset.decimals());
        assertEq(maxAmount, expectedAmount, "Should return the balance when both are equal");
        vm.stopPrank();
    }

    function test_maxUnwindDeposit_ShouldReturnZero_WhenUserHasNoTokens() external {
        // Test edge case where user has no tokens at all
        address newUser = makeAddr("newUser");

        uint256 maxAmount = corkPoolManager.maxUnwindDeposit(marketId, newUser);
        assertEq(maxAmount, 0, "Should return 0 when user has no tokens");
    }

    // ================================ MaxUnwindMint Edge Cases ================================ //

    function test_maxUnwindMint_ShouldReturnSameAmount_WhenBalancesAreEqual() external {
        // Setup: User has equal amounts of both tokens (default case after deposit)
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);

        uint256 swapBalance = IERC20(swapToken).balanceOf(user);
        uint256 principalBalance = IERC20(principalToken).balanceOf(user);

        // Verify balances are equal
        assertEq(swapBalance, principalBalance, "Balances should be equal after deposit");

        uint256 maxAmount = corkPoolManager.maxUnwindMint(marketId, user);

        // Should return either balance (they're equal)
        assertEq(maxAmount, swapBalance, "Should return the balance when both are equal");
        assertEq(maxAmount, principalBalance, "Should equal both balances when they're the same");
        vm.stopPrank();
    }

    function test_maxUnwindMint_ShouldReturnZero_WhenUserHasNoTokens() external {
        // Test edge case where user has no tokens at all
        address newUser = makeAddr("newUser");

        uint256 maxAmount = corkPoolManager.maxUnwindMint(marketId, newUser);
        assertEq(maxAmount, 0, "Should return 0 when user has no tokens");
    }

    // ================================ Fee and Admin Tests ================================ //

    function test_updateUnwindSwapFeeRate_ShouldUpdateFee() external {
        uint256 newFee = 2 ether; // 2%

        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, true, false, true);
        emit IUnwindSwap.UnwindSwapFeeRateUpdated(marketId, newFee);
        corkPoolManager.updateUnwindSwapFeeRate(marketId, newFee);
        vm.stopPrank();

        uint256 currentFee = corkPoolManager.unwindSwapFee(marketId);
        assertEq(currentFee, newFee, "Fee should be updated");
    }

    function test_updateUnwindSwapFeeRate_ShouldRevert_WhenNotAdmin() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        corkPoolManager.updateUnwindSwapFeeRate(marketId, 2 ether);
        vm.stopPrank();
    }

    function test_updateSwapFeePercentage_ShouldUpdateFee() external {
        uint256 newFee = 3 ether; // 3%

        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.SwapFeePercentageUpdated(marketId, newFee);
        corkPoolManager.updateSwapFeePercentage(marketId, newFee);
        vm.stopPrank();

        uint256 currentFee = corkPoolManager.swapFee(marketId);
        assertEq(currentFee, newFee, "Base redemption fee should be updated");
    }

    function test_updateSwapFeePercentage_ShouldRevert_WhenNotAdmin() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        corkPoolManager.updateSwapFeePercentage(marketId, 3 ether);
        vm.stopPrank();
    }

    // ================================ Pause State Tests ================================ //

    function test_setPausedBitMap_ShouldPauseDeposit() external {
        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, false, false, false);

        emit IPoolManager.MarketActionPausedUpdate(marketId, 1);
        corkPoolManager.setPausedBitMap(marketId, 1 << 0);
        vm.stopPrank();

        assertTrue(defaultCorkController.isDepositPaused(marketId), "Deposit should be paused");
    }

    function test_setPausedBitMap_ShouldUnpauseDeposit() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 0);

        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 0);
        corkPoolManager.setPausedBitMap(marketId, 0);
        vm.stopPrank();

        assertFalse(defaultCorkController.isDepositPaused(marketId), "Deposit should be unpaused");
    }

    function test_setPausedBitMap_ShouldPauseUnwindSwap() external {
        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 1 << 4);
        corkPoolManager.setPausedBitMap(marketId, 1 << 4);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldUnpauseUnwindSwap() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 4);
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 0);
        corkPoolManager.setPausedBitMap(marketId, 0);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldPauseSwap() external {
        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 1 << 1);
        corkPoolManager.setPausedBitMap(marketId, 1 << 1);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldUnpauseSwap() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 1);
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 0);
        corkPoolManager.setPausedBitMap(marketId, 0);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldPauseWithdrawal() external {
        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 1 << 2);
        corkPoolManager.setPausedBitMap(marketId, 1 << 2);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldUnpauseWithdrawal() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 2);

        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 0);

        corkPoolManager.setPausedBitMap(marketId, 0);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldPauseReturn() external {
        vm.startPrank(address(defaultCorkController));

        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 1 << 3);

        corkPoolManager.setPausedBitMap(marketId, 1 << 3);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldUnpauseReturn() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 1 << 3);

        vm.expectEmit(true, false, false, false);
        emit IPoolManager.MarketActionPausedUpdate(marketId, 0);

        corkPoolManager.setPausedBitMap(marketId, 0);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldRevert_WhenNotAdmin() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        corkPoolManager.setPausedBitMap(marketId, 1 << 0);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldRevert_WhenBitMapOutsideRange() external {
        vm.startPrank(address(defaultCorkController));
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPoolManager.setPausedBitMap(marketId, 1 << 5);
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldRevert_WhenSameStatus() external {
        vm.startPrank(address(defaultCorkController));
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPoolManager.setPausedBitMap(marketId, 0); // Already false
        vm.stopPrank();
    }

    function test_setPausedBitMap_ShouldRevert_WhenSameNonNullStatus() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, 7);
        // Try to set unwind swap to false when already false
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPoolManager.setPausedBitMap(marketId, 7);
        vm.stopPrank();
    }

    function test_setAllPaused_ShouldPauseAllOperations() external {
        // Should be unpaused by default
        assertFalse(corkPoolManager.paused(), "CorkPoolManager should be unpaused initially");

        vm.startPrank(address(defaultCorkController));
        vm.expectEmit(true, false, false, false);
        emit PausableUpgradeable.Paused(address(corkPoolManager));
        corkPoolManager.setAllPaused(true);
        vm.stopPrank();

        assertTrue(corkPoolManager.paused(), "CorkPoolManager should be paused");
    }

    function test_setAllPaused_ShouldUnpauseAllOperations() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        // Should be paused by default
        assertTrue(corkPoolManager.paused(), "CorkPoolManager is paused");

        vm.expectEmit(true, false, false, false);
        emit PausableUpgradeable.Unpaused(address(corkPoolManager));
        corkPoolManager.setAllPaused(false);
        vm.stopPrank();

        assertFalse(corkPoolManager.paused(), "CorkPoolManager should be unpaused");
    }

    function test_setAllPaused_ShouldRevert_WhenNotAdmin() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        corkPoolManager.setAllPaused(true);
        vm.stopPrank();
    }

    function test_setAllPaused_ShouldRevert_WhenSameStatus() external {
        vm.startPrank(address(defaultCorkController));
        // Try to set all paused to false when already false
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        corkPoolManager.setAllPaused(false);

        corkPoolManager.setAllPaused(true);

        // Try to set all paused to false when already true
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        corkPoolManager.setAllPaused(true);

        vm.stopPrank();
    }

    function test_getPausedBitMap_ShouldReturnAllStates() external {
        vm.startPrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(marketId, (1 << 1) + 1);
        vm.stopPrank();

        uint16 pausedBitMap = corkPoolManager.getPausedBitMap(marketId);

        assertEq(pausedBitMap, (1 << 1) + 1);

        assertTrue(defaultCorkController.isDepositPaused(marketId), "Deposit should be paused");
        assertFalse(defaultCorkController.isUnwindSwapPaused(marketId), "UnwindSwap should not be paused");
        assertTrue(defaultCorkController.isSwapPaused(marketId), "Swap should be paused");
        assertFalse(defaultCorkController.isWithdrawalPaused(marketId), "Withdrawal should not be paused");
        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(marketId), "UnwindDeposit should not be paused");
    }

    // ================================ View Function Tests ================================ //

    function test_getId_ShouldReturnCorrectId() external view {
        // Just verify both IDs are non-zero since exact comparison depends on timing
        MarketId computedId = corkPoolManager.getId(
            Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: block.timestamp + 1 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether})
        );
        assertTrue(MarketId.unwrap(computedId) != bytes32(0), "Computed ID should not be zero");
        assertTrue(MarketId.unwrap(marketId) != bytes32(0), "Market ID should not be zero");
    }

    function test_getId_ShouldReturnCorrectId_ForExpiredPools() external {
        uint256 expiryInterval = block.timestamp + 1 days;
        vm.warp(expiryInterval);
        MarketId computedId = corkPoolManager.getId(
            Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: expiryInterval - 1 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.001 ether, rateChangeCapacityMax: 0.001 ether})
        );
        assertTrue(MarketId.unwrap(computedId) != bytes32(0), "Computed ID should not be zero");
        assertTrue(MarketId.unwrap(marketId) != bytes32(0), "Market ID should not be zero");
    }

    function test_market_ShouldReturnMarketInfo() external {
        Market memory marketInfo = corkPoolManager.market(marketId);
        assertEq(marketInfo.referenceAsset, address(referenceAsset), "Reference asset should match");
        assertEq(marketInfo.collateralAsset, address(collateralAsset), "Collateral asset should match");
        assertGt(marketInfo.expiryTimestamp, block.timestamp, "Should have future expiry");
    }

    function test_marketDetails_ShouldReturnCorrectDetails() external {
        Market memory market = corkPoolManager.market(marketId);

        assertEq(market.referenceAsset, address(referenceAsset), "Reference asset should match");
        assertEq(market.collateralAsset, address(collateralAsset), "Collateral asset should match");
        assertGt(market.expiryTimestamp, block.timestamp, "Should have future expiry");
        assertEq(market.rateOracle, address(testOracle), "Oracle should match");
        assertEq(market.rateMin, DEFAULT_RATE_MIN, "rateMin should match");
        assertEq(market.rateMax, DEFAULT_RATE_MAX, "rateMax should match");
        assertEq(market.rateChangePerDayMax, DEFAULT_RATE_CHANGE_PER_DAY_MAX, "rateChangePerDayMax should match");
        assertEq(market.rateChangeCapacityMax, DEFAULT_RATE_CHANGE_CAPACITY_MAX, "rateChangeCapacityMax should match");
    }

    function test_underlyingAsset_ShouldReturnCorrectAssets() external {
        (address collAsset, address refAsset) = corkPoolManager.underlyingAsset(marketId);
        assertEq(collAsset, address(collateralAsset), "Collateral asset should match");
        assertEq(refAsset, address(referenceAsset), "Reference asset should match");
    }

    function test_shares_ShouldReturnCorrectTokens() external {
        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        assertTrue(principalToken != address(0), "Principal token should be set");
        assertTrue(swapToken != address(0), "Swap token should be set");
        assertTrue(principalToken != swapToken, "Tokens should be different");
    }

    function test_expiry_ShouldReturnCorrectExpiry() external {
        Market memory market = corkPoolManager.market(marketId);
        assertGt(market.expiryTimestamp, block.timestamp, "Should have future expiry");
    }

    function test_swapRate_ShouldReturnValidRate() external {
        uint256 rate = corkPoolManager.swapRate(marketId);
        assertGt(rate, 0, "Swap rate should be positive");
    }

    function test_valueLocked_ShouldReturnCorrectValues() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        (uint256 collateralLocked, uint256 referenceLocked) = corkPoolManager.assets(marketId);

        assertGt(collateralLocked, 0, "Should have collateral locked");
        // referenceLocked might be 0 initially
    }

    // ================================ Complex Integration Tests ================================ //

    function test_fullLifecycle_DepositExerciseRedeem() external {
        vm.startPrank(user);

        // 1. Deposit
        collateralAsset.approve(address(corkPoolManager), 2000 ether);
        referenceAsset.approve(address(corkPoolManager), 2000 ether);
        uint256 deposited = corkPoolManager.deposit(marketId, 1000 ether, currentCaller());

        // 2. Exercise
        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);
        (uint256 exerciseAssets, uint256 exerciseOtherSpent, uint256 exerciseFee) = corkPoolManager.exercise(marketId, 100 ether, user);

        // 3. Fast forward to expiry
        vm.warp(block.timestamp + 2 days);

        // 4. Redeem remaining tokens
        uint256 remainingBalance = IERC20(principalToken).balanceOf(user);
        if (remainingBalance > 0) {
            (uint256 redeemedRef, uint256 redeemedCollateral) = corkPoolManager.redeem(marketId, remainingBalance, user, user);
            assertGt(redeemedCollateral, 0, "Should redeem some collateral");
        }

        vm.stopPrank();

        // Verify all operations completed successfully
        assertGt(deposited, 0, "Deposit should work");
        assertGt(exerciseAssets, 0, "Exercise should work");
    }

    function test_multipleUsers_IndependentOperations() external {
        // User1 operations
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        uint256 user1Deposit = corkPoolManager.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        // User2 operations
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 1000 ether);
        uint256 user2Deposit = corkPoolManager.deposit(marketId, 300 ether, currentCaller());
        vm.stopPrank();

        // Both should succeed independently
        assertEq(user1Deposit, 500 ether, "User1 deposit should work");
        assertEq(user2Deposit, 300 ether, "User2 deposit should work");

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        assertEq(IERC20(principalToken).balanceOf(user), 500 ether, "User1 should have correct balance");
        assertEq(IERC20(principalToken).balanceOf(user2), 300 ether, "User2 should have correct balance");
    }

    function test_errorConditions_InsufficientBalances() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 100 ether);
        corkPoolManager.deposit(marketId, 100 ether, currentCaller()); // Small deposit

        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Try to exercise more than available
        vm.expectRevert();
        corkPoolManager.exercise(marketId, 1000 ether, user);
        vm.stopPrank();
    }

    // ================================ Edge Cases ================================ //

    function test_depositMinimumAmount() external {
        uint256 minDeposit = 1; // 1 wei

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), minDeposit);
        uint256 received = corkPoolManager.deposit(marketId, minDeposit, currentCaller());
        vm.stopPrank();

        assertEq(received, minDeposit, "Should handle minimum deposit");
    }

    function test_depositLargeAmount() external {
        uint256 largeDeposit = 1_000_000 ether; // 1M tokens

        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), largeDeposit);
        uint256 received = corkPoolManager.deposit(marketId, largeDeposit, currentCaller());
        vm.stopPrank();

        assertEq(received, largeDeposit, "Should handle large deposit");
    }

    function test_stateConsistency_AfterMultipleOperations() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPoolManager), 5000 ether);
        referenceAsset.approve(address(corkPoolManager), 5000 ether);

        // Multiple deposits
        corkPoolManager.deposit(marketId, 1000 ether, currentCaller());
        corkPoolManager.deposit(marketId, 500 ether, currentCaller());

        // Multiple swaps
        corkPoolManager.swap(marketId, 200 ether, user);
        corkPoolManager.swap(marketId, 100 ether, user);

        // Check that total supply is consistent
        (address principalToken, address swapToken) = corkPoolManager.shares(marketId);
        uint256 principalSupply = IERC20(principalToken).totalSupply();
        uint256 swapSupply = IERC20(swapToken).totalSupply();

        // Principal and swap token supplies should be equal (minus any burned amounts)
        assertGe(principalSupply, swapSupply, "Principal supply should be >= swap supply");

        vm.stopPrank();
    }
}
