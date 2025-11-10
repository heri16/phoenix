// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract RevokeRoleTest is BaseTest {
    address private adminUserAddress;
    address private configurator;
    address private poolCreator;
    address private corkPoolAddress;

    function setUp() public override {
        adminUserAddress = address(1);
        configurator = address(2);
        pauser = address(3);
        poolCreator = address(4);
        corkPoolAddress = address(5);

        overridePrank(adminUserAddress);
        defaultCorkController = new DefaultCorkController(adminUserAddress, configurator, pauser, poolCreator, corkPoolAddress, address(243), address(344));
    }

    //------------------------------------- Tests for revokeRole ------------------------------------------//
    function test_RevokeRole_ShouldRevert_WhenCalledByNonManager() public __as(alice) {
        bytes32 role = defaultCorkController.POOL_CREATOR_ROLE();
        assertFalse(defaultCorkController.hasRole(role, pauser));

        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, bytes32(0)));
        defaultCorkController.revokeRole(role, pauser);
        assertFalse(defaultCorkController.hasRole(role, pauser));
    }

    function test_RevokeRole_ShouldWorkCorrectly() public {
        bytes32 role = defaultCorkController.POOL_CREATOR_ROLE();

        defaultCorkController.grantRole(role, address(9));
        assertTrue(defaultCorkController.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit IAccessControl.RoleRevoked(role, address(9), adminUserAddress);
        defaultCorkController.revokeRole(role, address(9));

        assertFalse(defaultCorkController.hasRole(role, address(9)));
    }

    //-----------------------------------------------------------------------------------------------------//
}
