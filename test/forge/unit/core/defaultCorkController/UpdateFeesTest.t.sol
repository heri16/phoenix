// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {BaseTest} from "test/forge/BaseTest.sol";

contract UpdateFeesTest is BaseTest {
    //------------------------------------- Tests for updateUnwindSwapFeePercentage ----------------------------------------//
    function test_UpdateUnwindSwapFeePercentageRevertWhenCalledByNonManager() public __as(alice) {
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.CONFIGURATOR_ROLE()
            )
        );
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);
    }

    function test_UpdateUnwindSwapFeePercentageShouldWorkCorrectly() public {
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);

        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), 1.234_567_89 ether);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateSwapFeePercentage ----------------------------------------//
    function test_UpdateSwapFeePercentageRevertWhenCalledByNonManager() public __as(alice) {
        assertEq(corkPoolManager.swapFee(defaultPoolId), DEFAULT_BASE_REDEMPTION_FEE);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", alice, defaultCorkController.CONFIGURATOR_ROLE()
            )
        );
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.swapFee(defaultPoolId), DEFAULT_BASE_REDEMPTION_FEE);
    }

    function test_UpdateSwapFeePercentageShouldWorkCorrectly() public {
        assertEq(corkPoolManager.swapFee(defaultPoolId), DEFAULT_BASE_REDEMPTION_FEE);

        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.swapFee(defaultPoolId), 1.234_567_89 ether);
    }

    function test_UpdateSwapFeePercentage_ShouldRevert_WhenFeeExceedsMaximum() public {
        // MAX_ALLOWED_FEES = 5 ether, so 6 ether should revert
        vm.expectRevert("InvalidFees()");
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 6 ether);
    }

    function test_UpdateUnwindSwapFeePercentage_ShouldRevert_WhenFeeExceedsMaximum() public {
        // MAX_ALLOWED_FEES = 5 ether, so 6 ether should revert
        vm.expectRevert("InvalidFees()");
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 6 ether);
    }

    //-----------------------------------------------------------------------------------------------------//
}
