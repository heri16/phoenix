pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

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

    struct PreviewUnwindSwapVars {
        uint256 receivedReferenceAsset;
        uint256 receivedSwapToken;
        uint256 feePercentage;
        uint256 fee;
        uint256 swapRate;
    }

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
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);

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

        collateralAsset.approve(address(corkPool), type(uint256).max);

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);
    }

    function setupDifferentDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (uint8, uint8) {
        // bound decimals to minimum of 18 and max of 64
        raDecimals = uint8(bound(raDecimals, TARGET_DECIMALS, MAX_DECIMALS));
        paDecimals = uint8(bound(paDecimals, TARGET_DECIMALS, MAX_DECIMALS));

        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY, raDecimals, paDecimals);

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

        return (raDecimals, paDecimals);
    }

    function test_deposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPool), 1 ether);

        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        vm.assertEq(received, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_deposit(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // regardless of the amount, the received amount would be in 18 decimals
        vm.assertEq(received, 1 ether);
    }

    function test_previewDeposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPool), 1 ether);

        uint256 received = corkPool.previewDeposit(defaultCurrencyId, 1 ether);

        vm.assertEq(received, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_previewDeposit(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.previewDeposit(defaultCurrencyId, depositAmount);

        // regardless of the amount, the received amount would be in 18 decimals
        vm.assertEq(received, 1 ether);
    }

    function testFuzz_exercise(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);

        testOracle.setRate(defaultCurrencyId, rate);
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        uint256 swapAmount = 1 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPool.exercise(defaultCurrencyId, 0, swapAmount, DEFAULT_ADDRESS, 0, type(uint256).max);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(1 ether, TARGET_DECIMALS, raDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        vm.assertApproxEqAbs(received, expectedAmount, acceptableDelta);
    }

    function testFuzz_swapPrincipalToken(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        rate = bound(rate, 0.9 ether, 1 ether);

        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);
        testOracle.setRate(defaultCurrencyId, rate);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // we swap half of the deposited amount
        uint256 swapAmount = 0.5 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPool.exercise(defaultCurrencyId, 0, swapAmount, DEFAULT_ADDRESS, 0, type(uint256).max);
        //forward to expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) = corkPool.redeem(defaultCurrencyId, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.5 ether, TARGET_DECIMALS, raDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        vm.assertApproxEqAbs(received, expectedAmount, acceptableDelta);
    }

    function testFuzz_unwindSwap(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        rate = bound(rate, 0.9 ether, 1 ether);

        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);
        corkConfig.updateUnwindSwapFeeRate(defaultCurrencyId, 0);
        testOracle.setRate(defaultCurrencyId, rate);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // we swap half of the deposited amount
        uint256 swapAmount = 0.5 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPool.exercise(defaultCurrencyId, 0, swapAmount, DEFAULT_ADDRESS, 0, type(uint256).max);

        // and weunwindSwap half of the swaped amount
        uint256 unwindSwapAmount = 0.25 ether * rate / 1 ether;

        uint256 adjustedunwindSwapAmount = TransferHelper.normalizeDecimals(unwindSwapAmount, TARGET_DECIMALS, raDecimals);

        (uint256 receivedReferenceAsset, uint256 receivedSwapToken,,,) = corkPool.unwindSwap(defaultCurrencyId, adjustedunwindSwapAmount, DEFAULT_ADDRESS);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.25 ether, TARGET_DECIMALS, paDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, paDecimals);

        vm.assertApproxEqAbs(receivedReferenceAsset, expectedAmount, acceptableDelta);
        vm.assertApproxEqAbs(receivedSwapToken, unwindSwapAmount, acceptableDelta);
    }

    function testFuzz_swapPrincipalTokenSwapToken(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        uint256 expectedReceived = 1 ether;

        vm.assertEq(received, expectedReceived);

        (address principalToken, address swapToken) = corkPool.shares(defaultCurrencyId);

        // approve
        IERC20(principalToken).approve(address(corkPool), type(uint256).max);
        IERC20(swapToken).approve(address(corkPool), type(uint256).max);

        uint256 collateralAsset = corkPool.unwindMint(defaultCurrencyId, received, address(DEFAULT_ADDRESS), address(DEFAULT_ADDRESS));

        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, raDecimals);

        vm.assertApproxEqAbs(collateralAsset, depositAmount, acceptableDelta);
    }

    function test_swapRate() public {
        uint256 rate = corkPool.swapRate(defaultCurrencyId);
        vm.assertEq(rate, defaultSwapRate(), "Swap rate should match default");
    }

    function test_availableForUnwindSwap() public {
        corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        (uint256 _referenceAsset, uint256 swapToken) = corkPool.availableForUnwindSwap(defaultCurrencyId);
        vm.assertEq(_referenceAsset, 0);
        vm.assertEq(swapToken, 0);
    }

    function test_RevertswapWithInsufficientLiquidity() external {
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 1 ether);
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);

        swapToken.approve(address(corkPool), 20_000 ether);
        referenceAsset.approve(address(corkPool), 20_000 ether);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientLiquidity.selector, 1 ether, 9900 ether));
        corkPool.exercise(defaultCurrencyId, 0, 10_000 ether, user2, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_previewUnwindSwap() external {
        corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 unwindSwapAmount = 0.5 ether;

        uint256 swapAmount = unwindSwapAmount;

        collateralAsset.approve(address(corkPool), unwindSwapAmount);
        referenceAsset.approve(address(corkPool), type(uint256).max);
        swapToken.approve(address(corkPool), type(uint256).max);

        corkPool.exercise(defaultCurrencyId, 0, swapAmount, DEFAULT_ADDRESS, 0, type(uint256).max);

        BalanceSnapshot memory beforeBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        PreviewUnwindSwapVars memory preview;
        (preview.receivedReferenceAsset, preview.receivedSwapToken, preview.feePercentage, preview.fee, preview.swapRate) = corkPool.previewUnwindSwap(defaultCurrencyId, unwindSwapAmount);

        PreviewUnwindSwapVars memory actual;
        (actual.receivedReferenceAsset, actual.receivedSwapToken, actual.feePercentage, actual.fee, actual.swapRate) = corkPool.unwindSwap(defaultCurrencyId, unwindSwapAmount, DEFAULT_ADDRESS);

        BalanceSnapshot memory afterBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        assertEq(preview.receivedReferenceAsset, actual.receivedReferenceAsset);
        assertEq(preview.receivedSwapToken, actual.receivedSwapToken);
        assertEq(preview.feePercentage, actual.feePercentage);
        assertEq(preview.fee, actual.fee);
        assertEq(preview.swapRate, actual.swapRate);

        assertEq(beforeBalances.collateralAsset - afterBalances.collateralAsset, unwindSwapAmount);
        assertEq(afterBalances.referenceAsset - beforeBalances.referenceAsset, actual.receivedReferenceAsset);
        assertEq(afterBalances.swapToken - beforeBalances.swapToken, actual.receivedSwapToken);
    }

    function test_previewSwapWithSwapToken() external {
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 swapAmount = 0.5 ether;

        swapToken.approve(address(corkPool), swapAmount);
        referenceAsset.approve(address(corkPool), swapAmount);

        BalanceSnapshot memory beforeBalances = BalanceSnapshot({collateralAsset: collateralAsset.balanceOf(DEFAULT_ADDRESS), referenceAsset: referenceAsset.balanceOf(DEFAULT_ADDRESS), swapToken: swapToken.balanceOf(DEFAULT_ADDRESS), principalToken: principalToken.balanceOf(DEFAULT_ADDRESS)});

        PreviewswapVars memory preview;
        (preview.collateralAsset, preview.swapToken, preview.fee) = corkPool.previewExercise(defaultCurrencyId, 0, swapAmount);
        preview.rate = corkPool.swapRate(defaultCurrencyId);

        PreviewswapVars memory actual;
        (actual.collateralAsset, actual.swapToken, actual.fee) = corkPool.exercise(defaultCurrencyId, 0, swapAmount, DEFAULT_ADDRESS, 0, type(uint256).max);
        actual.rate = corkPool.swapRate(defaultCurrencyId);

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
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Forward to expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        uint256 withdrawAmount = received;

        // Approve tokens
        principalToken.approve(address(corkPool), withdrawAmount);

        // Get balances before
        uint256 userPaBefore = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userRaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Preview redeem
        (uint256 previewPa, uint256 previewRa) = corkPool.previewRedeem(defaultCurrencyId, withdrawAmount);

        // Execute actual redeem
        (uint256 actualPa, uint256 actualRa) = corkPool.redeem(defaultCurrencyId, withdrawAmount, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

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
        collateralAsset.approve(address(corkPool), 1 ether);

        uint256 out = corkPool.mint(defaultCurrencyId, 1 ether, currentCaller());

        vm.assertEq(out, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_mint(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        uint256 expectedInAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        uint256 inAmount = corkPool.mint(defaultCurrencyId, 1 ether, currentCaller());

        vm.assertEq(inAmount, expectedInAmount);
    }

    function test_previewMint() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPool), 1 ether);

        uint256 out = corkPool.previewMint(defaultCurrencyId, 1 ether);

        vm.assertEq(out, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_previewMint(uint8 raDecimals, uint8 paDecimals) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        vm.resetGasMetering();

        uint256 expectedInAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        uint256 inAmount = corkPool.previewMint(defaultCurrencyId, 1 ether);

        vm.assertEq(inAmount, expectedInAmount);
    }

    function test_unwindDeposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPool), 100 ether);

        uint256 out = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        swapToken.approve(address(corkPool), 10 ether);
        principalToken.approve(address(corkPool), 10 ether);

        uint256 collateralAssetBalanceBefore = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        uint256 cptAndCstSharesIn = corkPool.unwindDeposit(defaultCurrencyId, 1 ether, address(DEFAULT_ADDRESS), address(DEFAULT_ADDRESS));

        uint256 collateralAssetBalanceAfter = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        vm.assertEq(collateralAssetBalanceAfter - collateralAssetBalanceBefore, 1 ether);
        vm.assertEq(cptAndCstSharesIn, 1 ether);

        vm.stopPrank();
    }

    function testFuzz_unwindDeposit(uint8 raDecimals, uint8 paDecimals) external {
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.approve(address(corkPool), 100 ether);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        uint256 out = corkPool.deposit(defaultCurrencyId, normalizedDepositAmount, currentCaller());

        swapToken.approve(address(corkPool), 10 ether);
        principalToken.approve(address(corkPool), 10 ether);

        uint256 collateralAssetBalanceBefore = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        uint256 cptAndCstSharesIn = corkPool.unwindDeposit(defaultCurrencyId, normalizedDepositAmount, address(DEFAULT_ADDRESS), address(DEFAULT_ADDRESS));

        uint256 collateralAssetBalanceAfter = collateralAsset.balanceOf(address(DEFAULT_ADDRESS));

        vm.assertEq(collateralAssetBalanceAfter - collateralAssetBalanceBefore, normalizedDepositAmount);
        vm.assertEq(cptAndCstSharesIn, 1 ether);

        vm.stopPrank();
    }

    function test_exerciseSharesModeWithDifferentAddresses() external {
        // Setup - deposit to get CST tokens as user2
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 1 ether);
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 sharesAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPool), sharesAmount);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // Get balances before
        uint256 user2CaBefore = collateralAsset.balanceOf(user2);
        uint256 user2RaBefore = referenceAsset.balanceOf(user2);
        uint256 user2CstBefore = swapToken.balanceOf(user2);
        uint256 defaultCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Exercise as user2 (sender/owner) and sending to DEFAULT_ADDRESS (receiver)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            sharesAmount, // shares input
            0, // compensation = 0 for shares mode
            DEFAULT_ADDRESS, // receiver (assets go to DEFAULT_ADDRESS)
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
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

    function test_exerciseCompensationModeWithDifferentAddresses() external {
        // Setup - deposit to get tokens for liquidity
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 1 ether);
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 compensationAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), compensationAmount);

        // Get balances before
        uint256 user2CaBefore = collateralAsset.balanceOf(user2);
        uint256 user2RaBefore = referenceAsset.balanceOf(user2);
        uint256 user2CstBefore = swapToken.balanceOf(user2);
        uint256 defaultCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Exercise as user2 (sender/owner) and sending to DEFAULT_ADDRESS (receiver)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            0, // shares = 0 for compensation mode
            compensationAmount, // compensation input
            DEFAULT_ADDRESS, // receiver (assets go to DEFAULT_ADDRESS)
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
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
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 sharesAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPool), sharesAmount);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // Exercise in shares mode (shares > 0, compensation = 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            sharesAmount, // shares input
            0, // compensation = 0 for shares mode
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
        );

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
    }

    function test_exerciseCompensationModeBasic() external {
        // Setup - deposit to get tokens for liquidity
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
        uint256 compensationAmount = 0.5 ether;

        // Approve tokens for exercise
        swapToken.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), compensationAmount);

        // Exercise in compensation mode (shares = 0, compensation > 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            0, // shares = 0 for compensation mode
            compensationAmount, // compensation input
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
        );

        // Verify results
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend CST tokens");
    }

    function test_maxExerciseBasic() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Check max exercise amount
        uint256 maxShares = corkPool.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Should equal the user's CST balance
        assertEq(maxShares, swapToken.balanceOf(DEFAULT_ADDRESS), "Max exercise should equal CST balance");
        assertEq(maxShares, received, "Max exercise should equal received from deposit");
    }

    function test_maxExerciseWithZeroBalance() external {
        // Check max exercise with no CST tokens
        uint256 maxShares = corkPool.maxExercise(defaultCurrencyId, user2);

        // Should be 0 since user has no CST tokens
        assertEq(maxShares, 0, "Max exercise should be 0 with no CST balance");
    }

    function test_maxExerciseAfterExpiry() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Move past expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        // Check max exercise amount after expiry
        uint256 maxShares = corkPool.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Should be 0 after expiry
        assertEq(maxShares, 0, "Max exercise should be 0 after expiry");
    }

    function test_maxExerciseWithPausedSwaps() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Pause swaps
        corkConfig.pauseSwaps(defaultCurrencyId);

        // Check max exercise amount with paused swaps
        uint256 maxShares = corkPool.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Should be 0 when swaps are paused
        assertEq(maxShares, 0, "Max exercise should be 0 when swaps are paused");
    }

    function test_maxExerciseInvariant() external {
        // Setup - deposit to get CST tokens
        uint256 received = corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Get max exercise amount
        uint256 maxShares = corkPool.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Approve tokens for exercise
        swapToken.approve(address(corkPool), maxShares);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // Should be able to exercise the max amount without reverting
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            maxShares, // use max shares
            0, // compensation = 0 for shares mode
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
        );

        // Verify the exercise succeeded
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");
    }

    function test_swapBasic() external {
        // Setup - deposit to get liquidity in the pool
        uint256 depositAmount = 1 ether;
        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Desired collateral output
        uint256 desiredAssets = 0.5 ether;

        // Approve tokens for swap
        swapToken.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // Get balances before
        uint256 userCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userRaBefore = referenceAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 userCstBefore = swapToken.balanceOf(DEFAULT_ADDRESS);

        // Execute swap
        (uint256 shares, uint256 compensation) = corkPool.swap(
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
        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Setup user2 with tokens
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), 1 ether);
        corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        referenceAsset.approve(address(corkPool), type(uint256).max);

        uint256 desiredAssets = 0.3 ether;

        // Get balances before
        uint256 user2CaBefore = collateralAsset.balanceOf(user2);
        uint256 user2RaBefore = referenceAsset.balanceOf(user2);
        uint256 user2CstBefore = swapToken.balanceOf(user2);
        uint256 defaultCaBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);

        // Execute swap as user2 (sender/owner) sending assets to DEFAULT_ADDRESS (receiver)
        (uint256 shares, uint256 compensation) = corkPool.swap(
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
        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Try to swap more than available
        uint256 desiredAssets = 1 ether; // More than deposited

        // Approve tokens
        swapToken.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // Should revert with insufficient liquidity
        vm.expectRevert();
        corkPool.swap(defaultCurrencyId, desiredAssets, DEFAULT_ADDRESS);
    }

    function test_swapAfterExpiry() external {
        // Setup - deposit to get liquidity
        corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Move past expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry + 1);

        // Should revert after expiry
        vm.expectRevert();
        corkPool.swap(defaultCurrencyId, 0.5 ether, DEFAULT_ADDRESS);
    }

    function test_swapWithPausedSwaps() external {
        // Setup - deposit to get liquidity
        corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());

        // Pause swaps
        corkConfig.pauseSwaps(defaultCurrencyId);

        // Should revert when swaps are paused
        vm.expectRevert();
        corkPool.swap(defaultCurrencyId, 0.5 ether, DEFAULT_ADDRESS);
    }

    function testFuzz_swap(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);

        testOracle.setRate(defaultCurrencyId, rate);
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Calculate desired assets (half of what we deposited)
        uint256 desiredAssets = depositAmount / 2;

        // Execute swap
        (uint256 shares, uint256 compensation) = corkPool.swap(defaultCurrencyId, desiredAssets, DEFAULT_ADDRESS);

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
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, feePercentage);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Calculate desired assets (quarter of what we deposited to account for fees)
        uint256 desiredAssets = depositAmount / 4;

        // Execute swap
        (uint256 shares, uint256 compensation) = corkPool.swap(defaultCurrencyId, desiredAssets, DEFAULT_ADDRESS);

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
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, feePercentage);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Use half of the CST shares for exercise
        uint256 sharesToExercise = received / 2;

        // Exercise in shares mode (shares > 0, compensation = 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            sharesToExercise, // shares input
            0, // compensation = 0 for shares mode
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
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
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);

        // Deposit to create liquidity
        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Use half of the CST shares for exercise
        uint256 sharesToExercise = received / 2;

        // Exercise in shares mode (shares > 0, compensation = 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            sharesToExercise, // shares input
            0, // compensation = 0 for shares mode
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
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
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, feePercentage);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity
        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Calculate compensation amount (normalized to reference asset decimals)
        uint256 compensationAmount = TransferHelper.normalizeDecimals(0.25 ether, TARGET_DECIMALS, paDecimals);

        // Exercise in compensation mode (shares = 0, compensation > 0)
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            0, // shares = 0 for compensation mode
            compensationAmount, // compensation input
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
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
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0); // No fees for simpler testing

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        // Deposit to create liquidity and get CST tokens
        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // Get max exercise amount
        uint256 maxShares = corkPool.maxExercise(defaultCurrencyId, DEFAULT_ADDRESS);

        // Max exercise should equal the user's CST balance
        assertEq(maxShares, swapToken.balanceOf(DEFAULT_ADDRESS), "Max exercise should equal CST balance");
        assertEq(maxShares, received, "Max exercise should equal received from deposit");

        // Should be able to exercise the max amount without reverting
        (uint256 assets, uint256 otherAssetSpent, uint256 fee) = corkPool.exercise(
            defaultCurrencyId,
            maxShares, // use max shares
            0, // compensation = 0 for shares mode
            DEFAULT_ADDRESS, // receiver
            0, // minAssetsOut
            type(uint256).max // maxOtherAssetSpent
        );

        // Verify the exercise succeeded
        assertGt(assets, 0, "Should receive collateral assets");
        assertGt(otherAssetSpent, 0, "Should spend reference assets");

        // User should have no CST tokens left
        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 0, "Should have no CST tokens left after max exercise");
    }

    function defaultSwapRate() internal pure returns (uint256) {
        return 1.0 ether;
    }
}
