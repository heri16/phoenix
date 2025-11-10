// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract SafeWithdrawOtherTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal withdrawAmount = 1 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        _deposit(defaultPoolId, 1000 ether, DEFAULT_ADDRESS);

        _swap(defaultPoolId, 1000 ether, DEFAULT_ADDRESS);

        principalToken.transfer(address(corkAdapter), withdrawAmount);

        vm.warp(block.timestamp + 1 days);
    }

    // ================================ SAFE_WITHDRAW TESTS ================================ //

    function test_safeWithdrawOther_ShouldWithdrawTokensCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeWithdrawOther
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));

        // Take state snapshot after safeWithdrawOther
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(stateAfter.contractCollateral, stateBefore.contractCollateral - 0, "Contract should sent correct amount of collateral assets");
        assertEq(stateAfter.contractRef, stateBefore.contractRef - withdrawAmount, "Contract should sent correct amount of reference assets");
        assertEq(stateAfter.principalTokenTotalSupply, stateBefore.principalTokenTotalSupply - withdrawAmount, "Correct amount of CPT should get burned");
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeWithdrawOther_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: address(0), maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp - 1}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: address(0), maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenPassedInvalidOwner() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: alice, receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: 0, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenSlippageExeceed() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount / 10, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenNotExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp - 12 hours);

        vm.expectRevert(IErrors.NotExpired.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2); // 00100 = withdrawal paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenWithdrawsPaused() public __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }

    function test_safeWithdrawOther_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeWithdrawOther(ICorkAdapter.SafeWithdrawOtherParams({poolId: defaultPoolId, referenceAssetsOut: withdrawAmount, owner: address(corkAdapter), receiver: alice, maxCptSharesIn: withdrawAmount, deadline: block.timestamp}));
    }
}
