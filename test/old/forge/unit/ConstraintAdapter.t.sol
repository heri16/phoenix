// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Helper} from "test/old/forge/Helper.sol";

contract ConstraintRateAdapterTest is Helper {
    address private adminUserAddress;
    address private user;

    function setUp() public {
        adminUserAddress = address(1);
        user = address(2);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        vm.stopPrank();
    }

    //---------------------------------- Tests for ConstraintRateAdapter constructor ---------------------------------//

    function test_ConstraintRateAdapterConstructorRevertWhenPassedZeroAddress() public {
        address _constraintRateAdapter = address(new ConstraintRateAdapter());

        ERC1967Proxy constraintRateAdapterProxy = new ERC1967Proxy(_constraintRateAdapter, "");
        ConstraintRateAdapter constraintRateAdapter = ConstraintRateAdapter(address(constraintRateAdapterProxy));

        vm.expectRevert(IErrors.InvalidAddress.selector);
        constraintRateAdapter.initialize(address(0), address(0));

        vm.expectRevert(IErrors.InvalidAddress.selector);
        constraintRateAdapter.initialize(adminUserAddress, address(0));

        vm.expectRevert(IErrors.InvalidAddress.selector);
        constraintRateAdapter.initialize(address(0), address(corkPoolManager));
    }

    function test_ConstraintRateAdapterConstructorShouldWorkCorrectly() public {
        // Check that the owner is set correctly
        assertEq(constraintRateAdapter.owner(), DEFAULT_ADDRESS);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------- Negative Tests for ConstraintRateAdapter functions -----------------------//

    function test_bootstrap_shouldRevert_whenCalledByNonPoolAddress() external {
        vm.startPrank(user);
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.bootstrap(defaultCurrencyId);
        vm.stopPrank();
    }

    function test_adjustedRate_shouldRevert_whenCalledByNonPoolAddress() external {
        vm.startPrank(user);
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.adjustedRate(defaultCurrencyId);
        vm.stopPrank();
    }

    function test_previewAdjustedRate_shouldRevert_whenCalledByNonPoolAddress() external {
        vm.startPrank(user);
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.previewAdjustedRate(defaultCurrencyId);
        vm.stopPrank();
    }

    //-----------------------------------------------------------------------------------------------------//
}
