// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculatePercentageFeeTest is Test {
    // =============== calculatePercentageFee Tests ===============

    function test_calculatePercentageFee_BasicCalculation() public pure {
        uint256 fee1e18 = 5 ether; // 5%
        uint256 amount = 1000 ether;
        uint256 expected = 50 ether; // 5% of 1000

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_ZeroFee() public pure {
        uint256 fee1e18 = 0;
        uint256 amount = 1000 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_ZeroAmount() public pure {
        uint256 fee1e18 = 5 ether;
        uint256 amount = 0;
        uint256 expected = 0;

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_OnePercentFee() public pure {
        uint256 fee1e18 = 1 ether; // 1%
        uint256 amount = 1000 ether;
        uint256 expected = 10 ether;

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_HundredPercentFee() public pure {
        uint256 fee1e18 = 100 ether; // 100%
        uint256 amount = 1000 ether;
        uint256 expected = 1000 ether;

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_SmallAmount() public pure {
        uint256 fee1e18 = 1 ether; // 1%
        uint256 amount = 100 wei; // 100 wei
        uint256 expected = 1 wei; // 1% of 100 wei = 1 wei

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }

    function test_calculatePercentageFee_RoundinCeil() public pure {
        uint256 fee1e18 = 1 ether; // 1%
        uint256 amount = 99 wei; // 99 wei
        uint256 expected = 1 wei; // 1% of 99 wei = 0.99 wei, rounded up to 1 wei as we are using ceil rounding

        uint256 result = MathHelper.calculatePercentageFee(fee1e18, amount);
        assertEq(result, expected);
    }
}
