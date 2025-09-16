// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";

import {Guard} from "contracts/libraries/Guard.sol";

import {MarketId} from "contracts/libraries/Market.sol";
import {Shares} from "contracts/libraries/State.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";

// Helper contract to expose Guard library functions for testing
contract GuardHelper {
    using Guard for Shares;

    Shares public swapToken;

    function setSwapToken(address swap, address principal) external {
        swapToken.swap = swap;
        swapToken.principal = principal;
        swapToken.withdrawn = 0;
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
    PoolShare internal mockAsset;
    PoolShare internal mockPrincipalToken;

    address internal user1;
    address internal user2;

    IPoolShare.ConstructorParams constructorParams;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(DEFAULT_ADDRESS);

        constructorParams.poolId = MarketId.wrap(bytes32(""));
        constructorParams.expiry = block.timestamp + 1 days;
        constructorParams.pairName = "Swap Token";
        constructorParams.symbol = "SWT";
        constructorParams.poolManager = address(1);

        // Create mock assets for testing

        mockAsset = new PoolShare(constructorParams);
        mockPrincipalToken = new PoolShare(constructorParams);

        // Deploy guard helper
        guardHelper = new GuardHelper();

        // Initialize with valid Shares
        guardHelper.setSwapToken(address(mockAsset), address(mockPrincipalToken));

        vm.stopPrank();
    }

    // ------------------------------- safeBeforeExpired Tests ----------------------------------- //

    function test_safeBeforeExpired_ShouldPass_WhenInitializedAndNotExpired() external {
        // Shares should be initialized and not expired
        assertFalse(mockAsset.isExpired(), "PoolShare should not be expired");

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

        assertTrue(mockAsset.isExpired(), "PoolShare should be expired");

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

        assertTrue(mockAsset.isExpired(), "PoolShare should be expired");

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
        assertFalse(mockAsset.isExpired(), "PoolShare should not be expired");

        // Should revert with NotExpired error (checked after initialization)
        vm.expectRevert(IErrors.NotExpired.selector);
        guardHelper.safeAfterExpired();
    }

    function test_safeAfterExpired_ShouldRevert_WhenNotInitializedAndNotExpired() external {
        // Set to uninitialized state
        guardHelper.setSwapToken(address(0), address(0));

        assertFalse(mockAsset.isExpired(), "PoolShare should not be expired");

        // Should revert with Uninitialized error (checked first)
        vm.expectRevert(IErrors.Uninitialized.selector);
        guardHelper.safeAfterExpired();
    }

    // ------------------------------- Edge Cases and Integration Tests ----------------------------------- //

    function test_isExpired_Integration_WithRealAsset() external {
        // Test with real PoolShare contract behavior
        uint256 futureExpiry = block.timestamp + 1 hours;
        constructorParams.expiry = futureExpiry;

        PoolShare testAsset = new PoolShare(constructorParams);
        PoolShare testPrincipalToken = new PoolShare(constructorParams);

        // Set up with test assets
        guardHelper.setSwapToken(address(testAsset), address(testPrincipalToken));

        // Should not be expired initially
        assertFalse(testAsset.isExpired(), "Should not be expired initially");
        guardHelper.safeBeforeExpired();

        // Should be expired after time passes
        vm.warp(futureExpiry);
        assertTrue(testAsset.isExpired(), "Should be expired after time passes");

        vm.expectRevert(IErrors.Expired.selector);
        guardHelper.safeBeforeExpired();

        // Should pass expired check
        guardHelper.safeAfterExpired();
    }

    function test_allFunctions_WithDifferentAssetExpiryTimes() external {
        // Test with various expiry times
        uint256[] memory expiryTimes = new uint256[](3);
        expiryTimes[0] = block.timestamp + 1 minutes;
        expiryTimes[1] = block.timestamp + 1 hours;
        expiryTimes[2] = block.timestamp + 1 days;

        for (uint256 i = 0; i < expiryTimes.length; i++) {
            constructorParams.expiry = expiryTimes[i];

            PoolShare testAsset = new PoolShare(constructorParams);
            PoolShare testPrincipalToken = new PoolShare(constructorParams);

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
        // Verify our understanding of PoolShare.isExpired() behavior
        assertFalse(mockAsset.isExpired(), "PoolShare should not be expired initially");
        assertEq(mockAsset.expiry(), block.timestamp + 1 days, "Expiry should be set correctly");
    }

    function test_GuardHelperSetup() external view {
        // Verify the guard helper was set up correctly
        (bool success,) = address(guardHelper).staticcall(abi.encodeWithSignature("swapToken()"));
        assertTrue(success, "Guard helper should be properly deployed");
    }
}
