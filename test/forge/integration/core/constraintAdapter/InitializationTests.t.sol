// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Test} from "forge-std/Test.sol";

contract InitializationTests is Test {
    address ensOwner = makeAddr("ensOwner");
    address defaultAdmin = makeAddr("defaultAdmin");
    address alice = makeAddr("alice");
    address corkPoolManager = makeAddr("corkPoolManager");

    address constraintRateAdapterImpl;
    ConstraintRateAdapter constraintRateAdapter;

    function setUp() public {
        vm.startPrank(defaultAdmin);
        constraintRateAdapterImpl = address(new ConstraintRateAdapter());
        ERC1967Proxy constraintRateAdapterProxy = new ERC1967Proxy(
            constraintRateAdapterImpl,
            abi.encodeWithSelector(ConstraintRateAdapter.initialize.selector, ensOwner, defaultAdmin)
        );
        constraintRateAdapter = ConstraintRateAdapter(address(constraintRateAdapterProxy));
    }

    // ================================ Initialization Tests ================================ //
    function test_initialize_shouldSetCorrectValues() external {
        assertEq(constraintRateAdapter.owner(), ensOwner);
        constraintRateAdapter.setOnceCorkPoolManager(address(corkPoolManager));

        // Verify ERC-7201 storage position constant
        // Expected: keccak256(abi.encode(uint256(keccak256("cork.storage.ConstraintRateAdapter")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 expectedStoragePosition = 0xf88cefad790528de4ec7608c6ea34edd21e78fe1868b343ccaa1ae3a22fa9c00;

        // Calculate the storage position using ERC-7201 formula
        bytes32 baseHash = keccak256("cork.storage.ConstraintRateAdapter");
        bytes32 computedPosition = keccak256(abi.encode(uint256(baseHash) - 1)) & ~bytes32(uint256(0xff));

        // Verify the computed position matches the expected constant
        assertEq(computedPosition, expectedStoragePosition, "Computed storage position doesn't match expected constant");

        // Verify the storage position is actually being used in the contract by reading CORK_POOL_MANAGER
        // CORK_POOL_MANAGER is the first field in ConstraintRateAdapterStorage struct, so it's stored at _CONSTRAINT_ADAPTER_STORAGE_POSITION
        bytes32 storedValue = vm.load(address(constraintRateAdapter), expectedStoragePosition);
        address corkPoolManagerStoredValue = address(uint160(uint256(storedValue)));

        // Verify it matches the expected CorkPoolManager address
        assertEq(
            corkPoolManagerStoredValue,
            address(corkPoolManager),
            "CORK_POOL_MANAGER not found at expected storage position"
        );
    }

    function test_initialize_shouldRevert_whenInitialOwnerIsZeroAddress() external {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        new ERC1967Proxy(
            constraintRateAdapterImpl, abi.encodeCall(ConstraintRateAdapter.initialize, (address(0), defaultAdmin))
        );
    }

    function test_initialize_shouldRevert_whenCorkPoolManagerIsZeroAddress() external {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        new ERC1967Proxy(
            constraintRateAdapterImpl, abi.encodeCall(ConstraintRateAdapter.initialize, (ensOwner, address(0)))
        );
    }

    function test_initialize_shouldRevert_whenBothParametersAreZeroAddress() external {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        new ERC1967Proxy(
            constraintRateAdapterImpl, abi.encodeCall(ConstraintRateAdapter.initialize, (address(0), address(0)))
        );
    }

    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- setOnceCorkPoolManager ----------------------------------- //
    function test_setOnceCorkPoolManager_shouldWorkCorrectly() external {
        // Should succeed without reverting
        constraintRateAdapter.setOnceCorkPoolManager(address(corkPoolManager));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenCalledByNonDefaultAdmin() external {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                constraintRateAdapter.DEFAULT_ADMIN_ROLE()
            )
        );
        constraintRateAdapter.setOnceCorkPoolManager(address(corkPoolManager));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenCalledByZeroAddress() external {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        constraintRateAdapter.setOnceCorkPoolManager(address(0));
    }

    function test_setOnceCorkPoolManager_shouldRevert_whenCalledTwice() external {
        constraintRateAdapter.setOnceCorkPoolManager(address(corkPoolManager));
        vm.expectRevert(IErrors.AlreadySet.selector);
        constraintRateAdapter.setOnceCorkPoolManager(address(corkPoolManager));
    }

    //-----------------------------------------------------------------------------------------------------//
}
