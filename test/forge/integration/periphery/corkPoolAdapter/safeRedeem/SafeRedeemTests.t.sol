// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SafeRedeemTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal redeemAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(bravo);
        _deposit(defaultPoolId, redeemAmount, bravo);

        principalToken.transfer(address(corkAdapter), redeemAmount);

        vm.warp(block.timestamp + 1 days);
    }

    // ================================ SAFE_REDEEM TESTS ================================ //

    function test_safeRedeem_ShouldRedeemTokensCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeRedeem
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeRedeem
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral - redeemAmount,
            "Contract should sent correct amount of collateral assets"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef - 0,
            "Contract should sent correct amount of reference assets"
        );
        assertEq(
            stateAfter.principalTokenTotalSupply,
            stateBefore.principalTokenTotalSupply - redeemAmount,
            "Correct amount of cPT should get burned"
        );
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeRedeem_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: address(0),
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp - 1
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: address(0),
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenPassedInvalidOwner() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: alice,
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: 0,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenSlippageExeceed()
        external
        __giveAssets(address(corkAdapter))
        __as(BUNDLER3_ADDRESS)
    {
        // Less collateral asset than minCollateralAssetsOut
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount + 1,
                deadline: block.timestamp
            })
        );

        // Less reference asset than minReferenceAssetsOut
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: redeemAmount,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenNotExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp - 12 hours);

        vm.expectRevert(IErrors.NotExpired.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 2); // 00100 = withdrawal paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenRedeemsPaused() public __as(pauser) {
        defaultCorkController.pauseWithdrawals(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeRedeem_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: redeemAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: redeemAmount,
                deadline: block.timestamp
            })
        );
    }

    // ================================ TYPE(UINT256).MAX TESTS ================================ //

    function test_safeRedeem_ShouldUseCptBalance_WhenMaxUintAndOwnerIsAdapter() external __as(BUNDLER3_ADDRESS) {
        // Setup: Ensure adapter has cPT tokens
        uint256 expectedRedeemAmount = redeemAmount;

        // Take state snapshot before safeRedeem
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceBefore = principalToken.balanceOf(address(corkAdapter));

        // Verify precondition
        assertEq(adapterCptBalanceBefore, expectedRedeemAmount, "Adapter should have cPT tokens");

        // Call with type(uint256).max - should use adapter's cPT balance
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeRedeem
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceAfter = principalToken.balanceOf(address(corkAdapter));

        // Verify that all cPT balance was used
        assertEq(adapterCptBalanceAfter, 0, "All adapter cPT balance should be used");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + expectedRedeemAmount,
            "User should receive collateral"
        );
    }

    function test_safeRedeem_ShouldUseCptAllowance_WhenMaxUintAndOwnerIsNotAdapter() external {
        // Setup: Transfer cPT to alice and set allowance
        overridePrank(address(corkAdapter));
        principalToken.transfer(alice, redeemAmount);

        overridePrank(alice);
        uint256 allowanceAmount = 600 ether;
        principalToken.approve(address(corkAdapter), allowanceAmount);

        overridePrank(BUNDLER3_ADDRESS);
        mockBundler.setInitiator(alice);

        // Take state snapshot before safeRedeem
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptBalanceBefore = principalToken.balanceOf(alice);
        uint256 aliceCptAllowanceBefore = principalToken.allowance(alice, address(corkAdapter));

        // Verify preconditions
        assertEq(aliceCptAllowanceBefore, allowanceAmount, "Alice should have set allowance");
        assertGt(aliceCptBalanceBefore, allowanceAmount, "Alice should have more cPT than allowance");

        // Call with type(uint256).max - should use alice's allowance, not her full balance
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: type(uint256).max,
                owner: alice,
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeRedeem
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptBalanceAfter = principalToken.balanceOf(alice);

        // Verify that only the allowance amount was used, not the full balance
        uint256 actualUsedAmount = aliceCptBalanceBefore - aliceCptBalanceAfter;
        assertEq(actualUsedAmount, allowanceAmount, "Should use allowance amount, not full balance");
        assertEq(aliceCptBalanceAfter, aliceCptBalanceBefore - allowanceAmount, "Remaining balance should be correct");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + allowanceAmount,
            "User should receive collateral equal to allowance"
        );
    }

    function test_safeRedeem_ShouldUseFullBalance_WhenMaxUintAndOwnerIsAdapterWithPartialBalance() external {
        // Setup: Give adapter only partial cPT amount
        uint256 partialAmount = 400 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(bravo, principalToken.balanceOf(address(corkAdapter)));

        overridePrank(bravo);
        principalToken.transfer(address(corkAdapter), partialAmount);

        overridePrank(BUNDLER3_ADDRESS);

        // Take state snapshot before safeRedeem
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceBefore = principalToken.balanceOf(address(corkAdapter));

        // Verify precondition
        assertEq(adapterCptBalanceBefore, partialAmount, "Adapter should have partial cPT balance");

        // Call with type(uint256).max - should use adapter's actual balance
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeRedeem
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceAfter = principalToken.balanceOf(address(corkAdapter));

        // Verify that the partial balance was used
        assertEq(adapterCptBalanceAfter, 0, "All adapter cPT balance should be used");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + partialAmount,
            "User should receive collateral equal to partial amount"
        );
    }

    function test_safeRedeem_ShouldUsePartialAllowance_WhenMaxUintAndOwnerHasLimitedApproval() external {
        // Setup: Transfer cPT to alice and set limited allowance
        overridePrank(address(corkAdapter));
        principalToken.transfer(alice, redeemAmount);

        overridePrank(alice);
        uint256 limitedAllowance = 300 ether;
        principalToken.approve(address(corkAdapter), limitedAllowance);

        overridePrank(BUNDLER3_ADDRESS);
        mockBundler.setInitiator(alice);

        // Take state snapshot before safeRedeem
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptBalanceBefore = principalToken.balanceOf(alice);
        uint256 aliceCptAllowanceBefore = principalToken.allowance(alice, address(corkAdapter));

        // Verify preconditions
        assertEq(aliceCptAllowanceBefore, limitedAllowance, "Alice should have limited allowance");
        assertEq(aliceCptBalanceBefore, redeemAmount, "Alice should have full balance");

        // Call with type(uint256).max - should use only the limited allowance
        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: type(uint256).max,
                owner: alice,
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeRedeem
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptBalanceAfter = principalToken.balanceOf(alice);

        // Verify that only the limited allowance was used
        uint256 actualUsedAmount = aliceCptBalanceBefore - aliceCptBalanceAfter;
        assertEq(actualUsedAmount, limitedAllowance, "Should use only the limited allowance");
        assertEq(aliceCptBalanceAfter, redeemAmount - limitedAllowance, "Remaining balance should be correct");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + limitedAllowance,
            "User should receive collateral equal to limited allowance"
        );
    }

    function test_safeRedeem_ShouldWorkCorrectly_WhenOwnerIsAdapterAndMaxUintPassed() external {
        // Setup: Multiple redeems with different balances
        uint256 firstRedeemAmount = 700 ether;
        uint256 secondRedeemAmount = 300 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(bravo, principalToken.balanceOf(address(corkAdapter)));

        overridePrank(bravo);
        principalToken.transfer(address(corkAdapter), firstRedeemAmount);

        overridePrank(BUNDLER3_ADDRESS);

        // First redeem with type(uint256).max
        uint256 adapterBalanceBefore1 = principalToken.balanceOf(address(corkAdapter));
        assertEq(adapterBalanceBefore1, firstRedeemAmount, "Adapter should have first amount");

        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        uint256 adapterBalanceAfter1 = principalToken.balanceOf(address(corkAdapter));
        assertEq(adapterBalanceAfter1, 0, "All first amount should be used");

        // Give adapter more tokens for second redeem
        overridePrank(bravo);
        principalToken.transfer(address(corkAdapter), secondRedeemAmount);

        overridePrank(BUNDLER3_ADDRESS);

        // Second redeem with type(uint256).max
        uint256 adapterBalanceBefore2 = principalToken.balanceOf(address(corkAdapter));
        assertEq(adapterBalanceBefore2, secondRedeemAmount, "Adapter should have second amount");

        corkAdapter.safeRedeem(
            ICorkAdapter.SafeRedeemParams({
                poolId: defaultPoolId,
                cptSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minReferenceAssetsOut: 0,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        uint256 adapterBalanceAfter2 = principalToken.balanceOf(address(corkAdapter));
        assertEq(adapterBalanceAfter2, 0, "All second amount should be used");
    }
}
