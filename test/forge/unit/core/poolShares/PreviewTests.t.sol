pragma solidity ^0.8.30;

import {BaseTest} from "test/forge/BaseTest.sol";

contract PreviewTests is BaseTest {
    // --------------------------------------- preview functions --------------------------------------------//

    function test_previewDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 collateralAssetIn = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewDeposit(defaultPoolId, collateralAssetIn);
        uint256 poolShareResult = principalToken.previewDeposit(collateralAssetIn);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewDeposit should match PoolManager previewDeposit");
    }

    function test_previewMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 swapAndPricipalTokenAmountOut = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewMint(defaultPoolId, swapAndPricipalTokenAmountOut);
        uint256 poolShareResult = principalToken.previewMint(swapAndPricipalTokenAmountOut);

        assertEq(poolShareResult, poolManagerResult, "PoolShare previewMint should match PoolManager previewMint");
    }

    function test_previewUnwindDeposit_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 collateralAssetAmountOut = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewUnwindDeposit(defaultPoolId, collateralAssetAmountOut);
        uint256 poolShareResult = principalToken.previewUnwindDeposit(collateralAssetAmountOut);

        assertEq(
            poolShareResult,
            poolManagerResult,
            "PoolShare previewUnwindDeposit should match PoolManager previewUnwindDeposit"
        );
    }

    function test_previewUnwindMint_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 cptAndCstSharesIn = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewUnwindMint(defaultPoolId, cptAndCstSharesIn);
        uint256 poolShareResult = principalToken.previewUnwindMint(cptAndCstSharesIn);

        assertEq(
            poolShareResult, poolManagerResult, "PoolShare previewUnwindMint should match PoolManager previewUnwindMint"
        );
    }

    function test_previewRedeem_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        // Fast forward to expiry to allow redeem
        vm.warp(block.timestamp + 2 days);

        uint256 amount = 1 ether;

        (uint256 poolManagerRefAsset, uint256 poolManagerCollAsset) =
            corkPoolManager.previewRedeem(defaultPoolId, amount);
        (uint256 poolShareRefAsset, uint256 poolShareCollAsset) = principalToken.previewRedeem(amount);

        assertEq(
            poolShareRefAsset,
            poolManagerRefAsset,
            "PoolShare previewRedeem accruedReferenceAsset should match PoolManager previewRedeem"
        );
        assertEq(
            poolShareCollAsset,
            poolManagerCollAsset,
            "PoolShare previewRedeem accruedCollateralAsset should match PoolManager previewRedeem"
        );
    }

    function test_previewWithdraw_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        // Fast forward to expiry to allow withdraw
        vm.warp(block.timestamp + 2 days);

        uint256 collateralAssetOut = 0.01 ether;
        (
            uint256 poolManagerSharesIn,
            uint256 poolManagerActualCollateralAssetOut,
            uint256 poolManagerActualRefAssetOut
        ) = corkPoolManager.previewWithdraw(defaultPoolId, collateralAssetOut);
        (uint256 poolShareSharesIn, uint256 poolShareActualCollateralAssetOut, uint256 poolShareActualRefAssetOut) =
            principalToken.previewWithdraw(collateralAssetOut);

        assertEq(
            poolShareSharesIn,
            poolManagerSharesIn,
            "PoolShare previewWithdraw sharesIn should match PoolManager previewWithdraw"
        );
        assertEq(
            poolShareActualRefAssetOut,
            poolManagerActualRefAssetOut,
            "PoolShare previewWithdraw actualReferenceAssetOut should match PoolManager previewWithdraw"
        );
        assertEq(
            poolShareActualCollateralAssetOut,
            poolManagerActualCollateralAssetOut,
            "PoolShare previewWithdraw actualCollateralAssetOut should match PoolManager previewWithdraw"
        );
    }

    function test_previewExercise_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 shares = 1.456 ether;

        (uint256 poolManagerAssets, uint256 poolManagerOtherAssetSpent, uint256 poolManagerFee) =
            corkPoolManager.previewExercise(defaultPoolId, shares);
        (uint256 poolShareAssets, uint256 poolShareOtherAssetSpent, uint256 poolShareFee) =
            swapToken.previewExercise(shares);

        assertEq(
            poolShareAssets,
            poolManagerAssets,
            "PoolShare previewExercise assets should match PoolManager previewExercise"
        );
        assertEq(
            poolShareOtherAssetSpent,
            poolManagerOtherAssetSpent,
            "PoolShare previewExercise otherAssetSpent should match PoolManager previewExercise"
        );
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewExercise fee should match PoolManager previewExercise");
    }

    function test_previewSwap_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 assets = 1 ether;

        (uint256 poolManagerSharesOut, uint256 poolManagerCompensation, uint256 poolManagerFee) =
            corkPoolManager.previewSwap(defaultPoolId, assets);
        (uint256 poolShareSharesOut, uint256 poolShareCompensation, uint256 poolShareFee) =
            swapToken.previewSwap(assets);

        assertEq(
            poolShareSharesOut,
            poolManagerSharesOut,
            "PoolShare previewSwap sharesOut should match PoolManager previewSwap"
        );
        assertEq(
            poolShareCompensation,
            poolManagerCompensation,
            "PoolShare previewSwap compensation should match PoolManager previewSwap"
        );
        assertEq(poolShareFee, poolManagerFee, "PoolShare previewSwap fee should match PoolManager previewSwap");
    }

    function test_previewUnwindSwap_ShouldReturnSameValueAsPoolManager()
        external
        __depositAndSwap(11 ether, 10 ether, bravo)
    {
        uint256 amount = 0;

        (uint256 previewReceivedCst, uint256 previewReceivedRef, uint256 previewFee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, amount);
        (uint256 poolShareReceivedCst, uint256 poolShareReceivedRef, uint256 poolShareFee) =
            swapToken.previewUnwindSwap(amount);

        assertEq(
            poolShareReceivedRef,
            previewReceivedRef,
            "PoolShare previewUnwindSwap receivedRef should match PoolManager previewUnwindSwap"
        );
        assertEq(
            poolShareReceivedCst,
            previewReceivedCst,
            "PoolShare previewUnwindSwap receivedCst should match PoolManager previewUnwindSwap"
        );
        assertEq(poolShareFee, previewFee, "PoolShare previewUnwindSwap fee should match PoolManager previewUnwindSwap");
    }

    function test_previewUnwindExercise_ShouldReturnSameValueAsPoolManager()
        external
        __depositAndSwap(11 ether, 10 ether, bravo)
    {
        uint256 shares = 1.56 ether;

        (uint256 poolManagerAssetIn, uint256 poolManagerCompensationOut, uint256 poolManagerFee) =
            corkPoolManager.previewUnwindExercise(defaultPoolId, shares);
        (uint256 poolShareAssetIn, uint256 poolShareCompensationOut, uint256 poolShareFee) =
            swapToken.previewUnwindExercise(shares);

        assertEq(
            poolShareAssetIn,
            poolManagerAssetIn,
            "PoolShare previewUnwindExercise assetIn should match PoolManager previewUnwindExercise"
        );
        assertEq(
            poolShareCompensationOut,
            poolManagerCompensationOut,
            "PoolShare previewUnwindExercise compensationOut should match PoolManager previewUnwindExercise"
        );
        assertEq(
            poolShareFee,
            poolManagerFee,
            "PoolShare previewUnwindExercise fee should match PoolManager previewUnwindExercise"
        );
    }
}
