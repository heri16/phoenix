// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Test} from "forge-std/Test.sol";

contract SetOnceCorkPoolManagerTests is Test {
    address ensOwner = makeAddr("ensOwner");
    address defaultAdmin = makeAddr("defaultAdmin");
    address alice = makeAddr("alice");
    address corkPoolManager = makeAddr("corkPoolManager");
    address configurator = makeAddr("configurator");
    address pauser = makeAddr("pauser");
    address poolCreator = makeAddr("poolCreator");
    address whitelistManager = makeAddr("whitelistManager");
    address whitelistManagerAdmin = makeAddr("whitelistManagerAdmin");

    DefaultCorkController defaultCorkController;

    function setUp() public {
        vm.startPrank(defaultAdmin);
        defaultCorkController =
            new DefaultCorkController(ensOwner, defaultAdmin, makeAddr("not_used"), whitelistManager);
    }

    //------------------------------------------ Tests for setOnceCorkPoolManager -------------------------------------//
    function test_setOnceCorkPoolManager_shouldRevert_whenPassedZeroAddress() public {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        defaultCorkController.setOnceCorkPoolManager(address(0));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenAlreadySet() public {
        vm.startPrank(defaultAdmin);
        DefaultCorkController defaultCorkController1 =
            new DefaultCorkController(ensOwner, defaultAdmin, makeAddr("not_used"), whitelistManager);

        // Initialize should succeed first time
        defaultCorkController1.setOnceCorkPoolManager(address(corkPoolManager));

        // Initialize should revert second time
        vm.expectRevert(IErrors.AlreadySet.selector);
        defaultCorkController1.setOnceCorkPoolManager(address(corkPoolManager));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenCalledByNonDefaultAdmin() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                defaultCorkController.DEFAULT_ADMIN_ROLE()
            )
        );
        defaultCorkController.setOnceCorkPoolManager(address(0));
    }

    function test_setOnceCorkPoolManager_shouldWorkCorrectly() public {
        vm.startPrank(defaultAdmin);
        DefaultCorkController defaultCorkController1 =
            new DefaultCorkController(ensOwner, defaultAdmin, makeAddr("not_used"), whitelistManager);

        // Assert that the corkPoolManager is not initialized
        assertEq(address(defaultCorkController1.CORK_POOL_MANAGER()), address(0));

        // Initialize the corkPoolManager
        defaultCorkController1.setOnceCorkPoolManager(address(corkPoolManager));

        // Assert that the corkPoolManager is initialized
        assertEq(address(defaultCorkController1.CORK_POOL_MANAGER()), address(corkPoolManager));
    }
}
