// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WhitelistManager} from "contracts/core/WhitelistManager.sol";
import {Test} from "forge-std/Test.sol";

contract WhitelistManagerSetupTests is Test {
    address testUser1 = makeAddr("testUser1");
    address corkPoolManager = makeAddr("corkPoolManager");
    address ensOwner = makeAddr("ensOwner");
    address defaultAdmin = makeAddr("defaultAdmin");

    WhitelistManager whitelistManager;

    function setUp() public {
        vm.startPrank(defaultAdmin);
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(
            whitelistManagerImpl, abi.encodeWithSelector(WhitelistManager.initialize.selector, ensOwner, defaultAdmin)
        );
        whitelistManager = WhitelistManager(address(whitelistManagerProxy));
    }

    //============================== setOnceCorkPoolManager Tests ================================//

    function test_setOnceCorkPoolManager_ShouldWorkCorrectly() public {
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(
            whitelistManagerImpl, abi.encodeWithSelector(WhitelistManager.initialize.selector, ensOwner, defaultAdmin)
        );
        WhitelistManager newWhitelistManager = WhitelistManager(address(whitelistManagerProxy));

        // Should succed without reverting
        newWhitelistManager.setOnceCorkPoolManager(corkPoolManager);
    }

    function test_setOnceCorkPoolManager_ShouldRevert_WhenInvalidAddress() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        whitelistManager.setOnceCorkPoolManager(address(0));
    }

    function test_setOnceCorkPoolManager_ShouldRevert_WhenAlreadySet() public {
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(
            whitelistManagerImpl, abi.encodeWithSelector(WhitelistManager.initialize.selector, ensOwner, defaultAdmin)
        );
        WhitelistManager newWhitelistManager = WhitelistManager(address(whitelistManagerProxy));

        // Should succeed first time
        newWhitelistManager.setOnceCorkPoolManager(corkPoolManager);

        // Should revert second time
        vm.expectRevert(abi.encodeWithSignature("AlreadySet()"));
        newWhitelistManager.setOnceCorkPoolManager(corkPoolManager);
    }

    function test_setOnceCorkPoolManager_ShouldRevert_WhenCalledByNonDefaultAdminRole() public {
        vm.startPrank(testUser1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.DEFAULT_ADMIN_ROLE()
            )
        );
        whitelistManager.setOnceCorkPoolManager(corkPoolManager);
    }

    // ================================ Upgrade Authorization Tests ================================ //

    function test_upgradeToAndCall_ShouldRevert_WhenCalledByNonDefaultAdminRole() external {
        vm.startPrank(testUser1);
        WhitelistManager newImplementation = new WhitelistManager();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.DEFAULT_ADMIN_ROLE()
            )
        );
        whitelistManager.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeToAndCall_ShouldWork_WhenCalledByDefaultAdminRole() external {
        WhitelistManager newImplementation = new WhitelistManager();

        // This should succeed without reverting
        whitelistManager.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }
}
