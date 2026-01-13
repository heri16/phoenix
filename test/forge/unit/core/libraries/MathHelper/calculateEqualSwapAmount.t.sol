// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateEqualSwapAmountTest is Test {
    // =============== calculateEqualSwapAmount Tests ===============

    function test_calculateEqualSwapAmount_BasicCalculation() public pure {
        uint256 referenceAsset = 100 ether;
        uint256 swapRate = 1.5 ether;
        uint256 expected = 150 ether; // 100 * 1.5

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_ZeroReferenceAsset() public pure {
        uint256 referenceAsset = 0;
        uint256 swapRate = 1.5 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_ZeroSwapRate() public pure {
        uint256 referenceAsset = 100 ether;
        uint256 swapRate = 0;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_SmallValues() public pure {
        uint256 referenceAsset = 1; // 1 wei
        uint256 swapRate = 1 ether;
        uint256 expected = 1;

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_LargeValues() public pure {
        uint256 referenceAsset = type(uint128).max;
        uint256 swapRate = 2 ether;

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, referenceAsset * 2);
    }

    function test_calculateEqualSwapAmount_FractionalSwapRate() public pure {
        uint256 referenceAsset = 100 ether;
        uint256 swapRate = 0.543_21 ether;
        uint256 expected = 54.321 ether;

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }

    function test_calculateEqualSwapAmount_RoundingFloor() public pure {
        uint256 referenceAsset = 1 wei;
        uint256 swapRate = 5.000_000_000_000_000_01 ether;
        // 1 wei * 5.00000000000000001 ether = 5.00000000000000001 wei, rounded down to 5 wei as we are using floor rounding
        uint256 expected = 5 wei;

        uint256 result = MathHelper.calculateEqualSwapAmount(referenceAsset, swapRate);
        assertEq(result, expected);
    }
}
