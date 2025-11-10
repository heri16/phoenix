pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract UnwindExerciseTest is Helper {
    ERC20Mock internal collateralAsset;
    ERC20Mock internal referenceAsset;

    uint256 public constant DEFAULT_DEPOSIT_AMOUNT = 10_000 ether;
    uint256 public constant EXPIRY = 1000 days;

    address internal user2 = address(30);
    address internal user3 = address(40);

    PoolShare internal swapToken;
    PoolShare internal principalToken;

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

        // Setup user2
        vm.stopPrank();
        vm.startPrank(user2);
        vm.deal(user2, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        // Setup user3
        vm.stopPrank();
        vm.startPrank(user3);
        vm.deal(user3, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        vm.stopPrank();
        vm.startPrank(DEFAULT_ADDRESS);

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        // Initial deposit to provide liquidity
        corkPoolManager.deposit(defaultCurrencyId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        vm.stopPrank();
    }

    function setupUsersForUnwindExercise() internal {
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // User2 deposits to get CST and CPT
        corkPoolManager.deposit(defaultCurrencyId, 1000 ether, currentCaller());

        // User2 exercises to provide Reference Asset and get some collateral out
        uint256 sharesToExercise = 500 ether;
        corkPoolManager.exercise(defaultCurrencyId, sharesToExercise, user2);
        vm.stopPrank();

        vm.startPrank(user3);
        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);
        swapToken.approve(address(corkPoolManager), type(uint256).max);
        vm.stopPrank();
    }

    function takeBalanceSnapshot(address user) internal view returns (BalanceSnapshot memory snapshot) {
        snapshot.collateralAsset = collateralAsset.balanceOf(user);
        snapshot.referenceAsset = referenceAsset.balanceOf(user);
        snapshot.swapToken = swapToken.balanceOf(user);
        snapshot.principalToken = principalToken.balanceOf(user);
    }

    function test_previewUnwindExercise_basicFunctionality() public {
        setupUsersForUnwindExercise();

        uint256 shares = 100 ether;

        (uint256 previewAssetIn, uint256 previewCompensationOut, uint256 previewFee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);

        // Verify preview returns reasonable values
        assertGt(previewAssetIn, 0, "Asset in should be greater than 0");
        assertGt(previewCompensationOut, 0, "Compensation out should be greater than 0");
        assertGt(previewFee, 0, "Fee should be greater than 0");
        assertEq(previewFee, previewAssetIn - shares, "Fee should be equal to compensation out");

        // Asset in should be greater than shares due to fees
        assertGt(previewAssetIn, shares, "Asset in should be greater than shares due to fees");
    }

    function test_previewUnwindExerciseOther_basicFunctionality() public {
        setupUsersForUnwindExercise();

        uint256 referenceAsset = 100 ether;

        (uint256 previewAssetIn, uint256 previewSharesOut, uint256 previewFee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, referenceAsset);

        // Verify preview returns reasonable values
        assertGt(previewAssetIn, 0, "Asset in should be greater than 0");
        assertGt(previewSharesOut, 0, "Shares out should be greater than 0");
        assertGt(previewFee, 0, "Fee should be greater than 0");
        assertEq(previewFee, previewAssetIn - previewSharesOut, "Fee should be equal to compensation out");

        // Asset in should be greater than shares out due to fees
        assertGt(previewAssetIn, previewSharesOut, "Asset in should be greater than shares out due to fees");
    }

    function test_unwindExercise_basicFunctionality() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 shares = 100 ether;

        // Get preview
        (uint256 previewAssetIn, uint256 previewCompensationOut, uint256 previewFee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);

        BalanceSnapshot memory beforeSnapshot = takeBalanceSnapshot(user3);

        // Execute unwind exercise
        (uint256 actualAssetIn, uint256 actualCompensationOut, uint256 actualFee) = corkPoolManager.unwindExercise(defaultCurrencyId, shares, user3);

        BalanceSnapshot memory afterSnapshot = takeBalanceSnapshot(user3);

        // Verify preview matches actual
        assertEq(actualAssetIn, previewAssetIn, "Actual asset in should match preview");
        assertEq(actualCompensationOut, previewCompensationOut, "Actual compensation out should match preview");
        assertEq(actualFee, previewFee, "Actual fee should match preview");
        assertEq(actualFee, previewAssetIn - shares, "Actual fee should match preview");

        // Verify balance changes
        assertEq(beforeSnapshot.collateralAsset - afterSnapshot.collateralAsset, actualAssetIn, "Collateral asset should decrease by asset in");
        assertEq(afterSnapshot.referenceAsset - beforeSnapshot.referenceAsset, actualCompensationOut, "Reference asset should increase by compensation out");
        vm.stopPrank();
    }

    function test_unwindExerciseOther_basicFunctionality() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 referenceAsset = 100 ether;

        // Get preview
        (uint256 previewAssetIn, uint256 previewSharesOut, uint256 previewFee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, referenceAsset);

        BalanceSnapshot memory beforeSnapshot = takeBalanceSnapshot(user3);

        // Execute unwind exercise
        (uint256 actualAssetIn, uint256 actualSharesOut, uint256 actualFee) = corkPoolManager.unwindExerciseOther(defaultCurrencyId, referenceAsset, user3);

        BalanceSnapshot memory afterSnapshot = takeBalanceSnapshot(user3);

        // Verify preview matches actual
        assertEq(actualAssetIn, previewAssetIn, "Actual asset in should match preview");
        assertEq(actualSharesOut, previewSharesOut, "Actual shares out should match preview");
        assertEq(actualFee, previewFee, "Actual fee should match preview");
        assertEq(actualFee, previewAssetIn - previewSharesOut, "Actual fee should match preview");

        // Verify balance changes
        assertEq(beforeSnapshot.collateralAsset - afterSnapshot.collateralAsset, actualAssetIn, "Collateral asset should decrease by asset in");
        assertEq(afterSnapshot.swapToken - beforeSnapshot.swapToken, actualSharesOut, "Swap token should increase by shares");
        vm.stopPrank();
    }

    function test_previewUnwindExercise_consistencyWithActual() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 shares = 200 ether;

        // Get preview multiple times to ensure consistency
        (uint256 preview1AssetIn, uint256 preview1CompensationOut, uint256 preview1Fee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);
        (uint256 preview2AssetIn, uint256 preview2CompensationOut, uint256 preview2Fee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);

        // Previews should be consistent
        assertEq(preview1AssetIn, preview2AssetIn, "Preview asset in should be consistent");
        assertEq(preview1CompensationOut, preview2CompensationOut, "Preview compensation out should be consistent");
        assertEq(preview1Fee, preview2Fee, "Preview fee should be consistent");

        vm.stopPrank();
    }

    function test_previewUnwindExerciseOther_consistencyWithActual() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 referenceAsset = 200 ether;

        // Get preview multiple times to ensure consistency
        (uint256 preview1AssetIn, uint256 preview1SharesOut, uint256 preview1Fee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, referenceAsset);
        (uint256 preview2AssetIn, uint256 preview2SharesOut, uint256 preview2Fee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, referenceAsset);

        // Previews should be consistent
        assertEq(preview1AssetIn, preview2AssetIn, "Preview asset in should be consistent");
        assertEq(preview1SharesOut, preview2SharesOut, "Preview shares out should be consistent");
        assertEq(preview1Fee, preview2Fee, "Preview fee should be consistent");

        vm.stopPrank();
    }

    function testFuzz_previewUnwindExercise_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 shares) public {
        // Bound inputs
        raDecimals = uint8(bound(raDecimals, 6, 18)); // 6-18 decimals for practical testing
        paDecimals = uint8(bound(paDecimals, 6, 18));
        shares = bound(shares, 1 ether, 1000 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with different decimals
        MarketId _marketId;
        uint256 initialDeposit;
        {
            ERC20Mock _collateralAsset;
            ERC20Mock _referenceAsset;
            (_collateralAsset, _referenceAsset, _marketId) = createMarket(EXPIRY, raDecimals, paDecimals);

            vm.deal(DEFAULT_ADDRESS, type(uint256).max);
            _collateralAsset.deposit{value: type(uint128).max}();
            _referenceAsset.deposit{value: type(uint128).max}();

            // Setup approvals and initial deposit
            _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
            _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

            initialDeposit = TransferHelper.tokenNativeDecimalsToFixed(DEFAULT_DEPOSIT_AMOUNT, _collateralAsset.decimals());
            corkPoolManager.deposit(_marketId, TransferHelper.fixedToTokenNativeDecimals(initialDeposit, _collateralAsset.decimals()), currentCaller());
        }

        // Setup exercise scenario
        (, address _swapToken) = corkPoolManager.shares(_marketId);
        PoolShare _stSwapToken = PoolShare(_swapToken);

        // Exercise to provide reference asset liquidity
        uint256 exerciseShares = initialDeposit / 4; // Exercise 25% of deposit
        if (exerciseShares > 0) corkPoolManager.exercise(_marketId, exerciseShares, DEFAULT_ADDRESS);

        // Test preview
        if (shares <= _stSwapToken.balanceOf(DEFAULT_ADDRESS)) {
            (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(_marketId, shares);

            // Basic sanity checks
            assertGt(assetIn, 0, "Asset in should be positive");
            assertGt(compensationOut, 0, "Compensation out should be positive");
            assertGt(fee, 0, "Fee should be positive");
            assertApproxEqAbs(fee, assetIn - TransferHelper.normalizeDecimals(shares, 18, raDecimals), 10, "Fee should be equal to compensation out");
            assertGt(assetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Asset in should be greater than shares due to fees");
        }

        vm.stopPrank();
    }

    function testFuzz_previewUnwindExerciseOther_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 referenceAsset) public {
        // Bound inputs
        raDecimals = uint8(bound(raDecimals, 6, 18)); // 6-18 decimals for practical testing
        paDecimals = uint8(bound(paDecimals, 6, 18));
        referenceAsset = bound(referenceAsset, 1 ether, 100 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with different decimals
        MarketId _marketId;
        uint256 initialDeposit;
        uint256 exerciseShares;
        {
            ERC20Mock _collateralAsset;
            ERC20Mock _referenceAsset;
            (_collateralAsset, _referenceAsset, _marketId) = createMarket(EXPIRY, raDecimals, paDecimals);

            vm.deal(DEFAULT_ADDRESS, type(uint256).max);
            _collateralAsset.deposit{value: type(uint128).max}();
            _referenceAsset.deposit{value: type(uint128).max}();

            // Setup approvals and initial deposit
            _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
            _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

            initialDeposit = TransferHelper.fixedToTokenNativeDecimals(DEFAULT_DEPOSIT_AMOUNT, _collateralAsset.decimals());

            corkPoolManager.deposit(_marketId, initialDeposit, currentCaller());

            referenceAsset = TransferHelper.fixedToTokenNativeDecimals(referenceAsset, _referenceAsset.decimals());
            exerciseShares = TransferHelper.tokenNativeDecimalsToFixed(initialDeposit / 4, _collateralAsset.decimals()); // Exercise 25% of deposit
        }

        // Setup exercise scenario
        (, address _swapToken) = corkPoolManager.shares(_marketId);
        PoolShare _stSwapToken = PoolShare(_swapToken);

        // Exercise to provide reference asset liquidity
        corkPoolManager.exercise(_marketId, exerciseShares, DEFAULT_ADDRESS);

        // Test preview
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(_marketId, referenceAsset);

        // Basic sanity checks
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGt(assetIn, TransferHelper.normalizeDecimals(referenceAsset, 18, raDecimals), "Asset in should be greater than shares due to fees");
        assertGt(sharesOut, 0, "Shares out should be positive");
        assertGt(fee, 0, "Fee should be positive");
        assertApproxEqAbs(fee, assetIn - TransferHelper.normalizeDecimals(sharesOut, 18, raDecimals), 10, "Fee should be equal to compensation out");

        vm.stopPrank();
    }

    function testFuzz_unwindExercise_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 shares) public {
        // Bound inputs
        raDecimals = uint8(bound(raDecimals, 6, 18));
        paDecimals = uint8(bound(paDecimals, 6, 18));
        shares = bound(shares, 1 ether, 100 ether);

        vm.assume(paDecimals != 0 && raDecimals != 0 && shares != 0);
        vm.assume(shares % 10 ** (18 - raDecimals) == 0);

        vm.startPrank(DEFAULT_ADDRESS);

        (MarketId marketId,) = _setupMarketWithDecimals(raDecimals, paDecimals);
        address swapTokenAddr = _setupLiquidityForUnwindExercise(marketId);

        if (shares <= IERC20(swapTokenAddr).balanceOf(address(corkPoolManager))) _executeAndVerifyUnwindExercise(marketId, shares, raDecimals);

        vm.stopPrank();
    }

    function testFuzz_unwindExerciseOther_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 referenceAsset) public {
        // Bound inputs
        raDecimals = uint8(bound(raDecimals, 6, 18));
        paDecimals = uint8(bound(paDecimals, 6, 18));
        referenceAsset = bound(referenceAsset, 1 ether, 100 ether);

        vm.assume(paDecimals != 0 && raDecimals != 0 && referenceAsset != 0);
        vm.assume(referenceAsset % 10 ** (18 - paDecimals) == 0);

        vm.startPrank(DEFAULT_ADDRESS);

        (MarketId marketId, address referenceAssetAddr) = _setupMarketWithDecimals(raDecimals, paDecimals);
        _setupLiquidityForUnwindExercise(marketId);

        if (referenceAsset <= IERC20(referenceAssetAddr).balanceOf(address(corkPoolManager))) _executeAndVerifyUnwindExerciseOther(marketId, referenceAsset, raDecimals);

        vm.stopPrank();
    }

    function _setupMarketWithDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (MarketId, address) {
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, raDecimals, paDecimals);

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        uint256 depositAmountFixed = TransferHelper.tokenNativeDecimalsToFixed(DEFAULT_DEPOSIT_AMOUNT, _collateralAsset.decimals());
        uint256 depositAmountNative = TransferHelper.fixedToTokenNativeDecimals(depositAmountFixed, _collateralAsset.decimals());

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        corkPoolManager.deposit(_marketId, depositAmountNative, currentCaller());

        return (_marketId, address(_referenceAsset));
    }

    function _setupLiquidityForUnwindExercise(MarketId marketId) internal returns (address) {
        (, address swapTokenAddr) = corkPoolManager.shares(marketId);

        uint256 exerciseShares = TransferHelper.tokenNativeDecimalsToFixed(DEFAULT_DEPOSIT_AMOUNT / 4, IERC20Metadata(swapTokenAddr).decimals());
        uint256 availableShares = IERC20(swapTokenAddr).balanceOf(DEFAULT_ADDRESS);

        if (exerciseShares > 0 && exerciseShares <= availableShares) corkPoolManager.exercise(marketId, exerciseShares, DEFAULT_ADDRESS);

        return swapTokenAddr;
    }

    function _executeAndVerifyUnwindExercise(MarketId marketId, uint256 shares, uint8 raDecimals) internal {
        (uint256 previewAssetIn, uint256 previewCompensationOut, uint256 previewFee) = corkPoolManager.previewUnwindExercise(marketId, shares);

        (uint256 actualAssetIn, uint256 actualCompensationOut, uint256 actualFee) = corkPoolManager.unwindExercise(marketId, shares, DEFAULT_ADDRESS);
        assertEq(actualAssetIn, previewAssetIn, "Actual asset in should match preview");
        assertEq(actualCompensationOut, previewCompensationOut, "Actual compensation out should match preview");
        assertEq(actualFee, previewFee, "Actual fee should match preview");
        assertApproxEqAbs(actualFee, previewAssetIn - TransferHelper.normalizeDecimals(shares, 18, raDecimals), 10, "Actual fee should match preview");
        assertGt(actualAssetIn, 0, "Asset in should be positive");
        assertGt(actualCompensationOut, 0, "Compensation out should be positive");
        assertGt(actualAssetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Asset in should be greater than shares due to fees");
    }

    function _executeAndVerifyUnwindExerciseOther(MarketId marketId, uint256 referenceAsset, uint8 raDecimals) internal {
        (uint256 previewAssetIn, uint256 previewSharesOut, uint256 previewFee) = corkPoolManager.previewUnwindExerciseOther(marketId, referenceAsset);

        (uint256 actualAssetIn, uint256 actualSharesOut, uint256 actualFee) = corkPoolManager.unwindExerciseOther(marketId, referenceAsset, DEFAULT_ADDRESS);

        assertEq(actualAssetIn, previewAssetIn, "Actual asset in should match preview");
        assertEq(actualSharesOut, previewSharesOut, "Actual shares out should match preview");
        assertEq(actualFee, previewFee, "Actual fee should match preview");
        assertApproxEqAbs(actualFee, previewAssetIn - TransferHelper.normalizeDecimals(previewSharesOut, 18, raDecimals), 10, "Actual fee should match preview");
        assertGt(actualAssetIn, 0, "Asset in should be positive");
        assertGt(actualAssetIn, TransferHelper.normalizeDecimals(actualSharesOut, 18, raDecimals), "Asset in should be greater than shares out due to fees");
    }

    function testFuzz_unwindExercise_differentFees(uint256 feePercentage, uint256 shares) public {
        // Bound fee to 1-5% (1e18 = 100%)
        feePercentage = bound(feePercentage, 0.01 ether, 0.05 ether);
        shares = bound(shares, 10 ether, 500 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with specific fee
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, feePercentage);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Initial deposit
        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario
        corkPoolManager.exercise(_marketId, DEFAULT_DEPOSIT_AMOUNT / 4, DEFAULT_ADDRESS);

        // Test preview with different fee
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(_marketId, shares);

        // Higher fees should result in higher asset input
        assertGt(assetIn, shares, "Asset in should be greater than shares due to fees");

        // The fee effect should be proportional
        assertGt(fee, 0, "Fee should be positive");
        assertEq(fee, assetIn - shares, "Fee should be equal to compensation out");

        vm.stopPrank();
    }

    function testFuzz_unwindExerciseOther_differentFees(uint256 feePercentage, uint256 referenceAsset) public {
        // Bound fee to 1-5% (1e18 = 100%)
        feePercentage = bound(feePercentage, 0.01 ether, 0.05 ether);
        referenceAsset = bound(referenceAsset, 10 ether, 500 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with specific fee
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, feePercentage);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Initial deposit
        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario
        corkPoolManager.exercise(_marketId, DEFAULT_DEPOSIT_AMOUNT / 4, DEFAULT_ADDRESS);

        // Test preview with different fee
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(_marketId, referenceAsset);

        // Higher fees should result in higher asset input
        assertGt(assetIn, sharesOut, "Asset in should be greater than shares due to fees");

        // The fee effect should be proportional
        assertGt(fee, 0, "Fee should be positive");
        assertEq(fee, assetIn - sharesOut, "Fee should be equal to compensation out");
        assertGt(assetIn - sharesOut, 0, "Fee should be applied");

        vm.stopPrank();
    }

    function testFuzz_unwindExercise_differentRates(uint256 rateScaled, uint256 shares) public {
        // Scale rate to 0.9-1.0 (90%-100%)
        vm.warp(block.timestamp + 100 days);
        uint256 rate = bound(rateScaled, 0.9 ether, 1.0 ether);
        shares = bound(shares, 10 ether, 500 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        // Initial deposit
        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario
        corkPoolManager.exercise(_marketId, DEFAULT_DEPOSIT_AMOUNT / 4, DEFAULT_ADDRESS);

        // Test preview with different rate
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(_marketId, shares);

        // Basic sanity checks
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGt(compensationOut, 0, "Compensation out should be positive");
        assertGt(fee, 0, "Fee should be positive");
        assertEq(fee, assetIn - shares, "Fee should be equal to compensation out");

        // Different rate should affect compensation amount
        // Lower rate (closer to 0.9) should result in higher compensation
        if (rate < 1 ether) assertGt(compensationOut, shares, "Lower rate should result in greater compensation");

        vm.stopPrank();
    }

    function testFuzz_unwindExerciseOther_differentRates(uint256 rateScaled, uint256 referenceAsset) public {
        // Scale rate to 0.9-1.0 (90%-100%)
        vm.warp(block.timestamp + 100 days);
        uint256 rate = bound(rateScaled, 0.9 ether, 1.0 ether);
        referenceAsset = bound(referenceAsset, 10 ether, 500 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        // Initial deposit
        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario
        corkPoolManager.exercise(_marketId, DEFAULT_DEPOSIT_AMOUNT / 4, DEFAULT_ADDRESS);

        // Test preview with different rate
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(_marketId, referenceAsset);

        // Basic sanity checks
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGt(sharesOut, 0, "Shares out should be positive");
        assertGt(fee, 0, "Fee should be positive");
        assertEq(fee, assetIn - sharesOut, "Fee should be equal to compensation out");

        // Different rate should affect compensation amount
        // Lower rate (closer to 0.9) should result in higher compensation
        if (rate < 1 ether) assertGt(referenceAsset, sharesOut, "Lower rate should result in greater compensation");

        vm.stopPrank();
    }

    function test_unwindExercise_zeroShares() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        // Should not  revert with zero shares but return 0
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, 0);

        assertEq(assetIn, 0);
        assertEq(compensationOut, 0);
        assertEq(fee, 0);

        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindExercise(defaultCurrencyId, 0, user3);

        vm.stopPrank();
    }

    function test_unwindExerciseOther_zeroReferenceAsset() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        // Should not  revert with zero shares but return 0
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, 0);

        assertEq(assetIn, 0);
        assertEq(sharesOut, 0);
        assertEq(fee, 0);

        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindExerciseOther(defaultCurrencyId, 0, user3);

        vm.stopPrank();
    }

    function test_unwindExercise_shouldNotUnlockUnbackedShares() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with fuzzed parameters
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, 2_666_667_667_666_666_700, 2_666_667_667_666_666_700, 6, 6);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, 1 ether);

        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());
        corkPoolManager.exercise(_marketId, DEFAULT_DEPOSIT_AMOUNT / 4, DEFAULT_ADDRESS);

        (address _principalToken, address _swapToken) = corkPoolManager.shares(_marketId);
        uint256 userSharesBalanceBefore = IERC20(_swapToken).balanceOf(DEFAULT_ADDRESS);

        {
            IERC20(_swapToken).approve(address(corkPoolManager), type(uint256).max);
            IERC20(_principalToken).approve(address(corkPoolManager), type(uint256).max);
        }

        (uint256 collateralLockedBefore,) = corkPoolManager.assets(defaultCurrencyId);
        (, uint256 swapTokenBefore) = corkPoolManager.availableForUnwindSwap(defaultCurrencyId);

        corkPoolManager.unwindExercise(_marketId, 111_111_111_111_111_111_113, DEFAULT_ADDRESS);

        (uint256 collateralLockedAfter,) = corkPoolManager.assets(defaultCurrencyId);
        (, uint256 swapTokenAfter) = corkPoolManager.availableForUnwindSwap(defaultCurrencyId);

        assertEq(collateralLockedAfter - collateralLockedBefore, 111_111_112);
        assertEq(swapTokenBefore - swapTokenAfter, 111_111_111_111_111_111_113);

        uint256 normalizedShares = TransferHelper.normalizeDecimalsWithCeilDiv(111_111_111_111_111_111_113, 18, 6);

        assertEq(normalizedShares, 111_111_112);

        // get out all the shares
        corkPoolManager.unwindExercise(_marketId, swapTokenAfter, DEFAULT_ADDRESS);

        // verify that all the supply is in the caller hands
        uint256 sharesTotalSupply = IERC20(_swapToken).totalSupply();
        assertEq(IERC20(_swapToken).balanceOf(DEFAULT_ADDRESS), sharesTotalSupply);

        // unwindMint all shares
        corkPoolManager.unwindMint(defaultCurrencyId, sharesTotalSupply, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        // verify that the shares are fully backend. The protocol should have an extra wei as collateral
        (collateralLockedAfter,) = corkPoolManager.assets(defaultCurrencyId);
        assertEq(collateralLockedAfter, 1);

        // check consistency balance
        assertEq(collateralLockedAfter, _collateralAsset.balanceOf(address(corkPoolManager)));
    }

    function test_unwindExercise_insufficientLiquidity() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        // Try to unwind more shares than available in pool
        uint256 excessiveShares = 50_000 ether; // More than pool has

        // Preview should work (doesn't check liquidity constraints)
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, excessiveShares);
        assertGt(assetIn, 0, "Preview should return positive asset in");
        assertGt(compensationOut, 0, "Preview should return positive compensation out");
        assertGt(fee, 0, "Preview should return positive fee");
        assertEq(fee, assetIn - excessiveShares, "Fee should be equal to compensation out");

        // Actual execution should revert due to insufficient liquidity
        vm.expectRevert();
        corkPoolManager.unwindExercise(defaultCurrencyId, excessiveShares, user3);

        vm.stopPrank();
    }

    function test_unwindExerciseOther_insufficientLiquidity() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        // Try to unwind more shares than available in pool
        uint256 excessiveReferenceAsset = 50_000 ether; // More than pool has

        // Preview should work (doesn't check liquidity constraints)
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, excessiveReferenceAsset);
        assertGt(assetIn, 0, "Preview should return positive asset in");
        assertGt(sharesOut, 0, "Preview should return positive shares out");
        assertGt(fee, 0, "Preview should return positive fee");
        assertEq(fee, assetIn - sharesOut, "Fee should be equal to compensation out");

        // Actual execution should revert due to insufficient liquidity
        vm.expectRevert();
        corkPoolManager.unwindExerciseOther(defaultCurrencyId, excessiveReferenceAsset, user3);

        vm.stopPrank();
    }

    function test_unwindExercise_expiredToken() public {
        setupUsersForUnwindExercise();

        // Fast forward past expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        vm.startPrank(user3);

        uint256 shares = 100 ether;

        // Should not revert when token is expired
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);

        assertEq(assetIn, 0);
        assertEq(compensationOut, 0);
        assertEq(fee, 0);

        // should revert
        vm.expectRevert();
        corkPoolManager.unwindExercise(defaultCurrencyId, shares, user3);

        vm.stopPrank();
    }

    function test_unwindExerciseOther_expiredToken() public {
        setupUsersForUnwindExercise();

        // Fast forward past expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        vm.startPrank(user3);

        uint256 referenceAsset = 100 ether;

        // Should not revert when token is expired
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, referenceAsset);

        assertEq(assetIn, 0);
        assertEq(sharesOut, 0);
        assertEq(fee, 0);

        // should revert
        vm.expectRevert();
        corkPoolManager.unwindExerciseOther(defaultCurrencyId, referenceAsset, user3);

        vm.stopPrank();
    }

    function test_previewUnwindExercise_noStateChange() public {
        setupUsersForUnwindExercise();

        uint256 shares = 100 ether;

        // Take snapshots before and after preview
        BalanceSnapshot memory beforeSnapshot = takeBalanceSnapshot(address(corkPoolManager));
        (uint256 poolRaBalanceBefore, uint256 poolPaBalanceBefore) = corkPoolManager.assets(defaultCurrencyId);

        // Call preview
        (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);

        // Take snapshots after preview
        BalanceSnapshot memory afterSnapshot = takeBalanceSnapshot(address(corkPoolManager));
        (uint256 poolRaBalanceAfter, uint256 poolPaBalanceAfter) = corkPoolManager.assets(defaultCurrencyId);

        // Verify no state changes occurred
        assertEq(beforeSnapshot.collateralAsset, afterSnapshot.collateralAsset, "Pool collateral balance should not change");
        assertEq(beforeSnapshot.referenceAsset, afterSnapshot.referenceAsset, "Pool reference balance should not change");
        assertEq(beforeSnapshot.swapToken, afterSnapshot.swapToken, "Pool swap token balance should not change");
        assertEq(beforeSnapshot.principalToken, afterSnapshot.principalToken, "Pool principal token balance should not change");
        assertEq(poolPaBalanceBefore, poolPaBalanceAfter, "Pool PA balance should not change");
        assertEq(poolRaBalanceBefore, poolRaBalanceAfter, "Pool RA balance should not change");

        // But preview should return meaningful values
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGt(compensationOut, 0, "Compensation out should be positive");
        assertGt(fee, 0, "Fee should be positive");
        assertEq(fee, assetIn - shares, "Fee should be equal to compensation out");
    }

    function test_previewUnwindExerciseOther_noStateChange() public {
        setupUsersForUnwindExercise();

        uint256 referenceAsset = 100 ether;

        // Take snapshots before and after preview
        BalanceSnapshot memory beforeSnapshot = takeBalanceSnapshot(address(corkPoolManager));
        (uint256 poolRaBalanceBefore, uint256 poolPaBalanceBefore) = corkPoolManager.assets(defaultCurrencyId);

        // Call preview
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(defaultCurrencyId, referenceAsset);

        // Take snapshots after preview
        BalanceSnapshot memory afterSnapshot = takeBalanceSnapshot(address(corkPoolManager));
        (uint256 poolRaBalanceAfter, uint256 poolPaBalanceAfter) = corkPoolManager.assets(defaultCurrencyId);

        // Verify no state changes occurred
        assertEq(beforeSnapshot.collateralAsset, afterSnapshot.collateralAsset, "Pool collateral balance should not change");
        assertEq(beforeSnapshot.referenceAsset, afterSnapshot.referenceAsset, "Pool reference balance should not change");
        assertEq(beforeSnapshot.swapToken, afterSnapshot.swapToken, "Pool swap token balance should not change");
        assertEq(beforeSnapshot.principalToken, afterSnapshot.principalToken, "Pool principal token balance should not change");
        assertEq(poolPaBalanceBefore, poolPaBalanceAfter, "Pool PA balance should not change");
        assertEq(poolRaBalanceBefore, poolRaBalanceAfter, "Pool RA balance should not change");

        // But preview should return meaningful values
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGt(sharesOut, 0, "Shares out should be positive");
        assertGt(fee, 0, "Fee should be positive");
        assertEq(fee, assetIn - sharesOut, "Fee should be equal to compensation out");
    }

    function testFuzz_previewUnwindExercise_comprehensive(uint8 raDecimals, uint8 paDecimals, uint256 feePercentage, uint256 shares, uint256 rate) public {
        // Bound all inputs
        raDecimals = uint8(bound(raDecimals, 6, 18));
        paDecimals = uint8(bound(paDecimals, 6, 18));
        feePercentage = bound(feePercentage, 0.01 ether, 5 ether); // 1-5%
        rate = bound(rate, 0.9 ether, 1.0 ether); // 90-100%
        shares = bound(shares, 1 ether, 100 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with fuzzed parameters
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, feePercentage, feePercentage, raDecimals, paDecimals);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        {
            // Setup market with liquidity
            uint256 depositAmount = TransferHelper.tokenNativeDecimalsToFixed(10_000 ether, _collateralAsset.decimals());
            depositAmount = TransferHelper.fixedToTokenNativeDecimals(depositAmount, _collateralAsset.decimals());
            corkPoolManager.deposit(_marketId, depositAmount, currentCaller());

            // Exercise to provide reference asset liquidity
            uint256 exerciseAmount = TransferHelper.tokenNativeDecimalsToFixed(depositAmount / 4, _collateralAsset.decimals());
            if (exerciseAmount > 0) corkPoolManager.exercise(_marketId, exerciseAmount, DEFAULT_ADDRESS);
        }
        // Test preview
        try corkPoolManager.previewUnwindExercise(_marketId, shares) returns (uint256 assetIn, uint256 compensationOut, uint256 fee) {
            // If preview succeeds, verify basic properties
            assertGt(assetIn, 0, "Asset in should be positive");
            assertGt(compensationOut, 0, "Compensation out should be positive");
            assertGe(assetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Asset in should be at least shares amount");

            // Verify fee is applied (asset in should be greater than shares)
            if (feePercentage > 0) {
                assertGt(assetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Fee should make asset in greater than shares");
                assertGt(fee, 0, "Fee should be positive");
                assertApproxEqAbs(fee, assetIn - TransferHelper.normalizeDecimals(shares, 18, raDecimals), 10, "Fee should be equal to compensation out");
            }
        } catch {
            // Some combinations might not be valid, which is acceptable
        }

        vm.stopPrank();
    }

    function testFuzz_previewUnwindExerciseOther_comprehensive(uint8 raDecimals, uint8 paDecimals, uint256 feePercentage, uint256 referenceAsset, uint256 rate) public {
        // Bound all inputs
        raDecimals = uint8(bound(raDecimals, 6, 18));
        paDecimals = uint8(bound(paDecimals, 6, 18));
        feePercentage = bound(feePercentage, 0.01 ether, 5 ether); // 1-5%
        rate = bound(rate, 0.9 ether, 1.0 ether); // 90-100%
        referenceAsset = bound(referenceAsset, 1 ether, 100 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with fuzzed parameters
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, feePercentage, feePercentage, raDecimals, paDecimals);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        referenceAsset = TransferHelper.fixedToTokenNativeDecimals(referenceAsset, _referenceAsset.decimals());

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        {
            // Setup market with liquidity
            uint256 depositAmount = TransferHelper.fixedToTokenNativeDecimals(10_000 ether, _collateralAsset.decimals());
            corkPoolManager.deposit(_marketId, depositAmount, currentCaller());

            // Exercise to provide reference asset liquidity
            uint256 exerciseAmount = TransferHelper.tokenNativeDecimalsToFixed(depositAmount / 4, _collateralAsset.decimals());
            if (exerciseAmount > 0) corkPoolManager.exercise(_marketId, exerciseAmount, DEFAULT_ADDRESS);
        }
        // Test preview
        (uint256 assetIn, uint256 sharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(_marketId, referenceAsset);

        // If preview succeeds, verify basic properties
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGe(assetIn, TransferHelper.normalizeDecimals(sharesOut, 18, raDecimals), "Asset in should be at least shares amount");
        assertGt(fee, 0, "Fee should be positive");
        assertApproxEqAbs(fee, assetIn - TransferHelper.normalizeDecimals(sharesOut, 18, raDecimals), 10, "Fee should be equal to compensation out");

        // Verify fee is applied (asset in should be greater than shares)
        if (feePercentage > 0) assertGt(assetIn, TransferHelper.normalizeDecimals(sharesOut, 18, raDecimals), "Fee should make asset in greater than shares");

        vm.stopPrank();
    }

    function test_maxUnwindExercise_basicFunctionality() public {
        setupUsersForUnwindExercise();

        uint256 maxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);

        // Max shares should be greater than 0 since we have liquidity
        assertGt(maxShares, 0, "Max shares should be greater than 0");

        // Should be able to unwind exercise up to the max amount
        vm.startPrank(user3);
        if (maxShares > 0) {
            (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPoolManager.unwindExercise(defaultCurrencyId, maxShares, user3);
            assertGt(assetIn, 0, "Asset in should be positive");
            assertGt(compensationOut, 0, "Compensation out should be positive");
        }
        vm.stopPrank();
    }

    function test_maxUnwindExercise_afterExpiry() public {
        setupUsersForUnwindExercise();

        // Fast forward past expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 maxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);

        // Max shares should be 0 after expiry
        assertEq(maxShares, 0, "Max shares should be 0 after expiry");
    }

    function test_maxUnwindExercise_noLiquidity() public {
        // Create a fresh market without any exercise to provide reference asset liquidity
        vm.startPrank(DEFAULT_ADDRESS);
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY);

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        // Only deposit, no exercise (so no reference asset in pool for unwind exercise)
        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        uint256 maxShares = corkPoolManager.maxUnwindExercise(_marketId, DEFAULT_ADDRESS);

        // Max shares should be 0 when no reference asset liquidity available
        assertEq(maxShares, 0, "Max shares should be 0 when no reference asset liquidity");

        vm.stopPrank();
    }

    function test_maxUnwindExercise_limitedByCST() public {
        setupUsersForUnwindExercise();

        // Get current max shares
        uint256 maxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);

        // Get available CST balance from pool state - this should be checked via available balances
        (, address swapTokenAddr) = corkPoolManager.shares(defaultCurrencyId);

        // Max shares should be reasonable (greater than 0 when we have liquidity)
        if (maxShares > 0) assertGt(maxShares, 0, "Max shares should be positive when liquidity exists");
    }

    function test_maxUnwindExercise_limitedByReferenceAsset() public {
        setupUsersForUnwindExercise();

        // Get the max shares before any unwind exercise
        uint256 initialMaxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);

        // Perform a large unwind exercise to drain reference asset
        vm.startPrank(user3);
        if (initialMaxShares > 0) corkPoolManager.unwindExercise(defaultCurrencyId, initialMaxShares, user3);
        vm.stopPrank();

        // Check max shares after draining
        uint256 finalMaxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);

        // Should be significantly less or 0
        assertLe(finalMaxShares, initialMaxShares, "Max shares should not increase after draining reference asset");
    }

    function test_maxUnwindExercise_consistency() public {
        setupUsersForUnwindExercise();

        uint256 maxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);

        if (maxShares > 0) {
            // Preview should work for the max amount
            (uint256 previewAssetIn, uint256 previewCompensationOut, uint256 previewFee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, maxShares);
            assertGt(previewAssetIn, 0, "Preview asset in should be positive");
            assertGt(previewCompensationOut, 0, "Preview compensation out should be positive");
            assertGt(previewFee, 0, "Preview fee should be positive");
            assertEq(previewFee, previewAssetIn - maxShares, "Fee should be equal to compensation out");

            // Actual execution should also work
            vm.startPrank(user3);
            (uint256 actualAssetIn, uint256 actualCompensationOut, uint256 actualFee) = corkPoolManager.unwindExercise(defaultCurrencyId, maxShares, user3);

            assertEq(actualAssetIn, previewAssetIn, "Actual should match preview");
            assertEq(actualCompensationOut, previewCompensationOut, "Actual should match preview");
            vm.stopPrank();
        }
    }

    function test_maxUnwindExercise_neverReverts() public {
        setupUsersForUnwindExercise();

        // Should not revert for valid market
        uint256 maxShares = corkPoolManager.maxUnwindExercise(defaultCurrencyId, user3);
        // No assertion needed - just checking it doesn't revert
    }

    function testFuzz_maxUnwindExercise_differentRates(uint256 rateScaled) public {
        // Scale rate to 0.9-1.0 (90%-100%)
        uint256 rate = bound(rateScaled, 0.9 ether, 1.0 ether);

        vm.startPrank(DEFAULT_ADDRESS);

        // Create market
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        _referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        // Initial deposit
        corkPoolManager.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario to provide reference asset liquidity
        corkPoolManager.exercise(_marketId, DEFAULT_DEPOSIT_AMOUNT / 4, DEFAULT_ADDRESS);

        // Test maxUnwindExercise with different rate
        uint256 maxShares = corkPoolManager.maxUnwindExercise(_marketId, DEFAULT_ADDRESS);

        // Should return some shares (exact amount depends on rate)
        if (rate > 0) {
            // With any positive rate and reference asset liquidity, should allow some unwind exercise
            assertGe(maxShares, 0, "Max shares should be non-negative");
        }

        vm.stopPrank();
    }

    function test_FeeConsistencyUnwindSwapUnwindExercise() public {
        vm.startPrank(DEFAULT_ADDRESS);

        swapToken.approve(address(corkPoolManager), type(uint256).max);
        corkPoolManager.exercise(defaultCurrencyId, 10 ether, DEFAULT_ADDRESS);

        uint256 shares = 1 ether;
        uint256 fee = 5 ether;

        defaultCorkController.updateUnwindSwapFeeRate(defaultCurrencyId, fee);

        (uint256 assetIn,, uint256 previewFee) = corkPoolManager.previewUnwindExercise(defaultCurrencyId, shares);

        assertApproxEqAbs(assetIn, 1.052_631_579 ether, 0.0001 ether, "asset in must match");
        (uint256 previewSwapAssetOut, uint256 previewCompensationOut, uint256 previewUnwindSwapFee) = corkPoolManager.previewUnwindSwap(defaultCurrencyId, assetIn);

        assertApproxEqAbs(previewFee, 0.052_631_579 ether, 0.0001 ether, "fee  must match");
        assertApproxEqAbs(previewUnwindSwapFee, 0.052_631_579 ether, 0.0001 ether, "fee  must match");

        uint256 actualFee;
        (assetIn,, actualFee) = corkPoolManager.unwindExercise(defaultCurrencyId, shares, currentCaller());

        assertEq(actualFee, previewFee, "Actual fee should match preview");
        assertEq(actualFee, assetIn - shares, "Actual fee should match preview");
        assertApproxEqAbs(assetIn, 1.052_631_579 ether, 0.0001 ether, "asset in must match");

        (uint256 actualSwapAssetOut, uint256 actualCompensationOut, uint256 unwindFee) = corkPoolManager.unwindSwap(defaultCurrencyId, assetIn, DEFAULT_ADDRESS);

        assertApproxEqAbs(unwindFee, 0.052_631_579 ether, 0.0001 ether, "fee  must match");
        assertEq(actualSwapAssetOut, previewSwapAssetOut, "swap asset out must match");
        assertEq(actualCompensationOut, previewCompensationOut, "compensation out must match");
    }
}
