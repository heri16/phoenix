// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract SafeMintTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal mintAmount = 1000 ether;

    // ================================ SAFE_MINT TESTS ================================ //

    function test_safeMint_ShouldMintTokens() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));

        // Take state snapshot after safeMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify users balances
        assertEq(stateAfter.userPrincipalToken - stateBefore.userPrincipalToken, mintAmount, "User should get correct amount of principal tokens");
        assertEq(stateAfter.userSwapToken - stateBefore.userSwapToken, mintAmount, "User should get correct amount of swap tokens");

        // Verify contract state changes
        assertEq(stateAfter.contractCollateral - stateBefore.contractCollateral, mintAmount, "Contract should get correct amount of collateral assets");
        assertEq(stateAfter.principalTokenTotalSupply - stateBefore.principalTokenTotalSupply, mintAmount, "Correct amount of CPT should get minted");
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeMint_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: address(0), maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp - 1}));
    }

    function test_safeMint_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: address(0), maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenZeroShares() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: 0, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenSlippageExeceed() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount - 1, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1); // 00001 = deposit paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenDepositsPaused() public __as(pauser) {
        defaultCorkController.pauseDeposits(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }

    function test_safeMint_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeMint(ICorkAdapter.SafeMintParams({poolId: defaultPoolId, cptAndCstSharesOut: mintAmount, receiver: alice, maxCollateralAssetsIn: mintAmount, deadline: block.timestamp}));
    }
}
