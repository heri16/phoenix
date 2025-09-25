pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
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

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

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

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        // regardless of the amount, the received amount would be in 18 decimals
        vm.assertEq(received, 1 ether);
    }

    function testFuzz_swapSwapToken(uint8 raDecimals, uint8 paDecimals, uint256 rate) external {
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);
        rate = bound(rate, 0.9 ether, 1 ether);

        testOracle.setRate(defaultCurrencyId, rate);
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);

        depositAmount = TransferHelper.normalizeDecimals(depositAmount, TARGET_DECIMALS, raDecimals);

        uint256 received = corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        uint256 swapAmount = 1 ether * 1e18 / rate;

        swapAmount = TransferHelper.normalizeDecimals(swapAmount, TARGET_DECIMALS, paDecimals);

        (received,,) = corkPool.exercise(IPoolManager.ExerciseParams({poolId: defaultCurrencyId, shares: 0, compensation: swapAmount, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

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

        (received,,) = corkPool.exercise(IPoolManager.ExerciseParams({poolId: defaultCurrencyId, shares: 0, compensation: swapAmount, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));
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

        (received,,) = corkPool.exercise(IPoolManager.ExerciseParams({poolId: defaultCurrencyId, shares: 0, compensation: swapAmount, receiver: DEFAULT_ADDRESS, minAssetsOut: 0, maxOtherAssetSpent: type(uint256).max}));

        // and weunwindSwap half of the swaped amount
        uint256 unwindSwapAmount = 0.25 ether * rate / 1 ether;

        uint256 adjustedunwindSwapAmount = TransferHelper.normalizeDecimals(unwindSwapAmount, TARGET_DECIMALS, raDecimals);

        IUnwindSwap.UnwindSwapReturnParams memory unwindReturnParams = corkPool.unwindSwap(defaultCurrencyId, adjustedunwindSwapAmount, DEFAULT_ADDRESS);

        uint256 expectedAmount = TransferHelper.normalizeDecimals(0.25 ether, TARGET_DECIMALS, paDecimals);
        uint256 acceptableDelta = TransferHelper.normalizeDecimals(1, TARGET_DECIMALS, paDecimals);

        vm.assertApproxEqAbs(unwindReturnParams.receivedReferenceAsset, expectedAmount, acceptableDelta);
        vm.assertApproxEqAbs(unwindReturnParams.receivedSwapToken, unwindSwapAmount, acceptableDelta);
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

    function defaultSwapRate() internal pure returns (uint256) {
        return 1.0 ether;
    }
}
