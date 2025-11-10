// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

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
        assertEq(whitelistManager.hasRole(whitelistManager.DEFAULT_ADMIN_ROLE(), DEFAULT_ADDRESS), true);
        assertEq(whitelistManager.hasRole(whitelistManager.CORK_CONTROLLER_ROLE(), address(defaultCorkController)), true);
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

        whitelistManager.activateMarketWhitelist(poolId);
        assertTrue(whitelistManager.isMarketWhitelistEnabled(poolId));
    }

    function test_MarketWhitelistDisable() public __createPoolWithWhitelist(1 days) __as(address(defaultCorkController)) {
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

    function test_isWhitelisted_GlobalWhitelist() public __createPoolWithWhitelist(1 days) __as(address(defaultCorkController)) {
        assertTrue(whitelistManager.isMarketWhitelistEnabled(defaultPoolId));

        whitelistManager.addToGlobalWhitelist(testUsers);

        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isWhitelisted(defaultPoolId, testUser3));
    }

    function test_isWhitelisted_MarketWhitelist() public __createPoolWithWhitelist(1 days) __as(address(defaultCorkController)) {
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

    function test_Revert_UnauthorizedCaller() public __as(testUser1) {
        vm.expectRevert();
        whitelistManager.addToGlobalWhitelist(testUsers);

        vm.expectRevert();
        whitelistManager.removeFromGlobalWhitelist(testUsers);

        vm.expectRevert();
        whitelistManager.addToMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert();
        whitelistManager.removeFromMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert();
        whitelistManager.disableMarketWhitelist(defaultPoolId);

        vm.expectRevert();
        whitelistManager.activateMarketWhitelist(defaultPoolId);
    }
}
