// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.30;

// import {RateOracle} from "contracts/core/RateOracle.sol";
// import {IErrors} from "contracts/interfaces/IErrors.sol";
// import {MarketId} from "contracts/libraries/Market.sol";
// import {Helper} from "test/forge/Helper.sol";
// import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

// contract ChainlinkAggregatorMockTest is Helper {
// RateOracle private rateOracle;

// ERC20Mock collateralAsset;
// ERC20Mock referenceAsset;
// MarketId id;
// address user1;

// // events
// event RateUpdated(MarketId indexed id, uint256 newRate);

// function setUp() public {
//     user1 = makeAddr("user1");

//     rateOracle = new RateOracle(DEFAULT_ADDRESS);

//     vm.startPrank(DEFAULT_ADDRESS);
//     deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
//     (collateralAsset, referenceAsset, id) = createNewMarketPair(block.timestamp + 1 days);
//     vm.stopPrank();
// }

// //------------------------------------- Tests for constructor ----------------------------------------//
// function test_ConstructorShouldRevertWhenCalledWithZeroAddress() public {
//     vm.expectRevert(IErrors.ZeroAddress.selector);
//     new RateOracle(address(0));
// }

// function test_ConstructorShouldWorkCorrectly() public {
//     assertEq(rateOracle.CONFIG(), DEFAULT_ADDRESS);

//     // check config contract is set correctly then only config contract can call setRate
//     vm.startPrank(DEFAULT_ADDRESS);
//     rateOracle.setRate(id, 1e18);
//     assertEq(rateOracle.rate(id), 1e18);
//     vm.stopPrank();
// }
// //-----------------------------------------------------------------------------------------------------//

// //------------------------------------- Tests for rate() ----------------------------------------//
// function test_RateShouldReturnZero() public {
//     // check rate is 0 for all pairs
//     assertEq(rateOracle.rate(), 0);
// }
// //-----------------------------------------------------------------------------------------------------//

// //------------------------------------- Tests for rate(MarketId) ----------------------------------------//
// function test_RateShouldReturnZeroForAllPairs() public {
//     // check rate is initially 0 for all pairs
//     assertEq(rateOracle.rate(id), 0);

//     // set rate for the pair
//     vm.startPrank(DEFAULT_ADDRESS);
//     rateOracle.setRate(id, 1e18);
//     assertEq(rateOracle.rate(id), 1e18);
//     vm.stopPrank();
// }
// //-----------------------------------------------------------------------------------------------------//

// //------------------------------------- Tests for setRate(MarketId, uint256) ----------------------------------------//
// function test_SetRateShouldRevertWhenCalledByNonConfig() public {
//     vm.startPrank(user1);
//     vm.expectRevert(IErrors.OnlyConfigAllowed.selector);
//     rateOracle.setRate(id, 1e18);
//     vm.stopPrank();
// }

// function test_SetRateShouldWorkCorrectly() public {
//     // rate is initially 0 for all pairs
//     assertEq(rateOracle.rate(id), 0);

//     vm.startPrank(DEFAULT_ADDRESS);
//     vm.expectEmit();
//     emit RateUpdated(id, 1e18);
//     rateOracle.setRate(id, 1e18);
//     assertEq(rateOracle.rate(id), 1e18);
//     vm.stopPrank();
// }
// //-----------------------------------------------------------------------------------------------------//
// }
