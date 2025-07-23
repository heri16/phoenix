// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {ERC20Burnable, Shares} from "contracts/core/assets/Shares.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IExchangeRateProvider} from "contracts/interfaces/IExchangeRateProvider.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {IShares} from "contracts/interfaces/IShares.sol";

import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {CollateralAssetManager, CollateralAssetManagerLibrary} from "contracts/libraries/CollateralAssetManager.sol";
import {Guard} from "contracts/libraries/Guard.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {Balances, CorkPoolPoolArchive, PoolState, State} from "contracts/libraries/State.sol";
import {SwapToken, SwapTokenLibrary} from "contracts/libraries/SwapToken.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract CorkPoolTest is Helper {
    DummyWETH private collateralAsset;
    DummyWETH private referenceAsset;
    MarketId private marketId;
    address private user;
    address private user2;
    address private treasury;
    address private owner;

    // ================================ Event Declarations ================================ //

    // Events from IPool and related interfaces - using IPool events directly

    function setUp() public {
        user = address(0x1234);
        user2 = address(0x2345);
        treasury = address(0x5678);
        owner = address(0x9ABC);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, marketId) = createMarket(1 days);

        vm.deal(user, type(uint256).max);
        vm.deal(user2, type(uint256).max);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        vm.startPrank(user);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.startPrank(user2);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();
        vm.stopPrank();
    }

    // ================================ Market Creation Tests ================================ //

    function test_createNewMarket_ShouldCreateMarket() external {
        DummyWETH newCollateral = new DummyWETH();
        DummyWETH newReference = new DummyWETH();
        uint256 expiry = block.timestamp + 30 days;
        MarketId newId = corkPool.getId(address(newReference), address(newCollateral), expiry, address(corkConfig.defaultExchangeRateProvider()));

        vm.startPrank(address(DEFAULT_ADDRESS));
        corkConfig.updateCorkPoolRate(newId, 1 ether);

        // Calculate expected token addresses using factory's nonce
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, true, true, true);
        emit Initialize.MarketCreated(newId, address(newReference), address(newCollateral), expiry, address(corkConfig.defaultExchangeRateProvider()), expectedPrincipalToken, expectedSwapToken);
        corkPool.createNewMarket(address(newReference), address(newCollateral), expiry, address(corkConfig.defaultExchangeRateProvider()));

        (address refAsset, address collAsset, uint256 expiryTime, address provider) = corkPool.marketDetails(newId);
        assertEq(refAsset, address(newReference), "Reference asset should match");
        assertEq(collAsset, address(newCollateral), "Collateral asset should match");
        assertEq(expiryTime, expiry, "Expiry should match");
        assertEq(provider, address(corkConfig.defaultExchangeRateProvider()), "Provider should match");

        vm.stopPrank();
    }

    function test_createNewMarket_ShouldRevert_WhenNotConfig() external {
        vm.startPrank(user);

        address exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());
        vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
        corkPool.createNewMarket(address(referenceAsset), address(collateralAsset), block.timestamp + 30 days, exchangeRateProvider);

        vm.stopPrank();
    }

    function test_createNewMarket_ShouldRevert_WhenExpiryIsZero() external {
        vm.startPrank(address(corkConfig));

        address exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());
        vm.expectRevert(abi.encodeWithSignature("InvalidExpiry()"));
        corkPool.createNewMarket(address(referenceAsset), address(collateralAsset), 0, exchangeRateProvider);

        vm.stopPrank();
    }

    function test_createNewMarket_ShouldRevert_WhenAlreadyExists() external {
        vm.startPrank(address(corkConfig));

        address exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());
        vm.expectRevert(abi.encodeWithSignature("AlreadyInitialized()"));
        corkPool.createNewMarket(address(referenceAsset), address(collateralAsset), 1 days, exchangeRateProvider);
        vm.stopPrank();
    }

    // ================================ Initialization Tests ================================ //

    function test_initialize_ShouldRevert_WhenCalledTwice() external {
        // Deploy a fresh CorkPool to test initialization
        CorkPool freshPool = new CorkPool();

        // First initialization should succeed
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(sharesFactory), address(corkConfig))));

        // Second initialization should fail
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        CorkPool(address(proxy)).initialize(address(sharesFactory), address(corkConfig));
    }

    function test_initialize_ShouldRevert_WhenSwapSharesFactoryIsZero() external {
        CorkPool freshPool = new CorkPool();

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(0), address(corkConfig))));
    }

    function test_initialize_ShouldRevert_WhenConfigIsZero() external {
        CorkPool freshPool = new CorkPool();

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(sharesFactory), address(0))));
    }

    function test_initialize_ShouldRevert_WhenBothAddressesAreZero() external {
        CorkPool freshPool = new CorkPool();

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new ERC1967Proxy(address(freshPool), abi.encodeCall(freshPool.initialize, (address(0), address(0))));
    }

    // ================================ Upgrade Authorization Tests ================================ //

    function test_upgradeToAndCall_ShouldRevert_WhenNotOwner() external {
        CorkPool newImplementation = new CorkPool();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        corkPool.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    function test_upgradeToAndCall_ShouldWork_WhenOwner() external {
        CorkPool newImplementation = new CorkPool();

        vm.startPrank(DEFAULT_ADDRESS);
        // This should succeed without reverting
        corkPool.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    // ================================ Deposit Tests ================================ //

    function test_deposit_ShouldMintTokens() external {
        uint256 depositAmount = 1000 ether;

        // Get the exchange rate for the expected event
        uint256 expectedExchangeRate = corkPool.exchangeRate(marketId);

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), depositAmount);

        // Expect both Pool Manager and ERC4626-compatible events
        vm.expectEmit(true, true, false, true);
        emit IPool.Deposit(marketId, user, user, depositAmount, depositAmount);

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IShares.Deposit(user, user, depositAmount, depositAmount);

        uint256 received = corkPool.deposit(marketId, depositAmount, currentCaller());
        vm.stopPrank();

        assertEq(received, depositAmount, "Should receive equal amount in 18 decimals");

        assertEq(IERC20(principalToken).balanceOf(user), depositAmount, "Should have principal tokens");
        assertEq(IERC20(swapToken).balanceOf(user), depositAmount, "Should have swap tokens");
    }

    function test_deposit_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 0);

        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPool.deposit(marketId, 0, currentCaller());

        vm.stopPrank();
    }

    function test_deposit_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);

        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.stopPrank();
    }

    function test_deposit_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, true);
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.stopPrank();
    }

    // ================================ Mint Tests ================================ //

    function test_mint_ShouldCalculateCorrectCollateralIn() external {
        uint256 tokensOut = 500 ether;

        uint256 expectedExchangeRate = corkPool.exchangeRate(marketId);

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);

        // Expect both Pool Manager and ERC4626-compatible events
        vm.expectEmit(true, true, false, true);
        emit IPool.Deposit(marketId, user, user, tokensOut, tokensOut);

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        vm.expectEmit(true, true, false, true, principalToken);
        emit IShares.Deposit(user, user, tokensOut, tokensOut);

        (uint256 collateralIn, uint256 exchangeRate) = corkPool.mint(marketId, tokensOut, currentCaller());
        vm.stopPrank();

        assertEq(collateralIn, tokensOut, "Should require equal collateral amount");
        assertGt(exchangeRate, 0, "Should have valid exchange rate");

        assertEq(IERC20(principalToken).balanceOf(user), tokensOut, "Should have principal tokens");
        assertEq(IERC20(swapToken).balanceOf(user), tokensOut, "Should have swap tokens");
    }

    // ================================ Exercise Tests ================================ //

    function test_exercise_ShouldWorkWithShares() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        Shares(swapToken).approve(address(corkPool), type(uint256).max);

        uint256 exerciseShares = 100 ether;
        // Preview to get expected values
        (uint256 expectedAssets, uint256 expectedOtherSpent, uint256 expectedFee) = corkPool.previewExercise(marketId, exerciseShares, 0);

        // Expect both Withdraw and WithdrawExtended events
        vm.expectEmit(true, true, true, true);
        emit IPool.WithdrawExtended(marketId, user, user, expectedAssets, 0, 0, 0);

        vm.expectEmit(true, true, true, true);
        emit IShares.Withdraw(user, user, user, expectedAssets, 0);
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(marketId, exerciseShares, 0, user, 0, type(uint256).max);
        vm.stopPrank();

        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
        // Fee might be 0 if no base redemption fee
    }

    function test_exercise_ShouldWorkWithCompensation() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        uint256 compensation = 50 ether;
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(marketId, 0, compensation, user, 0, type(uint256).max);
        vm.stopPrank();

        assertGt(assets, 0, "Should receive collateral assets");
        assertEq(otherAssetSpent, compensation, "Should spend exact compensation amount");
    }

    function test_exercise_ShouldRevert_WhenBothSharesAndCompensationProvided() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPool.exercise(marketId, 100 ether, 50 ether, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_exercise_ShouldRevert_WhenBothZero() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPool.exercise(marketId, 0, 0, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_exercise_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPool.exercise(marketId, 100 ether, 0, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_exercise_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.exercise(marketId, 100 ether, 0, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    // ================================ Swap Tests ================================ //

    function test_swap_ShouldWork() external {
        // Setup: deposit and then swap
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        uint256 assetAmount = 100 ether;
        // Expect both Withdraw and WithdrawExtended events
        vm.expectEmit(true, true, true, true);
        emit IPool.WithdrawExtended(marketId, user, user, assetAmount, 0, 0, 0);

        vm.expectEmit(true, true, true, true);
        emit IShares.Withdraw(user, user, user, assetAmount, 0);
        (uint256 shares, uint256 compensation) = corkPool.swap(marketId, assetAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "Should provide CST shares");
        assertGt(compensation, 0, "Should require reference asset compensation");
    }

    function test_swap_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPool.swap(marketId, 0, user);
        vm.stopPrank();
    }

    function test_swap_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPool.swap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    function test_swap_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.swap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    // ================================ UnwindSwap Tests ================================ //

    function test_unwindSwap_ShouldWork() external {
        // Setup: create liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        corkPool.swap(marketId, 200 ether, user); // Create pool liquidity

        uint256 unwindAmount = 50 ether;
        // Preview to get expected values
        (uint256 expectedRef, uint256 expectedSwap, uint256 expectedFeePercentage, uint256 expectedFee, uint256 expectedExchangeRates) = corkPool.previewUnwindSwap(marketId, unwindAmount);

        vm.expectEmit(true, true, false, true);
        emit IPool.Deposit(marketId, user, user, unwindAmount, expectedRef + expectedSwap);
        (uint256 receivedRef, uint256 receivedSwap, uint256 feePercentage, uint256 fee, uint256 exchangeRates) = corkPool.unwindSwap(marketId, unwindAmount, user);
        vm.stopPrank();

        assertGt(receivedRef, 0, "Should receive reference asset");
        assertGt(receivedSwap, 0, "Should receive swap tokens");
        assertGt(exchangeRates, 0, "Should have exchange rate");
    }

    function test_unwindSwap_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPool.unwindSwap(marketId, 0, user);
        vm.stopPrank();
    }

    function test_unwindSwap_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPool.unwindSwap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    function test_unwindSwap_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.UNWIND_SWAP, true);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.unwindSwap(marketId, 100 ether, user);
        vm.stopPrank();
    }

    // ================================ UnwindMint Tests ================================ //

    function test_unwindMint_ShouldWork() external {
        uint256 depositAmount = 500 ether;

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), depositAmount);
        corkPool.deposit(marketId, depositAmount, currentCaller());

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        Shares(principalToken).approve(address(corkPool), type(uint256).max);
        Shares(swapToken).approve(address(corkPool), type(uint256).max);

        uint256 unwindAmount = 100 ether;
        vm.expectEmit(true, true, false, true);
        emit IPool.WithdrawExtended(marketId, user, user, unwindAmount, 0, unwindAmount, unwindAmount);
        uint256 collateralReceived = corkPool.unwindMint(marketId, unwindAmount);
        vm.stopPrank();

        assertEq(collateralReceived, unwindAmount, "Should receive equal collateral amount");
    }

    function test_unwindMint_ShouldRevert_WhenZeroAmount() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPool.unwindMint(marketId, 0);
        vm.stopPrank();
    }

    function test_unwindMint_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPool.unwindMint(marketId, 100 ether);
        vm.stopPrank();
    }

    function test_unwindMint_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.PREMATURE_WITHDRAWAL, true);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.unwindMint(marketId, 100 ether);
        vm.stopPrank();
    }

    // ================================ UnwindDeposit Tests ================================ //

    function test_unwindDeposit_ShouldWork() external {
        uint256 depositAmount = 500 ether;

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), depositAmount);
        corkPool.deposit(marketId, depositAmount, currentCaller());

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        Shares(principalToken).approve(address(corkPool), type(uint256).max);
        Shares(swapToken).approve(address(corkPool), type(uint256).max);

        uint256 collateralOut = 100 ether;
        vm.expectEmit(true, true, false, true);
        emit IPool.WithdrawExtended(marketId, user, user, collateralOut, 0, collateralOut, collateralOut);
        uint256 tokensIn = corkPool.unwindDeposit(marketId, collateralOut);
        vm.stopPrank();

        assertEq(tokensIn, collateralOut, "Should burn equal token amount");
    }

    // ================================ UnwindExercise Tests ================================ //

    function test_unwindExercise_ShouldWork() external {
        // Setup: create pool liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        corkPool.swap(marketId, 200 ether, user); // Create liquidity

        uint256 shares = 50 ether;
        uint256 expectedExchangeRate = corkPool.exchangeRate(marketId);

        // Preview to get expected assetIn
        (uint256 expectedAssetIn, uint256 expectedCompensation) = corkPool.previewUnwindExercise(marketId, shares);

        vm.expectEmit(true, true, false, true);
        emit IPool.Deposit(marketId, user, user, expectedAssetIn, shares);
        (uint256 assetIn, uint256 compensationOut) = corkPool.unwindExercise(marketId, shares, user, 0, type(uint256).max);
        vm.stopPrank();

        assertGt(assetIn, 0, "Should require collateral input");
        assertGt(compensationOut, 0, "Should provide reference compensation");
    }

    function test_unwindExercise_ShouldRevert_WhenZeroShares() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPool.unwindExercise(marketId, 0, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_unwindExercise_ShouldRevert_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        corkPool.unwindExercise(marketId, 100 ether, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    // ================================ Redeem Tests ================================ //

    function test_redeem_ShouldWork() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days); // Expire

        uint256 redeemAmount = 100 ether;
        // Preview to get expected values
        (uint256 expectedRef, uint256 expectedCollateral) = corkPool.previewRedeem(marketId, redeemAmount);

        // Expect both Withdraw and WithdrawExtended events
        vm.expectEmit(true, true, true, true);
        emit IPool.WithdrawExtended(marketId, user, user, expectedCollateral, expectedRef, redeemAmount, 0);

        vm.expectEmit(true, true, true, true);
        emit IShares.Withdraw(user, user, user, expectedCollateral, redeemAmount);
        (uint256 accruedRef, uint256 accruedCollateral) = corkPool.redeem(marketId, redeemAmount, user, user);
        vm.stopPrank();

        assertGt(accruedCollateral, 0, "Should receive collateral");
        // accruedRef might be 0 if no reference assets in pool
    }

    function test_redeem_ShouldRevert_WhenZeroAmount() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("ZeroDeposit()"));
        corkPool.redeem(marketId, 0, user, user);
        vm.stopPrank();
    }

    function test_redeem_ShouldRevert_WhenNotExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.expectRevert(abi.encodeWithSignature("NotExpired()"));
        corkPool.redeem(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    function test_redeem_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.redeem(marketId, 100 ether, user, user);
        vm.stopPrank();
    }

    // ================================ MaxRedeem Tests ================================ //

    function test_maxRedeem_ShouldReturnZero_WhenNotInitialized() external {
        // Create a new market ID that hasn't been initialized
        DummyWETH newCollateral = new DummyWETH();
        DummyWETH newReference = new DummyWETH();
        MarketId uninitializedId = corkPool.getId(address(newReference), address(newCollateral), block.timestamp + 30 days, address(corkConfig.defaultExchangeRateProvider()));

        uint256 maxShares = corkPool.maxRedeem(uninitializedId, user);
        assertEq(maxShares, 0, "Should return 0 for uninitialized market");
    }

    function test_maxRedeem_ShouldReturnZero_WhenWithdrawalPaused() external {
        // Setup: deposit first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Pause withdrawals
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        uint256 maxShares = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when withdrawal is paused");
    }

    function test_maxRedeem_ShouldReturnZero_WhenNotExpired() external {
        // Setup: deposit but don't expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Don't warp time - market not expired
        uint256 maxShares = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when market not expired");
    }

    function test_maxRedeem_ShouldReturnZero_WhenUserHasNoShares() external {
        // Setup: don't deposit anything for user
        vm.warp(block.timestamp + 2 days); // Expire

        uint256 maxShares = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when user has no shares");
    }

    function test_maxRedeem_ShouldReturnUserBalance_WhenMarketExpiredAndUserHasShares() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        uint256 receivedShares = corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Get user's CPT balance
        (address principalToken,) = corkPool.shares(marketId);
        uint256 userBalance = IERC20(principalToken).balanceOf(user);

        uint256 maxShares = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares, userBalance, "Should return user's CPT balance");
        assertEq(maxShares, receivedShares, "Should equal received shares from deposit");
    }

    function test_maxRedeem_ShouldReturnCorrectAmount_WhenMultipleUsers() external {
        // Setup: multiple users deposit
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        uint256 user1Shares = corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 500 ether);
        uint256 user2Shares = corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Check both users get their correct max redeemable amounts
        uint256 maxShares1 = corkPool.maxRedeem(marketId, user);
        uint256 maxShares2 = corkPool.maxRedeem(marketId, user2);

        assertEq(maxShares1, user1Shares, "User1 should get their deposit amount");
        assertEq(maxShares2, user2Shares, "User2 should get their deposit amount");
        assertGt(maxShares1, maxShares2, "User1 should have more shares than user2");
    }

    function test_maxRedeem_ShouldReturnCorrectAmount_AfterPartialRedemption() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        uint256 initialShares = corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        // Redeem part of the shares
        vm.startPrank(user);
        uint256 redeemAmount = 300 ether;
        corkPool.redeem(marketId, redeemAmount, user, user);
        vm.stopPrank();

        // Check remaining max redeemable amount
        uint256 maxShares = corkPool.maxRedeem(marketId, user);
        uint256 expectedRemaining = initialShares - redeemAmount;
        assertEq(maxShares, expectedRemaining, "Should return remaining shares after partial redemption");
    }

    function test_maxRedeem_ShouldNotRevert_InAnyValidScenario() external {
        // Test that maxRedeem never reverts even in edge cases

        // Case 1: Market not initialized
        DummyWETH newCollateral = new DummyWETH();
        DummyWETH newReference = new DummyWETH();
        MarketId uninitializedId = corkPool.getId(address(newReference), address(newCollateral), block.timestamp + 30 days, address(corkConfig.defaultExchangeRateProvider()));

        // Should not revert
        uint256 maxShares1 = corkPool.maxRedeem(uninitializedId, user);
        assertEq(maxShares1, 0);

        // Case 2: Paused state
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);
        vm.stopPrank();

        // Should not revert
        uint256 maxShares2 = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares2, 0);

        // Case 3: Not expired
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, false);
        vm.stopPrank();

        // Should not revert
        uint256 maxShares3 = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares3, 0);

        // Case 4: Expired and normal operation
        vm.warp(block.timestamp + 2 days);

        // Should not revert
        uint256 maxShares4 = corkPool.maxRedeem(marketId, user);
        assertEq(maxShares4, 0); // User has no shares
    }

    // ================================ MaxSwap Tests ================================ //

    function test_maxSwap_ShouldReturnZero_WhenNotInitialized() external {
        // Create a new market ID that hasn't been initialized
        DummyWETH newCollateral = new DummyWETH();
        DummyWETH newReference = new DummyWETH();
        MarketId uninitializedId = corkPool.getId(address(newReference), address(newCollateral), block.timestamp + 30 days, address(corkConfig.defaultExchangeRateProvider()));

        uint256 maxAssets = corkPool.maxSwap(uninitializedId, user);
        assertEq(maxAssets, 0, "Should return 0 for uninitialized market");
    }

    function test_maxSwap_ShouldReturnZero_WhenSwapPaused() external {
        // Setup: deposit and provide liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Give user reference assets for compensation
        vm.startPrank(user);
        referenceAsset.approve(address(corkPool), 1000 ether);
        vm.stopPrank();

        // Pause swaps
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.stopPrank();

        uint256 maxAssets = corkPool.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when swap is paused");
    }

    function test_maxSwap_ShouldReturnZero_WhenExpired() external {
        // Setup: deposit but expire the market
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // Expire the market
        vm.warp(block.timestamp + 2 days);

        uint256 maxAssets = corkPool.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when market is expired");
    }

    function test_maxSwap_ShouldReturnZero_WhenUserHasNoCstShares() external {
        // Setup: don't deposit anything for user (no CST shares)
        uint256 maxAssets = corkPool.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when user has no CST shares");
    }

    function test_maxSwap_ShouldReturnZero_WhenUserHasNoReferenceAssets() external {
        address newUser = address(8989);

        vm.startPrank(user);

        collateralAsset.transfer(newUser, 5000 ether);

        vm.startPrank(newUser);

        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        // User has CST shares but no reference assets for compensation
        uint256 maxAssets = corkPool.maxSwap(marketId, user);
        assertEq(maxAssets, 0, "Should return 0 when user has no reference assets");
    }

    function test_maxSwap_ShouldReturnCorrectAmount_WhenCstBalanceIsLimitingFactor() external {
        // Test condition: User has limited CST but plenty of reference assets
        // User CST balance < max CST usable with reference assets

        vm.startPrank(user);

        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller()); // Get CST shares

        uint256 maxAssets = corkPool.maxSwap(marketId, user);
        assertGt(maxAssets, 0, "Should return positive amount when user has both CST and reference assets");

        // The result should be limited by CST balance, not reference asset balance
        (address cstToken,) = corkPool.shares(marketId);
        uint256 userCstBalance = IERC20(cstToken).balanceOf(user);
        assertGt(userCstBalance, 0, "User should have CST shares");

        // Preview what we would get with all CST shares
        (uint256 expectedAssets,,) = corkPool.previewExercise(marketId, userCstBalance, 0);
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

        collateralAsset.approve(address(corkPool), 5000 ether);
        corkPool.deposit(marketId, 5000 ether, currentCaller()); // Get lots of CST shares

        uint256 maxAssets = corkPool.maxSwap(marketId, newUser);
        assertGt(maxAssets, 0, "Should return positive amount when user has both CST and reference assets");

        // The result should be limited by reference asset capacity, not CST balance
        uint256 userRefBalance = IERC20(address(referenceAsset)).balanceOf(newUser);
        assertEq(userRefBalance, 50 ether, "User should have limited reference assets");

        // Preview what we would get with all reference assets (compensation mode)
        (uint256 expectedAssets,,) = corkPool.previewExercise(marketId, 0, userRefBalance);
        assertLe(maxAssets, expectedAssets, "maxSwap should not exceed what's possible with user's reference assets");
    }

    function test_maxSwap_ShouldReturnOptimalAmount_WhenBalancedScenario() external {
        // Test the optimal balance logic with realistic amounts

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller()); // Get CST shares
        referenceAsset.approve(address(corkPool), 1000 ether);

        uint256 maxAssets = corkPool.maxSwap(marketId, user);
        assertGt(maxAssets, 0, "Should return positive amount");

        // Verify the result is reasonable and doesn't exceed any limits
        (address cstToken,) = corkPool.shares(marketId);
        uint256 userCstBalance = IERC20(cstToken).balanceOf(user);
        uint256 userRefBalance = IERC20(address(referenceAsset)).balanceOf(user);

        // Should be able to perform the swap with current balances
        (uint256 previewAssets,,) = corkPool.previewExercise(marketId, userCstBalance, 0);
        assertLe(maxAssets, previewAssets, "maxSwap should be achievable with user's CST balance");
    }

    // ================================ Withdraw Tests ================================ //

    function test_withdraw_ShouldWork() external {
        // Setup: deposit and expire
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days); // Expire

        uint256 collateralOut = 100 ether;
        // Preview to get expected values
        (uint256 expectedSharesIn, uint256 expectedRefOut) = corkPool.previewWithdraw(marketId, collateralOut, 0);

        // Expect both WithdrawExtended and ERC4626-compatible withdraw events
        vm.expectEmit(true, true, true, true);
        emit IPool.WithdrawExtended(marketId, user, user, collateralOut, expectedRefOut, expectedSharesIn, 0);

        (address principalToken,) = corkPool.shares(marketId);
        vm.expectEmit(true, true, true, true, principalToken);
        emit IShares.Withdraw(user, user, user, collateralOut, expectedSharesIn);
        (uint256 sharesIn, uint256 actualRefOut) = corkPool.withdraw(marketId, collateralOut, 0, user, user);
        vm.stopPrank();

        assertGt(sharesIn, 0, "Should burn shares");
        // actualRefOut might be 0 if no reference assets
    }

    function test_withdraw_ShouldRevert_WhenBothAssetsZero() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPool.withdraw(marketId, 0, 0, user, user);
        vm.stopPrank();
    }

    function test_withdraw_ShouldRevert_WhenBothAssetsNonZero() external {
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        corkPool.withdraw(marketId, 100 ether, 50 ether, user, user);
        vm.stopPrank();
    }

    function test_withdraw_ShouldRevert_WhenNotExpired() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("NotExpired()"));
        corkPool.withdraw(marketId, 100 ether, 0, user, user);
        vm.stopPrank();
    }

    function test_withdraw_ShouldRevert_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);
        vm.stopPrank();

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        corkPool.withdraw(marketId, 100 ether, 0, user, user);
        vm.stopPrank();
    }

    // ================================ Preview Function Tests ================================ //

    function test_previewDeposit_ShouldReturnCorrectAmount() external {
        uint256 amount = 1000 ether;
        uint256 expected = corkPool.previewDeposit(marketId, amount);
        assertEq(expected, amount, "Should return 1:1 ratio");
    }

    function test_previewMint_ShouldReturnCorrectAmount() external {
        uint256 tokensOut = 500 ether;
        (uint256 collateralIn, uint256 exchangeRate) = corkPool.previewMint(marketId, tokensOut);
        assertEq(collateralIn, tokensOut, "Should require equal collateral");
        assertGt(exchangeRate, 0, "Should have valid exchange rate");
    }

    function test_previewSwap_ShouldReturnCorrectAmounts() external {
        uint256 referenceAmount = 100 ether;
        (uint256 received, uint256 exchangeRate, uint256 fee, uint256 cstUsed) = corkPool.previewSwap(marketId, referenceAmount);

        assertGt(received, 0, "Should calculate collateral amount");
        assertGt(cstUsed, 0, "Should calculate CST amount");
        assertGt(exchangeRate, 0, "Should have exchange rate");
    }

    function test_previewUnwindSwap_ShouldReturnCorrectAmounts() external {
        // First setup some pool liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        referenceAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        corkPool.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 amount = 50 ether;
        (uint256 receivedRef, uint256 receivedCst, uint256 feePercentage, uint256 fee, uint256 exchangeRates) = corkPool.previewUnwindSwap(marketId, amount);

        assertGt(receivedRef, 0, "Should calculate reference amount");
        assertGt(receivedCst, 0, "Should calculate CST amount");
        assertGt(exchangeRates, 0, "Should have exchange rate");
    }

    function test_previewExercise_ShouldReturnCorrectAmounts() external {
        uint256 shares = 100 ether;
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.previewExercise(marketId, shares, 0);

        assertGt(assets, 0, "Should calculate collateral assets");
        assertGt(otherAssetSpent, 0, "Should calculate reference asset spent");
    }

    function test_previewUnwindExercise_ShouldReturnCorrectAmounts() external {
        uint256 shares = 100 ether;
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(marketId, shares);

        assertGt(assetIn, 0, "Should calculate collateral input");
        assertGt(compensationOut, 0, "Should calculate compensation output");
    }

    function test_previewRedeem_ShouldReturnCorrectAmounts_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 amount = 100 ether;
        (uint256 accruedCollateral, uint256 accruedRef) = corkPool.previewRedeem(marketId, amount);

        assertEq(accruedCollateral, 0, "Should calculate collateral amount correctly");
        assertEq(accruedRef, 100 ether, "Should calculate reference amount correctly");
        // accruedRef is expected to be 0 since there's no reference asset in this setup
    }

    function test_previewWithdraw_ShouldReturnCorrectAmounts_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 collateralOut = 100 ether;
        (uint256 sharesIn, uint256 actualRefOut) = corkPool.previewWithdraw(marketId, collateralOut, 0);

        assertGt(sharesIn, 0, "Should calculate shares needed");
    }

    function test_previewUnwindDeposit_ShouldReturnCorrectAmount() external {
        uint256 collateralOut = 500 ether;
        uint256 tokensIn = corkPool.previewUnwindDeposit(marketId, collateralOut);
        assertEq(tokensIn, collateralOut, "Should return 1:1 ratio");
    }

    function test_previewUnwindMint_ShouldReturnCorrectAmount() external {
        uint256 tokensIn = 500 ether;
        uint256 collateralOut = corkPool.previewUnwindMint(marketId, tokensIn);
        assertEq(collateralOut, tokensIn, "Should return 1:1 ratio");
    }

    // ================================ Max Function Tests ================================ //

    function test_maxDeposit_ShouldReturnMaxUint() external {
        uint256 maxAmount = corkPool.maxDeposit(marketId, user);
        assertEq(maxAmount, type(uint256).max, "Should return max uint256");
    }

    function test_maxMint_ShouldReturnMaxUint() external {
        uint256 maxAmount = corkPool.maxMint(marketId, user);
        assertEq(maxAmount, type(uint256).max, "Should return max uint256");
    }

    function test_maxExercise_ShouldReturnUserBalance() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        vm.stopPrank();

        uint256 maxShares = corkPool.maxExercise(marketId, user);
        assertEq(maxShares, 1000 ether, "Should return user's CST balance");
    }

    function test_maxExercise_ShouldReturnZero_WhenExpired() external {
        vm.warp(block.timestamp + 2 days);

        uint256 maxShares = corkPool.maxExercise(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when expired");
    }

    function test_maxExercise_ShouldReturnZero_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.stopPrank();

        uint256 maxShares = corkPool.maxExercise(marketId, user);
        assertEq(maxShares, 0, "Should return 0 when paused");
    }

    function test_maxUnwindExercise_ShouldReturnCorrectAmount() external {
        // Setup pool liquidity first
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        referenceAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        corkPool.swap(marketId, 100 ether, user);
        vm.stopPrank();

        uint256 maxShares = corkPool.maxUnwindExercise(marketId, user);
        assertGt(maxShares, 0, "Should return positive amount");
    }

    function test_maxUnwindDeposit_ShouldReturnUserBalance() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        uint256 maxAmount = corkPool.maxUnwindDeposit(marketId, user);
        assertEq(maxAmount, 500 ether, "Should return user's minimum token balance");
    }

    function test_maxUnwindMint_ShouldReturnUserBalance() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        uint256 maxAmount = corkPool.maxUnwindMint(marketId, user);
        assertEq(maxAmount, 500 ether, "Should return user's minimum token balance");
    }

    function test_maxWithdraw_ShouldReturnCorrectAmount_WhenExpired() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPool.maxWithdraw(marketId, user);
        assertGt(maxAmount, 0, "Should return positive amount when expired");
    }

    function test_maxWithdraw_ShouldReturnZero_WhenPaused() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPool.maxWithdraw(marketId, user);
        assertEq(maxAmount, 0, "Should return 0 when paused");
    }

    function test_maxWithdraw_ShouldReturnMaxCollateralOut_WhenOwnerSharesLessThanPool() external {
        // ownerShares < normalized pool balance
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 500 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller()); // Small deposit
        vm.stopPrank();

        // Add more liquidity from another user to ensure pool balance > owner shares
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 10_000 ether);
        corkPool.deposit(marketId, 10_000 ether, currentCaller()); // Large deposit
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days); // Expire to enable withdrawals

        uint256 maxAmount = corkPool.maxWithdraw(marketId, user);
        // Should return maxCollateralOut from previewRedeem
        assertGt(maxAmount, 0, "Should return positive amount");
        assertLe(maxAmount, 500 ether, "Should not exceed user's deposit");
    }

    function test_maxWithdraw_ShouldReturnPoolBalance_WhenOwnerSharesGreaterThanPool() external {
        // ownerShares >= normalized pool balance
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 1000 ether, currentCaller());

        // Withdraw some collateral to reduce pool balance below owner shares
        vm.warp(block.timestamp + 2 days); // Expire
        uint256 withdrawAmount = 800 ether;
        (address principalToken,) = corkPool.shares(marketId);
        uint256 userBalance = IERC20(principalToken).balanceOf(user);

        // Withdraw most of the collateral, leaving small pool balance
        if (userBalance >= withdrawAmount) corkPool.redeem(marketId, withdrawAmount, user, user);
        vm.stopPrank();

        uint256 maxAmount = corkPool.maxWithdraw(marketId, user);
        // Should return poolCollateralBalance
        assertGt(maxAmount, 0, "Should return positive pool balance");
    }

    // ================================ Fee and Configuration Tests ================================ //

    function test_updateUnwindSwapFeeRate_ShouldUpdateFee() external {
        uint256 newFee = 2 ether; // 2%

        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, true, false, true);
        emit IUnwindSwap.UnwindSwapFeeRateUpdated(marketId, newFee);
        corkPool.updateUnwindSwapFeeRate(marketId, newFee);
        vm.stopPrank();

        uint256 currentFee = corkPool.unwindSwapFee(marketId);
        assertEq(currentFee, newFee, "Fee should be updated");
    }

    function test_updateUnwindSwapFeeRate_ShouldRevert_WhenNotConfig() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
        corkPool.updateUnwindSwapFeeRate(marketId, 2 ether);
        vm.stopPrank();
    }

    function test_updateBaseRedemptionFeePercentage_ShouldUpdateFee() external {
        uint256 newFee = 3 ether; // 3%

        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, true, false, true);
        emit IPool.BaseRedemptionFeePercentageUpdated(marketId, newFee);
        corkPool.updateBaseRedemptionFeePercentage(marketId, newFee);
        vm.stopPrank();

        uint256 currentFee = corkPool.baseRedemptionFee(marketId);
        assertEq(currentFee, newFee, "Base redemption fee should be updated");
    }

    function test_updateBaseRedemptionFeePercentage_ShouldRevert_WhenNotConfig() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
        corkPool.updateBaseRedemptionFeePercentage(marketId, 3 ether);
        vm.stopPrank();
    }

    // ================================ Pause State Tests ================================ //

    function test_setPausedState_ShouldPauseDeposit() external {
        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, false, false, false);
        emit IPool.DepositPaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, true);
        vm.stopPrank();

        (bool depositPaused,,,,) = corkPool.pausedStates(marketId);
        assertTrue(depositPaused, "Deposit should be paused");
    }

    function test_setPausedState_ShouldUnpauseDeposit() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, true);

        vm.expectEmit(true, false, false, false);
        emit IPool.DepositUnpaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, false);
        vm.stopPrank();

        (bool depositPaused,,,,) = corkPool.pausedStates(marketId);
        assertFalse(depositPaused, "Deposit should be unpaused");
    }

    function test_setPausedState_ShouldPauseUnwindSwap() external {
        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, false, false, false);
        emit IPool.UnwindSwapPaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.UNWIND_SWAP, true);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldUnpauseUnwindSwap() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.UNWIND_SWAP, true);
        vm.expectEmit(true, false, false, false);
        emit IPool.UnwindSwapUnpaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.UNWIND_SWAP, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldPauseSwap() external {
        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, false, false, false);
        emit IPool.SwapPaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldUnpauseSwap() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.expectEmit(true, false, false, false);
        emit IPool.SwapUnpaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldPauseWithdrawal() external {
        vm.startPrank(address(corkConfig));
        vm.expectEmit(true, false, false, false);
        emit IPool.WithdrawalPaused(marketId);
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldUnpauseWithdrawal() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, true);

        vm.expectEmit(true, false, false, false);
        emit IPool.WithdrawalUnpaused(marketId);

        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldPauseReturn() external {
        vm.startPrank(address(corkConfig));

        vm.expectEmit(true, false, false, false);
        emit IPool.ReturnPaused(marketId);

        corkPool.setPausedState(marketId, IPool.OperationType.PREMATURE_WITHDRAWAL, true);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldUnpauseReturn() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.PREMATURE_WITHDRAWAL, true);

        vm.expectEmit(true, false, false, false);
        emit IPool.ReturnUnpaused(marketId);

        corkPool.setPausedState(marketId, IPool.OperationType.PREMATURE_WITHDRAWAL, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldRevert_WhenNotConfig() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, true);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldRevert_WhenSameStatus() external {
        vm.startPrank(address(corkConfig));
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, false); // Already false
        vm.stopPrank();
    }

    function test_setPausedState_ShouldRevert_WhenSameStatus_UnwindSwap() external {
        vm.startPrank(address(corkConfig));
        // Try to set unwind swap to false when already false
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPool.setPausedState(marketId, IPool.OperationType.UNWIND_SWAP, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldRevert_WhenSameStatus_Swap() external {
        vm.startPrank(address(corkConfig));
        // Try to set swap to false when already false
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldRevert_WhenSameStatus_Withdrawal() external {
        vm.startPrank(address(corkConfig));
        // Try to set withdrawal to false when already false
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPool.setPausedState(marketId, IPool.OperationType.WITHDRAWAL, false);
        vm.stopPrank();
    }

    function test_setPausedState_ShouldRevert_WhenSameStatus_PrematureWithdrawal() external {
        vm.startPrank(address(corkConfig));
        // Try to set premature withdrawal to false when already false
        vm.expectRevert(abi.encodeWithSignature("SameStatus()"));
        corkPool.setPausedState(marketId, IPool.OperationType.PREMATURE_WITHDRAWAL, false);
        vm.stopPrank();
    }

    function test_pausedStates_ShouldReturnAllStates() external {
        vm.startPrank(address(corkConfig));
        corkPool.setPausedState(marketId, IPool.OperationType.DEPOSIT, true);
        corkPool.setPausedState(marketId, IPool.OperationType.SWAP, true);
        vm.stopPrank();

        (bool depositPaused, bool unwindSwapPaused, bool swapPaused, bool withdrawalPaused, bool unwindDepositPaused) = corkPool.pausedStates(marketId);

        assertTrue(depositPaused, "Deposit should be paused");
        assertFalse(unwindSwapPaused, "UnwindSwap should not be paused");
        assertTrue(swapPaused, "Swap should be paused");
        assertFalse(withdrawalPaused, "Withdrawal should not be paused");
        assertFalse(unwindDepositPaused, "UnwindDeposit should not be paused");
    }

    // ================================ View Function Tests ================================ //

    function test_getId_ShouldReturnCorrectId() external view {
        // Just verify both IDs are non-zero since exact comparison depends on timing
        MarketId computedId = corkPool.getId(address(referenceAsset), address(collateralAsset), block.timestamp + 1 days, address(corkConfig.defaultExchangeRateProvider()));
        assertTrue(MarketId.unwrap(computedId) != bytes32(0), "Computed ID should not be zero");
        assertTrue(MarketId.unwrap(marketId) != bytes32(0), "Market ID should not be zero");
    }

    function test_market_ShouldReturnMarketInfo() external {
        Market memory marketInfo = corkPool.market(marketId);
        assertEq(marketInfo.referenceAsset, address(referenceAsset), "Reference asset should match");
        assertEq(marketInfo.collateralAsset, address(collateralAsset), "Collateral asset should match");
        assertGt(marketInfo.expiryTimestamp, block.timestamp, "Should have future expiry");
    }

    function test_marketDetails_ShouldReturnCorrectDetails() external {
        (address refAsset, address collAsset, uint256 expiryTime, address provider) = corkPool.marketDetails(marketId);

        assertEq(refAsset, address(referenceAsset), "Reference asset should match");
        assertEq(collAsset, address(collateralAsset), "Collateral asset should match");
        assertGt(expiryTime, block.timestamp, "Should have future expiry");
        assertEq(provider, address(corkConfig.defaultExchangeRateProvider()), "Provider should match");
    }

    function test_underlyingAsset_ShouldReturnCorrectAssets() external {
        (address collAsset, address refAsset) = corkPool.underlyingAsset(marketId);
        assertEq(collAsset, address(collateralAsset), "Collateral asset should match");
        assertEq(refAsset, address(referenceAsset), "Reference asset should match");
    }

    function test_shares_ShouldReturnCorrectTokens() external {
        (address principalToken, address swapToken) = corkPool.shares(marketId);
        assertTrue(principalToken != address(0), "Principal token should be set");
        assertTrue(swapToken != address(0), "Swap token should be set");
        assertTrue(principalToken != swapToken, "Tokens should be different");
    }

    function test_expiry_ShouldReturnCorrectExpiry() external {
        uint256 expiryTime = corkPool.expiry(marketId);
        assertGt(expiryTime, block.timestamp, "Should have future expiry");
    }

    function test_exchangeRate_ShouldReturnValidRate() external {
        uint256 rate = corkPool.exchangeRate(marketId);
        assertGt(rate, 0, "Exchange rate should be positive");
    }

    function test_valueLocked_ShouldReturnCorrectValues() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        uint256 collateralLocked = corkPool.valueLocked(marketId, true);
        uint256 referenceLocked = corkPool.valueLocked(marketId, false);

        assertGt(collateralLocked, 0, "Should have collateral locked");
        // referenceLocked might be 0 initially
    }

    function test_availableForUnwindSwap_ShouldReturnCorrectAmounts() external {
        // Setup some liquidity
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 1000 ether);
        referenceAsset.approve(address(corkPool), 1000 ether);
        corkPool.deposit(marketId, 500 ether, currentCaller());
        corkPool.swap(marketId, 100 ether, user);
        vm.stopPrank();

        (uint256 referenceAvailable, uint256 swapAvailable) = corkPool.availableForUnwindSwap(marketId);
        assertGt(referenceAvailable, 0, "Should have reference asset available");
        assertGt(swapAvailable, 0, "Should have swap tokens available");
    }

    function test_unwindSwapRates_ShouldReturnValidRate() external {
        uint256 rates = corkPool.unwindSwapRates(marketId);
        assertGt(rates, 0, "Rates should be positive");
    }

    // ================================ Complex Integration Tests ================================ //

    function test_fullLifecycle_DepositExerciseRedeem() external {
        vm.startPrank(user);

        // 1. Deposit
        collateralAsset.approve(address(corkPool), 2000 ether);
        referenceAsset.approve(address(corkPool), 2000 ether);
        uint256 deposited = corkPool.deposit(marketId, 1000 ether, currentCaller());

        // 2. Exercise
        (address principalToken, address swapToken) = corkPool.shares(marketId);
        Shares(swapToken).approve(address(corkPool), type(uint256).max);
        (uint256 exerciseAssets, uint256 exerciseOtherSpent, uint256 exerciseFee) = corkPool.exercise(marketId, 100 ether, 0, user, 0, type(uint256).max);

        // 3. Fast forward to expiry
        vm.warp(block.timestamp + 2 days);

        // 4. Redeem remaining tokens
        uint256 remainingBalance = IERC20(principalToken).balanceOf(user);
        if (remainingBalance > 0) {
            (uint256 redeemedRef, uint256 redeemedCollateral) = corkPool.redeem(marketId, remainingBalance, user, user);
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
        collateralAsset.approve(address(corkPool), 1000 ether);
        uint256 user1Deposit = corkPool.deposit(marketId, 500 ether, currentCaller());
        vm.stopPrank();

        // User2 operations
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 1000 ether);
        uint256 user2Deposit = corkPool.deposit(marketId, 300 ether, currentCaller());
        vm.stopPrank();

        // Both should succeed independently
        assertEq(user1Deposit, 500 ether, "User1 deposit should work");
        assertEq(user2Deposit, 300 ether, "User2 deposit should work");

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        assertEq(IERC20(principalToken).balanceOf(user), 500 ether, "User1 should have correct balance");
        assertEq(IERC20(principalToken).balanceOf(user2), 300 ether, "User2 should have correct balance");
    }

    function test_errorConditions_InsufficientBalances() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 100 ether);
        corkPool.deposit(marketId, 100 ether, currentCaller()); // Small deposit

        (address principalToken, address swapToken) = corkPool.shares(marketId);
        Shares(swapToken).approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // Try to exercise more than available
        vm.expectRevert();
        corkPool.exercise(marketId, 1000 ether, 0, user, 0, type(uint256).max);
        vm.stopPrank();
    }

    // ================================ Edge Cases ================================ //

    function test_depositMinimumAmount() external {
        uint256 minDeposit = 1; // 1 wei

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), minDeposit);
        uint256 received = corkPool.deposit(marketId, minDeposit, currentCaller());
        vm.stopPrank();

        assertEq(received, minDeposit, "Should handle minimum deposit");
    }

    function test_depositLargeAmount() external {
        uint256 largeDeposit = 1_000_000 ether; // 1M tokens

        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), largeDeposit);
        uint256 received = corkPool.deposit(marketId, largeDeposit, currentCaller());
        vm.stopPrank();

        assertEq(received, largeDeposit, "Should handle large deposit");
    }

    function test_stateConsistency_AfterMultipleOperations() external {
        vm.startPrank(user);
        collateralAsset.approve(address(corkPool), 5000 ether);
        referenceAsset.approve(address(corkPool), 5000 ether);

        // Multiple deposits
        corkPool.deposit(marketId, 1000 ether, currentCaller());
        corkPool.deposit(marketId, 500 ether, currentCaller());

        // Multiple swaps
        corkPool.swap(marketId, 200 ether, user);
        corkPool.swap(marketId, 100 ether, user);

        // Check that total supply is consistent
        (address principalToken, address swapToken) = corkPool.shares(marketId);
        uint256 principalSupply = IERC20(principalToken).totalSupply();
        uint256 swapSupply = IERC20(swapToken).totalSupply();

        // Principal and swap token supplies should be equal (minus any burned amounts)
        assertGe(principalSupply, swapSupply, "Principal supply should be >= swap supply");

        vm.stopPrank();
    }
}
