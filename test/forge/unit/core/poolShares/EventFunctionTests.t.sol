pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract EventFunctionTests is BaseTest {
    event Deposit(address indexed charlie, address indexed bob, uint256 assets, uint256 shares);
    event Withdraw(address indexed charlie, address indexed eve, address indexed bob, uint256 assets, uint256 shares);

    //----------------------------------------- EmitDeposit -----------------------------------------//
    function test_EmitDeposit_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.emitDeposit(bravo, alice, 1 ether, 0.5 ether);
    }

    function test_EmitDeposit_ShouldWorkCorrectlyAndEmitEvent() external __as(address(corkPoolManager)) {
        uint256 assets = 1.5 ether;
        uint256 shares = 0.75 ether;

        // Expect the Deposit event to be emitted with correct parameters
        vm.expectEmit(true, true, false, true);
        emit Deposit(charlie, eve, assets, shares);

        swapToken.emitDeposit(charlie, eve, assets, shares);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitWithdraw -----------------------------------------//
    function test_EmitWithdraw_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.emitWithdraw(bravo, alice, bravo, 1 ether, 0.5 ether);
    }

    function test_EmitWithdraw_ShouldWorkCorrectlyAndEmitEvent() external __as(address(corkPoolManager)) {
        uint256 assets = 2 ether;
        uint256 shares = 1 ether;

        // Expect the Withdraw event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit Withdraw(charlie, eve, bob, assets, shares);

        swapToken.emitWithdraw(charlie, eve, bob, assets, shares);
    }

    function test_EmitWithdraw_ShouldEmitEventWithDifferentOwnerAndReceiver() external __as(address(corkPoolManager)) {
        uint256 assets = 1.25 ether;
        uint256 shares = 0.625 ether;

        // Expect the Withdraw event to be emitted with different bob and eve
        vm.expectEmit(true, true, true, true);
        emit Withdraw(charlie, eve, bob, assets, shares);

        swapToken.emitWithdraw(charlie, eve, bob, assets, shares);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitWithdrawOther -----------------------------------------//
    function test_EmitWithdrawOther_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.emitWithdrawOther(bravo, alice, bob, address(referenceAsset), 1 ether, 0.5 ether);
    }

    function test_EmitWithdrawOther_ShouldWorkCorrectlyAndEmitEvent() external __as(address(corkPoolManager)) {
        uint256 assets = 2.5 ether;
        uint256 shares = 1.25 ether;
        address asset = address(referenceAsset);

        // Expect the WithdrawOther event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IPoolShare.WithdrawOther(charlie, eve, bob, asset, assets, shares);

        swapToken.emitWithdrawOther(charlie, eve, bob, asset, assets, shares);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitDepositOther -----------------------------------------//
    function test_EmitDepositOther_ShouldRevert_WhenCalledByNonOwner() external __as(alice) {
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.emitDepositOther(bravo, alice, address(referenceAsset), 1 ether, 0.5 ether);
    }

    function test_EmitDepositOther_ShouldWorkCorrectlyAndEmitEvent() external __as(address(corkPoolManager)) {
        uint256 assets = 1.8 ether;
        uint256 shares = 0.9 ether;
        address asset = address(referenceAsset);

        // Expect the DepositOther event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IPoolShare.DepositOther(charlie, eve, asset, assets, shares);

        swapToken.emitDepositOther(charlie, eve, asset, assets, shares);
    }

    // ----------------------------------------------------------------------------------------------------//
}
