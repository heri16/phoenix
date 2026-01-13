// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract InitializeTests is BaseTest {
    function test_InitializeCorkPoolManagerStorage_ShouldRevertIfInvalidParams() public {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolManager.exposeInitializeCorkPoolManagerStorage(
            address(0), CORK_PROTOCOL_TREASURY, address(whitelistManager)
        );
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolManager.exposeInitializeCorkPoolManagerStorage(
            address(constraintRateAdapter), address(0), address(whitelistManager)
        );
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolManager.exposeInitializeCorkPoolManagerStorage(
            address(constraintRateAdapter), CORK_PROTOCOL_TREASURY, address(0)
        );
    }
}
