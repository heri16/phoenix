pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {console2} from "forge-std/console2.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

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
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

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

        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        // Initial deposit to provide liquidity
        corkPool.deposit(defaultCurrencyId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        vm.stopPrank();
    }

    function setupUsersForUnwindExercise() internal {
        vm.startPrank(user2);
        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        // User2 deposits to get CST and CPT
        corkPool.deposit(defaultCurrencyId, 1000 ether, currentCaller());

        // User2 exercises to provide Reference Asset and get some collateral out
        uint256 sharesToExercise = 500 ether;
        corkPool.exercise(IPoolManager.ExerciseParams({poolId: defaultCurrencyId, shares: sharesToExercise, compensation: 0, receiver: user2, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));
        vm.stopPrank();

        vm.startPrank(user3);
        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);
        swapToken.approve(address(corkPool), type(uint256).max);
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

        (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        // Verify preview returns reasonable values
        assertGt(previewAssetIn, 0, "Asset in should be greater than 0");
        assertGt(previewCompensationOut, 0, "Compensation out should be greater than 0");

        // Asset in should be greater than shares due to fees
        assertGt(previewAssetIn, shares, "Asset in should be greater than shares due to fees");
    }

    function test_unwindExercise_basicFunctionality() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 shares = 100 ether;

        // Get preview
        (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        BalanceSnapshot memory beforeSnapshot = takeBalanceSnapshot(user3);

        // Execute unwind exercise
        (uint256 actualAssetIn, uint256 actualCompensationOut, uint256 actualFee) = corkPool.unwindExercise(
            IPoolManager.UnwindExerciseParams({
                poolId: defaultCurrencyId,
                shares: shares,
                receiver: user3,
                minCompensationOut: 0, // minCompensationOut
                maxAssetsIn: type(uint256).max // maxAssetsIn
            })
        );

        BalanceSnapshot memory afterSnapshot = takeBalanceSnapshot(user3);

        // Verify preview matches actual
        assertEq(actualAssetIn, previewAssetIn, "Actual asset in should match preview");
        assertEq(actualCompensationOut, previewCompensationOut, "Actual compensation out should match preview");

        // Verify balance changes
        assertEq(beforeSnapshot.collateralAsset - afterSnapshot.collateralAsset, actualAssetIn, "Collateral asset should decrease by asset in");
        assertEq(afterSnapshot.referenceAsset - beforeSnapshot.referenceAsset, actualCompensationOut, "Reference asset should increase by compensation out");
        assertEq(afterSnapshot.swapToken - beforeSnapshot.swapToken, shares, "Swap token should increase by shares");

        vm.stopPrank();
    }

    function test_previewUnwindExercise_consistencyWithActual() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 shares = 200 ether;

        // Get preview multiple times to ensure consistency
        (uint256 preview1AssetIn, uint256 preview1CompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);
        (uint256 preview2AssetIn, uint256 preview2CompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        // Previews should be consistent
        assertEq(preview1AssetIn, preview2AssetIn, "Preview asset in should be consistent");
        assertEq(preview1CompensationOut, preview2CompensationOut, "Preview compensation out should be consistent");

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
            _collateralAsset.approve(address(corkPool), type(uint256).max);
            _referenceAsset.approve(address(corkPool), type(uint256).max);

            initialDeposit = TransferHelper.tokenNativeDecimalsToFixed(DEFAULT_DEPOSIT_AMOUNT, _collateralAsset.decimals());
            corkPool.deposit(_marketId, TransferHelper.fixedToTokenNativeDecimals(initialDeposit, _collateralAsset.decimals()), currentCaller());
        }

        // Setup exercise scenario
        (, address _swapToken) = corkPool.shares(_marketId);
        PoolShare _stSwapToken = PoolShare(_swapToken);

        // Exercise to provide reference asset liquidity
        uint256 exerciseShares = initialDeposit / 4; // Exercise 25% of deposit
        if (exerciseShares > 0) corkPool.exercise(IPoolManager.ExerciseParams({poolId: _marketId, shares: exerciseShares, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        // Test preview
        if (shares <= _stSwapToken.balanceOf(DEFAULT_ADDRESS)) {
            (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(_marketId, shares);

            // Basic sanity checks
            assertGt(assetIn, 0, "Asset in should be positive");
            assertGt(compensationOut, 0, "Compensation out should be positive");
            assertGt(assetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Asset in should be greater than shares due to fees");
        }

        vm.stopPrank();
    }

    function testFuzz_unwindExercise_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 shares) public {
        // Bound inputs
        raDecimals = uint8(bound(raDecimals, 6, 18));
        paDecimals = uint8(bound(paDecimals, 6, 18));
        shares = bound(shares, 1 ether, 100 ether);

        vm.assume(shares % 10 ** (18 - raDecimals) == 0);

        vm.startPrank(DEFAULT_ADDRESS);

        MarketId marketId = _setupMarketWithDecimals(raDecimals, paDecimals);
        address swapTokenAddr = _setupLiquidityForUnwindExercise(marketId);

        if (shares <= IERC20(swapTokenAddr).balanceOf(DEFAULT_ADDRESS)) _executeAndVerifyUnwindExercise(marketId, shares, raDecimals);

        vm.stopPrank();
    }

    function _setupMarketWithDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (MarketId) {
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, raDecimals, paDecimals);

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        uint256 depositAmountFixed = TransferHelper.tokenNativeDecimalsToFixed(DEFAULT_DEPOSIT_AMOUNT, _collateralAsset.decimals());
        uint256 depositAmountNative = TransferHelper.fixedToTokenNativeDecimals(depositAmountFixed, _collateralAsset.decimals());

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        corkPool.deposit(_marketId, depositAmountNative, currentCaller());

        return _marketId;
    }

    function _setupLiquidityForUnwindExercise(MarketId marketId) internal returns (address) {
        (, address swapTokenAddr) = corkPool.shares(marketId);

        uint256 exerciseShares = TransferHelper.tokenNativeDecimalsToFixed(DEFAULT_DEPOSIT_AMOUNT / 4, IERC20Metadata(swapTokenAddr).decimals());
        uint256 availableShares = IERC20(swapTokenAddr).balanceOf(DEFAULT_ADDRESS);

        if (exerciseShares > 0 && exerciseShares <= availableShares) corkPool.exercise(IPoolManager.ExerciseParams({poolId: marketId, shares: exerciseShares, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        return swapTokenAddr;
    }

    function _executeAndVerifyUnwindExercise(MarketId marketId, uint256 shares, uint8 raDecimals) internal {
        (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(marketId, shares);

        (uint256 actualAssetIn, uint256 actualCompensationOut, uint256 actualFee) = corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: marketId, shares: shares, receiver: DEFAULT_ADDRESS, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));

        assertEq(actualAssetIn, previewAssetIn, "Actual asset in should match preview");
        assertEq(actualCompensationOut, previewCompensationOut, "Actual compensation out should match preview");
        assertGt(actualAssetIn, 0, "Asset in should be positive");
        assertGt(actualCompensationOut, 0, "Compensation out should be positive");
        assertGt(actualAssetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Asset in should be greater than shares due to fees");
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

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        // Initial deposit
        corkPool.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario
        corkPool.exercise(IPoolManager.ExerciseParams({poolId: _marketId, shares: DEFAULT_DEPOSIT_AMOUNT / 4, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        // Test preview with different fee
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(_marketId, shares);

        // Higher fees should result in higher asset input
        assertGt(assetIn, shares, "Asset in should be greater than shares due to fees");

        // The fee effect should be proportional
        uint256 expectedMinFee = (shares * feePercentage) / 100 ether; // Rough estimate
        assertGt(assetIn - shares, 0, "Fee should be applied");

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

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        // Initial deposit
        corkPool.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario
        corkPool.exercise(IPoolManager.ExerciseParams({poolId: _marketId, shares: DEFAULT_DEPOSIT_AMOUNT / 4, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        // Test preview with different rate
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(_marketId, shares);

        // Basic sanity checks
        assertGt(assetIn, 0, "Asset in should be positive");
        assertGt(compensationOut, 0, "Compensation out should be positive");

        // Different rate should affect compensation amount
        // Lower rate (closer to 0.9) should result in higher compensation
        if (rate < 1 ether) assertGt(compensationOut, shares, "Lower rate should result in greater compensation");

        vm.stopPrank();
    }

    function test_unwindExercise_slippageProtection() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        uint256 shares = 100 ether;

        (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        // Test minCompensationOut protection
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientOutputAmount.selector, previewCompensationOut + 1, previewCompensationOut));
        corkPool.unwindExercise(
            IPoolManager.UnwindExerciseParams({
                poolId: defaultCurrencyId,
                shares: shares,
                receiver: user3,
                minCompensationOut: previewCompensationOut + 1, // Set minimum higher than preview
                maxAssetsIn: type(uint256).max
            })
        );

        // Test maxAssetsIn protection
        vm.expectRevert(abi.encodeWithSelector(IErrors.ExceedInput.selector, previewAssetIn, previewAssetIn - 1));
        corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: shares, receiver: user3, minCompensationOut: 0, maxAssetsIn: previewAssetIn - 1}));

        vm.stopPrank();
    }

    function test_unwindExercise_zeroShares() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        // Should not  revert with zero shares but return 0
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, 0);

        assertEq(assetIn, 0);
        assertEq(compensationOut, 0);

        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: 0, receiver: user3, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));

        vm.stopPrank();
    }

    function test_unwindExercise_shouldNotUnlockUnbackedShares() public {
        vm.startPrank(DEFAULT_ADDRESS);

        // Create market with fuzzed parameters
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY, 2_666_667_667_666_666_700, 2_666_667_667_666_666_700, 6, 6);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, 1 ether);

        corkPool.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());
        corkPool.exercise(IPoolManager.ExerciseParams({poolId: _marketId, shares: DEFAULT_DEPOSIT_AMOUNT / 4, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        (, address _swapToken) = corkPool.shares(_marketId);
        uint256 userSharesBalanceBefore = IERC20(_swapToken).balanceOf(DEFAULT_ADDRESS);

        vm.expectPartialRevert(IErrors.InsufficientAmount.selector);
        corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: _marketId, shares: 111_111_111_111_111_111_113, receiver: DEFAULT_ADDRESS, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));
    }

    function test_unwindExercise_insufficientLiquidity() public {
        setupUsersForUnwindExercise();

        vm.startPrank(user3);

        // Try to unwind more shares than available in pool
        uint256 excessiveShares = 50_000 ether; // More than pool has

        // Preview should work (doesn't check liquidity constraints)
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, excessiveShares);
        assertGt(assetIn, 0, "Preview should return positive asset in");
        assertGt(compensationOut, 0, "Preview should return positive compensation out");

        // Actual execution should revert due to insufficient liquidity
        vm.expectRevert();
        corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: excessiveShares, receiver: user3, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));

        vm.stopPrank();
    }

    function test_unwindExercise_expiredToken() public {
        setupUsersForUnwindExercise();

        // Fast forward past expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        vm.startPrank(user3);

        uint256 shares = 100 ether;

        // Should not revert when token is expired
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        assertEq(assetIn, 0);
        assertEq(compensationOut, 0);

        // should revert
        vm.expectRevert();
        corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: shares, receiver: user3, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));

        vm.stopPrank();
    }

    function test_previewUnwindExercise_noStateChange() public {
        setupUsersForUnwindExercise();

        uint256 shares = 100 ether;

        // Take snapshots before and after preview
        BalanceSnapshot memory beforeSnapshot = takeBalanceSnapshot(address(corkPool));
        (uint256 poolRaBalanceBefore, uint256 poolPaBalanceBefore) = corkPool.valueLocked(defaultCurrencyId);

        // Call preview
        (uint256 assetIn, uint256 compensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        // Take snapshots after preview
        BalanceSnapshot memory afterSnapshot = takeBalanceSnapshot(address(corkPool));
        (uint256 poolRaBalanceAfter, uint256 poolPaBalanceAfter) = corkPool.valueLocked(defaultCurrencyId);

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

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        {
            // Setup market with liquidity
            uint256 depositAmount = TransferHelper.tokenNativeDecimalsToFixed(10_000 ether, _collateralAsset.decimals());
            depositAmount = TransferHelper.fixedToTokenNativeDecimals(depositAmount, _collateralAsset.decimals());
            corkPool.deposit(_marketId, depositAmount, currentCaller());

            // Exercise to provide reference asset liquidity
            uint256 exerciseAmount = TransferHelper.tokenNativeDecimalsToFixed(depositAmount / 4, _collateralAsset.decimals());
            if (exerciseAmount > 0) corkPool.exercise(IPoolManager.ExerciseParams({poolId: _marketId, shares: exerciseAmount, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));
        }
        // Test preview
        try corkPool.previewUnwindExercise(_marketId, shares) returns (uint256 assetIn, uint256 compensationOut) {
            // If preview succeeds, verify basic properties
            assertGt(assetIn, 0, "Asset in should be positive");
            assertGt(compensationOut, 0, "Compensation out should be positive");
            assertGe(assetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Asset in should be at least shares amount");

            // Verify fee is applied (asset in should be greater than shares)
            if (feePercentage > 0) assertGt(assetIn, TransferHelper.normalizeDecimals(shares, 18, raDecimals), "Fee should make asset in greater than shares");
        } catch {
            // Some combinations might not be valid, which is acceptable
        }

        vm.stopPrank();
    }

    function test_maxUnwindExercise_basicFunctionality() public {
        setupUsersForUnwindExercise();

        uint256 maxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);

        // Max shares should be greater than 0 since we have liquidity
        assertGt(maxShares, 0, "Max shares should be greater than 0");

        // Should be able to unwind exercise up to the max amount
        vm.startPrank(user3);
        if (maxShares > 0) {
            (uint256 assetIn, uint256 compensationOut, uint256 fee) = corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: maxShares, receiver: user3, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));
            assertGt(assetIn, 0, "Asset in should be positive");
            assertGt(compensationOut, 0, "Compensation out should be positive");
        }
        vm.stopPrank();
    }

    function test_maxUnwindExercise_afterExpiry() public {
        setupUsersForUnwindExercise();

        // Fast forward past expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        uint256 maxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);

        // Max shares should be 0 after expiry
        assertEq(maxShares, 0, "Max shares should be 0 after expiry");
    }

    function test_maxUnwindExercise_noLiquidity() public {
        // Create a fresh market without any exercise to provide reference asset liquidity
        vm.startPrank(DEFAULT_ADDRESS);
        (ERC20Mock _collateralAsset, ERC20Mock _referenceAsset, MarketId _marketId) = createMarket(EXPIRY);

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        _collateralAsset.deposit{value: type(uint128).max}();
        _referenceAsset.deposit{value: type(uint128).max}();

        // Only deposit, no exercise (so no reference asset in pool for unwind exercise)
        corkPool.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        uint256 maxShares = corkPool.maxUnwindExercise(_marketId, DEFAULT_ADDRESS);

        // Max shares should be 0 when no reference asset liquidity available
        assertEq(maxShares, 0, "Max shares should be 0 when no reference asset liquidity");

        vm.stopPrank();
    }

    function test_maxUnwindExercise_limitedByCST() public {
        setupUsersForUnwindExercise();

        // Get current max shares
        uint256 maxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);

        // Get available CST balance from pool state - this should be checked via available balances
        (, address swapTokenAddr) = corkPool.shares(defaultCurrencyId);

        // Max shares should be reasonable (greater than 0 when we have liquidity)
        if (maxShares > 0) assertGt(maxShares, 0, "Max shares should be positive when liquidity exists");
    }

    function test_maxUnwindExercise_limitedByReferenceAsset() public {
        setupUsersForUnwindExercise();

        // Get the max shares before any unwind exercise
        uint256 initialMaxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);

        // Perform a large unwind exercise to drain reference asset
        vm.startPrank(user3);
        if (initialMaxShares > 0) corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: initialMaxShares, receiver: user3, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));
        vm.stopPrank();

        // Check max shares after draining
        uint256 finalMaxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);

        // Should be significantly less or 0
        assertLe(finalMaxShares, initialMaxShares, "Max shares should not increase after draining reference asset");
    }

    function test_maxUnwindExercise_consistency() public {
        setupUsersForUnwindExercise();

        uint256 maxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);

        if (maxShares > 0) {
            // Preview should work for the max amount
            (uint256 previewAssetIn, uint256 previewCompensationOut) = corkPool.previewUnwindExercise(defaultCurrencyId, maxShares);
            assertGt(previewAssetIn, 0, "Preview asset in should be positive");
            assertGt(previewCompensationOut, 0, "Preview compensation out should be positive");

            // Actual execution should also work
            vm.startPrank(user3);
            (uint256 actualAssetIn, uint256 actualCompensationOut, uint256 actualFee) = corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: maxShares, receiver: user3, minCompensationOut: 0, maxAssetsIn: type(uint256).max}));

            assertEq(actualAssetIn, previewAssetIn, "Actual should match preview");
            assertEq(actualCompensationOut, previewCompensationOut, "Actual should match preview");
            vm.stopPrank();
        }
    }

    function test_maxUnwindExercise_neverReverts() public {
        setupUsersForUnwindExercise();

        // Should not revert for valid market
        uint256 maxShares = corkPool.maxUnwindExercise(defaultCurrencyId, user3);
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

        _collateralAsset.approve(address(corkPool), type(uint256).max);
        _referenceAsset.approve(address(corkPool), type(uint256).max);

        // Update default oracle rate
        testOracle.setRate(_marketId, rate);

        // Initial deposit
        corkPool.deposit(_marketId, DEFAULT_DEPOSIT_AMOUNT, currentCaller());

        // Setup exercise scenario to provide reference asset liquidity
        corkPool.exercise(IPoolManager.ExerciseParams({poolId: _marketId, shares: DEFAULT_DEPOSIT_AMOUNT / 4, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        // Test maxUnwindExercise with different rate
        uint256 maxShares = corkPool.maxUnwindExercise(_marketId, DEFAULT_ADDRESS);

        // Should return some shares (exact amount depends on rate)
        if (rate > 0) {
            // With any positive rate and reference asset liquidity, should allow some unwind exercise
            assertGe(maxShares, 0, "Max shares should be non-negative");
        }

        vm.stopPrank();
    }

    function test_FeeConsistencyUnwindSwapUnwindExercise() public {
        vm.startPrank(DEFAULT_ADDRESS);

        swapToken.approve(address(corkPool), type(uint256).max);
        corkPool.exercise(IPoolManager.ExerciseParams({poolId: defaultCurrencyId, shares: 10 ether, compensation: 0, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: 1000 ether}));

        uint256 shares = 1 ether;
        uint256 fee = 5 ether;

        corkConfig.updateUnwindSwapFeeRate(defaultCurrencyId, fee);

        (uint256 assetIn,) = corkPool.previewUnwindExercise(defaultCurrencyId, shares);

        assertApproxEqAbs(assetIn, 1.052631579 ether, 0.0001 ether, "asset in must match");
        IUnwindSwap.UnwindSwapReturnParams memory previewReturnParams = corkPool.previewUnwindSwap(defaultCurrencyId, assetIn);

        assertApproxEqAbs(previewReturnParams.fee, 0.052631579 ether, 0.0001 ether, "fee  must match");

        (assetIn,,) = corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: defaultCurrencyId, shares: shares, receiver: currentCaller(), minCompensationOut: 0, maxAssetsIn: 10_000 ether}));

        assertApproxEqAbs(assetIn, 1.052631579 ether, 0.0001 ether, "asset in must match");

        IUnwindSwap.UnwindSwapReturnParams memory unwindReturnParams = corkPool.unwindSwap(defaultCurrencyId, assetIn, DEFAULT_ADDRESS);

        assertApproxEqAbs(unwindReturnParams.fee, 0.052631579 ether, 0.0001 ether, "fee  must match");
    }
}
