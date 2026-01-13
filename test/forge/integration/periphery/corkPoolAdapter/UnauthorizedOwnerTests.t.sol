// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

/**
 * @title UnauthorizedOwnerTests
 * @notice Test suite to verify that functions with owner parameter properly validate ownership.
 * @dev Tests that when Alice approves tokens to CorkAdapter, Bob cannot call functions passing Alice as owner.
 *      According to the validation logic: owner must be either address(this) or initiator()
 */
contract UnauthorizedOwnerTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal testAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        // Setup: Alice has tokens and approves them to CorkAdapter
        overridePrank(alice);
        _deposit(defaultPoolId, testAmount * 2, alice);

        _approveAllTokens(alice, address(corkAdapter));
        _approveAllTokens(bob, address(corkAdapter));
    }

    // ================================ UNAUTHORIZED OWNER TESTS ================================ //

    function test_safeUnwindDeposit_ShouldRevert_WhenUnauthorizedCallerUsesApprovedOwner() external {
        // Bob tries to call CorkAdapter with Alice as owner (Alice has approvals but Bob != Alice)
        overridePrank(bob); // Bob is the initiator

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeUnwindDeposit.selector,
                ICorkAdapter.SafeUnwindDepositParams({
                    poolId: defaultPoolId,
                    collateralAssetsOut: testAmount,
                    owner: alice, // Alice as owner
                    receiver: bob,
                    maxCptAndCstSharesIn: testAmount,
                    deadline: block.timestamp
                })
            )
        );
    }

    function test_safeUnwindMint_ShouldRevert_WhenUnauthorizedCallerUsesApprovedOwner() external {
        // Bob tries to call CorkAdapter with Alice as owner
        overridePrank(bob); // Bob is the initiator

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeUnwindMint.selector,
                ICorkAdapter.SafeUnwindMintParams({
                    poolId: defaultPoolId,
                    cptAndCstSharesIn: testAmount,
                    owner: alice, // Alice as owner
                    receiver: bob,
                    minCollateralAssetsOut: 0,
                    deadline: block.timestamp
                })
            )
        );
    }

    function test_safeRedeem_ShouldRevert_WhenUnauthorizedCallerUsesApprovedOwner() external {
        // Bob tries to call CorkAdapter with Alice as owner
        overridePrank(bob); // Bob is the initiator

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeRedeem.selector,
                ICorkAdapter.SafeRedeemParams({
                    poolId: defaultPoolId,
                    cptSharesIn: testAmount,
                    owner: alice, // Alice as owner
                    receiver: bob,
                    minReferenceAssetsOut: 0,
                    minCollateralAssetsOut: 0,
                    deadline: block.timestamp
                })
            )
        );
    }

    function test_safeWithdraw_ShouldRevert_WhenUnauthorizedCallerUsesApprovedOwner() external {
        // Bob tries to call CorkAdapter with Alice as owner
        overridePrank(bob); // Bob is the initiator

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeWithdraw.selector,
                ICorkAdapter.SafeWithdrawParams({
                    poolId: defaultPoolId,
                    collateralAssetsOut: testAmount,
                    owner: alice, // Alice as owner
                    receiver: bob,
                    maxCptSharesIn: testAmount,
                    deadline: block.timestamp
                })
            )
        );
    }

    function test_AllFunctions_ShouldRevert_WhenOwnerIsUnauthorized() external {
        address unauthorizedOwner = alice;

        overridePrank(bob); // Bob is the initiator

        // Test 1: safeUnwindDeposit
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeUnwindDeposit.selector,
                ICorkAdapter.SafeUnwindDepositParams({
                    poolId: defaultPoolId,
                    collateralAssetsOut: testAmount,
                    owner: unauthorizedOwner,
                    receiver: bob,
                    maxCptAndCstSharesIn: testAmount,
                    deadline: block.timestamp
                })
            )
        );

        // Test 2: safeUnwindMint
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeUnwindMint.selector,
                ICorkAdapter.SafeUnwindMintParams({
                    poolId: defaultPoolId,
                    cptAndCstSharesIn: testAmount,
                    owner: unauthorizedOwner,
                    receiver: bob,
                    minCollateralAssetsOut: 0,
                    deadline: block.timestamp
                })
            )
        );

        // Test 3: safeRedeem
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeRedeem.selector,
                ICorkAdapter.SafeRedeemParams({
                    poolId: defaultPoolId,
                    cptSharesIn: testAmount,
                    owner: unauthorizedOwner,
                    receiver: bob,
                    minReferenceAssetsOut: 0,
                    minCollateralAssetsOut: 0,
                    deadline: block.timestamp
                })
            )
        );

        // Test 4: safeWithdraw
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeWithdraw.selector,
                ICorkAdapter.SafeWithdrawParams({
                    poolId: defaultPoolId,
                    collateralAssetsOut: testAmount,
                    owner: unauthorizedOwner,
                    receiver: bob,
                    maxCptSharesIn: testAmount,
                    deadline: block.timestamp
                })
            )
        );

        // Test 5: safeWithdrawOther
        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeWithdrawOther.selector,
                ICorkAdapter.SafeWithdrawOtherParams({
                    poolId: defaultPoolId,
                    referenceAssetsOut: 1 ether,
                    owner: unauthorizedOwner,
                    receiver: bob,
                    maxCptSharesIn: testAmount,
                    deadline: block.timestamp
                })
            )
        );
    }

    function test_AllFunctions_ShouldRevert_WhenOwnerIsZeroAddress() external {
        overridePrank(bob);

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        _bundlerCall(
            abi.encodeWithSelector(
                corkAdapter.safeUnwindDeposit.selector,
                ICorkAdapter.SafeUnwindDepositParams({
                    poolId: defaultPoolId,
                    collateralAssetsOut: testAmount,
                    owner: address(0),
                    receiver: bob,
                    maxCptAndCstSharesIn: testAmount,
                    deadline: block.timestamp
                })
            )
        );
    }
}
