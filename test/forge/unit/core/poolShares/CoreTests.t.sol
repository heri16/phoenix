pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract CoreTests is BaseTest {
    //------------------------------------------------- Mint -------------------------------------------------//
    function test_MintShouldRevertWhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.mint(alice, 1 ether);
    }

    function test_MintShouldWorkCorrectly() external __as(address(corkPoolManager)) {
        assertEq(swapToken.balanceOf(bravo), 0);

        swapToken.mint(bravo, 1.234 ether);

        assertEq(swapToken.balanceOf(bravo), 1.234 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- TransferFrom -----------------------------------------//
    function test_TransferFrom_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.transferFrom(bravo, alice, address(this), 1 ether);
    }

    function test_TransferFrom_ShouldWorkCorrectly_WhencharlieIsOwner() external __as(address(corkPoolManager)) {
        // Setup: mint some tokens to alice
        swapToken.mint(alice, 10 ether);

        assertEq(swapToken.balanceOf(alice), 10 ether);
        assertEq(swapToken.balanceOf(bravo), 0);

        // Transfer from alice to bravo
        swapToken.transferFrom(alice, alice, bravo, 5 ether);

        assertEq(swapToken.balanceOf(alice), 5 ether);
        assertEq(swapToken.balanceOf(bravo), 5 ether);
    }

    function test_TransferFrom_ShouldSpendAllowance_WhencharlieNotOwner() external __as(address(corkPoolManager)) {
        // Setup: mint tokens and approve eve
        swapToken.mint(alice, 10 ether);

        overridePrank(alice);
        swapToken.approve(eve, 5 ether);

        assertEq(swapToken.allowance(alice, eve), 5 ether);

        overridePrank(address(corkPoolManager));
        // Transfer using eve address
        swapToken.transferFrom(eve, alice, bravo, 3 ether);

        assertEq(swapToken.allowance(alice, eve), 2 ether);
        assertEq(swapToken.balanceOf(alice), 7 ether);
        assertEq(swapToken.balanceOf(bravo), 3 ether);
    }

    function test_TransferFrom_ShouldRevert_WhenInsufficientAllowance() external __as(address(corkPoolManager)) {
        // Setup: mint tokens and approve eve
        swapToken.mint(alice, 10 ether);
        swapToken.approve(eve, 2 ether);

        // Try to transfer more than allowance
        overridePrank(alice);
        vm.expectRevert();
        swapToken.transferFrom(eve, alice, bravo, 3 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- Burn -----------------------------------------//
    function test_Burn_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.burn(1 ether);
    }

    function test_Burn_ShouldWorkCorrectly() external __as(address(corkPoolManager)) {
        // Setup: mint some tokens to corkPoolManager
        swapToken.mint(address(corkPoolManager), 10 ether);

        assertEq(swapToken.balanceOf(address(corkPoolManager)), 10 ether);
        assertEq(swapToken.totalSupply(), 10 ether);

        // Burn tokens from corkPoolManager (msg.sender)
        swapToken.burn(4 ether);

        assertEq(swapToken.balanceOf(address(corkPoolManager)), 6 ether);
        assertEq(swapToken.totalSupply(), 6 ether);
    }

    function test_Burn_ShouldRevert_WhenInsufficientBalance() external __as(address(corkPoolManager)) {
        // Setup: mint some tokens to corkPoolManager
        swapToken.mint(address(corkPoolManager), 5 ether);

        // Try to burn more than balance
        vm.expectRevert();
        swapToken.burn(6 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- BurnFrom (2 parameters) -----------------------------------------//
    function test_BurnFrom2Params_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.burnFrom(alice, 1 ether);
    }

    function test_BurnFrom2Params_ShouldWorkCorrectlyAndSpendAllowance() external __as(address(corkPoolManager)) {
        // Setup: mint tokens to alice and approve corkPoolManager
        swapToken.mint(alice, 10 ether);

        overridePrank(alice);
        swapToken.approve(address(corkPoolManager), 5 ether);

        assertEq(swapToken.balanceOf(alice), 10 ether);
        assertEq(swapToken.allowance(alice, address(corkPoolManager)), 5 ether);
        assertEq(swapToken.totalSupply(), 10 ether);

        // Burn tokens from alice using corkPoolManager
        overridePrank(address(corkPoolManager));
        swapToken.burnFrom(alice, 3 ether);

        assertEq(swapToken.balanceOf(alice), 7 ether);
        assertEq(swapToken.allowance(alice, address(corkPoolManager)), 2 ether);
        assertEq(swapToken.totalSupply(), 7 ether);
    }

    function test_BurnFrom2Params_ShouldRevert_WhenInsufficientAllowance() external __as(address(corkPoolManager)) {
        // Setup: mint tokens to alice and approve corkPoolManager
        swapToken.mint(alice, 10 ether);

        overridePrank(alice);
        swapToken.approve(address(corkPoolManager), 2 ether);

        // Try to burn more than allowance
        overridePrank(address(corkPoolManager));
        vm.expectRevert();
        swapToken.burnFrom(alice, 3 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- BurnFrom (3 parameters) -----------------------------------------//
    function test_BurnFrom3Params_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.burnFrom(alice, alice, 1 ether);
    }

    function test_BurnFrom3Params_ShouldWorkCorrectly_WhenSenderIsOwner() external __as(address(corkPoolManager)) {
        // Setup: mint some tokens to alice
        swapToken.mint(alice, 10 ether);

        assertEq(swapToken.balanceOf(alice), 10 ether);
        assertEq(swapToken.totalSupply(), 10 ether);

        // Burn from alice when sender == owner (no allowance needed)
        swapToken.burnFrom(alice, alice, 4 ether);

        assertEq(swapToken.balanceOf(alice), 6 ether);
        assertEq(swapToken.totalSupply(), 6 ether);
    }

    function test_BurnFrom3Params_ShouldSpendAllowance_WhenSenderNotOwner() external __as(address(corkPoolManager)) {
        // Setup: mint tokens to alice and approve eve
        swapToken.mint(alice, 10 ether);

        overridePrank(alice);
        swapToken.approve(eve, 5 ether);

        assertEq(swapToken.balanceOf(alice), 10 ether);
        assertEq(swapToken.allowance(alice, eve), 5 ether);
        assertEq(swapToken.totalSupply(), 10 ether);

        // Burn from alice using eve's allowance
        overridePrank(address(corkPoolManager));
        swapToken.burnFrom(eve, alice, 3 ether);

        assertEq(swapToken.balanceOf(alice), 7 ether);
        assertEq(swapToken.allowance(alice, eve), 2 ether);
        assertEq(swapToken.totalSupply(), 7 ether);
    }

    function test_BurnFrom3Params_ShouldRevert_WhenInsufficientAllowance() external __as(address(corkPoolManager)) {
        // Setup: mint tokens to alice and approve eve
        swapToken.mint(alice, 10 ether);

        overridePrank(alice);
        swapToken.approve(eve, 2 ether);

        // Try to burn more than allowance
        overridePrank(address(corkPoolManager));
        vm.expectRevert();
        swapToken.burnFrom(eve, alice, 3 ether);
    }

    function test_BurnFrom3Params_ShouldRevert_WhenInsufficientBalance() external __as(address(corkPoolManager)) {
        // Setup: mint tokens to alice and approve eve
        swapToken.mint(alice, 5 ether);

        overridePrank(alice);
        swapToken.approve(eve, 10 ether);

        // Try to burn more than balance
        overridePrank(address(corkPoolManager));
        vm.expectRevert();
        swapToken.burnFrom(eve, alice, 6 ether);
    }

    // ----------------------------------------------------------------------------------------------------//
}
