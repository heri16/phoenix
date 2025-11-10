// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Test} from "forge-std/Test.sol";

contract CalculateSharesNeededTest is Test {
    // =============== calculateSharesNeeded Tests ===============

    function test_calculateSharesNeeded_BasicCalculation() public pure {
        uint256 amount = 100 ether;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 200 ether; // 100 * (1000/500)

        uint256 result = MathHelper.calculateSharesNeeded(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateSharesNeeded_ZeroAmount() public pure {
        uint256 amount = 0;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateSharesNeeded(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateSharesNeeded_ZeroAvailable() public pure {
        uint256 amount = 100 ether;
        uint256 available = 0;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 0;

        uint256 result = MathHelper.calculateSharesNeeded(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateSharesNeeded_ZeroPrincipalTokenIssued() public pure {
        uint256 amount = 100 ether;
        uint256 available = 500 ether;
        uint256 totalPrincipalTokenIssued = 0;

        // Will return 0 as totalPrincipalTokenIssued is 0
        uint256 expected = 0;

        uint256 result = MathHelper.calculateSharesNeeded(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateSharesNeeded_EqualAvailableAndIssued() public pure {
        uint256 amount = 100 ether;
        uint256 available = 1000 ether;
        uint256 totalPrincipalTokenIssued = 1000 ether;
        uint256 expected = 100 ether;

        uint256 result = MathHelper.calculateSharesNeeded(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }

    function test_calculateSharesNeeded_RoundingUsingCeil() public pure {
        uint256 amount = 7 wei;
        uint256 available = 2 wei;
        uint256 totalPrincipalTokenIssued = 1 wei;

        // (7 wei * 1 wei) / 2 wei = 7/2 = 3.5, rounded up to 4 wei as we are using ceil rounding
        uint256 expected = 4 wei;

        uint256 result = MathHelper.calculateSharesNeeded(amount, available, totalPrincipalTokenIssued);
        assertEq(result, expected);
    }
}
