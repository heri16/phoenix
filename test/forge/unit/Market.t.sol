// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";

// Helper contract to expose MarketLibrary functions for testing
contract MarketHelper {
    Market public market;

    function setMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address exchangeRateProvider) external {
        market.referenceAsset = referenceAsset;
        market.collateralAsset = collateralAsset;
        market.expiryTimestamp = expiryTimestamp;
        market.exchangeRateProvider = exchangeRateProvider;
    }

    // Exposed MarketLibrary functions
    function toId() external view returns (MarketId) {
        return MarketLibrary.toId(market);
    }

    function initialize(address referenceAsset, address collateralAsset, uint256 expiry, address exchangeRateProvider) external pure returns (Market memory) {
        return MarketLibrary.initialize(referenceAsset, collateralAsset, expiry, exchangeRateProvider);
    }

    function referenceAsset() external view returns (address) {
        return market.referenceAsset;
    }

    function underlyingAsset() external view returns (address collateralAsset, address referenceAsset) {
        return MarketLibrary.underlyingAsset(market);
    }

    function collateralAsset() external view returns (address) {
        return market.collateralAsset;
    }

    function isInitialized() external view returns (bool) {
        return MarketLibrary.isInitialized(market);
    }
}

contract MarketTest is Helper {
    MarketHelper internal marketHelper;

    address internal mockPA;
    address internal mockRA;
    address internal mockExchangeRateProvider;
    address internal user1;
    address internal user2;

    uint256 internal constant EXPIRY_INTERVAL = 7 days;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        mockPA = makeAddr("mockPA");
        mockRA = makeAddr("mockRA");
        mockExchangeRateProvider = makeAddr("mockExchangeRateProvider");

        // Deploy market helper
        marketHelper = new MarketHelper();

        // Set up with valid market data
        marketHelper.setMarket(mockPA, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);
    }

    // ------------------------------- initialize Tests ----------------------------------- //
    function test_initialize_ShouldPass_WithValidParameters() external {
        Market memory newMarket = marketHelper.initialize(mockPA, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);

        assertEq(newMarket.referenceAsset, mockPA, "Reference Asset should be set correctly");
        assertEq(newMarket.collateralAsset, mockRA, "Collateral Asset should be set correctly");
        assertEq(newMarket.expiryTimestamp, EXPIRY_INTERVAL, "Expiry interval should be set correctly");
        assertEq(newMarket.exchangeRateProvider, mockExchangeRateProvider, "Exchange rate provider should be set correctly");
    }

    function test_initialize_ShouldRevert_WhenPAIsZeroAddress() external {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        marketHelper.initialize(address(0), mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);
    }

    function test_initialize_ShouldRevert_WhenRAIsZeroAddress() external {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        marketHelper.initialize(mockPA, address(0), EXPIRY_INTERVAL, mockExchangeRateProvider);
    }

    function test_initialize_ShouldRevert_WhenBothPAAndRAAreZeroAddress() external {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        marketHelper.initialize(address(0), address(0), EXPIRY_INTERVAL, mockExchangeRateProvider);
    }

    function test_initialize_ShouldRevert_WhenPAEqualsRA() external {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        marketHelper.initialize(mockPA, mockPA, EXPIRY_INTERVAL, mockExchangeRateProvider);
    }

    function test_initialize_ShouldRevert_WithZeroexpiryTimestamp() external {
        vm.expectRevert(IErrors.InvalidExpiry.selector);
        marketHelper.initialize(mockPA, mockRA, 0, mockExchangeRateProvider);
    }

    function test_initialize_ShouldRevert_WithZeroExchangeRateProvider() external {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        marketHelper.initialize(mockPA, mockRA, EXPIRY_INTERVAL, address(0));
    }

    // ------------------------------- toId Tests ----------------------------------- //
    function test_toId_ShouldReturnConsistentId() external {
        MarketId id1 = marketHelper.toId();
        MarketId id2 = marketHelper.toId();

        assertEq(MarketId.unwrap(id1), MarketId.unwrap(id2), "Same market should return same ID");
    }

    function test_toId_ShouldReturnDifferentIds_ForDifferentMarkets() external {
        MarketId id1 = marketHelper.toId();

        // Change market data
        marketHelper.setMarket(user1, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);
        MarketId id2 = marketHelper.toId();

        assertFalse(MarketId.unwrap(id1) == MarketId.unwrap(id2), "Different markets should return different ISwapToken");
    }

    function test_toId_ShouldReturnDifferentIds_WhenPAChanges() external {
        MarketId id1 = marketHelper.toId();

        marketHelper.setMarket(user1, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);
        MarketId id2 = marketHelper.toId();

        assertFalse(MarketId.unwrap(id1) == MarketId.unwrap(id2), "Different Reference Asset should return different ID");
    }

    function test_toId_ShouldReturnDifferentIds_WhenRAChanges() external {
        MarketId id1 = marketHelper.toId();

        marketHelper.setMarket(mockPA, user1, EXPIRY_INTERVAL, mockExchangeRateProvider);
        MarketId id2 = marketHelper.toId();

        assertFalse(MarketId.unwrap(id1) == MarketId.unwrap(id2), "Different Collateral Asset should return different ID");
    }

    function test_toId_ShouldReturnDifferentIds_WhenexpiryTimestampChanges() external {
        MarketId id1 = marketHelper.toId();

        marketHelper.setMarket(mockPA, mockRA, EXPIRY_INTERVAL * 2, mockExchangeRateProvider);
        MarketId id2 = marketHelper.toId();

        assertFalse(MarketId.unwrap(id1) == MarketId.unwrap(id2), "Different expiry interval should return different ID");
    }

    function test_toId_ShouldReturnDifferentIds_WhenExchangeRateProviderChanges() external {
        MarketId id1 = marketHelper.toId();

        marketHelper.setMarket(mockPA, mockRA, EXPIRY_INTERVAL, user1);
        MarketId id2 = marketHelper.toId();

        assertFalse(MarketId.unwrap(id1) == MarketId.unwrap(id2), "Different exchange rate provider should return different ID");
    }

    // ------------------------------- referenceAsset Tests ----------------------------------- //
    function test_peggedAsset_ShouldReturnCorrectPA() external {
        address referenceAsset = marketHelper.referenceAsset();
        assertEq(referenceAsset, mockPA, "Should return the correct Reference Asset address");

        marketHelper.setMarket(address(1234), mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);

        referenceAsset = marketHelper.referenceAsset();
        assertEq(referenceAsset, address(1234), "Should return zero address when Reference Asset is zero");
    }

    // ------------------------------- underlyingAsset Tests ----------------------------------- //
    function test_underlyingAsset_ShouldReturnCorrectRAAndPA() external {
        (address collateralAsset, address referenceAsset) = marketHelper.underlyingAsset();

        assertEq(collateralAsset, mockRA, "Should return the correct Collateral Asset address");
        assertEq(referenceAsset, mockPA, "Should return the correct Reference Asset address");

        marketHelper.setMarket(address(1234), address(5678), EXPIRY_INTERVAL, mockExchangeRateProvider);

        (collateralAsset, referenceAsset) = marketHelper.underlyingAsset();

        assertEq(collateralAsset, address(5678), "Should return zero Collateral Asset address");
        assertEq(referenceAsset, address(1234), "Should return zero Reference Asset address");
    }

    // ------------------------------- collateralAsset Tests ----------------------------------- //
    function test_redemptionAsset_ShouldReturnCorrectRA() external {
        address collateralAsset = marketHelper.collateralAsset();
        assertEq(collateralAsset, mockRA, "Should return the correct Collateral Asset address");

        marketHelper.setMarket(mockPA, address(1234), EXPIRY_INTERVAL, mockExchangeRateProvider);

        collateralAsset = marketHelper.collateralAsset();
        assertEq(collateralAsset, address(1234), "Should return zero address when Collateral Asset is zero");
    }

    // ------------------------------- isInitialized Tests ----------------------------------- //
    function test_isInitialized_ShouldReturnTrue_WhenBothAddressesAreSet() external {
        bool initialized = marketHelper.isInitialized();
        assertTrue(initialized, "Should return true when both Reference Asset and Collateral Asset are set");
    }

    function test_isInitialized_ShouldReturnFalse_WhenPAIsZero() external {
        marketHelper.setMarket(address(0), mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);

        bool initialized = marketHelper.isInitialized();
        assertFalse(initialized, "Should return false when Reference Asset is zero");
    }

    function test_isInitialized_ShouldReturnFalse_WhenRAIsZero() external {
        marketHelper.setMarket(mockPA, address(0), EXPIRY_INTERVAL, mockExchangeRateProvider);

        bool initialized = marketHelper.isInitialized();
        assertFalse(initialized, "Should return false when Collateral Asset is zero");
    }

    function test_isInitialized_ShouldReturnFalse_WhenBothAddressesAreZero() external {
        marketHelper.setMarket(address(0), address(0), EXPIRY_INTERVAL, mockExchangeRateProvider);

        bool initialized = marketHelper.isInitialized();
        assertFalse(initialized, "Should return false when both Reference Asset and Collateral Asset are zero");
    }

    function test_isInitialized_ShouldReturnTrue_RegardlessOfOtherFields() external {
        // Test with zero values for other fields
        marketHelper.setMarket(mockPA, mockRA, 0, address(0));

        bool initialized = marketHelper.isInitialized();
        assertTrue(initialized, "Should return true when Reference Asset and Collateral Asset are set, regardless of other fields");
    }

    // ------------------------------- Integration Tests ----------------------------------- //

    function test_completeWorkflow_InitializeAndQuery() external {
        // Initialize a new market
        Market memory newMarket = marketHelper.initialize(user1, user2, 456, mockExchangeRateProvider);

        // Set the helper to use this new market
        marketHelper.setMarket(user1, user2, 456, mockExchangeRateProvider);

        // Test all getter functions
        assertEq(marketHelper.referenceAsset(), user1, "Reference Asset should match");
        assertEq(marketHelper.collateralAsset(), user2, "Collateral Asset should match");

        (address collateralAsset, address referenceAsset) = marketHelper.underlyingAsset();
        assertEq(collateralAsset, user2, "Collateral Asset from underlyingAsset should match");
        assertEq(referenceAsset, user1, "Reference Asset from underlyingAsset should match");

        assertTrue(marketHelper.isInitialized(), "Market should be initialized");

        // Test ID generation
        MarketId id = marketHelper.toId();
        assertTrue(MarketId.unwrap(id) != bytes32(0), "ID should not be zero");
    }

    function test_edgeCases_MaxValues() external {
        uint256 maxUint = type(uint256).max;
        address maxAddress = address(type(uint160).max);

        Market memory newMarket = marketHelper.initialize(maxAddress, user1, maxUint, maxAddress);

        assertEq(newMarket.referenceAsset, maxAddress, "Should handle max address for Reference Asset");
        assertEq(newMarket.collateralAsset, user1, "Should handle normal address for Collateral Asset");
        assertEq(newMarket.expiryTimestamp, maxUint, "Should handle max uint256 for expiry interval");
        assertEq(newMarket.exchangeRateProvider, maxAddress, "Should handle max address for exchange rate provider");
    }

    function test_marketId_Consistency() external {
        // Create same market configuration twice
        Market memory market1 = marketHelper.initialize(mockPA, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);
        Market memory market2 = marketHelper.initialize(mockPA, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);

        // Set helper to first market
        marketHelper.setMarket(mockPA, mockRA, EXPIRY_INTERVAL, mockExchangeRateProvider);
        MarketId id1 = marketHelper.toId();

        // Markets should be identical, so ISwapToken should be identical
        marketHelper.setMarket(market2.referenceAsset, market2.collateralAsset, market2.expiryTimestamp, market2.exchangeRateProvider);
        MarketId id2 = marketHelper.toId();

        assertEq(MarketId.unwrap(id1), MarketId.unwrap(id2), "Identical markets should have identical ISwapToken");
    }

    // ------------------------------- Test Helper Functions ----------------------------------- //

    function test_MarketHelperSetup() external view {
        // Verify the market helper was set up correctly
        (bool success,) = address(marketHelper).staticcall(abi.encodeWithSignature("market()"));
        assertTrue(success, "Market helper should be properly deployed");
    }

    function test_MarketStruct_FieldAccess() external view {
        // Test that we can access all market fields through the helper
        // This indirectly tests that our setMarket function works correctly
        address referenceAsset = marketHelper.referenceAsset();
        address collateralAsset = marketHelper.collateralAsset();
        bool initialized = marketHelper.isInitialized();

        assertEq(referenceAsset, mockPA, "Reference Asset field should be accessible");
        assertEq(collateralAsset, mockRA, "Collateral Asset field should be accessible");
        assertTrue(initialized, "Initialization status should be accessible");
    }
}
