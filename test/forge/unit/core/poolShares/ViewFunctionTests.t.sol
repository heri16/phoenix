pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract ViewFunctionTests is BaseTest {
    uint256 public constant depositAmount = 1 ether;

    //---------------------------------- IsExpired ----------------------------------//
    function test_IsExpiredShouldReturnCorrectValue() external {
        assertFalse(swapToken.isExpired());

        vm.warp(block.timestamp + 10 days);
        assertTrue(swapToken.isExpired());
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------------------- getReserves -------------------------------------------------//
    function test_getReservesShouldReturnCorrectReserves() external __as(alice) {
        // deppsit to get some data
        _deposit(defaultPoolId, depositAmount, alice);

        // principalToken, should return current reserve
        assertReserve(principalToken, depositAmount, 0);

        // swapToken, should return current reserve
        assertReserve(swapToken, depositAmount, 0);

        // fast forward to expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry);

        assertReserve(principalToken, depositAmount, 0);
        assertReserve(swapToken, depositAmount, 0);

        corkPoolManager.redeem(defaultPoolId, depositAmount, alice, alice);

        assertReserve(principalToken, 0, 0);
        assertReserve(swapToken, 0, 0);
    }

    // some helper to assert reserve
    function assertReserve(PoolShare token, uint256 expectedRa, uint256 expectedPa) internal {
        (uint256 collateralAsset, uint256 referenceAsset) = token.getReserves();

        vm.assertEq(collateralAsset, expectedRa);
        vm.assertEq(referenceAsset, expectedPa);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- swapRate -----------------------------------------//
    function test_swapRate_ShouldReturnCorrectValue() external __as(address(corkPoolManager)) {
        // swapRate should return the same value as the corkPoolManager
        assertEq(swapToken.swapRate(), corkPoolManager.swapRate(defaultPoolId));
    }

    // ----------------------------------------------------------------------------------------------------//
}
