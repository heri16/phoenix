pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract PoolShareTest is Helper {
    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare principalToken;
    PoolShare swapToken;
    MarketId poolId;

    address user1;
    address user2;

    uint256 public constant depositAmount = 1000 ether;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(DEFAULT_ADDRESS);

        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, poolId) = createMarket(block.timestamp + 1 days);
        vm.deal(DEFAULT_ADDRESS, 100_000_000_000 ether);
        collateralAsset.deposit{value: 1_000_000_000 ether}();
        referenceAsset.deposit{value: 1_000_000_000 ether}();

        collateralAsset.approve(address(corkPoolManager), 100_000_000_000 ether);
        referenceAsset.approve(address(corkPoolManager), 100_000_000_000 ether);

        // Create some initial liquidity
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);

        swapToken.approve(address(corkPoolManager), type(uint256).max);
    }

    function test_maxMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxMint(poolId, user1);
        uint256 poolShareResult = principalToken.maxMint(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxMint should match PoolManager maxMint");
    }

    function test_maxDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxDeposit(poolId, user1);
        uint256 poolShareResult = principalToken.maxDeposit(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxDeposit should match PoolManager maxDeposit");
    }

    function test_maxUnwindDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxUnwindDeposit(poolId, user1);
        uint256 poolShareResult = principalToken.maxUnwindDeposit(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindDeposit should match PoolManager maxUnwindDeposit");
    }

    function test_maxUnwindMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxUnwindMint(poolId, user1);
        uint256 poolShareResult = principalToken.maxUnwindMint(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindMint should match PoolManager maxUnwindMint");
    }

    function test_maxWithdraw_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxWithdraw(poolId, user1);
        uint256 poolShareResult = principalToken.maxWithdraw(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxWithdraw should match PoolManager maxWithdraw");
    }

    function test_maxExercise_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxExercise(poolId, user1);
        uint256 poolShareResult = swapToken.maxExercise(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxExercise should match PoolManager maxExercise");
    }

    function test_maxRedeem_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxRedeem(poolId, user1);
        uint256 poolShareResult = principalToken.maxRedeem(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxRedeem should match PoolManager maxRedeem");
    }

    function test_maxSwap_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxSwap(poolId, user1);
        uint256 poolShareResult = swapToken.maxSwap(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxSwap should match PoolManager maxSwap");
    }

    function test_maxUnwindExercise_ShouldReturnSameValueAsPoolManager() external {
        // exercise first so that it won't return 0
        corkPoolManager.exercise(poolId, 10 ether, DEFAULT_ADDRESS);

        uint256 poolManagerResult = corkPoolManager.maxUnwindExercise(poolId, user1);
        uint256 poolShareResult = swapToken.maxUnwindExercise(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindExercise should match PoolManager maxUnwindExercise");
    }

    function test_maxUnwindExerciseOther_ShouldReturnSameValueAsPoolManager() external {
        // exercise first so that it won't return 0
        corkPoolManager.exercise(poolId, 10 ether, DEFAULT_ADDRESS);

        uint256 poolManagerResult = corkPoolManager.maxUnwindExerciseOther(poolId, user1);
        uint256 poolShareResult = swapToken.maxUnwindExerciseOther(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindExerciseOther should match PoolManager maxUnwindExerciseOther");
    }

    function test_maxUnwindSwap_ShouldReturnSameValueAsPoolManager() external {
        // exercise first so that it won't return 0
        corkPoolManager.exercise(poolId, 10 ether, DEFAULT_ADDRESS);

        uint256 poolManagerResult = corkPoolManager.maxUnwindSwap(poolId, user1);
        uint256 poolShareResult = swapToken.maxUnwindSwap(user1);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindSwap should match PoolManager maxUnwindSwap");
    }

    function test_previewExercise_ShouldReturnSameValueAsPoolManager() external {
        uint256 shares = 1.456 ether;

        (uint256 poolManagerAssets, uint256 poolManagerOtherAssetSpent, uint256 poolManagerFee) = corkPoolManager.previewExercise(poolId, shares);
        (uint256 poolShareAssets, uint256 poolShareOtherAssetSpent, uint256 poolShareFee) = swapToken.previewExercise(shares);

        assertEq(poolShareAssets, poolManagerAssets, "PoolShare previewExercise assets should match PoolManager previewExercise");
        assertEq(poolShareOtherAssetSpent, poolManagerOtherAssetSpent, "PoolShare previewExercise otherAssetSpent should match PoolManager previewExercise");
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewExercise fee should match PoolManager previewExercise");
    }

    function test_previewUnwindExercise_ShouldReturnSameValueAsPoolManager() external {
        // exercise first so that it won't return 0
        corkPoolManager.exercise(poolId, 10 ether, DEFAULT_ADDRESS);

        uint256 shares = 1.56 ether;

        (uint256 poolManagerAssetIn, uint256 poolManagerCompensationOut, uint256 poolManagerFee) = corkPoolManager.previewUnwindExercise(poolId, shares);
        (uint256 poolShareAssetIn, uint256 poolShareCompensationOut, uint256 poolShareFee) = swapToken.previewUnwindExercise(shares);

        assertEq(poolShareAssetIn, poolManagerAssetIn, "PoolShare previewUnwindExercise assetIn should match PoolManager previewUnwindExercise");
        assertEq(poolShareCompensationOut, poolManagerCompensationOut, "PoolShare previewUnwindExercise compensationOut should match PoolManager previewUnwindExercise");
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewUnwindExercise fee should match PoolManager previewUnwindExercise");
    }

    function test_previewDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 collateralAssetIn = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewDeposit(poolId, collateralAssetIn);
        uint256 poolShareResult = principalToken.previewDeposit(collateralAssetIn);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewDeposit should match PoolManager previewDeposit");
    }

    function test_previewSwap_ShouldReturnSameValueAsPoolManager() external {
        uint256 assets = 1 ether;

        (uint256 poolManagerSharesOut, uint256 poolManagerCompensation, uint256 poolManagerFee) = corkPoolManager.previewSwap(poolId, assets);
        (uint256 poolShareSharesOut, uint256 poolShareCompensation, uint256 poolShareFee) = swapToken.previewSwap(assets);

        assertEq(poolShareSharesOut, poolManagerSharesOut, "PoolShare previewSwap sharesOut should match PoolManager previewSwap");
        assertEq(poolShareCompensation, poolManagerCompensation, "PoolShare previewSwap compensation should match PoolManager previewSwap");
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewSwap fee should match PoolManager previewSwap");
    }

    function test_previewRedeem_ShouldReturnSameValueAsPoolManager() external {
        // Fast forward to expiry to allow redeem
        vm.warp(block.timestamp + 2 days);

        uint256 amount = 1 ether;

        (uint256 poolManagerRefAsset, uint256 poolManagerCollAsset) = corkPoolManager.previewRedeem(poolId, amount);
        (uint256 poolShareRefAsset, uint256 poolShareCollAsset) = principalToken.previewRedeem(amount);

        assertEq(poolShareRefAsset, poolManagerRefAsset, "PoolShare previewRedeem accruedReferenceAsset should match PoolManager previewRedeem");
        assertEq(poolShareCollAsset, poolManagerCollAsset, "PoolShare previewRedeem accruedCollateralAsset should match PoolManager previewRedeem");
    }

    function test_previewUnwindDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 collateralAssetAmountOut = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewUnwindDeposit(poolId, collateralAssetAmountOut);
        uint256 poolShareResult = principalToken.previewUnwindDeposit(collateralAssetAmountOut);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewUnwindDeposit should match PoolManager previewUnwindDeposit");
    }

    function test_previewUnwindSwap_ShouldReturnSameValueAsPoolManager() external {
        // exercise first so that it won't return 0
        corkPoolManager.exercise(poolId, 10 ether, DEFAULT_ADDRESS);

        uint256 amount = 0;

        (uint256 previewReceivedCst, uint256 previewReceivedRef, uint256 previewFee) = corkPoolManager.previewUnwindSwap(poolId, amount);
        (uint256 poolShareReceivedCst, uint256 poolShareReceivedRef, uint256 poolShareFee) = swapToken.previewUnwindSwap(amount);

        assertEq(poolShareReceivedRef, previewReceivedRef, "PoolShare previewUnwindSwap receivedRef should match PoolManager previewUnwindSwap");
        assertEq(poolShareReceivedCst, previewReceivedCst, "PoolShare previewUnwindSwap receivedCst should match PoolManager previewUnwindSwap");
        assertEq(poolShareFee, previewFee, "PoolShare previewUnwindSwap fee should match PoolManager previewUnwindSwap");
    }

    function test_previewMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 swapAndPricipalTokenAmountOut = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewMint(poolId, swapAndPricipalTokenAmountOut);
        uint256 poolShareResult = principalToken.previewMint(swapAndPricipalTokenAmountOut);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewMint should match PoolManager previewMint");
    }

    function test_previewUnwindMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 cptAndCstSharesIn = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewUnwindMint(poolId, cptAndCstSharesIn);
        uint256 poolShareResult = principalToken.previewUnwindMint(cptAndCstSharesIn);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewUnwindMint should match PoolManager previewUnwindMint");
    }

    function test_previewWithdraw_ShouldReturnSameValueAsPoolManager() external {
        // Fast forward to expiry to allow withdraw
        vm.warp(block.timestamp + 2 days);

        uint256 collateralAssetOut = 0.01 ether;
        (uint256 poolManagerSharesIn, uint256 poolManagerActualCollateralAssetOut, uint256 poolManagerActualRefAssetOut) = corkPoolManager.previewWithdraw(poolId, collateralAssetOut);
        (uint256 poolShareSharesIn, uint256 poolShareActualCollateralAssetOut, uint256 poolShareActualRefAssetOut) = principalToken.previewWithdraw(collateralAssetOut);

        assertEq(poolShareSharesIn, poolManagerSharesIn, "PoolShare previewWithdraw sharesIn should match PoolManager previewWithdraw");
        assertEq(poolShareActualRefAssetOut, poolManagerActualRefAssetOut, "PoolShare previewWithdraw actualReferenceAssetOut should match PoolManager previewWithdraw");
        assertEq(poolShareActualCollateralAssetOut, poolManagerActualCollateralAssetOut, "PoolShare previewWithdraw actualCollateralAssetOut should match PoolManager previewWithdraw");
    }
}
