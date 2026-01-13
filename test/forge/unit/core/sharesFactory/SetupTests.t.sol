pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Test} from "forge-std/Test.sol";
import {DummyWETH} from "test/forge/mocks/DummyWETH.sol";

contract SetUpTests is Test {
    SharesFactory sharesFactory;
    address corkPoolManager = address(1);
    address ensOwner = makeAddr("ensOwner");

    // ------------------------------- Constructor ----------------------------------- //
    function test_Constructor_ShouldRevert_WhenInvalidParams() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SharesFactory(address(0), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SharesFactory(address(corkPoolManager), address(0));

        vm.expectRevert(abi.encodeWithSelector(IErrors.ZeroAddress.selector));
        new SharesFactory(address(0), ensOwner);
    }

    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- onlyCorkPoolManager ----------------------------------- //
    function test_onlyCorkPoolManager_ShouldRevert_WhenCalledByNonCorkPoolManager() external {
        sharesFactory = new SharesFactory(corkPoolManager, ensOwner);

        DummyWETH collateralAsset = new DummyWETH();
        DummyWETH referenceAsset = new DummyWETH();
        Market memory marketObject = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: 0,
            rateMax: 0,
            rateChangePerDayMax: 0,
            rateChangeCapacityMax: 0,
            rateOracle: address(1)
        });
        MarketId poolId = MarketId.wrap(keccak256(abi.encode(marketObject)));

        vm.startPrank(makeAddr("user1"));
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotCorkPoolManager.selector));
        sharesFactory.deployPoolShares(ISharesFactory.DeployParams({poolParams: marketObject, poolId: poolId}));
    }

    //-----------------------------------------------------------------------------------------------------//
}
