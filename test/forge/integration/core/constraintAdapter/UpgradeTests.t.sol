// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UpgradeTests is BaseTest {
    // ================================ Upgrade Authorization Tests ================================ //

    function test_upgradeToAndCall_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        ConstraintRateAdapter newImplementation = new ConstraintRateAdapter();

        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", alice, bytes32(0x00))
        );
        constraintRateAdapter.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeToAndCall_ShouldWork_WhenCalledByOwner() external __as(bravo) {
        ConstraintRateAdapter newImplementation = new ConstraintRateAdapter();

        // This should succeed without reverting
        constraintRateAdapter.upgradeToAndCall(address(newImplementation), "");
    }
}
