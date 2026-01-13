// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract DefaultCorkControllerSetUpTest is BaseTest {
    // ----------------------- Tests for constant variables of DefaultCorkController contract -----------------------//
    function test_DefaultCorkControllerRolesVariables() public {
        // Assert the roles variables are correct
        assertEq(defaultCorkController.CONFIGURATOR_ROLE(), keccak256("CONFIGURATOR_ROLE"));
        assertEq(defaultCorkController.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(defaultCorkController.POOL_CREATOR_ROLE(), keccak256("POOL_CREATOR_ROLE"));

        assertEq(address(defaultCorkController.CORK_POOL_MANAGER()), address(corkPoolManager));
    }

    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- Tests for DefaultCorkController constructor ---------------------------------//
    function test_DefaultCorkControllerConstructorRevertWhenPassedZeroAddress() public {
        // Revert when all address parameters are zero - here the ensOwner set to 0 fails with OwnableInvalidOwner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new DefaultCorkController(address(0), address(0), address(0), address(0));

        // Revert when ensOwner is zero - here Ownable rejects this
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new DefaultCorkController(address(0), bravo, makeAddr("not_used"), address(whitelistManager));

        // Revert when admin is zero
        vm.expectRevert(IErrors.InvalidAddress.selector);
        new DefaultCorkController(bob, address(0), makeAddr("not_used"), address(whitelistManager));

        // Revert when operationsManager is zero
        vm.expectRevert(IErrors.InvalidAddress.selector);
        new DefaultCorkController(bob, bravo, address(0), makeAddr("not_used"));

        // Revert when whitelistManager is zero
        vm.expectRevert(IErrors.InvalidAddress.selector);
        new DefaultCorkController(bob, bravo, makeAddr("not_used"), address(0));
    }

    function test_DefaultCorkControllerConstructorShouldWorkCorrectly() public {
        // Assign roles correctly
        assertEq(defaultCorkController.hasRole(defaultCorkController.DEFAULT_ADMIN_ROLE(), bravo), true);
        assertEq(defaultCorkController.hasRole(defaultCorkController.PAUSER_ROLE(), pauser), true);
        assertEq(defaultCorkController.hasRole(defaultCorkController.POOL_CREATOR_ROLE(), bravo), true);
        assertEq(defaultCorkController.hasRole(defaultCorkController.CONFIGURATOR_ROLE(), bravo), true);

        // Assign Role Hierarchy correctly
        assertEq(
            defaultCorkController.getRoleAdmin(defaultCorkController.PAUSER_ROLE()),
            defaultCorkController.DEFAULT_ADMIN_ROLE()
        );
        assertEq(
            defaultCorkController.getRoleAdmin(defaultCorkController.POOL_CREATOR_ROLE()),
            defaultCorkController.DEFAULT_ADMIN_ROLE()
        );
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------------ Tests for setOnceCorkPoolManager -------------------------------------//
    function test_setOnceCorkPoolManager_shouldRevert_whenPassedZeroAddress() public {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        defaultCorkController.setOnceCorkPoolManager(address(0));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenAlreadySet() public __as(bravo) {
        DefaultCorkController defaultCorkController1 =
            new DefaultCorkController(address(1), bravo, makeAddr("not_used"), address(whitelistManager));

        // Initialize should succeed first time
        defaultCorkController1.setOnceCorkPoolManager(address(corkPoolManager));

        // Initialize should revert second time
        vm.expectRevert(IErrors.AlreadySet.selector);
        defaultCorkController1.setOnceCorkPoolManager(address(corkPoolManager));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenCalledByNonDefaultAdmin() public __as(alice) {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                defaultCorkController.DEFAULT_ADMIN_ROLE()
            )
        );
        defaultCorkController.setOnceCorkPoolManager(address(0));
    }

    function test_setOnceCorkPoolManager_shouldWorkCorrectly() public __as(bravo) {
        DefaultCorkController defaultCorkController1 =
            new DefaultCorkController(address(1), bravo, makeAddr("not_used"), address(whitelistManager));

        // Assert that the corkPoolManager is not initialized
        assertEq(address(defaultCorkController1.CORK_POOL_MANAGER()), address(0));

        // Initialize the corkPoolManager
        defaultCorkController1.setOnceCorkPoolManager(address(corkPoolManager));

        // Assert that the corkPoolManager is initialized
        assertEq(address(defaultCorkController1.CORK_POOL_MANAGER()), address(corkPoolManager));
    }
}
