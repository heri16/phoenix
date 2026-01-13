// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {BaseTest} from "test/forge/BaseTest.sol";

/**
 * @title BobOwnershipTest
 * @notice Test to verify that ensOwner is the owner of all Ownable contracts
 */
contract OwnershipTest is BaseTest {
    function test_BobIsOwnerOfAllContracts() external {
        // Test DefaultCorkController
        assertEq(defaultCorkController.owner(), ensOwner, "Bob should be owner of DefaultCorkController");

        // Test SharesFactory
        assertEq(sharesFactory.owner(), ensOwner, "Bob should be owner of SharesFactory");

        // Test CorkPoolManager
        assertEq(corkPoolManager.owner(), ensOwner, "Bob should be owner of CorkPoolManager");

        // Test WhitelistManager
        assertEq(whitelistManager.owner(), ensOwner, "Bob should be owner of WhitelistManager");

        // Test ConstraintRateAdapter
        assertEq(constraintRateAdapter.owner(), ensOwner, "Bob should be owner of ConstraintRateAdapter");

        // Test CorkAdapter
        assertEq(corkAdapter.owner(), ensOwner, "Bob should be owner of CorkAdapter");

        // Test that PoolShare tokens also have ensOwner as owner
        // The PoolShare tokens are created when a market is created, so they should have ensOwner as owner too
        assertEq(principalToken.owner(), ensOwner, "Bob should be owner of PrincipalToken");
        assertEq(swapToken.owner(), ensOwner, "Bob should be owner of SwapToken");
    }

    function test_BobCanTransferOwnership() external {
        // Test that ensOwner can transfer ownership (proving ensOwner is indeed the owner)
        address newOwner = makeAddr("newOwner");

        vm.startPrank(ensOwner);

        // Transfer ownership of one contract as example
        defaultCorkController.transferOwnership(newOwner);

        vm.stopPrank();

        // Verify ownership transferred
        assertEq(defaultCorkController.owner(), newOwner, "Ownership should be transferred to newOwner");
    }
}
