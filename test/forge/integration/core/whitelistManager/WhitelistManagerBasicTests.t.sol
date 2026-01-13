// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WhitelistManager} from "contracts/core/WhitelistManager.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract WhitelistManagerBasicTests is BaseTest {
    address testUser1 = makeAddr("testUser1");
    address testUser2 = makeAddr("testUser2");
    address testUser3 = makeAddr("testUser3");
    address[] testUsers;

    function setUp() public override {
        super.setUp();

        testUsers.push(testUser1);
        testUsers.push(testUser2);
        testUsers.push(testUser3);
    }

    function test_Initialize() public {
        assertEq(whitelistManager.hasRole(whitelistManager.DEFAULT_ADMIN_ROLE(), bravo), true);
        assertEq(
            whitelistManager.hasRole(whitelistManager.CORK_CONTROLLER_ROLE(), address(defaultCorkController)), true
        );

        // Verify ERC-7201 storage position constant
        // Expected: keccak256(abi.encode(uint256(keccak256("cork.storage.WhitelistManager")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 expectedStoragePosition = 0x0da519c821e1a8f2910e4e535b0245b25f0e3189410accd869caacafbf3ff700;

        // Calculate the storage position using ERC-7201 formula
        bytes32 baseHash = keccak256("cork.storage.WhitelistManager");
        bytes32 computedPosition = keccak256(abi.encode(uint256(baseHash) - 1)) & ~bytes32(uint256(0xff));

        // Verify the computed position matches the expected constant
        assertEq(computedPosition, expectedStoragePosition, "Computed storage position doesn't match expected constant");

        // Verify the storage position is actually being used in the contract by reading CORK_POOL_MANAGER
        // CORK_POOL_MANAGER is the first field in WhitelistManagerStorage struct, so it's stored at _WHITELIST_MANAGER_STORAGE_POSITION
        bytes32 storedValue = vm.load(address(whitelistManager), expectedStoragePosition);
        address corkPoolManagerStoredValue = address(uint160(uint256(storedValue)));

        // Verify it matches the expected CorkPoolManager address
        assertEq(
            corkPoolManagerStoredValue,
            address(corkPoolManager),
            "CORK_POOL_MANAGER not found at expected storage position"
        );
    }

    function test_Initialize_ShouldRevert_WhenInvalidAddresses() public {
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(whitelistManagerImpl, bytes(""));
        WhitelistManager newWhitelistManager = WhitelistManager(address(whitelistManagerProxy));

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        newWhitelistManager.initialize(address(0), address(0));

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        newWhitelistManager.initialize(address(0), bravo);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        newWhitelistManager.initialize(ensOwner, address(0));
    }

    function test_GlobalWhitelist_Add() public __as(address(defaultCorkController)) {
        vm.expectEmit(true, true, true, true);

        for (uint256 index = 0; index < testUsers.length; index++) {
            emit IWhitelistManager.GlobalWhitelistAdded(testUsers[index]);
        }

        whitelistManager.addToGlobalWhitelist(testUsers);

        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser2));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser3));
    }

    function test_GlobalWhitelist_Remove() public __as(address(defaultCorkController)) {
        whitelistManager.addToGlobalWhitelist(testUsers);

        address[] memory usersToRemove = new address[](2);
        usersToRemove[0] = testUser1;
        usersToRemove[1] = testUser2;

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.GlobalWhitelistRemoved(usersToRemove[0]);
        emit IWhitelistManager.GlobalWhitelistRemoved(usersToRemove[1]);

        whitelistManager.removeFromGlobalWhitelist(usersToRemove);

        assertFalse(whitelistManager.isGlobalWhitelisted(testUser1));
        assertFalse(whitelistManager.isGlobalWhitelisted(testUser2));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser3));
    }

    function test_MarketWhitelist_Add() public __as(address(defaultCorkController)) {
        vm.expectEmit(true, true, true, true);

        emit IWhitelistManager.MarketWhitelistAdded(defaultPoolId, testUsers[0]);
        emit IWhitelistManager.MarketWhitelistAdded(defaultPoolId, testUsers[1]);

        whitelistManager.addToMarketWhitelist(defaultPoolId, testUsers);

        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser3));
    }

    function test_MarketWhitelist_Remove() public __as(address(defaultCorkController)) {
        whitelistManager.addToMarketWhitelist(defaultPoolId, testUsers);

        address[] memory usersToRemove = new address[](1);
        usersToRemove[0] = testUser1;

        vm.expectEmit(true, true, true, true);

        emit IWhitelistManager.MarketWhitelistRemoved(defaultPoolId, usersToRemove[0]);

        whitelistManager.removeFromMarketWhitelist(defaultPoolId, usersToRemove);

        assertFalse(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser3));
    }

    function test_MarketWhitelistStatus_Set() public __as(address(defaultCorkController)) {
        assertFalse(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));

        MarketId poolId = MarketId.wrap(bytes32(uint256(12_345)));

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.MarketWhitelistEnabled(poolId);

        whitelistManager.activateMarketWhitelist(poolId);
        assertTrue(whitelistManager.isMarketWhitelistEnabled(poolId));
    }

    function test_MarketWhitelistStatus_Set_ShouldRevert_WhenAlreadySet()
        public
        __createPoolWithWhitelist(1 days)
        __as(address(defaultCorkController))
    {
        corkPoolManager.setPartiallyInitializedMarket(defaultPoolId, testUser1, true);

        vm.expectRevert(abi.encodeWithSignature("AlreadyInitialized()"));
        whitelistManager.activateMarketWhitelist(defaultPoolId);
    }

    function test_MarketWhitelistDisable()
        public
        __createPoolWithWhitelist(1 days)
        __as(address(defaultCorkController))
    {
        assertTrue(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.MarketWhitelistDisabled(defaultPoolId);

        whitelistManager.disableMarketWhitelist(defaultPoolId);
        assertFalse(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));
    }

    function test_isWhitelisted_MarketDisabled() public {
        assertFalse(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser1));
    }

    function test_isWhitelisted_GlobalWhitelist()
        public
        __createPoolWithWhitelist(1 days)
        __as(address(defaultCorkController))
    {
        assertTrue(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));

        whitelistManager.addToGlobalWhitelist(testUsers);

        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser3));
    }

    function test_isWhitelisted_MarketWhitelist()
        public
        __createPoolWithWhitelist(1 days)
        __as(address(defaultCorkController))
    {
        assertTrue(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));

        whitelistManager.addToMarketWhitelist(defaultPoolId, testUsers);

        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser3));
    }

    function test_isWhitelisted_NotWhitelisted() public __createPoolWithWhitelist(1 days) {
        assertTrue(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));
        assertFalse(whitelistManager.isWhitelisted(defaultPoolId, testUser1));
    }

    function test_Revert_AddGlobalWhitelist_InvalidAddress() public __as(address(defaultCorkController)) {
        address[] memory invalidUsers = new address[](1);
        invalidUsers[0] = address(0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        whitelistManager.addToGlobalWhitelist(invalidUsers);
    }

    function test_Revert_RemoveGlobalWhitelist_InvalidAddress() public __as(address(defaultCorkController)) {
        address[] memory invalidUsers = new address[](1);
        invalidUsers[0] = address(0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        whitelistManager.removeFromGlobalWhitelist(invalidUsers);
    }

    function test_Revert_AddMarketWhitelist_InvalidAddress() public __as(address(defaultCorkController)) {
        address[] memory invalidUsers = new address[](1);
        invalidUsers[0] = address(0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        whitelistManager.addToMarketWhitelist(defaultPoolId, invalidUsers);
    }

    function test_Revert_RemoveMarketWhitelist_InvalidAddress() public __as(address(defaultCorkController)) {
        address[] memory invalidUsers = new address[](1);
        invalidUsers[0] = address(0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        whitelistManager.removeFromMarketWhitelist(defaultPoolId, invalidUsers);
    }

    function test_Revert_DisableMarketWhitelist_AlreadyDisabled() public __as(address(defaultCorkController)) {
        assertFalse(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));

        vm.expectRevert(abi.encodeWithSignature("WhitelistAlreadyDisabled()"));
        whitelistManager.disableMarketWhitelist(defaultPoolId);
    }

    /// @notice Mutation test to catch && to || change in disableMarketWhitelist
    /// @dev Tests that disabling whitelist on a partially initialized market (one address is zero) should succeed
    /// This catches the mutation where `market.referenceAsset != address(0) && market.collateralAsset != address(0)`
    /// is changed to `market.referenceAsset != address(0) || market.collateralAsset != address(0)`
    function test_DisableMarketWhitelist_PartiallyInitializedMarket_ReferenceNonZero()
        public
        __as(address(defaultCorkController))
    {
        // Create a new market ID that doesn't exist yet
        MarketId partialMarketId = MarketId.wrap(bytes32(uint256(99_999)));

        // Set up a partially initialized market (only referenceAsset is non-zero)
        corkPoolManager.setPartiallyInitializedMarket(partialMarketId, testUser1, true);

        // Whitelist should be disabled by default
        assertFalse(whitelistManager.isMarketWhitelistEnabled(partialMarketId));

        // This should NOT revert because the condition `market.referenceAsset != address(0) && market.collateralAsset != address(0)`
        // evaluates to false (since collateralAsset is address(0) and referenceAsset is non-zero)
        // If mutated to ||, this would revert with WhitelistAlreadyDisabled
        whitelistManager.disableMarketWhitelist(partialMarketId);

        // Whitelist should still be disabled
        assertFalse(whitelistManager.isMarketWhitelistEnabled(partialMarketId));
    }

    /// @notice Mutation test to catch && to || change in disableMarketWhitelist (collateral variant)
    function test_DisableMarketWhitelist_PartiallyInitializedMarket_CollateralNonZero()
        public
        __as(address(defaultCorkController))
    {
        // Create a new market ID that doesn't exist yet
        MarketId partialMarketId = MarketId.wrap(bytes32(uint256(88_888)));

        // Set up a partially initialized market (only collateralAsset is non-zero)
        corkPoolManager.setPartiallyInitializedMarket(partialMarketId, testUser1, false);

        // Whitelist should be disabled by default
        assertFalse(whitelistManager.isMarketWhitelistEnabled(partialMarketId));

        // This should NOT revert because the condition `market.referenceAsset != address(0) && market.collateralAsset != address(0)`
        // evaluates to false (since referenceAsset is address(0) and collateralAsset is non-zero)
        // If mutated to ||, this would revert with WhitelistAlreadyDisabled
        whitelistManager.disableMarketWhitelist(partialMarketId);

        // Whitelist should still be disabled
        assertFalse(whitelistManager.isMarketWhitelistEnabled(partialMarketId));
    }

    function test_Revert_UnauthorizedCaller() public __as(testUser1) {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.CORK_CONTROLLER_ROLE()
            )
        );
        whitelistManager.addToGlobalWhitelist(testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.CORK_CONTROLLER_ROLE()
            )
        );
        whitelistManager.removeFromGlobalWhitelist(testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.CORK_CONTROLLER_ROLE()
            )
        );
        whitelistManager.addToMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.CORK_CONTROLLER_ROLE()
            )
        );
        whitelistManager.removeFromMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.CORK_CONTROLLER_ROLE()
            )
        );
        whitelistManager.disableMarketWhitelist(defaultPoolId);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", testUser1, whitelistManager.CORK_CONTROLLER_ROLE()
            )
        );
        whitelistManager.activateMarketWhitelist(defaultPoolId);
    }
}
