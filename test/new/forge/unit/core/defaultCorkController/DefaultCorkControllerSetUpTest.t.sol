// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract DefaultCorkControllerSetUpTest is BaseTest {
    // ----------------------- Tests for constant variables of DefaultCorkController contract -----------------------//
    function test_DefaultCorkControllerRolesVariables() public {
        // Assert the roles variables are correct
        assertEq(defaultCorkController.CONFIGURATOR_ROLE(), keccak256("CONFIGURATOR_ROLE"));
        assertEq(defaultCorkController.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(defaultCorkController.POOL_CREATOR_ROLE(), keccak256("POOL_CREATOR_ROLE"));

        assertEq(address(defaultCorkController.corkPoolManager()), address(corkPoolManager));
    }

    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- Tests for DefaultCorkController constructor ---------------------------------//
    function test_DefaultCorkControllerConstructorRevertWhenPassedZeroAddress() public {
        // Revert when all address parameters are zero
        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(address(0), address(0), address(0), address(0), address(0), address(0), address(0));

        // Revert when any address parameter is zero
        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(address(0), DEFAULT_ADDRESS, pauser, DEFAULT_ADDRESS, address(corkPoolManager), address(whitelistManager), currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, address(0), pauser, DEFAULT_ADDRESS, address(corkPoolManager), address(whitelistManager), currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, DEFAULT_ADDRESS, address(0), DEFAULT_ADDRESS, address(corkPoolManager), address(whitelistManager), currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, DEFAULT_ADDRESS, pauser, address(0), address(corkPoolManager), address(whitelistManager), currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, DEFAULT_ADDRESS, pauser, DEFAULT_ADDRESS, address(0), address(whitelistManager), currentCaller());
    }

    function test_DefaultCorkControllerConstructorShouldWorkCorrectly() public {
        // Assign roles correctly
        assertEq(defaultCorkController.hasRole(defaultCorkController.DEFAULT_ADMIN_ROLE(), DEFAULT_ADDRESS), true);
        assertEq(defaultCorkController.hasRole(defaultCorkController.PAUSER_ROLE(), pauser), true);
        assertEq(defaultCorkController.hasRole(defaultCorkController.POOL_CREATOR_ROLE(), DEFAULT_ADDRESS), true);
        assertEq(defaultCorkController.hasRole(defaultCorkController.CONFIGURATOR_ROLE(), DEFAULT_ADDRESS), true);

        // Assign Role Hierarchy correctly
        assertEq(defaultCorkController.getRoleAdmin(defaultCorkController.PAUSER_ROLE()), defaultCorkController.DEFAULT_ADMIN_ROLE());
        assertEq(defaultCorkController.getRoleAdmin(defaultCorkController.POOL_CREATOR_ROLE()), defaultCorkController.DEFAULT_ADMIN_ROLE());
    }

    //-----------------------------------------------------------------------------------------------------//
}
