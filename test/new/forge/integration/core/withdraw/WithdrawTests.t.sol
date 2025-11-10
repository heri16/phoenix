// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IPoolShare, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract WithdrawTests is BaseTest {
    // ================================ Core Withdraw Tests ================================ //

    function test_withdraw_ShouldWork() external __as(alice) __deposit(1000 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 collateralOut = 100 ether;
        (uint256 expectedSharesIn, uint256 expectedCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdraw(defaultPoolId, collateralOut);

        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, collateralOut, expectedRefOut, true);

        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.Withdraw(alice, alice, alice, collateralOut, expectedSharesIn);
        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.WithdrawOther(alice, alice, alice, address(referenceAsset), expectedRefOut, expectedSharesIn);

        (uint256 sharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdraw(defaultPoolId, collateralOut, alice, alice);

        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        assertEq(expectedSharesIn, 100 ether);
        assertEq(expectedCollateralOut, 100 ether);
        assertEq(expectedRefOut, 0);

        assertEq(sharesIn, expectedSharesIn);
        assertEq(actualCollateralOut, expectedCollateralOut);
        assertEq(actualRefOut, expectedRefOut);

        assertEq(stateAfter.userCollateral, stateBefore.userCollateral + expectedCollateralOut, "User collateral balance should increase");
        assertEq(stateAfter.userRef, stateBefore.userRef + expectedRefOut, "User reference balance should increase");
        assertEq(stateAfter.userPrincipalToken, stateBefore.userPrincipalToken - expectedSharesIn, "User principal token balance should decrease");

        assertEq(stateAfter.contractCollateral, stateBefore.contractCollateral - expectedCollateralOut, "Contract collateral balance should decrease");
        assertEq(stateAfter.contractRef, stateBefore.contractRef - expectedRefOut, "Contract reference balance should decrease");
        assertEq(stateAfter.principalTokenTotalSupply, stateBefore.principalTokenTotalSupply - expectedSharesIn, "Principal token total supply should decrease");

        assertEq(stateAfter.poolCollateral, stateBefore.poolCollateral - expectedCollateralOut, "Pool collateral balance should decrease");
        assertEq(stateAfter.poolRef, stateBefore.poolRef - expectedRefOut, "Pool reference balance should decrease");

        assertEq(stateAfter.internalState.shares.withdrawn, stateBefore.internalState.shares.withdrawn + expectedSharesIn, "Internal state shares withdrawn should increase");
    }

    function test_withdraw_ShouldRevert_WhenCollateralAssetOutIsZero() external __as(alice) {
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(IErrors.InvalidParams.selector);
        corkPoolManager.withdraw(defaultPoolId, 0, alice, alice);
    }

    function test_withdraw_ShouldRevert_WhenNotExpired() external __as(alice) {
        vm.expectRevert(IErrors.NotExpired.selector);
        corkPoolManager.withdraw(defaultPoolId, 100 ether, alice, alice);
    }

    function test_withdraw_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2);

        overridePrank(alice);
        _deposit(defaultPoolId, 1000 ether, currentCaller());
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(defaultPoolId, 100 ether, alice, alice);
    }

    // ================================ WithdrawOther Tests ================================ //

    function test_withdrawOther_ShouldWork() external {
        overridePrank(alice);
        _deposit(defaultPoolId, 1000 ether, currentCaller());

        corkPoolManager.exercise(defaultPoolId, 100 ether, alice);

        vm.warp(block.timestamp + 2 days);

        uint256 referenceOut = 100 ether;
        uint256 expectedCollateralOut = 900 ether;
        (uint256 expectedSharesIn, uint256 previewActualCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdrawOther(defaultPoolId, referenceOut);

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, expectedCollateralOut, expectedRefOut, true);

        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.Withdraw(alice, alice, alice, expectedCollateralOut, expectedSharesIn);
        vm.expectEmit(true, true, true, true, address(principalToken));
        emit IPoolShare.WithdrawOther(alice, alice, alice, address(referenceAsset), expectedRefOut, expectedSharesIn);

        (uint256 sharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdrawOther(defaultPoolId, referenceOut, alice, alice);

        assertEq(expectedSharesIn, 1000 ether);
        assertEq(sharesIn, 1000 ether);
        assertEq(actualCollateralOut, 900 ether);
        assertEq(previewActualCollateralOut, 900 ether);
        assertEq(expectedRefOut, 100 ether);
        assertEq(actualRefOut, 100 ether);
    }

    function test_withdrawOther_ShouldRevert_WhenReferenceAssetOutIsZero() external __as(alice) {
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(IErrors.InvalidParams.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 0, alice, alice);
    }

    function test_withdrawOther_ShouldRevert_WhenNotExpired() external __as(alice) {
        vm.expectRevert(IErrors.NotExpired.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 100 ether, alice, alice);
    }

    function test_withdrawOther_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2);

        overridePrank(alice);
        _deposit(defaultPoolId, 1000 ether, currentCaller());
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 100 ether, alice, alice);
    }

    // ================================ Access Control Tests ================================ //

    function test_PauseWithdrawalsRevertWhenCalledByNonManager() external __as(alice) {
        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    function test_PauseWithdrawalsShouldWorkCorrectly() external __as(pauser) {
        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 1 << 2);
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    function test_UnpauseWithdrawalsRevertWhenCalledByNonManager() external __as(alice) {
        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseWithdrawals(defaultPoolId);

        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    function test_UnpauseWithdrawalsShouldWorkCorrectly() external __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);
        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        overridePrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.MarketActionPausedUpdate(defaultPoolId, 0);
        defaultCorkController.unpauseWithdrawals(defaultPoolId);

        assertFalse(defaultCorkController.isWithdrawalPaused(defaultPoolId));
    }

    function test_PauseMarketShouldDisableWithdrawal() external __as(pauser) {
        defaultCorkController.pauseMarket(defaultPoolId);
        assertTrue(defaultCorkController.isWithdrawalPaused(defaultPoolId));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(defaultPoolId, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    function test_PauseAllShouldDisableWithdrawal() external __as(pauser) {
        assertFalse(corkPoolManager.paused());

        defaultCorkController.pauseAll();
        assertTrue(corkPoolManager.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(defaultPoolId, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    function test_UnpauseAllShouldAllowWithdrawAfterExpiry() external __as(pauser) {
        defaultCorkController.pauseAll();
        assertTrue(corkPoolManager.paused());

        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.unpauseAll();
        assertFalse(corkPoolManager.paused());

        overridePrank(alice);
        _deposit(defaultPoolId, 1000 ether, alice);
        corkPoolManager.swap(defaultPoolId, 1 ether, alice);
        vm.warp(block.timestamp + 2 days);

        corkPoolManager.withdraw(defaultPoolId, 0.01 ether, alice, alice);
        corkPoolManager.withdrawOther(defaultPoolId, 0.01 ether, alice, alice);
    }

    // ================================ Pause Status Tests ================================ //

    function test_PauseWithdrawStatus_blocksWithdrawal() external __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);
        Market memory market = corkPoolManager.market(defaultPoolId);
        uint256 expiry = market.expiryTimestamp;
        vm.warp(expiry + 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.redeem(defaultPoolId, 0, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    function test_PauseWithdrawStatus_blocksWithdraw() external __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);
        Market memory market = corkPoolManager.market(defaultPoolId);
        uint256 expiry = market.expiryTimestamp;
        vm.warp(expiry + 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(defaultPoolId, 0.01 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    function test_PauseWithdrawStatus_blocksWithdrawOther() external __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);
        Market memory market = corkPoolManager.market(defaultPoolId);
        uint256 expiry = market.expiryTimestamp;
        vm.warp(expiry + 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 0.01 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    // ================================ Emit Tests ================================ //

    function test_EmitWithdrawShouldRevertWhenCalledByNonOwner() external __as(DEFAULT_ADDRESS) {
        IPoolShare.ConstructorParams memory constructorParams = IPoolShare.ConstructorParams({poolId: MarketId.wrap(bytes32("")), pairName: "Swap Token", symbol: "SWT", poolManager: address(1)});

        PoolShare share = new PoolShare(constructorParams);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        share.emitWithdraw(DEFAULT_ADDRESS, alice, DEFAULT_ADDRESS, 1 ether, 0.5 ether);
    }

    function test_EmitWithdrawShouldWorkCorrectlyAndEmitEvent() external {
        IPoolShare.ConstructorParams memory constructorParams = IPoolShare.ConstructorParams({poolId: MarketId.wrap(bytes32("")), pairName: "Swap Token", symbol: "SWT", poolManager: address(1)});

        PoolShare share = new PoolShare(constructorParams);

        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address owner = sender;
        uint256 assets = 2 ether;
        uint256 shares = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit IPoolShare.Withdraw(sender, receiver, owner, assets, shares);

        overridePrank(address(1));
        share.emitWithdraw(sender, receiver, owner, assets, shares);
        revertPrank();
    }

    function test_EmitWithdrawShouldEmitEventWithDifferentOwnerAndReceiver() external {
        IPoolShare.ConstructorParams memory constructorParams = IPoolShare.ConstructorParams({poolId: MarketId.wrap(bytes32("")), pairName: "Swap Token", symbol: "SWT", poolManager: address(1)});

        PoolShare share = new PoolShare(constructorParams);

        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address owner = makeAddr("owner");
        uint256 assets = 1.25 ether;
        uint256 shares = 0.625 ether;

        vm.expectEmit(true, true, true, true);
        emit IPoolShare.Withdraw(sender, receiver, owner, assets, shares);

        overridePrank(address(1));
        share.emitWithdraw(sender, receiver, owner, assets, shares);
        revertPrank();
    }

    // ================================ MaxWithdraw Tests ================================ //

    function test_maxWithdraw_ownerWithShares() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 ownerShares = principalToken.balanceOf(alice);
        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);

        assertEq(maxWithdrawAmount, 1 ether, "Owner should be able to withdraw some amount");
        assertEq(ownerShares, 1 ether, "Owner should have shares");
    }

    function test_maxWithdraw_ownerWithoutShares() external {
        address userWithoutShares = address(0x5);
        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultPoolId, userWithoutShares);
        assertEq(maxWithdrawAmount, 0, "User without shares should not be able to withdraw");
    }

    function test_maxWithdraw_whenWithdrawalsPaused() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 maxWithdrawBeforePause = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertEq(maxWithdrawBeforePause, 1 ether, "Should be able to withdraw before pause");

        overridePrank(pauser);
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        uint256 maxWithdrawAfterPause = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertEq(maxWithdrawAfterPause, 0, "Should not be able to withdraw when paused");
    }

    function test_maxWithdraw_consistencyWithActualWithdraw() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        uint256 receiverBalanceBefore = collateralAsset.balanceOf(bob);

        (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) = corkPoolManager.withdraw(defaultPoolId, maxWithdrawAmount, alice, bob);

        uint256 receiverBalanceAfter = collateralAsset.balanceOf(bob);
        uint256 actualWithdrawn = receiverBalanceAfter - receiverBalanceBefore;

        assertEq(actualWithdrawn, maxWithdrawAmount, "Actual withdraw should match maxWithdraw");
        assertEq(sharesIn, 1 ether, "Should have burned some shares");
    }

    function test_maxWithdraw_edgeCaseZeroPoolBalance() external __as(alice) __deposit(1 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 ownerShares = principalToken.balanceOf(alice);
        uint256 maxWithdraw = corkPoolManager.maxWithdraw(defaultPoolId, alice);

        corkPoolManager.withdraw(defaultPoolId, maxWithdraw, alice, alice);

        uint256 maxWithdrawAfterDrain = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertEq(maxWithdrawAfterDrain, 0, "Should not be able to withdraw when pool is drained");
    }

    function test_maxWithdraw_ShouldBeZeroBeforeExpiry() external __as(alice) __deposit(1 ether, alice) {
        uint256 expiry = corkPoolManager.expiry(defaultPoolId);
        vm.warp(expiry - 1 hours);

        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertEq(maxWithdrawAmount, 0, "Should not be able to withdraw before expiry");
    }

    // ================================ PoolShare Tests ================================ //

    function test_maxWithdraw_ShouldReturnSameValueAsPoolManager() external __as(DEFAULT_ADDRESS) __deposit(1000 ether, DEFAULT_ADDRESS) {
        uint256 poolManagerResult = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxWithdraw(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxWithdraw should match PoolManager maxWithdraw");
    }

    function test_previewWithdraw_ShouldReturnSameValueAsPoolManager() external __as(DEFAULT_ADDRESS) __deposit(1000 ether, DEFAULT_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        uint256 collateralAssetOut = 0.01 ether;
        (uint256 poolManagerSharesIn, uint256 poolManagerActualCollateralAssetOut, uint256 poolManagerActualRefAssetOut) = corkPoolManager.previewWithdraw(defaultPoolId, collateralAssetOut);
        (uint256 poolShareSharesIn, uint256 poolShareActualCollateralAssetOut, uint256 poolShareActualRefAssetOut) = principalToken.previewWithdraw(collateralAssetOut);

        assertEq(poolShareSharesIn, poolManagerSharesIn, "PoolShare previewWithdraw sharesIn should match PoolManager previewWithdraw");
        assertEq(poolShareActualRefAssetOut, poolManagerActualRefAssetOut, "PoolShare previewWithdraw actualReferenceAssetOut should match PoolManager previewWithdraw");
        assertEq(poolShareActualCollateralAssetOut, poolManagerActualCollateralAssetOut, "PoolShare previewWithdraw actualCollateralAssetOut should match PoolManager previewWithdraw");
    }

    // ================================ Preview Function Tests ================================ //

    function test_previewWithdraw_ShouldReturnCorrectAmounts_WhenExpired() external __as(alice) __deposit(1000 ether, DEFAULT_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        uint256 collateralOut = 100 ether;
        (uint256 expectedSharesIn, uint256 expectedCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdraw(defaultPoolId, collateralOut);

        assertEq(expectedSharesIn, 100 ether);
        assertEq(expectedCollateralOut, 100 ether);
        assertEq(expectedRefOut, 0);
    }

    // ================================ Max Function Tests ================================ //

    function test_maxWithdraw_ShouldReturnCorrectAmount_WhenExpired() external __as(alice) __deposit(500 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertEq(maxAmount, 500 ether, "Should return positive amount when expired");
    }

    function test_maxWithdrawOther_ShouldReturnCorrectAmount_WhenExpired() external __as(alice) __deposit(500 ether, alice) {
        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        corkPoolManager.swap(defaultPoolId, 500 ether, alice);
        revertPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdrawOther(defaultPoolId, alice);
        assertEq(maxAmount, 500 ether, "Should return positive amount when expired");
    }

    function test_maxWithdraw_ShouldReturnZero_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2);
        revertPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertEq(maxAmount, 0, "Should return 0 when paused");
    }

    function test_maxWithdraw_ShouldReturnMaxCollateralOut_WhenOwnerSharesLessThanPool() external {
        overridePrank(alice);
        _deposit(defaultPoolId, 500 ether, currentCaller());

        overridePrank(bob);
        _deposit(defaultPoolId, 10_000 ether, currentCaller());

        vm.warp(block.timestamp + 2 days);

        uint256 maxAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertGt(maxAmount, 0, "Should return positive amount");
        assertLe(maxAmount, 500 ether, "Should not exceed alice's deposit");
    }

    function test_maxWithdraw_ShouldReturnPoolBalance_WhenOwnerSharesGreaterThanPool() external __as(alice) __deposit(1000 ether, alice) {
        vm.warp(block.timestamp + 2 days);
        uint256 withdrawAmount = 800 ether;
        uint256 userBalance = principalToken.balanceOf(alice);

        corkPoolManager.redeem(defaultPoolId, withdrawAmount, alice, alice);

        uint256 maxAmount = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        assertGt(maxAmount, 0, "Should return positive pool balance");
    }

    // ================================ Negative Test Cases ================================ //

    function test_withdraw_ShouldRevert_WhenInsufficientCollateralLiquidity() external __as(alice) __deposit(500 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 excessiveCollateralOut = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientLiquidity.selector, 500 ether, excessiveCollateralOut));
        corkPoolManager.withdraw(defaultPoolId, excessiveCollateralOut, alice, alice);
    }

    function test_withdrawOther_ShouldRevert_WhenInsufficientReferenceLiquidity() external __as(alice) __deposit(500 ether, alice) {
        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        corkPoolManager.swap(defaultPoolId, 250 ether, alice);

        vm.warp(block.timestamp + 2 days);

        uint256 excessiveReferenceOut = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientLiquidity.selector, 250 ether, excessiveReferenceOut));
        corkPoolManager.withdrawOther(defaultPoolId, excessiveReferenceOut, alice, alice);
    }

    function test_withdraw_ShouldRevert_WhenOwnerHasNoShares() external __as(alice) __deposit(500 ether, bob) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        corkPoolManager.withdraw(defaultPoolId, 1 ether, alice, alice);
    }

    function test_withdrawOther_ShouldRevert_WhenOwnerHasNoShares() external __as(alice) __deposit(10 ether, bob) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        corkPoolManager.withdraw(defaultPoolId, 1 ether, alice, alice);
    }

    function test_withdraw_ShouldRevert_WhenInsufficientAllowance() external __as(alice) __deposit(1000 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        overridePrank(bob);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 100 ether));
        corkPoolManager.withdraw(defaultPoolId, 100 ether, alice, bob);
    }

    function test_withdrawOther_ShouldRevert_WhenInsufficientAllowance() external __as(alice) __deposit(1000 ether, alice) {
        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        corkPoolManager.swap(defaultPoolId, 500 ether, alice);

        vm.warp(block.timestamp + 2 days);

        overridePrank(bob);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        corkPoolManager.withdrawOther(defaultPoolId, 100 ether, alice, bob);
    }

    function test_withdraw_ShouldRevert_WhenPoolIsEmpty() external __as(alice) __deposit(1000 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        corkPoolManager.redeem(defaultPoolId, 1000 ether, alice, alice);

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.withdraw(defaultPoolId, 1 ether, alice, alice);
    }

    function test_withdrawOther_ShouldRevert_WhenPoolIsEmpty() external __as(alice) __deposit(1000 ether, alice) {
        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        corkPoolManager.swap(defaultPoolId, 500 ether, alice);

        vm.warp(block.timestamp + 2 days);

        corkPoolManager.redeem(defaultPoolId, 1000 ether, alice, alice);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientLiquidity.selector, 0, 1 ether));
        corkPoolManager.withdrawOther(defaultPoolId, 1 ether, alice, alice);
    }

    function test_withdraw_ShouldRevert_WhenExceedsAvailableCollateral() external __as(alice) __deposit(100 ether, alice) {
        vm.warp(block.timestamp + 2 days);

        uint256 excessiveWithdraw = 800 ether;

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientLiquidity.selector, 100 ether, excessiveWithdraw));
        corkPoolManager.withdraw(defaultPoolId, excessiveWithdraw, alice, alice);
    }

    function test_withdrawOther_ShouldRevert_WhenExceedsAvailableReference() external __as(alice) __deposit(1000 ether, alice) {
        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        overridePrank(alice);
        corkPoolManager.swap(defaultPoolId, 500 ether, alice);

        vm.warp(block.timestamp + 2 days);

        overridePrank(alice);
        corkPoolManager.redeem(defaultPoolId, 400 ether, alice, alice);

        uint256 excessiveReferenceWithdraw = 400 ether;

        vm.expectPartialRevert(IErrors.InsufficientLiquidity.selector);
        corkPoolManager.withdrawOther(defaultPoolId, excessiveReferenceWithdraw, alice, alice);
    }

    // ================================ Fuzz Tests ================================ //

    function testFuzz_withdraw_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1000 ether, collateralAsset.decimals());

        // First deposit to have tokens for withdrawal
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());

        // Wait for expiry
        vm.warp(block.timestamp + 2 days);

        uint256 collateralOut = TransferHelper.fixedToTokenNativeDecimals(100 ether, collateralAsset.decimals());

        // Take snapshots before withdraw
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedSharesIn, uint256 expectedCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdraw(defaultPoolId, collateralOut);

        (uint256 sharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdraw(defaultPoolId, collateralOut, alice, alice);

        // Take snapshots after withdraw
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(sharesIn, expectedSharesIn, "Shares in should match preview");
        assertEq(actualCollateralOut, expectedCollateralOut, "Collateral out should match preview");
        assertEq(actualRefOut, expectedRefOut, "Reference out should match preview");

        // ================================ User State Changes ================================ //
        assertEq(afterSnapshot.userCollateral, beforeSnapshot.userCollateral + actualCollateralOut, "User collateral balance should increase");
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef + actualRefOut, "User reference balance should increase");
        assertEq(afterSnapshot.userPrincipalToken, beforeSnapshot.userPrincipalToken - sharesIn, "User principal token balance should decrease");

        // ================================ Contract State Changes ================================ //
        assertEq(afterSnapshot.contractCollateral, beforeSnapshot.contractCollateral - actualCollateralOut, "Contract collateral balance should decrease");
        assertEq(afterSnapshot.contractRef, beforeSnapshot.contractRef - actualRefOut, "Contract reference balance should decrease");

        // ================================ Token Supply Changes ================================ //
        assertEq(afterSnapshot.principalTokenTotalSupply, beforeSnapshot.principalTokenTotalSupply - sharesIn, "Principal token total supply should decrease");

        // ================================ Pool Internal State Changes ================================ //
        assertEq(afterSnapshot.poolCollateral, beforeSnapshot.poolCollateral - actualCollateralOut, "Pool collateral balance should decrease");
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef - actualRefOut, "Pool reference balance should decrease");

        // ================================ Internal State Consistency ================================ //
        assertEq(afterSnapshot.internalState.shares.withdrawn, beforeSnapshot.internalState.shares.withdrawn + sharesIn, "Internal state shares withdrawn should increase");
    }

    function testFuzz_withdrawOther_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1000 ether, collateralAsset.decimals());
        uint256 normalizedExerciseAmount = TransferHelper.fixedToTokenNativeDecimals(100 ether, referenceAsset.decimals());

        // First deposit and exercise to have reference assets in pool
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());
        corkPoolManager.exerciseOther(defaultPoolId, normalizedExerciseAmount, alice);

        // Wait for expiry
        vm.warp(block.timestamp + 2 days);

        uint256 referenceOut = TransferHelper.fixedToTokenNativeDecimals(100 ether, referenceAsset.decimals());

        // Take snapshots before withdrawOther
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Get preview values for comparison
        (uint256 expectedSharesIn, uint256 expectedCollateralOut, uint256 expectedRefOut) = corkPoolManager.previewWithdrawOther(defaultPoolId, referenceOut);

        (uint256 sharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdrawOther(defaultPoolId, referenceOut, alice, alice);

        // Take snapshots after withdrawOther
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(sharesIn, expectedSharesIn, "Shares in should match preview");
        assertEq(actualCollateralOut, expectedCollateralOut, "Collateral out should match preview");
        assertEq(actualRefOut, expectedRefOut, "Reference out should match preview");

        // ================================ User State Changes ================================ //
        assertEq(afterSnapshot.userCollateral, beforeSnapshot.userCollateral + actualCollateralOut, "User collateral balance should increase");
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef + actualRefOut, "User reference balance should increase");
        assertEq(afterSnapshot.userPrincipalToken, beforeSnapshot.userPrincipalToken - sharesIn, "User principal token balance should decrease");

        // ================================ Contract State Changes ================================ //
        assertEq(afterSnapshot.contractCollateral, beforeSnapshot.contractCollateral - actualCollateralOut, "Contract collateral balance should decrease");
        assertEq(afterSnapshot.contractRef, beforeSnapshot.contractRef - actualRefOut, "Contract reference balance should decrease");

        // ================================ Token Supply Changes ================================ //
        assertEq(afterSnapshot.principalTokenTotalSupply, beforeSnapshot.principalTokenTotalSupply - sharesIn, "Principal token total supply should decrease");

        // ================================ Pool Internal State Changes ================================ //
        assertEq(afterSnapshot.poolCollateral, beforeSnapshot.poolCollateral - actualCollateralOut, "Pool collateral balance should decrease");
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef - actualRefOut, "Pool reference balance should decrease");

        // ================================ Internal State Consistency ================================ //
        assertEq(afterSnapshot.internalState.shares.withdrawn, beforeSnapshot.internalState.shares.withdrawn + sharesIn, "Internal state shares withdrawn should increase");
    }

    function testFuzz_previewWithdraw_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1000 ether, collateralAsset.decimals());

        // First deposit to have tokens for withdrawal
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());

        // Wait for expiry
        vm.warp(block.timestamp + 2 days);

        uint256 collateralOut = TransferHelper.fixedToTokenNativeDecimals(100 ether, collateralAsset.decimals());

        // Preview withdraw
        (uint256 previewSharesIn, uint256 previewCollateralOut, uint256 previewRefOut) = corkPoolManager.previewWithdraw(defaultPoolId, collateralOut);

        // Execute actual withdraw
        (uint256 actualSharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdraw(defaultPoolId, collateralOut, alice, alice);

        // Verify preview matches actual
        assertEq(previewSharesIn, actualSharesIn, "Preview shares in should match actual shares in");
        assertEq(previewCollateralOut, actualCollateralOut, "Preview collateral out should match actual collateral out");
        assertEq(previewRefOut, actualRefOut, "Preview ref out should match actual ref out");

        // Verify that the withdrawal functioned correctly with decimal normalization
        assertEq(actualCollateralOut, collateralOut, "Should withdraw exact collateral amount requested");
    }

    function testFuzz_previewWithdrawOther_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1000 ether, collateralAsset.decimals());
        uint256 normalizedExerciseAmount = TransferHelper.fixedToTokenNativeDecimals(100 ether, referenceAsset.decimals());

        // First deposit and exercise to have reference assets in pool
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());
        corkPoolManager.exerciseOther(defaultPoolId, normalizedExerciseAmount, alice);

        // Wait for expiry
        vm.warp(block.timestamp + 2 days);

        uint256 referenceOut = TransferHelper.fixedToTokenNativeDecimals(100 ether, referenceAsset.decimals());

        // Preview withdrawOther
        (uint256 previewSharesIn, uint256 previewCollateralOut, uint256 previewRefOut) = corkPoolManager.previewWithdrawOther(defaultPoolId, referenceOut);

        // Execute actual withdrawOther
        (uint256 actualSharesIn, uint256 actualCollateralOut, uint256 actualRefOut) = corkPoolManager.withdrawOther(defaultPoolId, referenceOut, alice, alice);

        // Verify preview matches actual
        assertEq(previewSharesIn, actualSharesIn, "Preview shares in should match actual shares in");
        assertEq(previewCollateralOut, actualCollateralOut, "Preview collateral out should match actual collateral out");
        assertEq(previewRefOut, actualRefOut, "Preview ref out should match actual ref out");

        // Verify that the withdrawal functioned correctly with decimal normalization
        assertEq(actualRefOut, referenceOut, "Should withdraw exact reference amount requested");
    }
}
