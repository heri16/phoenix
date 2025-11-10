// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract SafeUnwindMintTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal unwindAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(DEFAULT_ADDRESS);
        _deposit(defaultPoolId, unwindAmount, DEFAULT_ADDRESS);

        principalToken.transfer(address(corkAdapter), unwindAmount);
        swapToken.transfer(address(corkAdapter), unwindAmount);
    }

    // ================================ SAFE_UNWIND_MINT TESTS ================================ //

    function test_safeUnwindMint_ShouldBurnTokensCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(stateAfter.contractCollateral, stateBefore.contractCollateral - unwindAmount, "Contract should sent correct amount of collateral assets");
        assertEq(stateAfter.principalTokenTotalSupply, stateBefore.principalTokenTotalSupply - unwindAmount, "Correct amount of CPT should get burned");
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeUnwindMint_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: address(0), minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp - 1}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: address(0), minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenPassedInvalidOwner() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: alice, receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: 0, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenSlippageExeceed() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount + 1, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 3); // 01000 = unwind deposit paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenUnwindMintsPaused() public __as(pauser) {
        defaultCorkController.pauseUnwindDepositAndMints(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindMint_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindMint(ICorkAdapter.SafeUnwindMintParams({poolId: defaultPoolId, cptAndCstSharesIn: unwindAmount, owner: address(corkAdapter), receiver: alice, minCollateralAssetsOut: unwindAmount, deadline: block.timestamp}));
    }
}
