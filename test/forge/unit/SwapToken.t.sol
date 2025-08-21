// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {SwapToken, SwapTokenLibrary} from "contracts/libraries/SwapToken.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";

// Helper contract to expose SwapTokenLibrary functions for testing
contract SwapTokenHelper {
    using SwapTokenLibrary for SwapToken;

    SwapToken public swapToken;

    function setSwapToken(address _address, address principalToken, uint256 ctRedeemed) external {
        swapToken._address = _address;
        swapToken.principalToken = principalToken;
        swapToken.withdrawn = ctRedeemed;
    }

    function getSwapToken() external view returns (address, address, uint256) {
        return (swapToken._address, swapToken.principalToken, swapToken.withdrawn);
    }

    // Exposed SwapTokenLibrary functions
    function isExpired() external view returns (bool) {
        return swapToken.isExpired();
    }

    function isInitialized() external view returns (bool) {
        return swapToken.isInitialized();
    }

    function issue(address to, uint256 amount) external {
        SwapTokenLibrary.issue(swapToken, to, amount);
    }

    function updateSwapRate(uint256 rate) external {
        swapToken.updateSwapRate(rate);
    }
}

contract SwapTokenTest is Helper {
    SwapTokenHelper internal swapTokenHelper;
    PoolShare internal mockSwapToken;
    PoolShare internal mockPrincipalToken;

    address internal user1;
    address internal user2;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(DEFAULT_ADDRESS);

        // Deploy SwapToken helper
        swapTokenHelper = new SwapTokenHelper();

        // Create mock assets for testing
        mockSwapToken = new PoolShare("Swap Token", "SWT", address(swapTokenHelper), block.timestamp + 1 days, 1 ether);
        mockPrincipalToken = new PoolShare("Principal Token", "PT", address(swapTokenHelper), block.timestamp + 1 days, 1 ether);

        // Initialize with valid SwapToken
        swapTokenHelper.setSwapToken(address(mockSwapToken), address(mockPrincipalToken), 0);

        vm.stopPrank();
    }

    // ------------------------------- isExpired Tests ----------------------------------- //

    function test_isExpired_ShouldReturnFalse_WhenNotExpired() external {
        // Asset should not be expired at setup
        assertFalse(mockSwapToken.isExpired(), "Asset should not be expired");

        // Should return false
        assertFalse(swapTokenHelper.isExpired(), "SwapToken should not be expired");
    }

    function test_isExpired_ShouldReturnTrue_WhenExpired() external {
        // Warp time to make asset expired
        vm.warp(block.timestamp + 2 days);

        assertTrue(mockSwapToken.isExpired(), "Asset should be expired");

        // Should return true
        assertTrue(swapTokenHelper.isExpired(), "SwapToken should be expired");
    }

    function test_isExpired_ShouldReturnTrue_WhenExactlyAtExpiry() external {
        // Warp to exact expiry time
        vm.warp(mockSwapToken.expiry());

        assertTrue(mockSwapToken.isExpired(), "Asset should be expired at expiry time");

        // Should return true
        assertTrue(swapTokenHelper.isExpired(), "SwapToken should be expired at expiry time");
    }

    function test_isExpired_ShouldRevert_WhenAddressIsZero() external {
        // Set address to zero
        swapTokenHelper.setSwapToken(address(0), address(mockPrincipalToken), 0);

        // Should revert when trying to call isExpired on zero address
        vm.expectRevert();
        swapTokenHelper.isExpired();
    }

    // ------------------------------- isInitialized Tests ----------------------------------- //

    function test_isInitialized_ShouldReturnTrue_WhenBothAddressesAreNonZero() external {
        // Both addresses should be non-zero in setup
        assertTrue(swapTokenHelper.isInitialized(), "SwapToken should be initialized");
    }

    function test_isInitialized_ShouldReturnFalse_WhenAddressIsZero() external {
        // Set address to zero
        swapTokenHelper.setSwapToken(address(0), address(mockPrincipalToken), 0);

        // Should return false
        assertFalse(swapTokenHelper.isInitialized(), "SwapToken should not be initialized when address is zero");
    }

    function test_isInitialized_ShouldReturnFalse_WhenPrincipalTokenIsZero() external {
        // Set principalToken to zero
        swapTokenHelper.setSwapToken(address(mockSwapToken), address(0), 0);

        // Should return false
        assertFalse(swapTokenHelper.isInitialized(), "SwapToken should not be initialized when principalToken is zero");
    }

    function test_isInitialized_ShouldReturnFalse_WhenBothAddressesAreZero() external {
        // Set both addresses to zero
        swapTokenHelper.setSwapToken(address(0), address(0), 0);

        // Should return false
        assertFalse(swapTokenHelper.isInitialized(), "SwapToken should not be initialized when both addresses are zero");
    }

    function test_isInitialized_ShouldReturnTrue_WithNonZeroPrincipalTokenRedeemed() external {
        // Set ctRedeemed to non-zero value
        swapTokenHelper.setSwapToken(address(mockSwapToken), address(mockPrincipalToken), 1000);

        // Should still return true (ctRedeemed doesn't affect initialization status)
        assertTrue(swapTokenHelper.isInitialized(), "SwapToken should be initialized regardless of ctRedeemed value");
    }

    // ------------------------------- issue Tests ----------------------------------- //

    function test_issue_ShouldMintTokensToBothAssets() external {
        uint256 amount = 1000 ether;

        // Check initial balances
        assertEq(mockSwapToken.balanceOf(user1), 0, "Initial Swap Token balance should be 0");
        assertEq(mockPrincipalToken.balanceOf(user1), 0, "Initial Principal Token balance should be 0");

        // Issue tokens
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.issue(user1, amount);

        // Check balances after issuing
        assertEq(mockSwapToken.balanceOf(user1), amount, "Swap Token balance should equal issued amount");
        assertEq(mockPrincipalToken.balanceOf(user1), amount, "Principal Token balance should equal issued amount");
    }

    function test_issue_ShouldMintZeroTokens() external {
        uint256 amount = 0;

        // Check initial balances
        assertEq(mockSwapToken.balanceOf(user1), 0, "Initial Swap Token balance should be 0");
        assertEq(mockPrincipalToken.balanceOf(user1), 0, "Initial Principal Token balance should be 0");

        // Issue zero tokens
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.issue(user1, amount);

        // Check balances remain zero
        assertEq(mockSwapToken.balanceOf(user1), 0, "Swap Token balance should remain 0");
        assertEq(mockPrincipalToken.balanceOf(user1), 0, "Principal Token balance should remain 0");
    }

    function test_issue_ShouldMintToMultipleUsers() external {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 1000 ether;

        vm.startPrank(DEFAULT_ADDRESS);

        // Issue to user1
        swapTokenHelper.issue(user1, amount1);

        // Issue to user2
        swapTokenHelper.issue(user2, amount2);

        vm.stopPrank();

        // Check balances
        assertEq(mockSwapToken.balanceOf(user1), amount1, "User1 Swap Token balance should equal issued amount");
        assertEq(mockPrincipalToken.balanceOf(user1), amount1, "User1 Principal Token balance should equal issued amount");
        assertEq(mockSwapToken.balanceOf(user2), amount2, "User2 Swap Token balance should equal issued amount");
        assertEq(mockPrincipalToken.balanceOf(user2), amount2, "User2 Principal Token balance should equal issued amount");
    }

    function test_issue_ShouldRevert_WhenAddressIsZero() external {
        uint256 amount = 1000 ether;

        // Set address to zero
        swapTokenHelper.setSwapToken(address(0), address(mockPrincipalToken), 0);

        // Should revert when trying to mint on zero address
        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert();
        swapTokenHelper.issue(user1, amount);
    }

    function test_issue_ShouldRevert_WhenPrincipalTokenIsZero() external {
        uint256 amount = 1000 ether;

        // Set principalToken to zero
        swapTokenHelper.setSwapToken(address(mockSwapToken), address(0), 0);

        // Should revert when trying to mint on zero principalToken address
        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert();
        swapTokenHelper.issue(user1, amount);
    }

    function test_issue_ShouldHandleLargeAmounts() external {
        uint256 amount = type(uint256).max / 2; // Large but safe amount

        // Issue large amount
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.issue(user1, amount);

        // Check balances
        assertEq(mockSwapToken.balanceOf(user1), amount, "Swap Token balance should equal large issued amount");
        assertEq(mockPrincipalToken.balanceOf(user1), amount, "Principal Token balance should equal large issued amount");
    }

    // ------------------------------- updateSwapRate Tests ----------------------------------- //

    function test_updateSwapRate_ShouldUpdateBothAssets() external {
        uint256 newRate = 2 ether;

        // Check initial rate
        assertEq(mockSwapToken.swapRate(), 1 ether, "Initial Swap Token rate should be 1 ether");
        assertEq(mockPrincipalToken.swapRate(), 1 ether, "Initial Principal Token rate should be 1 ether");

        // Update swap rate
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.updateSwapRate(newRate);

        // Check rate after update
        assertEq(mockSwapToken.swapRate(), newRate, "Swap Token rate should be updated");
        assertEq(mockPrincipalToken.swapRate(), newRate, "Principal Token rate should be updated");
    }

    function test_updateSwapRate_ShouldUpdateToZero() external {
        uint256 newRate = 0;

        // Update swap rate to zero
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.updateSwapRate(newRate);

        // Check rate after update
        assertEq(mockSwapToken.swapRate(), newRate, "Swap Token rate should be 0");
        assertEq(mockPrincipalToken.swapRate(), newRate, "Principal Token rate should be 0");
    }

    function test_updateSwapRate_ShouldUpdateToMaxValue() external {
        uint256 newRate = type(uint256).max;

        // Update swap rate to max value
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.updateSwapRate(newRate);

        // Check rate after update
        assertEq(mockSwapToken.swapRate(), newRate, "Swap Token rate should be max value");
        assertEq(mockPrincipalToken.swapRate(), newRate, "Principal Token rate should be max value");
    }

    function test_updateSwapRate_ShouldRevert_WhenAddressIsZero() external {
        uint256 newRate = 2 ether;

        // Set address to zero
        swapTokenHelper.setSwapToken(address(0), address(mockPrincipalToken), 0);

        // Should revert when trying to update rate on zero address
        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert();
        swapTokenHelper.updateSwapRate(newRate);
    }

    function test_updateSwapRate_ShouldRevert_WhenPrincipalTokenIsZero() external {
        uint256 newRate = 2 ether;

        // Set principalToken to zero
        swapTokenHelper.setSwapToken(address(mockSwapToken), address(0), 0);

        // Should revert when trying to update rate on zero principalToken address
        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert();
        swapTokenHelper.updateSwapRate(newRate);
    }

    function test_updateSwapRate_ShouldAllowMultipleUpdates() external {
        uint256 rate1 = 0.5 ether;
        uint256 rate2 = 1.5 ether;
        uint256 rate3 = 2.5 ether;

        vm.startPrank(DEFAULT_ADDRESS);

        // First update
        swapTokenHelper.updateSwapRate(rate1);
        assertEq(mockSwapToken.swapRate(), rate1, "Swap Token rate should be updated to rate1");
        assertEq(mockPrincipalToken.swapRate(), rate1, "Principal Token rate should be updated to rate1");

        // Second update
        swapTokenHelper.updateSwapRate(rate2);
        assertEq(mockSwapToken.swapRate(), rate2, "Swap Token rate should be updated to rate2");
        assertEq(mockPrincipalToken.swapRate(), rate2, "Principal Token rate should be updated to rate2");

        // Third update
        swapTokenHelper.updateSwapRate(rate3);
        assertEq(mockSwapToken.swapRate(), rate3, "Swap Token rate should be updated to rate3");
        assertEq(mockPrincipalToken.swapRate(), rate3, "Principal Token rate should be updated to rate3");

        vm.stopPrank();
    }

    // ------------------------------- Integration Tests ----------------------------------- //

    function test_integration_IssueAndUpdateRate() external {
        uint256 amount = 1000 ether;
        uint256 newRate = 2 ether;

        vm.startPrank(DEFAULT_ADDRESS);

        // Issue tokens first
        swapTokenHelper.issue(user1, amount);

        // Update swap rate
        swapTokenHelper.updateSwapRate(newRate);

        vm.stopPrank();

        // Check balances and rate
        assertEq(mockSwapToken.balanceOf(user1), amount, "Swap Token balance should equal issued amount");
        assertEq(mockPrincipalToken.balanceOf(user1), amount, "Principal Token balance should equal issued amount");
        assertEq(mockSwapToken.swapRate(), newRate, "Swap Token rate should be updated");
        assertEq(mockPrincipalToken.swapRate(), newRate, "Principal Token rate should be updated");
    }

    function test_integration_CheckInitializationAndExpiry() external {
        // Check initialization
        assertTrue(swapTokenHelper.isInitialized(), "Should be initialized");
        assertFalse(swapTokenHelper.isExpired(), "Should not be expired");

        // Warp time to make expired
        vm.warp(block.timestamp + 2 days);

        // Check expiry
        assertTrue(swapTokenHelper.isExpired(), "Should be expired after time warp");
        assertTrue(swapTokenHelper.isInitialized(), "Should still be initialized");
    }

    // ------------------------------- Edge Cases ----------------------------------- //

    function test_edgeCase_RevertWhenExpiredAssetOperations() external {
        // Warp time to make asset expired
        vm.warp(block.timestamp + 2 days);

        // Should be expired
        assertTrue(swapTokenHelper.isExpired(), "Should be expired");

        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.updateSwapRate(2 ether);

        // Verify operations
        assertEq(mockSwapToken.balanceOf(user1), 0, "Should not be able to issue on expired asset");
        assertEq(mockSwapToken.swapRate(), 2 ether, "Should be able to update rate on expired asset");
    }

    function test_edgeCase_UninitializedSwapToken() external {
        // Set to uninitialized state
        swapTokenHelper.setSwapToken(address(0), address(0), 0);

        assertFalse(swapTokenHelper.isInitialized(), "Should not be initialized");

        // Operations should revert on uninitialized SwapToken
        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert();
        swapTokenHelper.issue(user1, 1000 ether);

        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert();
        swapTokenHelper.updateSwapRate(2 ether);

        vm.expectRevert();
        swapTokenHelper.isExpired();
    }

    function test_edgeCase_AllowMultipleOperationsWithDifferentPrincipalTokenRedeemedValues() external {
        // Set different ctRedeemed values
        swapTokenHelper.setSwapToken(address(mockSwapToken), address(mockPrincipalToken), 1000);

        // Should not affect other operations
        assertTrue(swapTokenHelper.isInitialized(), "Should be initialized with ctRedeemed set");
        assertFalse(swapTokenHelper.isExpired(), "Should not be expired with ctRedeemed set");

        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.issue(user1, 500 ether);

        assertEq(mockSwapToken.balanceOf(user1), 500 ether, "Should issue correctly with ctRedeemed set");
    }

    // ------------------------------- Fuzz Tests ----------------------------------- //

    function testFuzz_issue_ShouldMintCorrectAmounts(uint256 amount) external {
        // Bound amount to avoid overflow
        amount = bound(amount, 0, type(uint256).max / 2);

        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.issue(user1, amount);

        assertEq(mockSwapToken.balanceOf(user1), amount, "Swap Token balance should equal issued amount");
        assertEq(mockPrincipalToken.balanceOf(user1), amount, "Principal Token balance should equal issued amount");
    }

    function testFuzz_updateSwapRate_ShouldUpdateCorrectly(uint256 rate) external {
        vm.prank(DEFAULT_ADDRESS);
        swapTokenHelper.updateSwapRate(rate);

        assertEq(mockSwapToken.swapRate(), rate, "Swap Token rate should be updated");
        assertEq(mockPrincipalToken.swapRate(), rate, "Principal Token rate should be updated");
    }

    function testFuzz_isInitialized_ShouldReturnCorrectValue(address addr1, address addr2) external {
        swapTokenHelper.setSwapToken(addr1, addr2, 0);

        bool expected = addr1 != address(0) && addr2 != address(0);
        assertEq(swapTokenHelper.isInitialized(), expected, "isInitialized should return correct value");
    }
}
