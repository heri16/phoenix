pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract RedeemAllowanceTest is Helper {
    address owner = DEFAULT_ADDRESS;
    address sender = address(0x2);
    address receiver = address(0x3);

    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant REDEEM_AMOUNT = 0.5 ether;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;

    function setUp() public {
        vm.startPrank(owner);

        deployContracts(owner, owner, owner, owner);
        (collateralAsset, referenceAsset,) = createMarket(1 days);

        vm.deal(owner, 100 ether);

        collateralAsset.deposit{value: 10 ether}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);

        corkPoolManager.deposit(defaultCurrencyId, DEPOSIT_AMOUNT, currentCaller());

        uint256 expiry = corkPoolManager.expiry(defaultCurrencyId);
        vm.warp(expiry + 1);

        vm.stopPrank();
    }

    function test_redeemWithSameOwnerSender() public {
        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(address(corkPoolManager), REDEEM_AMOUNT);

        uint256 ownerRaBalanceBefore = collateralAsset.balanceOf(owner);
        uint256 ownerPaBalanceBefore = referenceAsset.balanceOf(owner);
        uint256 receiverRaBalanceBefore = collateralAsset.balanceOf(receiver);
        uint256 receiverPaBalanceBefore = referenceAsset.balanceOf(receiver);

        (uint256 actualPa, uint256 actualRa) = corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT, owner, receiver);

        uint256 receiverRaBalanceAfter = collateralAsset.balanceOf(receiver);
        uint256 receiverPaBalanceAfter = referenceAsset.balanceOf(receiver);

        assertEq(receiverRaBalanceAfter - receiverRaBalanceBefore, actualRa, "Receiver should receive collateral assets");
        assertEq(receiverPaBalanceAfter - receiverPaBalanceBefore, actualPa, "Receiver should receive reference assets");

        uint256 ownerRaBalanceAfter = collateralAsset.balanceOf(owner);
        uint256 ownerPaBalanceAfter = referenceAsset.balanceOf(owner);

        assertEq(ownerRaBalanceAfter, ownerRaBalanceBefore, "Owner should not receive collateral assets");
        assertEq(ownerPaBalanceAfter, ownerPaBalanceBefore, "Owner should not receive reference assets");

        vm.stopPrank();
    }

    function test_redeemWithDifferentSenderOwner() public {
        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(sender, REDEEM_AMOUNT);
        PoolShare(principalToken).approve(address(corkPoolManager), REDEEM_AMOUNT);

        vm.stopPrank();

        uint256 allowanceBefore = PoolShare(principalToken).allowance(owner, sender);
        assertEq(allowanceBefore, REDEEM_AMOUNT, "Allowance should be set correctly");

        uint256 receiverRaBalanceBefore = collateralAsset.balanceOf(receiver);
        uint256 receiverPaBalanceBefore = referenceAsset.balanceOf(receiver);

        vm.startPrank(sender);

        (uint256 actualPa, uint256 actualRa) = corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT, owner, receiver);
        vm.stopPrank();

        uint256 receiverRaBalanceAfter = collateralAsset.balanceOf(receiver);
        uint256 receiverPaBalanceAfter = referenceAsset.balanceOf(receiver);

        assertEq(receiverRaBalanceAfter - receiverRaBalanceBefore, actualRa, "Receiver should receive collateral assets");
        assertEq(receiverPaBalanceAfter - receiverPaBalanceBefore, actualPa, "Receiver should receive reference assets");

        uint256 allowanceAfter = PoolShare(principalToken).allowance(owner, sender);
        assertEq(allowanceAfter, 0, "Allowance should be fully spent");
    }

    function test_redeemWithInsufficientAllowance() public {
        vm.startPrank(owner);
        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        vm.stopPrank();

        vm.startPrank(sender);
        vm.expectRevert();
        corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT, owner, receiver);
        vm.stopPrank();
    }

    function test_redeemWithExactAllowance() public {
        vm.startPrank(owner);
        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(sender, REDEEM_AMOUNT);
        vm.stopPrank();

        uint256 receiverRaBalanceBefore = collateralAsset.balanceOf(receiver);
        uint256 receiverPaBalanceBefore = referenceAsset.balanceOf(receiver);

        vm.startPrank(sender);
        (uint256 actualPa, uint256 actualRa) = corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT, owner, receiver);
        vm.stopPrank();

        uint256 receiverRaBalanceAfter = collateralAsset.balanceOf(receiver);
        uint256 receiverPaBalanceAfter = referenceAsset.balanceOf(receiver);

        assertEq(receiverRaBalanceAfter - receiverRaBalanceBefore, actualRa, "Receiver should receive collateral assets");
        assertEq(receiverPaBalanceAfter - receiverPaBalanceBefore, actualPa, "Receiver should receive reference assets");

        uint256 allowanceAfter = PoolShare(principalToken).allowance(owner, sender);
        assertEq(allowanceAfter, 0, "Allowance should be fully spent");
    }

    function test_redeemWithZeroAmount() public {
        vm.startPrank(owner);

        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.redeem(defaultCurrencyId, 0, owner, receiver);

        vm.stopPrank();
    }

    function test_redeemMultipleReceivers() public {
        address receiver2 = address(0x4);

        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(address(corkPoolManager), REDEEM_AMOUNT);

        uint256 receiver1RaBalanceBefore = collateralAsset.balanceOf(receiver);
        uint256 receiver2RaBalanceBefore = collateralAsset.balanceOf(receiver2);

        (uint256 actualPa1, uint256 actualRa1) = corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT / 2, owner, receiver);

        (uint256 actualPa2, uint256 actualRa2) = corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT / 2, owner, receiver2);

        uint256 receiver1RaBalanceAfter = collateralAsset.balanceOf(receiver);
        uint256 receiver2RaBalanceAfter = collateralAsset.balanceOf(receiver2);

        assertEq(receiver1RaBalanceAfter - receiver1RaBalanceBefore, actualRa1, "Receiver1 should receive collateral assets");
        assertEq(receiver2RaBalanceAfter - receiver2RaBalanceBefore, actualRa2, "Receiver2 should receive collateral assets");

        vm.stopPrank();
    }

    function test_redeemPreviewConsistency() public {
        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(address(corkPoolManager), REDEEM_AMOUNT);

        (uint256 previewPa, uint256 previewRa) = corkPoolManager.previewRedeem(defaultCurrencyId, REDEEM_AMOUNT);

        (uint256 actualPa, uint256 actualRa) = corkPoolManager.redeem(defaultCurrencyId, REDEEM_AMOUNT, owner, receiver);

        assertEq(actualPa, previewPa, "Actual reference asset should match preview");
        assertEq(actualRa, previewRa, "Actual collateral asset should match preview");

        vm.stopPrank();
    }

    function test_maxWithdraw_ownerWithShares() public {
        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        uint256 ownerShares = IERC20(principalToken).balanceOf(owner);

        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);

        assertEq(maxWithdrawAmount, DEPOSIT_AMOUNT, "Owner should be able to withdraw some amount");
        assertEq(ownerShares, DEPOSIT_AMOUNT, "Owner should have shares");

        vm.stopPrank();
    }

    function test_maxWithdraw_ownerWithoutShares() public {
        address userWithoutShares = address(0x5);

        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultCurrencyId, userWithoutShares);

        assertEq(maxWithdrawAmount, 0, "User without shares should not be able to withdraw");
    }

    function test_maxWithdraw_whenWithdrawalsPaused() public {
        vm.startPrank(owner);

        uint256 maxWithdrawBeforePause = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);
        assertEq(maxWithdrawBeforePause, DEPOSIT_AMOUNT, "Should be able to withdraw before pause");

        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseWithdrawals(defaultCurrencyId);
        revertPrank();

        uint256 maxWithdrawAfterPause = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);
        assertEq(maxWithdrawAfterPause, 0, "Should not be able to withdraw when paused");

        vm.stopPrank();
    }

    function test_maxWithdraw_consistencyWithActualWithdraw() public {
        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        PoolShare(principalToken).approve(address(corkPoolManager), type(uint256).max);

        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);

        uint256 receiverBalanceBefore = collateralAsset.balanceOf(receiver);

        (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) = corkPoolManager.withdraw(defaultCurrencyId, maxWithdrawAmount, owner, receiver);

        uint256 receiverBalanceAfter = collateralAsset.balanceOf(receiver);
        uint256 actualWithdrawn = receiverBalanceAfter - receiverBalanceBefore;

        assertEq(actualWithdrawn, maxWithdrawAmount, "Actual withdraw should match maxWithdraw");
        assertEq(sharesIn, DEPOSIT_AMOUNT, "Should have burned some shares");

        vm.stopPrank();
    }

    function test_maxWithdraw_edgeCaseZeroPoolBalance() public {
        vm.startPrank(owner);

        (address principalToken,) = corkPoolManager.shares(defaultCurrencyId);
        uint256 ownerShares = IERC20(principalToken).balanceOf(owner);

        uint256 maxWithdraw = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);

        if (ownerShares > 0) {
            PoolShare(principalToken).approve(address(corkPoolManager), type(uint256).max);
            corkPoolManager.withdraw(defaultCurrencyId, maxWithdraw, owner, owner);
        }

        uint256 maxWithdrawAfterDrain = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);
        assertEq(maxWithdrawAfterDrain, 0, "Should not be able to withdraw when pool is drained");

        vm.stopPrank();
    }

    function test_maxWithdraw_ShouldBeZeroBeforeExpiry() public {
        vm.startPrank(owner);

        uint256 expiry = corkPoolManager.expiry(defaultCurrencyId);
        vm.warp(expiry - 1 hours);

        uint256 maxWithdrawAmount = corkPoolManager.maxWithdraw(defaultCurrencyId, owner);

        assertEq(maxWithdrawAmount, 0, "Should not be able to withdraw before expiry");

        vm.stopPrank();
    }
}
