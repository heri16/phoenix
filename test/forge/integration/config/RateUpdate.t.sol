pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Shares} from "contracts/core/assets/Shares.sol";

import {Helper} from "test/forge/Helper.sol";

contract RateUpdateTest is Helper {
    function setUp() external {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        createMarket(100);
    }

    function test_shouldUpdateRateDownCorrectly() external {
        uint256 rate = corkPool.exchangeRate(defaultCurrencyId);

        vm.assertEq(rate, 1 ether);

        corkConfig.updateCorkPoolRate(defaultCurrencyId, 0.9 ether);

        rate = corkPool.exchangeRate(defaultCurrencyId);

        vm.assertEq(rate, 0.9 ether);
    }

    function test_ShouldNotUpdateRateUpCorrectlyOnActive() external {
        uint256 rate = corkPool.exchangeRate(defaultCurrencyId);

        vm.assertEq(rate, 1 ether);

        corkConfig.updateCorkPoolRate(defaultCurrencyId, 1.1 ether);

        rate = corkPool.exchangeRate(defaultCurrencyId);

        vm.assertEq(rate, 1 ether);
    }
}
