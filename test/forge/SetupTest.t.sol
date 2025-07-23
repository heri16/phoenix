pragma solidity ^0.8.30;

import {Helper} from "./Helper.sol";

contract SetupTest is Helper {
    function test_setupCorkPool() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        vm.stopPrank();
    }
}
