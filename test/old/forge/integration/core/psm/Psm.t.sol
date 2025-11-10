pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {DummyERC20} from "test/old/mocks/DummyERC20.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract CorkPoolTest is Helper {
    ERC20Mock internal collateralAsset;
    ERC20Mock internal referenceAsset;

    uint256 public constant DEFAULT_DEPOSIT_AMOUNT = 10_000 ether;
    uint256 public constant EXPIRY = 1 days;

    address user2 = address(30);
    address public lv;

    uint256 depositAmount = 1 ether;

    PoolShare internal swapToken;
    PoolShare internal principalToken;

    struct PreviewswapVars {
        uint256 collateralAsset;
        uint256 swapToken;
        uint256 fee;
        uint256 rate;
    }

    struct PreviewWithdrawVars {
        uint256 referenceAsset;
        uint256 collateralAsset;
    }

    struct BalanceSnapshot {
        uint256 collateralAsset;
        uint256 referenceAsset;
        uint256 swapToken;
        uint256 principalToken;
    }

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset,) = createMarket(EXPIRY, 1 ether);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.stopPrank();

        vm.startPrank(user2);

        vm.deal(user2, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.stopPrank();
        vm.startPrank(DEFAULT_ADDRESS);

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);
    }

    function setupDifferentDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (uint8, uint8) {
        // bound decimals to minimum of 18 and max of 64
        raDecimals = uint8(bound(raDecimals, TARGET_DECIMALS, MAX_DECIMALS));
        paDecimals = uint8(bound(paDecimals, TARGET_DECIMALS, MAX_DECIMALS));

        return deployWithDifferentDecimals(raDecimals, paDecimals);
    }

    function deployWithDifferentDecimals(uint8 raDecimals, uint8 paDecimals) public returns (uint8, uint8) {
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

    function test_deployHighDecimalsShouldRevert() external {
        DummyERC20 collateralAsset = new DummyERC20("Collateral Asset", "CA", 19);
        DummyERC20 referenceAsset = new DummyERC20("Reference Asset", "REF", 18);

        IDefaultCorkController.PoolCreationParams memory poolCreationParams = IDefaultCorkController.PoolCreationParams({
            pool: Market({
                collateralAsset: address(collateralAsset),
                referenceAsset: address(referenceAsset),
                expiryTimestamp: block.timestamp + 1,
                rateMin: defaultRateMin(),
                rateMax: defaultRateMax(),
                rateChangePerDayMax: defaultRateChangePerDayMax(),
                rateChangeCapacityMax: defaultRateChangeCapacityMax(),
                rateOracle: address(testOracle)
            }),
            unwindSwapFeePercentage: 0,
            swapFeePercentage: 0,
            isWhitelistEnabled: false
        });

        // should revert if collateral decimals > 18
        vm.expectPartialRevert(IErrors.InvalidParams.selector);
        defaultCorkController.createNewPool(poolCreationParams);

        collateralAsset = new DummyERC20("Collateral Asset", "CA", 18);
        referenceAsset = new DummyERC20("Reference Asset", "REF", 19);

        poolCreationParams.pool.collateralAsset = address(collateralAsset);
        poolCreationParams.pool.referenceAsset = address(referenceAsset);

        // should revert if reference decimals > 18
        vm.expectPartialRevert(IErrors.InvalidParams.selector);
        defaultCorkController.createNewPool(poolCreationParams);
    }

    function test_deposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPoolManager), 1 ether);

        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        vm.assertEq(received, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_deposit(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // regardless of the amount, the received amount would be in 18 decimals
        vm.assertEq(received, 1 ether);
    }

    function test_previewDeposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPoolManager), 1 ether);

        uint256 received = corkPoolManager.previewDeposit(defaultCurrencyId, 1 ether);

        vm.assertEq(received, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_previewDeposit(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPoolManager.previewDeposit(defaultCurrencyId, depositAmount);

        // regardless of the amount, the received amount would be in 18 decimals
        vm.assertEq(received, 1 ether);
    }

    function testFuzz_exerciseOther(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);

        testOracle.setRate(defaultCurrencyId, rate);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        uint256 swapAmount = 1 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPoolManager.exerciseOther(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, raDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        vm.assertApproxEqAbs(received, expectedAmount, acceptableDelta);
    }

    function testFuzz_swapPrincipalToken(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        rate = bound(rate, 0.9 ether, 1 ether);

        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0);
        testOracle.setRate(defaultCurrencyId, rate);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // we swap half of the deposited amount
        uint256 swapAmount = 0.5 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPoolManager.exerciseOther(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);
        //forward to expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) = corkPoolManager.redeem(defaultCurrencyId, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.5 ether, TARGET_DECIMALS, raDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        vm.assertApproxEqAbs(received, expectedAmount, acceptableDelta);
    }

    function testFuzz_unwindSwap(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        rate = bound(rate, 0.9 ether, 1 ether);

        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0);
        defaultCorkController.updateUnwindSwapFeeRate(defaultCurrencyId, 0);
        testOracle.setRate(defaultCurrencyId, rate);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // we swap half of the deposited amount
        uint256 swapAmount = 0.5 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPoolManager.exerciseOther(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        // and weunwindSwap half of the swaped amount
        uint256 unwindSwapAmount = 0.25 ether * rate / 1 ether;

        uint256 adjustedunwindSwapAmount = TransferHelper.normalizeDecimals(unwindSwapAmount, TARGET_DECIMALS, raDecimals);

        (uint256 unwindReceivedCst, uint256 unwindReceivedRef, uint256 unwindFee) = corkPoolManager.unwindSwap(defaultCurrencyId, adjustedunwindSwapAmount, DEFAULT_ADDRESS);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.25 ether, TARGET_DECIMALS, paDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, paDecimals);

        vm.assertApproxEqAbs(unwindReceivedRef, expectedAmount, acceptableDelta);
        vm.assertApproxEqAbs(unwindReceivedCst, unwindSwapAmount, acceptableDelta);
    }

    function testFuzz_swapPrincipalTokenSwapToken(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        uint256 expectedReceived = 1 ether;

        vm.assertEq(received, expectedReceived);

        (address principalToken, address swapToken) = corkPoolManager.shares(defaultCurrencyId);

        // approve
        IERC20(principalToken).approve(address(corkPoolManager), type(uint256).max);
        IERC20(swapToken).approve(address(corkPoolManager), type(uint256).max);

        assumeMinimum(raDecimals, received);

        uint256 collateralAsset = corkPoolManager.unwindMint(defaultCurrencyId, received, address(DEFAULT_ADDRESS), address(DEFAULT_ADDRESS));

        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        vm.assertApproxEqAbs(collateralAsset, depositAmount, acceptableDelta);
    }

    function test_swapRate() public {
        uint256 rate = corkPoolManager.swapRate(defaultCurrencyId);
        vm.assertEq(rate, defaultSwapRate(), "Swap rate should match default");
    }

    function test_RevertswapWithInsufficientLiquidity() external {
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 1 ether);
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);

        swapToken.approve(address(corkPoolManager), 20_000 ether);
        referenceAsset.approve(address(corkPoolManager), 20_000 ether);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientLiquidity.selector, 1 ether, 10_000 ether));
        corkPoolManager.exerciseOther(defaultCurrencyId, 10_000 ether, user2);
        vm.stopPrank();
    }

    function test_previewUnwindSwap() external {
        corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 unwindSwapAmount = 0.5 ether;

        uint256 swapAmount = unwindSwapAmount;

        collateralAsset.approve(address(corkPoolManager), unwindSwapAmount);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);
        swapToken.approve(address(corkPoolManager), type(uint256).max);

        corkPoolManager.exerciseOther(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        BalanceSnapshot memory beforeBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        (uint256 previewReceivedCst, uint256 previewReceivedRef, uint256 previewFee) = corkPoolManager.previewUnwindSwap(defaultCurrencyId, unwindSwapAmount);

        (uint256 actualReceivedCst, uint256 actualReceivedRef, uint256 unwindFee) = corkPoolManager.unwindSwap(defaultCurrencyId, unwindSwapAmount, DEFAULT_ADDRESS);

        BalanceSnapshot memory afterBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        assertEq(previewReceivedRef, actualReceivedRef);
        assertEq(previewReceivedCst, actualReceivedCst);
        assertEq(previewFee, unwindFee);

        assertEq(beforeBalances.collateralAsset - afterBalances.collateralAsset, unwindSwapAmount);
        assertEq(afterBalances.referenceAsset - beforeBalances.referenceAsset, actualReceivedRef);
        assertEq(afterBalances.swapToken - beforeBalances.swapToken, actualReceivedCst);
    }

    function test_previewSwapWithSwapToken() external {
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 swapAmount = 0.5 ether;

        swapToken.approve(address(corkPoolManager), swapAmount);
        referenceAsset.approve(address(corkPoolManager), swapAmount);

        BalanceSnapshot memory beforeBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        PreviewswapVars memory preview;
        (preview.collateralAsset, preview.swapToken, preview.fee) = corkPoolManager.previewExercise(defaultCurrencyId, swapAmount);
        preview.rate = corkPoolManager.swapRate(defaultCurrencyId);

        PreviewswapVars memory actual;
        (actual.collateralAsset, actual.swapToken, actual.fee) = corkPoolManager.exerciseOther(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);
        actual.rate = corkPoolManager.swapRate(defaultCurrencyId);

        BalanceSnapshot memory afterBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        assertEq(preview.collateralAsset, actual.collateralAsset);
        assertEq(preview.swapToken, actual.swapToken);
        assertEq(preview.fee, actual.fee);
        assertEq(preview.rate, actual.rate);

        assertEq(afterBalances.collateralAsset - beforeBalances.collateralAsset, actual.collateralAsset);
        assertEq(beforeBalances.swapToken - afterBalances.swapToken, actual.swapToken);
    }

    function test_previewRedeem() external {
        // Setup - deposit and move past expiry
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Forward to expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        uint256 withdrawAmount = received;

        // Approve tokens
        principalToken.approve(address(corkPoolManager), withdrawAmount);

        // Get balances before
        uint256 userPaBefore = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userRaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Preview redeem
        (uint256 previewPa, uint256 previewRa) = corkPoolManager.previewRedeem(defaultCurrencyId, withdrawAmount);

        // Execute actual redeem
        (uint256 actualPa, uint256 actualRa) = corkPoolManager.redeem(defaultCurrencyId, withdrawAmount, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        // Get balances after
        uint256 userPaAfter = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userRaAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Assert preview matches actual
        assertEq(previewPa, actualPa);
        assertEq(previewRa, actualRa);

        // Assert balances changed correctly
        assertEq(userPaAfter - userPaBefore, actualPa); // User received Reference Asset
        assertEq(userRaAfter - userRaBefore, actualRa); // User received Collateral Asset
    }

    function test_mint() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPoolManager), 1 ether);

        uint256 out = corkPoolManager.mint(defaultCurrencyId, 1 ether, currentCaller());

        vm.assertEq(out, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_mint(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        uint256 expectedInAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        uint256 inAmount = corkPoolManager.mint(defaultCurrencyId, 1 ether, currentCaller());

        vm.assertEq(inAmount, expectedInAmount);
    }

    function test_previewMint() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPoolManager), 1 ether);

        uint256 out = corkPoolManager.previewMint(defaultCurrencyId, 1 ether);

        vm.assertEq(out, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_previewMint(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        uint256 expectedInAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        uint256 inAmount = corkPoolManager.previewMint(defaultCurrencyId, 1 ether);

        vm.assertEq(inAmount, expectedInAmount);
    }

    function test_unwindDeposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPoolManager), 100 ether);

        uint256 out = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        swapToken.approve(address(corkPoolManager), 10 ether);
        principalToken.approve(address(corkPoolManager), 10 ether);

        uint256 collateralAssetBalanceBefore = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        uint256 cptAndCstSharesIn = corkPoolManager.unwindDeposit(defaultCurrencyId, 1 ether, address(DEFAULT_ADDRESS), address(DEFAULT_ADDRESS));

        uint256 collateralAssetBalanceAfter = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        vm.assertEq(collateralAssetBalanceAfter - collateralAssetBalanceBefore, 1 ether);
        vm.assertEq(cptAndCstSharesIn, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_unwindDeposit(uint8 raDecimals, uint8 paDecimals) external {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPoolManager), 100 ether);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        uint256 out = corkPoolManager.deposit(defaultCurrencyId, normalizedDepositAmount, currentCaller());

        swapToken.approve(address(corkPoolManager), 10 ether);
        principalToken.approve(address(corkPoolManager), 10 ether);

        uint256 collateralAssetBalanceBefore = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        uint256 cptAndCstSharesIn = corkPoolManager.unwindDeposit(defaultCurrencyId, normalizedDepositAmount, address(DEFAULT_ADDRESS), address(DEFAULT_ADDRESS));

        uint256 collateralAssetBalanceAfter = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        vm.assertEq(collateralAssetBalanceAfter - collateralAssetBalanceBefore, normalizedDepositAmount);
        vm.assertEq(cptAndCstSharesIn, 1 ether);

        vm.stopPrank();
    }

    function test_exerciseWithDifferentAddresses() external {
        // Setup - deposit to get CST tokens as user2
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 1 ether);
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 sharesAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPoolManager), sharesAmount);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Get balances before
        uint256 user2CaBefore = collateralAsset.balanceOf(user2);
        uint256 user2RaBefore = referenceAsset.balanceOf(user2);
        uint256 user2CstBefore = swapToken.balanceOf(user2);
        uint256 defaultCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Exercise as user2 (sender/owner) and sending to DEFAULT_ADDRESS (receiver)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(
                defaultCurrencyId,
                sharesAmount, // shares input
                DEFAULT_ADDRESS // receiver (assets go to DEFAULT_ADDRESS)
            );
        vm.stopPrank();

        // Get balances after
        uint256 user2CaAfter = collateralAsset.balanceOf(user2);
        uint256 user2RaAfter = referenceAsset.balanceOf(user2);
        uint256 user2CstAfter = swapToken.balanceOf(user2);
        uint256 defaultCaAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
        assertEq(defaultCaAfter - defaultCaBefore, assets, "Receiver should receive collateral assets");
        assertEq(user2RaBefore - user2RaAfter, otherAssetSpent, "user2 should spend reference assets");
        assertEq(user2CstBefore - user2CstAfter, sharesAmount, "user2 should spend CST shares");
        assertEq(user2CaAfter, user2CaBefore, "user2 should not receive collateral assets");
    }

    function test_exerciseOtherWithDifferentAddresses() external {
        // Setup - deposit to get tokens for liquidity
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 1 ether);
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 compensationAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), compensationAmount);

        // Get balances before
        uint256 user2CaBefore = collateralAsset.balanceOf(user2);
        uint256 user2RaBefore = referenceAsset.balanceOf(user2);
        uint256 user2CstBefore = swapToken.balanceOf(user2);
        uint256 defaultCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Exercise as user2 (sender/owner) and sending to DEFAULT_ADDRESS (receiver)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exerciseOther(
                defaultCurrencyId,
                compensationAmount, // compensation input
                DEFAULT_ADDRESS // receiver (assets go to DEFAULT_ADDRESS)
            );
        vm.stopPrank();

        // Get balances after
        uint256 user2CaAfter = collateralAsset.balanceOf(user2);
        uint256 user2RaAfter = referenceAsset.balanceOf(user2);
        uint256 user2CstAfter = swapToken.balanceOf(user2);
        uint256 defaultCaAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend CST tokens");
        assertEq(defaultCaAfter - defaultCaBefore, assets, "Receiver should receive collateral assets");
        assertEq(user2RaBefore - user2RaAfter, compensationAmount, "user2 should spend reference assets");
        assertEq(user2CstBefore - user2CstAfter, otherAssetSpent, "user2 should spend CST tokens");
        assertEq(user2CaAfter, user2CaBefore, "user2 should not receive collateral assets");
    }

    function test_exerciseSharesModeBasic() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 sharesAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPoolManager), sharesAmount);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Exercise in shares mode (shares > 0, compensation = 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(
                defaultCurrencyId,
                sharesAmount, // shares input
                DEFAULT_ADDRESS // receiver
            );

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
    }

    function test_exerciseCompensationModeBasic() external {
        // Setup - deposit to get tokens for liquidity
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 compensationAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), compensationAmount);

        // Exercise in compensation mode (shares = 0, compensation > 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exerciseOther(
                defaultCurrencyId,
                compensationAmount, // compensation input
                DEFAULT_ADDRESS // receiver
            );

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend CST tokens");
    }

    function test_maxExerciseBasic() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Check max exercise amount
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Should equal the user's CST balance
        assertEq(maxShares, swapToken.balanceOf(DEFAULT_ADDRESS), "Max exercise should equal CST balance");
        assertEq(maxShares, received, "Max exercise should equal received from deposit");
    }

    function test_maxExerciseWithZeroBalance() external {
        // Check max exercise with no CST tokens
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, user2);

        // Should be 0 since user has no CST tokens
        assertEq(maxShares, 0, "Max exercise should be 0 with no CST balance");
    }

    function test_maxExerciseAfterExpiry() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Move past expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        // Check max exercise amount after expiry
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Should be 0 after expiry
        assertEq(maxShares, 0, "Max exercise should be 0 after expiry");
    }

    function test_maxExerciseWithPausedSwaps() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Pause swaps
        defaultCorkController.pauseSwaps(defaultCurrencyId);

        // Check max exercise amount with paused swaps
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Should be 0 when swaps are paused
        assertEq(maxShares, 0, "Max exercise should be 0 when swaps are paused");
    }

    function test_maxExerciseInvariant() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Get max exercise amount
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Approve tokens for exercise
        swapToken.approve(address(corkPoolManager), maxShares);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Should be able to exercise the max amount without reverting
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(
                defaultCurrencyId,
                maxShares, // use max shares
                DEFAULT_ADDRESS // receiver
            );

        // Verify the exercise succeeded
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
    }

    function test_maxExerciseWithLimitedReferenceAsset() external {
        uint256 depositAmount = 1 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());
        uint256 userCstBalance = swapToken.balanceOf(DEFAULT_ADDRESS);

        // Transfer away some reference assets to simulate limited reference asset balance
        // Keep only 0.3 ether worth of reference assets
        uint256 referenceBalanceBefore = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 limitedReferenceBalance = 0.3 ether;
        referenceAsset.transfer(user2, referenceBalanceBefore - limitedReferenceBalance);

        // Get max exercise amount - should be limited by reference asset balance
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Max shares should be less than user's total CST balance due to limited reference assets but also greater than 0
        assertLt(maxShares, userCstBalance, "Max exercise should be limited by reference asset balance");
        assertGt(maxShares, 0, "Max exercise should be greater than 0");

        // Preview how much reference asset the max shares would require
        (, uint256 referenceRequired,) = corkPoolManager.previewExercise(defaultCurrencyId, maxShares);

        // The required reference asset should be approximately equal to what the user has
        assertApproxEqAbs(referenceRequired, limitedReferenceBalance, 10, "Required reference should match limited balance");

        // Approve tokens for exercise
        swapToken.approve(address(corkPoolManager), maxShares);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Should be able to exercise the max amount without reverting
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPoolManager.exercise(defaultCurrencyId, maxShares, DEFAULT_ADDRESS);

        // Verify the exercise succeeded
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");

        // Verify the reference asset spent matches what was previewed
        assertEq(otherAssetSpent, referenceRequired, "Reference asset spent should match preview");

        // User should still have some CST tokens left (since they couldn't exercise all)
        uint256 remainingCst = swapToken.balanceOf(DEFAULT_ADDRESS);
        assertGt(remainingCst, 0, "User should have CST tokens remaining");
        assertEq(remainingCst, userCstBalance - maxShares, "Remaining CST should equal original minus exercised");
    }

    function test_swapBasic() external {
        // Setup - deposit to get liquidity in the pool
        uint256 depositAmount = 1 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Desired collateral output
        uint256 desiredAssets = 0.5 ether;

        // Approve tokens for swap
        swapToken.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Get balances before
        uint256 userCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userRaBefore = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userCstBefore = swapToken.balanceOf(DEFAULT_ADDRESS);

        // Execute swap
        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.swap(
                defaultCurrencyId,
                desiredAssets,
                DEFAULT_ADDRESS // receiver
            );

        // Get balances after
        uint256 userCaAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userRaAfter = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userCstAfter = swapToken.balanceOf(DEFAULT_ADDRESS);

        // Verify results
        assertGt(shares, 0, "Should lock CST shares");
        assertGt(compensation, 0, "Should lock reference asset compensation");
        assertEq(userCaAfter - userCaBefore, desiredAssets, "Should receive exact collateral amount");
        assertEq(userCstBefore - userCstAfter, shares, "Should spend CST shares");
        assertEq(userRaBefore - userRaAfter, compensation, "Should spend reference asset compensation");
    }

    function test_swapWithDifferentOwnerReceiver() external {
        // Setup - deposit to get liquidity in the pool
        uint256 depositAmount = 1 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Setup user2 with tokens
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), 1 ether);
        corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        uint256 desiredAssets = 0.3 ether;

        // Get balances before
        uint256 user2CaBefore = collateralAsset.balanceOf(user2);
        uint256 user2RaBefore = referenceAsset.balanceOf(user2);
        uint256 user2CstBefore = swapToken.balanceOf(user2);
        uint256 defaultCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Execute swap as user2 (sender/owner) sending assets to DEFAULT_ADDRESS (receiver)
        (uint256 shares, uint256 compensation, uint256 fee) =
            corkPoolManager.swap(
                defaultCurrencyId,
                desiredAssets,
                DEFAULT_ADDRESS // receiver (assets go to DEFAULT_ADDRESS)
            );
        vm.stopPrank();

        // Get balances after
        uint256 user2CaAfter = collateralAsset.balanceOf(user2);
        uint256 user2RaAfter = referenceAsset.balanceOf(user2);
        uint256 user2CstAfter = swapToken.balanceOf(user2);
        uint256 defaultCaAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Verify results
        assertGt(shares, 0, "Should lock CST shares");
        assertGt(compensation, 0, "Should lock reference asset compensation");
        assertEq(defaultCaAfter - defaultCaBefore, desiredAssets, "Receiver should get exact collateral amount");
        assertEq(user2CstBefore - user2CstAfter, shares, "user2 should spend CST shares");
        assertEq(user2RaBefore - user2RaAfter, compensation, "user2 should spend reference asset compensation");
        assertEq(user2CaAfter, user2CaBefore, "user2 should not receive collateral assets");
    }

    function test_swapInsufficientLiquidity() external {
        // Setup - deposit small amount to get minimal liquidity
        uint256 depositAmount = 0.1 ether;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Try to swap more than available
        uint256 desiredAssets = 1 ether; // More than deposited

        // Approve tokens
        swapToken.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Should revert with insufficient liquidity
        vm.expectRevert();
        corkPoolManager.swap(defaultCurrencyId, desiredAssets, DEFAULT_ADDRESS);
    }

    function test_swapAfterExpiry() external {
        // Setup - deposit to get liquidity
        corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Move past expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        // Should revert after expiry
        vm.expectRevert();
        corkPoolManager.swap(defaultCurrencyId, 0.5 ether, DEFAULT_ADDRESS);
    }

    function test_swapWithPausedSwaps() external {
        // Setup - deposit to get liquidity
        corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Pause swaps
        defaultCorkController.pauseSwaps(defaultCurrencyId);

        // Should revert when swaps are paused
        vm.expectRevert();
        corkPoolManager.swap(defaultCurrencyId, 0.5 ether, DEFAULT_ADDRESS);
    }

    function testFuzz_swap(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);

        testOracle.setRate(defaultCurrencyId, rate);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Calculate desired assets (half of what we deposited)
        uint256 desiredAssets = depositAmount / 2;

        // Execute swap
        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultCurrencyId, desiredAssets, DEFAULT_ADDRESS);

        // Verify results
        assertGt(shares, 0, "Should lock CST shares");
        assertGt(compensation, 0, "Should lock reference asset compensation");

        // Verify we received the exact desired amount
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        // The swap should work with different decimal precisions
        assertGt(shares, 0, "Should have locked some CST shares");
        assertGt(compensation, 0, "Should have locked some reference asset");
    }

    function testFuzz_swapWithFees(uint8 raDecimals, uint8 paDecimals, uint256 rate, uint256 feePercentage) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);
        feePercentage = bound(feePercentage, 1 ether, 5 ether); // 1-5% fee

        testOracle.setRate(defaultCurrencyId, rate);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, feePercentage);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Calculate desired assets (quarter of what we deposited to account for fees)
        uint256 desiredAssets = depositAmount / 4;

        // Execute swap
        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultCurrencyId, desiredAssets, DEFAULT_ADDRESS);

        // Verify results
        assertGt(shares, 0, "Should lock CST shares");
        assertGt(compensation, 0, "Should lock reference asset compensation");

        // With fees, we should need more gross amount
        if (feePercentage > 0) {
            // The shares locked should be more than the desired assets due to fees
            uint256 sharesInCollateralDecimals = TransferHelper.fixedToTokenNativeDecimals(shares, collateralAsset.decimals());
            assertGt(sharesInCollateralDecimals, desiredAssets, "Should lock more than desired due to fees");
        }
    }

    function testFuzz_exerciseSharesMode(uint8 raDecimals, uint8 paDecimals, uint256 rate, uint256 feePercentage) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);
        feePercentage = bound(feePercentage, 1 ether, 5 ether); // 1-5% fee

        testOracle.setRate(defaultCurrencyId, rate);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, feePercentage);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Use half of the CST shares for exercise
        uint256 sharesToExercise = received / 2;

        // Exercise in shares mode (shares > 0, compensation = 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(
                defaultCurrencyId,
                sharesToExercise, // shares input
                DEFAULT_ADDRESS // receiver
            );

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");

        // The assets received should be roughly equal to shares (minus fees)
        uint256 expectedAssetsBeforeFee = TransferHelper.fixedToTokenNativeDecimals(sharesToExercise, collateralAsset.decimals());
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        if (feePercentage > 0) assertLt(assets, expectedAssetsBeforeFee, "Should receive less than gross amount due to fees");
    }

    function testFuzz_exerciseSharesModeNoFee(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0);

        // Deposit to create liquidity
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Use half of the CST shares for exercise
        uint256 sharesToExercise = received / 2;

        // Exercise in shares mode (shares > 0, compensation = 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(
                defaultCurrencyId,
                sharesToExercise, // shares input
                DEFAULT_ADDRESS // receiver
            );

        // Verify results
        assertEq(fee, 0);
        assertEq(assets, TransferHelper.normalizeDecimals(sharesToExercise, TARGET_DECIMALS, raDecimals), "Should receive collateral assets");
        assertEq(otherAssetSpent, TransferHelper.normalizeDecimals(sharesToExercise, TARGET_DECIMALS, paDecimals), "Should receive collateral assets");
    }

    function testFuzz_exerciseCompensationMode(uint8 raDecimals, uint8 paDecimals, uint256 rate, uint256 feePercentage) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);
        feePercentage = bound(feePercentage, 1 ether, 5 ether); // 1-5% fee

        testOracle.setRate(defaultCurrencyId, rate);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, feePercentage);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Calculate compensation amount (normalized to reference asset decimals)
        uint256 compensationAmount = TransferHelper.normalizeDecimals(0.25 ether, TARGET_DECIMALS, paDecimals);

        // Exercise in compensation mode (shares = 0, compensation > 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exerciseOther(
                defaultCurrencyId,
                compensationAmount, // compensation input
                DEFAULT_ADDRESS // receiver
            );

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend CST tokens");

        // The otherAssetSpent should be CST tokens calculated based on swap rate
        // assets should be roughly equal to the CST amount (converted to collateral decimals, minus fees)
        assertGt(assets, 0, "Should have received some collateral assets");
        assertGt(otherAssetSpent, 0, "Should have spent some CST tokens");
    }

    function testFuzz_exerciseMaxExercise(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);

        testOracle.setRate(defaultCurrencyId, rate);
        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 0); // No fees for simpler testing

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity and get CST tokens
        uint256 received = corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Get max exercise amount
        uint256 maxShares = corkPoolManager.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Max exercise should equal the user's CST balance
        assertEq(maxShares, swapToken.balanceOf(DEFAULT_ADDRESS), "Max exercise should equal CST balance");
        assertEq(maxShares, received, "Max exercise should equal received from deposit");

        // Should be able to exercise the max amount without reverting
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) =
            corkPoolManager.exercise(
                defaultCurrencyId,
                maxShares, // use max shares
                DEFAULT_ADDRESS // receiver
            );

        // Verify the exercise succeeded
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");

        // User should have no CST tokens left
        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 0, "Should have no CST tokens left after max exercise");
    }

    function testUnwindDepositShouldFailWhenSenderDoesNotHaveAllowance() external {
        vm.startPrank(DEFAULT_ADDRESS);
        uint256 depositAmount = 10 ether;
        // deposit
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        address randomPerson = address(0x333);
        vm.startPrank(randomPerson);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, randomPerson, 0, depositAmount));
        corkPoolManager.unwindDeposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS, randomPerson);
    }

    function testUnwindMintShouldFailWhenSenderDoesNotHaveAllowance() external {
        vm.startPrank(DEFAULT_ADDRESS);
        uint256 depositAmount = 10 ether;
        // deposit
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        address randomPerson = address(0x333);
        vm.startPrank(randomPerson);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, randomPerson, 0, depositAmount));
        corkPoolManager.unwindMint(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS, randomPerson);
    }

    function test_mintShouldRevertWhenCollateralInIsZero() external {
        vm.startPrank(DEFAULT_ADDRESS);
        deployWithDifferentDecimals(6, 18);

        // this should fail, max amount to be accepted is 1e12
        uint256 depositAmount = 1e11;

        uint256 collateralAmountIn = corkPoolManager.previewMint(defaultCurrencyId, depositAmount);

        // atleast 1 wei of collateral
        assertEq(collateralAmountIn, 1);

        collateralAmountIn = corkPoolManager.mint(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        // atleast 1 wei of collateral
        assertEq(collateralAmountIn, 1);
    }

    function test_exerciseShouldNotAcceptZeroShares() external {
        vm.startPrank(DEFAULT_ADDRESS);
        deployWithDifferentDecimals(18, 6);

        corkPoolManager.mint(defaultCurrencyId, 100 ether, DEFAULT_ADDRESS);

        (, uint256 referenceSpent,) = corkPoolManager.exercise(defaultCurrencyId, 9e11, DEFAULT_ADDRESS);

        assertEq(referenceSpent, 1);
    }

    function defaultSwapRate() internal pure returns (uint256) {
        return 1.0 ether;
    }

    function test_swap_shouldNotReleaseFreeCollateral() external {
        vm.startPrank(DEFAULT_ADDRESS);
        deployWithDifferentDecimals(6, 18);

        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 99_999_900_001_000);

        corkPoolManager.mint(defaultCurrencyId, 100 ether, DEFAULT_ADDRESS);

        uint256 collateralOut = 1e6;

        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultCurrencyId, collateralOut, DEFAULT_ADDRESS);

        assertEq(shares, collateralOut * 10 ** 12 + fee * 10 ** 12);

        (uint256 collateralLocked, uint256 referenceLocked) = corkPoolManager.assets(defaultCurrencyId);

        uint256 collateralNormalized = TransferHelper.normalizeDecimals(collateralLocked, 6, 18);

        uint256 sharesTotalSupply = swapToken.totalSupply();

        // make sure the shares have an equivalent backing of reference and collateral assets
        assertEq(referenceLocked + collateralNormalized, sharesTotalSupply);
    }

    function test_swap_shouldNotReleaseFreeCollateralWithOne() external {
        vm.startPrank(DEFAULT_ADDRESS);
        deployWithDifferentDecimals(6, 18);

        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 99_999_900_001_000);

        corkPoolManager.mint(defaultCurrencyId, 100 ether, DEFAULT_ADDRESS);

        uint256 collateralOut = 1;

        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultCurrencyId, collateralOut, DEFAULT_ADDRESS);

        // make sure that there's a fee even though the output is very small
        assertGe(fee, 1);

        (uint256 collateralLocked, uint256 referenceLocked) = corkPoolManager.assets(defaultCurrencyId);

        uint256 collateralNormalized = TransferHelper.normalizeDecimals(collateralLocked, 6, 18);

        uint256 sharesTotalSupply = swapToken.totalSupply();

        // make sure the shares have an equivalent backing of reference and collateral assets
        assertEq(referenceLocked + collateralNormalized, sharesTotalSupply);
    }

    function testFuzz_swap_shouldNotReleaseFreeCollateral(uint8 collateralDecimals, uint8 referenceDecimals) external {
        vm.startPrank(DEFAULT_ADDRESS);

        collateralDecimals = uint8(bound(collateralDecimals, 6, 17));
        referenceDecimals = uint8(bound(collateralDecimals, 6, 17));

        (collateralDecimals, referenceDecimals) = deployWithDifferentDecimals(collateralDecimals, referenceDecimals);

        defaultCorkController.updateSwapFeePercentage(defaultCurrencyId, 99_999_900_001_000);

        corkPoolManager.mint(defaultCurrencyId, 100 ether, DEFAULT_ADDRESS);

        uint256 collateralOut = 10 ** collateralDecimals;

        (uint256 shares, uint256 compensation, uint256 fee) = corkPoolManager.swap(defaultCurrencyId, collateralOut, DEFAULT_ADDRESS);

        assertEq(shares, collateralOut * 10 ** (18 - collateralDecimals) + fee * 10 ** (18 - collateralDecimals));

        (uint256 collateralLocked, uint256 referenceLocked) = corkPoolManager.assets(defaultCurrencyId);

        uint256 collateralNormalized = TransferHelper.normalizeDecimals(collateralLocked, collateralDecimals, 18);
        uint256 referencelNormalized = TransferHelper.normalizeDecimals(referenceLocked, referenceDecimals, 18);

        uint256 sharesTotalSupply = swapToken.totalSupply();

        // make sure the shares have an equivalent backing of reference and collateral assets
        assertEq(referencelNormalized + collateralNormalized, sharesTotalSupply);
    }

    function test_unwindMint_ShouldNotUseExtra() external {
        deployWithDifferentDecimals(6, 18);

        uint256 depositAmount = 500 ether;

        collateralAsset.approve(address(corkPoolManager), depositAmount);
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address principalToken, address swapToken) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(address(corkPoolManager), type(uint256).max);
        PoolShare(swapToken).approve(address(corkPoolManager), type(uint256).max);

        // extra 1 wei
        uint256 unwindAmount = 1e12 + 1;

        uint256 principalBalanceBefore = PoolShare(principalToken).balanceOf(DEFAULT_ADDRESS);
        uint256 swapBalanceBefore = PoolShare(swapToken).balanceOf(DEFAULT_ADDRESS);

        corkPoolManager.unwindMint(defaultCurrencyId, unwindAmount, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        uint256 principalBalanceAfter = PoolShare(principalToken).balanceOf(DEFAULT_ADDRESS);
        uint256 swapBalanceAfter = PoolShare(swapToken).balanceOf(DEFAULT_ADDRESS);

        // should have atleast 1e(shares decimal - collateral decimals : 18 - 6 = 12) wei of unused shares
        uint256 unused = 1e12;
        assertEq(unused, principalBalanceBefore - principalBalanceAfter);
        assertEq(unused, swapBalanceBefore - swapBalanceAfter);
    }
}
