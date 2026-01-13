// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract ComputeTTest is Test {
    // =============== computeT Tests ===============

    function test_computeT_StartOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // At start
        uint256 expected = 1 ether - 0.001 ether; // Should be 1.0 - 0.001

        uint256 result = MathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_MiddleOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1500; // Halfway
        uint256 expected = 0.5 ether; // Should be 0.5

        uint256 result = MathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_EndOfPeriod() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2000; // At end
        uint256 expected = 0; // Should be 0.0

        uint256 result = MathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_PastMaturity() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 2500; // Past end
        uint256 expected = 0; // Should be 0.0

        uint256 result = MathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }

    function test_computeT_AlmostAtStart() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1001; // Just after start

        uint256 result = MathHelper.computeT(start, end, current);
        assertTrue(result < 1 ether && result > 0.99 ether);
    }

    function test_computeT_AlmostAtEnd() public pure {
        uint256 start = 1000;
        uint256 end = 2000;
        uint256 current = 1999; // Just before end

        uint256 result = MathHelper.computeT(start, end, current);
        assertTrue(result > 0 && result < 0.01 ether);
    }

    function test_computeT_SamePeriod() public pure {
        uint256 start = 1000;
        uint256 end = 1000; // Same start and end
        uint256 current = 1000;
        uint256 expected = 0; // Should be 0 for zero duration

        uint256 result = MathHelper.computeT(start, end, current);
        assertEq(result, expected);
    }
}
