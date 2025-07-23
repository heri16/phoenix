pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Helper} from "test/forge/Helper.sol";

contract TokenName is Helper {
    function setUp() external {
        vm.startPrank(DEFAULT_ADDRESS);
        // saturday, June 3, 2000 1:07:47 PM
        // 06/03/2000 @ 1:07:47pm
        vm.warp(960_037_567);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        createMarket(block.timestamp + 100);
    }

    function test_tokenNames() external {
        (address principalToken, address swapToken) = corkPool.shares(defaultCurrencyId);

        IERC20Metadata _principalToken = IERC20Metadata(principalToken);
        IERC20Metadata _swapToken = IERC20Metadata(swapToken);

        vm.assertEq(_principalToken.symbol(), "DWETH6CPT");
        vm.assertEq(_swapToken.symbol(), "DWETH6CST");

        createMarket(block.timestamp + 1000);
    }
}
