// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ExchangeRateProvider} from "contracts/core/ExchangeRateProvider.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract ExchangeRateProviderTest is Helper {
    ExchangeRateProvider private exchangeRateProvider;

    DummyWETH collateralAsset;
    DummyWETH referenceAsset;
    MarketId id;
    address user1;

    // events
    event RateUpdated(MarketId indexed id, uint256 newRate);

    function setUp() public {
        user1 = makeAddr("user1");

        exchangeRateProvider = new ExchangeRateProvider(DEFAULT_ADDRESS);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, id) = createNewMarketPair(block.timestamp + 1 days);
        vm.stopPrank();
    }

    //------------------------------------- Tests for constructor ----------------------------------------//
    function test_ConstructorShouldRevertWhenCalledWithZeroAddress() public {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        new ExchangeRateProvider(address(0));
    }

    function test_ConstructorShouldWorkCorrectly() public {
        assertEq(exchangeRateProvider.CONFIG(), DEFAULT_ADDRESS);

        // check config contract is set correctly then only config contract can call setRate
        vm.startPrank(DEFAULT_ADDRESS);
        exchangeRateProvider.setRate(id, 1e18);
        assertEq(exchangeRateProvider.rate(id), 1e18);
        vm.stopPrank();
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for rate() ----------------------------------------//
    function test_RateShouldReturnZero() public {
        // check rate is 0 for all pairs
        assertEq(exchangeRateProvider.rate(), 0);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for rate(MarketId) ----------------------------------------//
    function test_RateShouldReturnZeroForAllPairs() public {
        // check rate is initially 0 for all pairs
        assertEq(exchangeRateProvider.rate(id), 0);

        // set rate for the pair
        vm.startPrank(DEFAULT_ADDRESS);
        exchangeRateProvider.setRate(id, 1e18);
        assertEq(exchangeRateProvider.rate(id), 1e18);
        vm.stopPrank();
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setRate(MarketId, uint256) ----------------------------------------//
    function test_SetRateShouldRevertWhenCalledByNonConfig() public {
        vm.startPrank(user1);
        vm.expectRevert(IErrors.OnlyConfigAllowed.selector);
        exchangeRateProvider.setRate(id, 1e18);
        vm.stopPrank();
    }

    function test_SetRateShouldWorkCorrectly() public {
        // rate is initially 0 for all pairs
        assertEq(exchangeRateProvider.rate(id), 0);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit();
        emit RateUpdated(id, 1e18);
        exchangeRateProvider.setRate(id, 1e18);
        assertEq(exchangeRateProvider.rate(id), 1e18);
        vm.stopPrank();
    }
    //-----------------------------------------------------------------------------------------------------//
}
