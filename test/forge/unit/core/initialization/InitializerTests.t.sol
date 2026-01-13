// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {WhitelistManager} from "contracts/core/WhitelistManager.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {Test} from "forge-std/Test.sol";

/**
 * @title InitializerTests
 * @notice Tests InvalidInitialization error for upgradeable contracts
 * @dev Tests that contracts cannot be initialized more than once
 */
contract InitializerTests is Test {
    // Test addresses
    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address corkController = makeAddr("corkController");
    address ensOwner = makeAddr("bob"); // ENS owner

    // Contract proxy instances
    ConstraintRateAdapter constraintRateAdapter;
    CorkPoolManager corkPoolManager;
    WhitelistManager whitelistManager;
    SharesFactory sharesFactory;

    function setUp() public {
        vm.startPrank(admin);

        // ==================== Deploy ConstraintRateAdapter ====================
        address constraintRateAdapterImpl = address(new ConstraintRateAdapter());
        ERC1967Proxy constraintRateAdapterProxy = new ERC1967Proxy(constraintRateAdapterImpl, bytes(""));
        constraintRateAdapter = ConstraintRateAdapter(address(constraintRateAdapterProxy));

        // ==================== Deploy WhitelistManager ====================
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(whitelistManagerImpl, bytes(""));
        whitelistManager = WhitelistManager(address(whitelistManagerProxy));

        // ==================== Deploy CorkPoolManager ====================
        address corkPoolManagerImpl = address(new CorkPoolManager());
        ERC1967Proxy corkPoolManagerProxy = new ERC1967Proxy(corkPoolManagerImpl, bytes(""));
        corkPoolManager = CorkPoolManager(address(corkPoolManagerProxy));

        // Deploy SharesFactory with the actual CorkPoolManager address
        sharesFactory = new SharesFactory(address(corkPoolManager), admin);
    }

    /// @notice Test that ConstraintRateAdapter cannot be initialized twice
    function test_ConstraintRateAdapter_ShouldRevert_WhenAlreadySet() public {
        // First initialization should succeed
        constraintRateAdapter.initialize(ensOwner, admin);

        // Second initialization should revert
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        constraintRateAdapter.initialize(ensOwner, admin);
    }

    /// @notice Test that CorkPoolManager cannot be initialized twice
    function test_CorkPoolManager_ShouldRevert_WhenAlreadySet() public {
        // First initialization should succeed
        corkPoolManager.initialize(ensOwner, admin, address(constraintRateAdapter), treasury, address(whitelistManager));

        // Second initialization should revert
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        corkPoolManager.initialize(ensOwner, admin, address(constraintRateAdapter), treasury, address(whitelistManager));
    }

    /// @notice Test that WhitelistManager cannot be initialized twice
    function test_WhitelistManager_ShouldRevert_WhenAlreadySet() public {
        // First initialization should succeed
        whitelistManager.initialize(ensOwner, admin);

        // Second initialization should revert
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        whitelistManager.initialize(ensOwner, admin);
    }
}
