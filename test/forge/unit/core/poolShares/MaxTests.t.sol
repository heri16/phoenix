pragma solidity ^0.8.30;

import {BaseTest} from "test/forge/BaseTest.sol";

contract MaxTests is BaseTest {
    //----------------------------------------- max functions -----------------------------------------//
    function test_maxMint_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxMint(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxMint(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxMint should match PoolManager maxMint");
    }

    function test_maxDeposit_ShouldReturnSameValueAsPoolManager() external {
        uint256 poolManagerResult = corkPoolManager.maxDeposit(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxDeposit(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxDeposit should match PoolManager maxDeposit");
    }

    function test_maxUnwindDeposit_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxUnwindDeposit(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxUnwindDeposit(alice);

        assertEq(
            poolShareResult, poolManagerResult, "PoolShare maxUnwindDeposit should match PoolManager maxUnwindDeposit"
        );
    }

    function test_maxUnwindMint_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxUnwindMint(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxUnwindMint(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindMint should match PoolManager maxUnwindMint");
    }

    function test_maxWithdraw_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxWithdraw(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxWithdraw(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxWithdraw should match PoolManager maxWithdraw");
    }

    function test_maxExercise_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxExercise(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxExercise(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxExercise should match PoolManager maxExercise");
    }

    function test_maxRedeem_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxRedeem(defaultPoolId, alice);
        uint256 poolShareResult = principalToken.maxRedeem(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxRedeem should match PoolManager maxRedeem");
    }

    function test_maxSwap_ShouldReturnSameValueAsPoolManager() external __deposit(1 ether, alice) {
        uint256 poolManagerResult = corkPoolManager.maxSwap(defaultPoolId, alice);
        uint256 poolShareResult = swapToken.maxSwap(alice);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxSwap should match PoolManager maxSwap");
    }

    function test_maxUnwindExercise_ShouldReturnSameValueAsPoolManager()
        external
        __depositAndSwap(10 ether, 0.1 ether, bravo)
    {
        uint256 poolManagerResult = corkPoolManager.maxUnwindExercise(defaultPoolId, bravo);
        uint256 poolShareResult = swapToken.maxUnwindExercise(bravo);

        assertEq(
            poolShareResult, poolManagerResult, "PoolShare maxUnwindExercise should match PoolManager maxUnwindExercise"
        );
    }

    function test_maxUnwindExerciseOther_ShouldReturnSameValueAsPoolManager()
        external
        __depositAndSwap(10 ether, 0.1 ether, bravo)
    {
        uint256 poolManagerResult = corkPoolManager.maxUnwindExerciseOther(defaultPoolId, bravo);
        uint256 poolShareResult = swapToken.maxUnwindExerciseOther(bravo);

        assertEq(
            poolShareResult,
            poolManagerResult,
            "PoolShare maxUnwindExerciseOther should match PoolManager maxUnwindExerciseOther"
        );
    }

    function test_maxUnwindSwap_ShouldReturnSameValueAsPoolManager()
        external
        __depositAndSwap(10 ether, 0.1 ether, bravo)
    {
        uint256 poolManagerResult = corkPoolManager.maxUnwindSwap(defaultPoolId, bravo);
        uint256 poolShareResult = swapToken.maxUnwindSwap(bravo);

        assertEq(poolShareResult, poolManagerResult, "PoolShare maxUnwindSwap should match PoolManager maxUnwindSwap");
    }
}
