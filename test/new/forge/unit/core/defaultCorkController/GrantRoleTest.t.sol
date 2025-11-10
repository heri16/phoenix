// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract GrantRoleTest is BaseTest {
    address private adminUserAddress;
    address private configurator;
    address private poolCreator;
    address private corkPoolAddress;

    bytes32 DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public override {
        adminUserAddress = address(1);
        configurator = address(2);
        pauser = address(3);
        poolCreator = address(4);
        corkPoolAddress = address(5);

        overridePrank(adminUserAddress);
        defaultCorkController = new DefaultCorkController(adminUserAddress, configurator, pauser, poolCreator, corkPoolAddress, address(123), address(1234));
    }

    //------------------------------------- Tests for grantRole ------------------------------------------//
    function test_GrantRole_ShouldRevert_WhenCalledByNonManager() public __as(alice) {
        bytes32 role = defaultCorkController.POOL_CREATOR_ROLE();
        assertFalse(defaultCorkController.hasRole(role, pauser));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, bytes32(0)));
        defaultCorkController.grantRole(role, pauser);

        assertFalse(defaultCorkController.hasRole(role, pauser));
    }

    function test_GrantRole_ShouldWorkCorrectly() public {
        bytes32 role = defaultCorkController.POOL_CREATOR_ROLE();
        assertFalse(defaultCorkController.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit IAccessControl.RoleGranted(role, address(9), pauser);

        defaultCorkController.grantRole(role, address(9));

        assertTrue(defaultCorkController.hasRole(role, address(9)));
        assertTrue(defaultCorkController.hasRole(role, poolCreator));
    }

    function test_GrantRole_ShouldWorkCorrectly_WhenNoManagerRole() public {
        bytes32 role = defaultCorkController.POOL_CREATOR_ROLE();
        defaultCorkController.revokeRole(defaultCorkController.PAUSER_ROLE(), pauser);
        assertFalse(defaultCorkController.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit IAccessControl.RoleGranted(role, address(9), pauser);
        defaultCorkController.grantRole(role, address(9));
        assertTrue(defaultCorkController.hasRole(role, address(9)));
        assertTrue(defaultCorkController.hasRole(role, poolCreator));
    }

    //-----------------------------------------------------------------------------------------------------//

    //----------------------------- Tests for grantRole DEFAULT_ADMIN_ROLE --------------------------------//
    function test_GrantRoleAdminRevertWhenCalledByNonAdmin() public __as(eve) {
        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, adminUserAddress), true);
        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, eve), false);

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", eve, bytes32(0)));
        defaultCorkController.grantRole(DEFAULT_ADMIN_ROLE, eve);

        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, adminUserAddress), true);
        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, eve), false);
    }

    function test_GrantRoleAdminShouldWorkCorrectly() public {
        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, adminUserAddress), true);
        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, alice), false);

        vm.expectEmit(false, false, false, true);
        emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, alice, adminUserAddress);
        defaultCorkController.grantRole(DEFAULT_ADMIN_ROLE, alice);

        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, adminUserAddress), true);

        defaultCorkController.revokeRole(DEFAULT_ADMIN_ROLE, adminUserAddress);

        assertEq(defaultCorkController.hasRole(DEFAULT_ADMIN_ROLE, alice), true);
    }

    //-----------------------------------------------------------------------------------------------------//
}
