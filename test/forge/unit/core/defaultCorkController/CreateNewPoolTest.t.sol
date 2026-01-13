// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";
import {DummyWETH} from "test/forge/mocks/DummyWETH.sol";

contract CreateNewPoolTest is BaseTest {
    //------------------------------------- Tests for createNewPool ----------------------------------------//
    function test_CreateNewPool_ShouldRevert_WhenCalledByNonPoolDeployer() public __as(alice) {
        Market memory market = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: 0,
            rateOracle: address(0),
            rateMin: 0,
            rateMax: 0,
            rateChangePerDayMax: 0,
            rateChangeCapacityMax: 0
        });

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.POOL_CREATOR_ROLE()
            )
        );
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, 0, 0, false));
    }

    function test_CreateNewPool_ShouldRevert_WhenAdminIsPaused() external __as(pauser) {
        defaultCorkController.pause();
        assertTrue(defaultCorkController.paused());

        Market memory market = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: 0,
            rateOracle: address(0),
            rateMin: 0,
            rateMax: 0,
            rateChangePerDayMax: 0,
            rateChangeCapacityMax: 0
        });

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, 0, 0, false));
    }

    function test_CreateNewPool_ShouldRevert_WhenRateMinIsZero() public {
        Market memory market = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 1,
            rateOracle: address(testOracle),
            rateMin: 0,
            rateMax: 0,
            rateChangePerDayMax: 0,
            rateChangeCapacityMax: 0
        });

        vm.expectRevert(IErrors.InvalidParams.selector);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, 0, 0, false));
    }

    function test_CreateNewPool_ShouldWorkCorrectly() public {
        DummyWETH collateral = new DummyWETH();
        DummyWETH references = new DummyWETH();

        uint256 expiry = block.timestamp + 1;

        Market memory market = Market({
            collateralAsset: address(collateral),
            referenceAsset: address(references),
            expiryTimestamp: expiry,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        MarketId id = MarketId.wrap(keccak256(abi.encode(market)));

        uint256 unwindSwapFee = 1.5 ether;
        uint256 swapFee = 2 ether;

        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(market, unwindSwapFee, swapFee, false)
        );

        market = corkPoolManager.market(id);

        assertEq(market.collateralAsset, address(collateral));
        assertEq(market.referenceAsset, address(references));
        assertEq(market.expiryTimestamp, expiry);
        assertEq(market.rateMin, DEFAULT_RATE_MIN);
        assertEq(market.rateMax, DEFAULT_RATE_MAX);
        assertEq(market.rateChangePerDayMax, DEFAULT_RATE_CHANGE_PER_DAY_MAX);
        assertEq(market.rateChangeCapacityMax, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
        assertEq(market.rateOracle, address(testOracle));
        assertEq(corkPoolManager.unwindSwapFee(id), unwindSwapFee);
        assertEq(corkPoolManager.swapFee(id), swapFee);
    }

    //-----------------------------------------------------------------------------------------------------//
}
