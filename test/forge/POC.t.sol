pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";

import {Market, MarketId} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract POCTest is Helper {
    ERC20Mock internal collateralAsset;
    ERC20Mock internal referenceAsset;
    MarketId public currencyId;

    uint256 public DEFAULT_DEPOSIT_AMOUNT = 10_000 ether;
    uint256 redemptionFeePercentage = 5 ether;

    address public lv;
    address user2 = address(30);
    address swapToken;
    uint256 _expiry = 1 days;

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);

        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, currencyId) = createMarket(_expiry, redemptionFeePercentage);
        vm.deal(DEFAULT_ADDRESS, type(uint256).max);

        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        // 10000 for pool 10000 for LV
        collateralAsset.approve(address(corkPool), type(uint256).max);

        corkPool.deposit(currencyId, DEFAULT_DEPOSIT_AMOUNT, DEFAULT_ADDRESS);

        // save initial data
        (, swapToken) = corkPool.shares(currencyId);
        PoolShare(swapToken).approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);
    }

    function test_POC() external {}
}
