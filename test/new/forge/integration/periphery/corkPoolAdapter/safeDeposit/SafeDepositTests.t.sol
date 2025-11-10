// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract SafeDepositTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal depositAmount = 1000 ether;

    // ================================ SAFE_DEPOSIT TESTS ================================ //

    function test_safeDeposit_ShouldMintTokensCorrectly() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeDeposit
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp}));

        // Take state snapshot after safeDeposit
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify users balances
        assertEq(stateAfter.userPrincipalToken - stateBefore.userPrincipalToken, depositAmount, "User should get correct amount of principal tokens");
        assertEq(stateAfter.userSwapToken - stateBefore.userSwapToken, depositAmount, "User should get correct amount of swap tokens");

        // Verify contract state changes
        assertEq(stateAfter.contractCollateral - stateBefore.contractCollateral, depositAmount, "Contract should get correct amount of collateral assets");
        assertEq(stateAfter.principalTokenTotalSupply - stateBefore.principalTokenTotalSupply, depositAmount, "Correct amount of CPT should get minted");
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeDeposit_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: address(0), minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp - 1}));
    }

    function test_safeDeposit_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: address(0), minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAmount.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: 0, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenSlippageExeceed() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: depositAmount + 100, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // 00001 = deposit paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenDepositsPaused() public __as(pauser) {
        defaultCorkController.pauseDeposits(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }

    function test_safeDeposit_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultPoolId, collateralAssetsIn: depositAmount, receiver: alice, minCptAndCstSharesOut: 0, deadline: block.timestamp}));
    }
}
