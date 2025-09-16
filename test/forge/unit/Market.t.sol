// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";

// Helper contract to expose MarketLibrary functions for testing
contract MarketHelper {
    Market public market;

    function setMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax) external {
        market.referenceAsset = referenceAsset;
        market.collateralAsset = collateralAsset;
        market.expiryTimestamp = expiryTimestamp;
        market.rateOracle = rateOracle;
        market.rateMin = rateMin;
        market.rateMax = rateMax;
        market.rateChangePerDayMax = rateChangePerDayMax;
        market.rateChangeCapacityMax = rateChangeCapacityMax;
    }

    function referenceAsset() external view returns (address) {
        return market.referenceAsset;
    }

    function collateralAsset() external view returns (address) {
        return market.collateralAsset;
    }
}

contract MarketTest is Helper {
    MarketHelper internal marketHelper;

    address internal mockPA;
    address internal mockRA;
    address internal mockRateOracle;
    address internal user1;
    address internal user2;

    uint256 internal constant EXPIRY_INTERVAL = 7 days;
    uint256 internal constant RATE_MIN = 0.9 ether;
    uint256 internal constant RATE_MAX = 1.1 ether;
    uint256 internal constant RATE_CHANGE_PER_DAY_MAX = 0.001 ether;
    uint256 internal constant RATE_CHANGE_CAPACITY_MAX = 0.001 ether;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        mockPA = makeAddr("mockPA");
        mockRA = makeAddr("mockRA");
        mockRateOracle = makeAddr("mockRateOracle");

        // Deploy market helper
        marketHelper = new MarketHelper();

        // Set up with valid market data
        marketHelper.setMarket(mockPA, mockRA, EXPIRY_INTERVAL, mockRateOracle, RATE_MIN, RATE_MAX, RATE_CHANGE_PER_DAY_MAX, RATE_CHANGE_CAPACITY_MAX);
    }

    // ------------------------------- referenceAsset Tests ----------------------------------- //
    function test_peggedAsset_ShouldReturnCorrectPA() external {
        address referenceAsset = marketHelper.referenceAsset();
        assertEq(referenceAsset, mockPA, "Should return the correct Reference Asset address");

        marketHelper.setMarket(address(1234), mockRA, EXPIRY_INTERVAL, mockRateOracle, RATE_MIN, RATE_MAX, RATE_CHANGE_PER_DAY_MAX, RATE_CHANGE_CAPACITY_MAX);

        referenceAsset = marketHelper.referenceAsset();
        assertEq(referenceAsset, address(1234), "Should return zero address when Reference Asset is zero");
    }

    // ------------------------------- collateralAsset Tests ----------------------------------- //
    function test_redemptionAsset_ShouldReturnCorrectRA() external {
        address collateralAsset = marketHelper.collateralAsset();
        assertEq(collateralAsset, mockRA, "Should return the correct Collateral Asset address");

        marketHelper.setMarket(mockPA, address(1234), EXPIRY_INTERVAL, mockRateOracle, RATE_MIN, RATE_MAX, RATE_CHANGE_PER_DAY_MAX, RATE_CHANGE_CAPACITY_MAX);

        collateralAsset = marketHelper.collateralAsset();
        assertEq(collateralAsset, address(1234), "Should return zero address when Collateral Asset is zero");
    }

    // ------------------------------- Integration Tests ----------------------------------- //

    function test_completeWorkflow_CreateAndQuery() external {
        // Create a new market
        Market memory newMarket = Market({collateralAsset: user1, referenceAsset: user2, expiryTimestamp: 456, rateOracle: mockRateOracle, rateMin: RATE_MIN, rateMax: RATE_MAX, rateChangePerDayMax: RATE_CHANGE_PER_DAY_MAX, rateChangeCapacityMax: RATE_CHANGE_CAPACITY_MAX});

        // Set the helper to use this new market
        marketHelper.setMarket(user1, user2, 456, mockRateOracle, RATE_MIN, RATE_MAX, RATE_CHANGE_PER_DAY_MAX, RATE_CHANGE_CAPACITY_MAX);

        // Test all getter functions
        assertEq(marketHelper.referenceAsset(), user1, "Reference Asset should match");
        assertEq(marketHelper.collateralAsset(), user2, "Collateral Asset should match");

        // Test ID generation
        MarketId id = MarketId.wrap(keccak256(abi.encode(marketHelper.market)));
        assertTrue(MarketId.unwrap(id) != bytes32(0), "ID should not be zero");
    }

    function test_marketId_Consistency() external {
        // Create same market configuration twice
        Market memory market1 = Market({collateralAsset: mockPA, referenceAsset: mockRA, expiryTimestamp: EXPIRY_INTERVAL, rateOracle: mockRateOracle, rateMin: RATE_MIN, rateMax: RATE_MAX, rateChangePerDayMax: RATE_CHANGE_PER_DAY_MAX, rateChangeCapacityMax: RATE_CHANGE_CAPACITY_MAX});
        Market memory market2 = Market({collateralAsset: mockPA, referenceAsset: mockRA, expiryTimestamp: EXPIRY_INTERVAL, rateOracle: mockRateOracle, rateMin: RATE_MIN, rateMax: RATE_MAX, rateChangePerDayMax: RATE_CHANGE_PER_DAY_MAX, rateChangeCapacityMax: RATE_CHANGE_CAPACITY_MAX});

        // Set helper to first market
        marketHelper.setMarket(market1.referenceAsset, market1.collateralAsset, market1.expiryTimestamp, market1.rateOracle, market1.rateMin, market1.rateMax, market1.rateChangePerDayMax, market1.rateChangeCapacityMax);
        MarketId id1 = MarketId.wrap(keccak256(abi.encode(marketHelper.market)));

        // Markets should be identical, so ISwapToken should be identical
        marketHelper.setMarket(market2.referenceAsset, market2.collateralAsset, market2.expiryTimestamp, market2.rateOracle, market2.rateMin, market2.rateMax, market2.rateChangePerDayMax, market2.rateChangeCapacityMax);
        MarketId id2 = MarketId.wrap(keccak256(abi.encode(marketHelper.market)));

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

        assertEq(referenceAsset, mockPA, "Reference Asset field should be accessible");
        assertEq(collateralAsset, mockRA, "Collateral Asset field should be accessible");
    }
}
