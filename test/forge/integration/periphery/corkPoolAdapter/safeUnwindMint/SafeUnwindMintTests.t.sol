// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SafeUnwindMintTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal unwindAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(bravo);
        _deposit(defaultPoolId, unwindAmount, bravo);

        principalToken.transfer(address(corkAdapter), unwindAmount);
        swapToken.transfer(address(corkAdapter), unwindAmount);
    }

    // ================================ SAFE_UNWIND_MINT TESTS ================================ //

    function test_safeUnwindMint_ShouldBurnTokensCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral - unwindAmount,
            "Contract should sent correct amount of collateral assets"
        );
        assertEq(
            stateAfter.principalTokenTotalSupply,
            stateBefore.principalTokenTotalSupply - unwindAmount,
            "Correct amount of cPT should get burned"
        );
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeUnwindMint_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: address(0),
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp - 1
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: address(0),
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenPassedInvalidOwner() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: alice,
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: 0,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenSlippageExeceed()
        external
        __giveAssets(address(corkAdapter))
        __as(BUNDLER3_ADDRESS)
    {
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount + 1,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 3); // 01000 = unwind deposit paused

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenUnwindMintsPaused() public __as(pauser) {
        defaultCorkController.pauseUnwindDepositAndMints(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: unwindAmount,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: unwindAmount,
                deadline: block.timestamp
            })
        );
    }

    // ================================ TYPE(UINT256).MAX TESTS ================================ //

    function test_safeUnwindMint_ShouldWorkWithMaxUint_WhenOwnerIsAdapter() external __as(BUNDLER3_ADDRESS) {
        uint256 expectedAmount = unwindAmount;

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceBefore = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceBefore = swapToken.balanceOf(address(corkAdapter));

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: expectedAmount,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceAfter = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceAfter = swapToken.balanceOf(address(corkAdapter));

        // Verify that the expected amount was used (minimum of cPT and cST balances)
        uint256 expectedUsedAmount =
            adapterCptBalanceBefore < adapterCstBalanceBefore ? adapterCptBalanceBefore : adapterCstBalanceBefore;

        // Verify contract state changes
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + expectedUsedAmount,
            "User should receive correct amount of collateral assets"
        );
        assertEq(
            adapterCptBalanceAfter,
            adapterCptBalanceBefore - expectedUsedAmount,
            "Adapter cPT balance should decrease by used amount"
        );
        assertEq(
            adapterCstBalanceAfter,
            adapterCstBalanceBefore - expectedUsedAmount,
            "Adapter cST balance should decrease by used amount"
        );
    }

    function test_safeUnwindMint_ShouldWorkWithMaxUint_WhenOwnerHasApproval() external {
        // Setup: Transfer tokens from adapter back to alice and have alice approve adapter
        overridePrank(address(corkAdapter));
        principalToken.transfer(alice, unwindAmount);
        swapToken.transfer(alice, unwindAmount);

        overridePrank(alice);
        principalToken.approve(address(corkAdapter), unwindAmount);
        swapToken.approve(address(corkAdapter), unwindAmount);

        overridePrank(BUNDLER3_ADDRESS);
        mockBundler.setInitiator(alice);

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptBalanceBefore = principalToken.balanceOf(alice);
        uint256 aliceCstBalanceBefore = swapToken.balanceOf(alice);
        uint256 aliceCptAllowanceBefore = principalToken.allowance(alice, address(corkAdapter));
        uint256 aliceCstAllowanceBefore = swapToken.allowance(alice, address(corkAdapter));

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: alice,
                receiver: alice,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify that the expected amount was used (minimum of cPT and cST allowances)
        uint256 expectedUsedAmount =
            aliceCptAllowanceBefore < aliceCstAllowanceBefore ? aliceCptAllowanceBefore : aliceCstAllowanceBefore;

        // Verify contract state changes
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + expectedUsedAmount,
            "User should receive correct amount of collateral assets"
        );
        assertEq(
            principalToken.balanceOf(alice),
            aliceCptBalanceBefore - expectedUsedAmount,
            "Alice cPT balance should decrease by used amount"
        );
        assertEq(
            swapToken.balanceOf(alice),
            aliceCstBalanceBefore - expectedUsedAmount,
            "Alice cST balance should decrease by used amount"
        );
    }

    function test_safeUnwindMint_ShouldUseCptBalance_WhenCptBalanceLessThanCstBalance() external {
        // Setup: Give adapter different amounts of cPT and cST (cPT < cST)
        uint256 cptAmount = 500 ether;
        uint256 cstAmount = 1000 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(bravo, principalToken.balanceOf(address(corkAdapter)));
        swapToken.transfer(bravo, swapToken.balanceOf(address(corkAdapter)));

        overridePrank(bravo);
        principalToken.transfer(address(corkAdapter), cptAmount);
        swapToken.transfer(address(corkAdapter), cstAmount);

        overridePrank(BUNDLER3_ADDRESS);

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceBefore = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceBefore = swapToken.balanceOf(address(corkAdapter));

        // Verify preconditions
        assertLt(adapterCptBalanceBefore, adapterCstBalanceBefore, "cPT balance should be less than cST balance");

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceAfter = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceAfter = swapToken.balanceOf(address(corkAdapter));

        // Verify that cPT balance was used (the smaller one)
        uint256 actualUsedAmount = adapterCptBalanceBefore - adapterCptBalanceAfter;
        assertEq(actualUsedAmount, cptAmount, "Should use cPT balance as it's smaller");
        assertEq(adapterCptBalanceAfter, 0, "All cPT should be used");
        assertEq(adapterCstBalanceAfter, cstAmount - cptAmount, "cST should have remaining balance");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + cptAmount,
            "User should receive collateral equal to cPT amount"
        );
    }

    function test_safeUnwindMint_ShouldUseCstBalance_WhenCstBalanceLessThanCptBalance() external {
        // Setup: Give adapter different amounts of cPT and cST (cST < cPT)
        uint256 cptAmount = 1000 ether;
        uint256 cstAmount = 500 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(bravo, principalToken.balanceOf(address(corkAdapter)));
        swapToken.transfer(bravo, swapToken.balanceOf(address(corkAdapter)));

        overridePrank(bravo);
        principalToken.transfer(address(corkAdapter), cptAmount);
        swapToken.transfer(address(corkAdapter), cstAmount);

        overridePrank(BUNDLER3_ADDRESS);

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceBefore = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceBefore = swapToken.balanceOf(address(corkAdapter));

        // Verify preconditions
        assertGt(adapterCptBalanceBefore, adapterCstBalanceBefore, "cPT balance should be greater than cST balance");

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceAfter = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceAfter = swapToken.balanceOf(address(corkAdapter));

        // Verify that cST balance was used (the smaller one)
        uint256 actualUsedAmount = adapterCstBalanceBefore - adapterCstBalanceAfter;
        assertEq(actualUsedAmount, cstAmount, "Should use cST balance as it's smaller");
        assertEq(adapterCstBalanceAfter, 0, "All cST should be used");
        assertEq(adapterCptBalanceAfter, cptAmount - cstAmount, "cPT should have remaining balance");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + cstAmount,
            "User should receive collateral equal to cST amount"
        );
    }

    function test_safeUnwindMint_ShouldUseEitherBalance_WhenCptBalanceEqualsCstBalance() external {
        // Setup: Give adapter equal amounts of cPT and cST
        uint256 equalAmount = 750 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(bravo, principalToken.balanceOf(address(corkAdapter)));
        swapToken.transfer(bravo, swapToken.balanceOf(address(corkAdapter)));

        overridePrank(bravo);
        principalToken.transfer(address(corkAdapter), equalAmount);
        swapToken.transfer(address(corkAdapter), equalAmount);

        overridePrank(BUNDLER3_ADDRESS);

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceBefore = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceBefore = swapToken.balanceOf(address(corkAdapter));

        // Verify preconditions
        assertEq(adapterCptBalanceBefore, adapterCstBalanceBefore, "cPT and cST balances should be equal");

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: address(corkAdapter),
                receiver: alice,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);
        uint256 adapterCptBalanceAfter = principalToken.balanceOf(address(corkAdapter));
        uint256 adapterCstBalanceAfter = swapToken.balanceOf(address(corkAdapter));

        // Verify that the equal amount was used
        assertEq(adapterCptBalanceAfter, 0, "All cPT should be used");
        assertEq(adapterCstBalanceAfter, 0, "All cST should be used");
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + equalAmount,
            "User should receive collateral equal to the equal amount"
        );
    }

    function test_safeUnwindMint_ShouldUseCptAllowance_WhenCptAllowanceLessThanCstAllowance() external {
        // Setup: Transfer tokens to alice and give different allowances (cPT < cST)
        uint256 cptAllowance = 400 ether;
        uint256 cstAllowance = 800 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(alice, unwindAmount);
        swapToken.transfer(alice, unwindAmount);

        overridePrank(alice);
        principalToken.approve(address(corkAdapter), cptAllowance);
        swapToken.approve(address(corkAdapter), cstAllowance);

        overridePrank(BUNDLER3_ADDRESS);
        mockBundler.setInitiator(alice);

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptAllowanceBefore = principalToken.allowance(alice, address(corkAdapter));
        uint256 aliceCstAllowanceBefore = swapToken.allowance(alice, address(corkAdapter));

        // Verify preconditions
        assertLt(aliceCptAllowanceBefore, aliceCstAllowanceBefore, "cPT allowance should be less than cST allowance");

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: alice,
                receiver: alice,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify that cPT allowance was used (the smaller one)
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + cptAllowance,
            "User should receive collateral equal to cPT allowance"
        );
    }

    function test_safeUnwindMint_ShouldUseCstAllowance_WhenCstAllowanceLessThanCptAllowance() external {
        // Setup: Transfer tokens to alice and give different allowances (cST < cPT)
        uint256 cptAllowance = 800 ether;
        uint256 cstAllowance = 400 ether;

        overridePrank(address(corkAdapter));
        principalToken.transfer(alice, unwindAmount);
        swapToken.transfer(alice, unwindAmount);

        overridePrank(alice);
        principalToken.approve(address(corkAdapter), cptAllowance);
        swapToken.approve(address(corkAdapter), cstAllowance);

        overridePrank(BUNDLER3_ADDRESS);
        mockBundler.setInitiator(alice);

        // Take state snapshot before safeUnwindMint
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);
        uint256 aliceCptAllowanceBefore = principalToken.allowance(alice, address(corkAdapter));
        uint256 aliceCstAllowanceBefore = swapToken.allowance(alice, address(corkAdapter));

        // Verify preconditions
        assertGt(aliceCptAllowanceBefore, aliceCstAllowanceBefore, "cPT allowance should be greater than cST allowance");

        corkAdapter.safeUnwindMint(
            ICorkAdapter.SafeUnwindMintParams({
                poolId: defaultPoolId,
                cptAndCstSharesIn: type(uint256).max,
                owner: alice,
                receiver: alice,
                minCollateralAssetsOut: 0,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after safeUnwindMint
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify that cST allowance was used (the smaller one)
        assertEq(
            stateAfter.userCollateral,
            stateBefore.userCollateral + cstAllowance,
            "User should receive collateral equal to cST allowance"
        );
    }
}
