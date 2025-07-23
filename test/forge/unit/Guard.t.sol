// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Shares} from "contracts/core/assets/Shares.sol";

import {IErrors} from "contracts/interfaces/IErrors.sol";

import {Guard} from "contracts/libraries/Guard.sol";
import {SwapToken, SwapTokenLibrary} from "contracts/libraries/SwapToken.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";

// Helper contract to expose Guard library functions for testing
contract GuardHelper {
    using Guard for SwapToken;

    SwapToken public swapToken;

    function setSwapToken(address _address, address principalToken) external {
        swapToken._address = _address;
        swapToken.principalToken = principalToken;
        swapToken.withdrawn = 0;
    }

    // Exposed Guard functions
    function onlyNotExpired() external view {
        Guard._onlyNotExpired(swapToken);
    }

    function onlyExpired() external view {
        Guard._onlyExpired(swapToken);
    }

    function onlyInitialized() external view {
        Guard._onlyInitialized(swapToken);
    }

    function safeBeforeExpired() external view {
        Guard.safeBeforeExpired(swapToken);
    }

    function safeAfterExpired() external view {
        Guard.safeAfterExpired(swapToken);
    }
}

contract GuardTest is Helper {
    GuardHelper internal guardHelper;
    Shares internal mockAsset;
    Shares internal mockPrincipalToken;

    address internal user1;
    address internal user2;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(DEFAULT_ADDRESS);

        // Create mock assets for testing
        mockAsset = new Shares("Swap Token", user1, block.timestamp + 1 days, 1 ether);
        mockPrincipalToken = new Shares("Principal Token", user1, block.timestamp + 1 days, 1 ether);

        // Deploy guard helper
        guardHelper = new GuardHelper();

        // Initialize with valid SwapToken
        guardHelper.setSwapToken(address(mockAsset), address(mockPrincipalToken));

        vm.stopPrank();
    }

    // ------------------------------- _onlyNotExpired Tests ----------------------------------- //

    function test_onlyNotExpired_ShouldPass_WhenNotExpired() external {
        // Shares should not be expired at setup
        assertFalse(mockAsset.isExpired(), "Shares should not be expired");

        // Should not revert
        guardHelper.onlyNotExpired();
    }

    function test_onlyNotExpired_ShouldRevert_WhenExpired() external {
        // Warp time to make asset expired
        vm.warp(block.timestamp + 2 days);

        assertTrue(mockAsset.isExpired(), "Shares should be expired");

        // Should revert with Expired error
        vm.expectRevert(IErrors.Expired.selector);
        guardHelper.onlyNotExpired();
    }

    function test_onlyNotExpired_ShouldRevert_WhenExactlyAtExpiry() external {
        // Warp to exact expiry time
        vm.warp(mockAsset.expiry());

        assertTrue(mockAsset.isExpired(), "Shares should be expired at expiry time");

        // Should revert with Expired error
        vm.expectRevert(IErrors.Expired.selector);
        guardHelper.onlyNotExpired();
    }

    // ------------------------------- _onlyExpired Tests ----------------------------------- //

    function test_onlyExpired_ShouldRevert_WhenNotExpired() external {
        // Shares should not be expired at setup
        assertFalse(mockAsset.isExpired(), "Shares should not be expired");

        // Should revert with NotExpired error
        vm.expectRevert(IErrors.NotExpired.selector);
        guardHelper.onlyExpired();
    }

    function test_onlyExpired_ShouldPass_WhenExpired() external {
        // Warp time to make asset expired
        vm.warp(block.timestamp + 2 days);

        assertTrue(mockAsset.isExpired(), "Shares should be expired");

        // Should not revert
        guardHelper.onlyExpired();
    }

    function test_onlyExpired_ShouldPass_WhenExactlyAtExpiry() external {
        // Warp to exact expiry time
        vm.warp(mockAsset.expiry());

        assertTrue(mockAsset.isExpired(), "Shares should be expired at expiry time");

        // Should not revert
        guardHelper.onlyExpired();
    }

    // ------------------------------- _onlyInitialized Tests ----------------------------------- //

    function test_onlyInitialized_ShouldPass_WhenInitialized() external {
        // SwapToken should be initialized in setup (both addresses non-zero)
        // Should not revert
        guardHelper.onlyInitialized();
    }

    function test_onlyInitialized_ShouldRevert_WhenNotInitialized_BothZero() external {
        // Set both addresses to zero
        guardHelper.setSwapToken(address(0), address(0));

        // Should revert with Uninitialized error
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.onlyInitialized();
    }

    function test_onlyInitialized_ShouldRevert_WhenNotInitialized_ZeroDSAddress() external {
        // Set Swap Token address to zero, keep Principal Token
        guardHelper.setSwapToken(address(0), address(mockPrincipalToken));

        // Should revert with Uninitialized error
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.onlyInitialized();
    }

    function test_onlyInitialized_ShouldRevert_WhenNotInitialized_ZeroCTAddress() external {
        // Set Principal Token address to zero, keep Swap Token
        guardHelper.setSwapToken(address(mockAsset), address(0));

        // Should revert with Uninitialized error
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.onlyInitialized();
    }

    // ------------------------------- safeBeforeExpired Tests ----------------------------------- //

    function test_safeBeforeExpired_ShouldPass_WhenInitializedAndNotExpired() external {
        // SwapToken should be initialized and not expired
        assertFalse(mockAsset.isExpired(), "Shares should not be expired");

        // Should not revert
        guardHelper.safeBeforeExpired();
    }

    function test_safeBeforeExpired_ShouldRevert_WhenNotInitialized() external {
        // Set to uninitialized state
        guardHelper.setSwapToken(address(0), address(0));

        // Should revert with Uninitialized error (checked first)
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.safeBeforeExpired();
    }

    function test_safeBeforeExpired_ShouldRevert_WhenInitializedButExpired() external {
        // Make asset expired
        vm.warp(block.timestamp + 2 days);

        assertTrue(mockAsset.isExpired(), "Shares should be expired");

        // Should revert with Expired error (checked after initialization)
        vm.expectRevert(IErrors.Expired.selector);
        guardHelper.safeBeforeExpired();
    }

    function test_safeBeforeExpired_ShouldRevert_WhenNotInitializedAndExpired() external {
        // Set to uninitialized state and make time expired
        guardHelper.setSwapToken(address(0), address(0));
        vm.warp(block.timestamp + 2 days);

        // Should revert with Uninitialized error (checked first)
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.safeBeforeExpired();
    }

    // ------------------------------- safeAfterExpired Tests ----------------------------------- //

    function test_safeAfterExpired_ShouldPass_WhenInitializedAndExpired() external {
        // Make asset expired
        vm.warp(block.timestamp + 2 days);

        assertTrue(mockAsset.isExpired(), "Shares should be expired");

        // Should not revert
        guardHelper.safeAfterExpired();
    }

    function test_safeAfterExpired_ShouldRevert_WhenNotInitialized() external {
        // Set to uninitialized state and make time expired
        guardHelper.setSwapToken(address(0), address(0));
        vm.warp(block.timestamp + 2 days);

        // Should revert with Uninitialized error (checked first)
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.safeAfterExpired();
    }

    function test_safeAfterExpired_ShouldRevert_WhenInitializedButNotExpired() external {
        assertFalse(mockAsset.isExpired(), "Shares should not be expired");

        // Should revert with NotExpired error (checked after initialization)
        vm.expectRevert(IErrors.NotExpired.selector);
        guardHelper.safeAfterExpired();
    }

    function test_safeAfterExpired_ShouldRevert_WhenNotInitializedAndNotExpired() external {
        // Set to uninitialized state
        guardHelper.setSwapToken(address(0), address(0));

        assertFalse(mockAsset.isExpired(), "Shares should not be expired");

        // Should revert with Uninitialized error (checked first)
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.safeAfterExpired();
    }

    // ------------------------------- Edge Cases and Integration Tests ----------------------------------- //

    function test_isExpired_Integration_WithRealAsset() external {
        // Test with real Shares contract behavior
        uint256 futureExpiry = block.timestamp + 1 hours;
        Shares testAsset = new Shares("TEST", user1, futureExpiry, 1 ether);
        Shares testPrincipalToken = new Shares("TEST_CT", user1, futureExpiry, 1 ether);

        // Set up with test assets
        guardHelper.setSwapToken(address(testAsset), address(testPrincipalToken));

        // Should not be expired initially
        assertFalse(testAsset.isExpired(), "Should not be expired initially");
        guardHelper.onlyNotExpired();

        // Should be expired after time passes
        vm.warp(futureExpiry);
        assertTrue(testAsset.isExpired(), "Should be expired after time passes");

        vm.expectRevert(IErrors.Expired.selector);
        guardHelper.onlyNotExpired();

        // Should pass expired check
        guardHelper.onlyExpired();
    }

    function test_allFunctions_WithDifferentAssetExpiryTimes() external {
        // Test with various expiry times
        uint256[] memory expiryTimes = new uint256[](3);
        expiryTimes[0] = block.timestamp + 1 minutes;
        expiryTimes[1] = block.timestamp + 1 hours;
        expiryTimes[2] = block.timestamp + 1 days;

        for (uint256 i = 0; i < expiryTimes.length; i++) {
            Shares testAsset = new Shares("TEST", user1, expiryTimes[i], 1 ether);
            Shares testPrincipalToken = new Shares("TEST_CT", user1, expiryTimes[i], 1 ether);

            // Set up with test assets
            guardHelper.setSwapToken(address(testAsset), address(testPrincipalToken));

            // Test before expiry
            guardHelper.safeBeforeExpired();

            // Test after expiry
            vm.warp(expiryTimes[i]);
            guardHelper.safeAfterExpired();
        }
    }

    // ------------------------------- Test Helper Functions ----------------------------------- //

    function test_AssetExpiryBehavior() external view {
        // Verify our understanding of Shares.isExpired() behavior
        assertFalse(mockAsset.isExpired(), "Shares should not be expired initially");
        assertEq(mockAsset.expiry(), block.timestamp + 1 days, "Expiry should be set correctly");
    }

    function test_GuardHelperSetup() external view {
        // Verify the guard helper was set up correctly
        (bool success,) = address(guardHelper).staticcall(abi.encodeWithSignature("swapToken()"));
        assertTrue(success, "Guard helper should be properly deployed");
    }
}
