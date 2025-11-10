// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract SafeRedeemTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal redeemAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(DEFAULT_ADDRESS);
        _deposit(defaultPoolId, redeemAmount, DEFAULT_ADDRESS);

        principalToken.transfer(address(corkAdapter), redeemAmount);

        vm.warp(block.timestamp + 1 days);
    }

    // ================================ SAFE_REDEEM TESTS ================================ //

    function test_safeRedeem_ShouldRedeemTokensCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeRedeem
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));

        // Take state snapshot after safeRedeem
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(stateAfter.contractCollateral, stateBefore.contractCollateral - redeemAmount, "Contract should sent correct amount of collateral assets");
        assertEq(stateAfter.contractRef, stateBefore.contractRef - 0, "Contract should sent correct amount of reference assets");
        assertEq(stateAfter.principalTokenTotalSupply, stateBefore.principalTokenTotalSupply - redeemAmount, "Correct amount of CPT should get burned");
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeRedeem_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: address(0), minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp - 1}));
    }

    function test_safeRedeem_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: address(0), minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenPassedInvalidOwner() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: alice, receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: 0, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenSlippageExeceed() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        // Less collateral asset than minCollateralAssetsOut
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount + 1, deadline: block.timestamp}));

        // Less reference asset than minReferenceAssetsOut
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: redeemAmount, minCollateralAssetsOut: 0, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenNotExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp - 12 hours);

        vm.expectRevert(IErrors.NotExpired.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2); // 00100 = withdrawal paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenRedeemsPaused() public __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }

    function test_safeRedeem_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultPoolId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: alice, minReferenceAssetsOut: 0, minCollateralAssetsOut: redeemAmount, deadline: block.timestamp}));
    }
}
