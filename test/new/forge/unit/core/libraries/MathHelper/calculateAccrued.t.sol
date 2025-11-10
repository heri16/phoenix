// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateAccruedTest is Test {
    // =============== calculateAccrued Tests ===============

    function test_calculateAccrued_BasicCalculation() public pure {
        uint256 amount = 100 ether;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 50 ether; // 100 * (500/1000)

        uint256 result = MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_ZeroAmount() public pure {
        uint256 amount = 0;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_ZeroAvailable() public pure {
        uint256 amount = 100 ether;
        uint256 available = 0;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_ZeroTotalPrincipalTokenIssued() public pure {
        uint256 amount = 100 ether;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 0;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_EqualAvailableAndIssued() public pure {
        uint256 amount = 100 ether;
        uint256 available = 1000 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 100 ether;

        uint256 result = MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateAccrued_RoundingDown() public pure {
        uint256 amount = 3 wei;
        uint256 available = 3 wei;
        uint256 totalPrincipalTokenIssued = 2 wei;

        // (3 wei * 3 wei) / 2 wei = 4.5 wei, rounded down to 4 wei as we are using floor rounding
        uint256 expected = 4 wei;

        uint256 result = MathHelper.calculateAccrued(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }
}
