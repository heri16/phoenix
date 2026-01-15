// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UnwindDepositTests is BaseTest {
    uint256 amount = 500 ether;
    uint256 unwindAmount = 100 ether;

    // ================================ Core UnwindDeposit Tests ================================ //

    function test_unwindDeposit_ShouldWork() external __as(alice) __deposit(amount, alice) {
        // Take snapshots before unwindDeposit
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // Execute unwindDeposit
        vm.expectEmit(true, true, false, true);
        emit IPoolManager.PoolModifyLiquidity(defaultPoolId, alice, alice, unwindAmount, 0, true);
        uint256 tokensIn = corkPoolManager.unwindDeposit(defaultPoolId, unwindAmount, alice, alice);

        // Take snapshots after unwindDeposit
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(tokensIn, unwindAmount, "Should burn equal token amount");

        // ================================ User State Changes ================================ //
        assertEq(
            afterSnapshot.userCollateral,
            beforeSnapshot.userCollateral + unwindAmount,
            "User collateral balance should increase by unwindAmount"
        );
        assertEq(
            afterSnapshot.userPrincipalToken,
            beforeSnapshot.userPrincipalToken - unwindAmount,
            "User principal token balance should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.userSwapToken,
            beforeSnapshot.userSwapToken - unwindAmount,
            "User swap token balance should decrease by unwindAmount"
        );
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef, "User reference asset balance should remain unchanged");

        // ================================ Contract State Changes ================================ //
        assertEq(
            afterSnapshot.contractCollateral,
            beforeSnapshot.contractCollateral - unwindAmount,
            "Contract collateral balance should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.contractRef,
            beforeSnapshot.contractRef,
            "Contract reference asset balance should remain unchanged"
        );

        // ================================ Token Supply Changes ================================ //
        assertEq(
            afterSnapshot.principalTokenTotalSupply,
            beforeSnapshot.principalTokenTotalSupply - unwindAmount,
            "Principal token total supply should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.swapTokenTotalSupply,
            beforeSnapshot.swapTokenTotalSupply - unwindAmount,
            "Swap token total supply should decrease by unwindAmount"
        );

        // ================================ Pool Internal State Changes ================================ //
        assertEq(
            afterSnapshot.poolCollateral,
            beforeSnapshot.poolCollateral - unwindAmount,
            "Pool locked collateral should decrease by unwindAmount"
        );
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef, "Pool reference asset should remain unchanged");

        // ================================ Internal State Consistency ================================ //
        assertEq(
            afterSnapshot.internalState.pool.balances.collateralAsset.locked,
            beforeSnapshot.internalState.pool.balances.collateralAsset.locked - unwindAmount,
            "Internal state locked collateral should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.internalState.pool.balances.referenceAssetBalance,
            beforeSnapshot.internalState.pool.balances.referenceAssetBalance,
            "Internal state locked reference asset should remain unchanged"
        );
    }

    function test_unwindDeposit_ShouldRevert_WhenZeroAmount() external __as(alice) {
        vm.expectRevert(IErrors.InvalidAmount.selector);
        corkPoolManager.unwindDeposit(defaultPoolId, 0, alice, alice);
    }

    function test_unwindDeposit_ShouldRevert_WhenExpired() external __as(alice) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkPoolManager.unwindDeposit(defaultPoolId, unwindAmount, alice, alice);
    }

    function test_unwindDeposit_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 3); // 01000 = unwind deposit paused

        overridePrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindDeposit(defaultPoolId, unwindAmount, alice, alice);
    }

    // ================================ Preview Function Tests ================================ //

    function test_previewUnwindDeposit_ShouldReturnCorrectAmount() external {
        uint256 collateralOut = amount;
        uint256 tokensIn = corkPoolManager.previewUnwindDeposit(defaultPoolId, collateralOut);
        assertEq(tokensIn, collateralOut, "Should return 1:1 ratio");
    }

    // ================================ Max Function Tests ================================ //

    function test_maxUnwindDeposit_ShouldReturnUserBalance() external __as(alice) {
        _deposit(defaultPoolId, amount, currentCaller());

        uint256 maxAmount = corkPoolManager.maxUnwindDeposit(defaultPoolId, alice);
        assertEq(maxAmount, amount, "Should return alice's minimum token balance");
    }

    function test_maxUnwindDeposit_ShouldReturnSameAmount_WhenBalancesAreEqual()
        external
        __as(alice)
        __deposit(1000 ether, alice)
    {
        uint256 swapBalance = swapToken.balanceOf(alice);
        uint256 principalBalance = principalToken.balanceOf(alice);

        // Verify balances are equal
        assertEq(swapBalance, principalBalance, "Balances should be equal after deposit");

        uint256 maxAmount = corkPoolManager.maxUnwindDeposit(defaultPoolId, alice);

        // Should return either balance converted to collateral native decimals
        uint256 expectedAmount = TransferHelper.fixedToTokenNativeDecimals(swapBalance, collateralAsset.decimals());
        assertEq(maxAmount, expectedAmount, "Should return the balance when both are equal");
    }

    function test_maxUnwindDeposit_ShouldReturnZero_WhenUserHasNoTokens() external {
        // Test edge case where alice has no tokens at all
        address delta = makeAddr("delta");

        uint256 maxAmount = corkPoolManager.maxUnwindDeposit(defaultPoolId, delta);
        assertEq(maxAmount, 0, "Should return 0 when alice has no tokens");
    }

    // ================================ PoolShare Wrapper Tests ================================ //

    function test_maxUnwindDeposit_ShouldReturnSameValueAsPoolManager()
        external
        __as(alice)
        __deposit(1000 ether, alice)
    {
        uint256 poolManagerResult = corkPoolManager.maxUnwindDeposit(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxUnwindDeposit(alice);

        assertEq(
            poolShareResult, poolManagerResult, "PoolShare maxUnwindDeposit should match PoolManager maxUnwindDeposit"
        );
    }

    function test_previewUnwindDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 collateralAssetAmountOut = 1 ether;

        uint256 poolManagerResult = corkPoolManager.previewUnwindDeposit(defaultPoolId, collateralAssetAmountOut);
        uint256 poolShareResult = principalToken.previewUnwindDeposit(collateralAssetAmountOut);

        assertEq(
            poolShareResult,
            poolManagerResult,
            "PoolShare previewUnwindDeposit should match PoolManager previewUnwindDeposit"
        );
    }

    // ================================  Integration Tests ================================ //

    function testFuzz_unwindDeposit_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals) external {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());

        // Take snapshots before unwindDeposit
        StateSnapshot memory beforeSnapshot = _getStateSnapshot(alice, defaultPoolId);

        uint256 cptAndCstSharesIn = corkPoolManager.unwindDeposit(defaultPoolId, normalizedDepositAmount, alice, alice);

        // Take snapshots after unwindDeposit
        StateSnapshot memory afterSnapshot = _getStateSnapshot(alice, defaultPoolId);

        // ================================ Core Assertions ================================ //
        assertEq(cptAndCstSharesIn, 1 ether, "Should burn equal token amount");

        // ================================ User State Changes ================================ //
        assertEq(
            afterSnapshot.userCollateral,
            beforeSnapshot.userCollateral + normalizedDepositAmount,
            "User collateral balance should increase by unwindAmount"
        );
        assertEq(
            afterSnapshot.userPrincipalToken,
            beforeSnapshot.userPrincipalToken - 1 ether,
            "User principal token balance should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.userSwapToken,
            beforeSnapshot.userSwapToken - 1 ether,
            "User swap token balance should decrease by unwindAmount"
        );
        assertEq(afterSnapshot.userRef, beforeSnapshot.userRef, "User reference asset balance should remain unchanged");

        // ================================ Contract State Changes ================================ //
        assertEq(
            afterSnapshot.contractCollateral,
            beforeSnapshot.contractCollateral - normalizedDepositAmount,
            "Contract collateral balance should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.contractRef,
            beforeSnapshot.contractRef,
            "Contract reference asset balance should remain unchanged"
        );

        // ================================ Token Supply Changes ================================ //
        assertEq(
            afterSnapshot.principalTokenTotalSupply,
            beforeSnapshot.principalTokenTotalSupply - 1 ether,
            "Principal token total supply should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.swapTokenTotalSupply,
            beforeSnapshot.swapTokenTotalSupply - 1 ether,
            "Swap token total supply should decrease by unwindAmount"
        );

        // ================================ Pool Internal State Changes ================================ //
        assertEq(
            afterSnapshot.poolCollateral,
            beforeSnapshot.poolCollateral - normalizedDepositAmount,
            "Pool locked collateral should decrease by unwindAmount"
        );
        assertEq(afterSnapshot.poolRef, beforeSnapshot.poolRef, "Pool reference asset should remain unchanged");

        // ================================ Internal State Consistency ================================ //
        assertEq(
            afterSnapshot.internalState.pool.balances.collateralAsset.locked,
            beforeSnapshot.internalState.pool.balances.collateralAsset.locked - normalizedDepositAmount,
            "Internal state locked collateral should decrease by unwindAmount"
        );
        assertEq(
            afterSnapshot.internalState.pool.balances.referenceAssetBalance,
            beforeSnapshot.internalState.pool.balances.referenceAssetBalance,
            "Internal state locked reference asset should remain unchanged"
        );
    }

    function test_unwindDeposit_ShouldRevert_WhenSenderDoesNotHaveAllowance() external __as(alice) {
        uint256 depositAmount = 10 ether;
        // deposit
        _deposit(defaultPoolId, depositAmount, alice);

        address randomPerson = address(0x333);
        overridePrank(randomPerson);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, randomPerson, 0, depositAmount)
        );
        corkPoolManager.unwindDeposit(defaultPoolId, depositAmount, alice, randomPerson);
    }

    // ================================ Additional Negative Test Cases ================================ //

    function test_unwindDeposit_ShouldRevert_WhenPoolNotInitialized() external __as(alice) {
        // Create a random market ID that doesn't exist
        MarketId nonExistentPoolId = MarketId.wrap(keccak256("nonexistent"));

        vm.expectRevert(IErrors.NotInitialized.selector);
        corkPoolManager.unwindDeposit(nonExistentPoolId, unwindAmount, alice, alice);
    }

    function test_unwindDeposit_ShouldRevert_WhenInsufficientPrincipalTokenBalance()
        external
        __as(alice)
        __deposit(amount, alice)
    {
        // Try to unwind more than alice has
        uint256 excessiveAmount = amount + 1 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                amount, // alice's actual balance
                excessiveAmount // amount needed
            )
        );
        corkPoolManager.unwindDeposit(defaultPoolId, excessiveAmount, alice, alice);
    }

    function test_unwindDeposit_ShouldRevert_WhenInsufficientSwapTokenBalance()
        external
        __as(alice)
        __deposit(amount, alice)
    {
        // Transfer some swap tokens away to create imbalance
        swapToken.transfer(bob, 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                amount - 50 ether, // alice's remaining swap token balance
                amount // amount needed for full unwind
            )
        );
        corkPoolManager.unwindDeposit(defaultPoolId, amount, alice, alice);
    }

    function test_unwindDeposit_ShouldRevert_WhenInsufficientAllowance() external __as(alice) __deposit(amount, alice) {
        overridePrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(bob),
                0, // current allowance
                unwindAmount // amount needed
            )
        );

        corkPoolManager.unwindDeposit(defaultPoolId, unwindAmount, alice, alice);
    }

    // ================================ Preview Consistency Tests ================================ //

    function testFuzz_previewUnwindDeposit_WithDifferentDecimals(uint8 collateralDecimals, uint8 referenceDecimals)
        external
    {
        // Bound decimals to reasonable ranges
        collateralDecimals = uint8(bound(collateralDecimals, 6, 18));
        referenceDecimals = uint8(bound(referenceDecimals, 6, 18));

        // Create market with different decimals
        createMarket(1 days, collateralDecimals, referenceDecimals, false);
        _giveAssets(alice);
        _approveAllTokens(alice, address(corkPoolManager));

        overridePrank(alice);

        uint256 normalizedDepositAmount = TransferHelper.fixedToTokenNativeDecimals(1 ether, collateralAsset.decimals());

        // First deposit to have tokens for unwinding
        _deposit(defaultPoolId, normalizedDepositAmount, currentCaller());

        // Preview unwind deposit
        uint256 previewTokensIn = corkPoolManager.previewUnwindDeposit(defaultPoolId, normalizedDepositAmount);

        // Execute actual unwind deposit
        uint256 actualTokensIn = corkPoolManager.unwindDeposit(defaultPoolId, normalizedDepositAmount, alice, alice);

        // Verify preview matches actual
        assertEq(previewTokensIn, actualTokensIn, "Preview tokens in should match actual tokens in");

        // Verify that the unwinding functioned correctly with decimal normalization
        assertEq(actualTokensIn, 1 ether, "Should return 1 ether in fixed-point representation");
        assertGt(actualTokensIn, 0, "Should require some tokens for unwinding");
    }

    function testFuzz_unwindDepositShouldNotRevert_WhenUsingMaxUnwindDepositInput(
        uint8 _collateralDecimal,
        uint8 _referenceDecimal,
        uint256 depositAmount
    )
        external
        __createPoolBounded(1 days, _collateralDecimal, _referenceDecimal)
        __giveAssets(alice)
        __approveAllTokens(alice, address(corkPoolManager))
        __as(alice)
    {
        // Bound deposit amount to reasonable values
        depositAmount = bound(depositAmount, 1 ether, type(uint64).max);

        // Deposit to get cPT and cST shares
        _deposit(defaultPoolId, depositAmount, alice);

        // Get max unwindable collateral
        uint256 collateralAssetsOut = corkPoolManager.maxUnwindDeposit(defaultPoolId, alice);

        // should not revert
        corkPoolManager.unwindDeposit(defaultPoolId, collateralAssetsOut, alice, alice);
    }
}
