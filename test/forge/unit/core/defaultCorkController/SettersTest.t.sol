// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";
import {DummyWETH} from "test/forge/mocks/DummyWETH.sol";
import {MockSharesFactory} from "test/forge/mocks/MockSharesFactory.sol";

contract SettersTest is BaseTest {
    //------------------------------------- Tests for setTreasury ----------------------------------------//
    function test_SetTreasuryRevertWhenCalledByNonManager() public __as(alice) {
        address mockTreasury = address(5);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.CONFIGURATOR_ROLE()
            )
        );
        defaultCorkController.setTreasury(mockTreasury);
    }

    function test_SetTreasuryRevertWhenPassedZeroAddress() public __as(bravo) {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        defaultCorkController.setTreasury(address(0));
    }

    function test_SetTreasuryShouldWorkCorrectly() public __as(bravo) {
        address mockTreasury = address(5);

        vm.expectEmitAnonymous(false, false, false, false, true);
        emit IDefaultCorkController.TreasurySet(mockTreasury);
        defaultCorkController.setTreasury(mockTreasury);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setSharesFactory ----------------------------------------//
    function test_SetSharesFactory_ShouldRevertWhenCalledByNonManager() public __as(alice) {
        address mockSharesFactory = address(5);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.CONFIGURATOR_ROLE()
            )
        );
        defaultCorkController.setSharesFactory(mockSharesFactory);
    }

    function test_SetSharesFactory_ShouldRevertWhenPassedZeroAddress() public __as(bravo) {
        vm.expectRevert(IErrors.InvalidAddress.selector);
        defaultCorkController.setSharesFactory(address(0));
    }

    function test_SetSharesFactory_ShouldWorkCorrectly() public __as(bravo) {
        address mockSharesFactory = address(new MockSharesFactory());

        vm.expectEmitAnonymous(false, false, false, false, true);
        emit IPoolManager.SharesFactorySet(mockSharesFactory);
        defaultCorkController.setSharesFactory(mockSharesFactory);

        // Create a new pool should use the new shares factory
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
        uint256 unwindSwapFee = 1.5 ether;
        uint256 swapFee = 2 ether;

        vm.expectRevert(MockSharesFactory.MockSharesFactoryIsCalled.selector);
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(market, unwindSwapFee, swapFee, false)
        );
    }
    //-----------------------------------------------------------------------------------------------------//
}
