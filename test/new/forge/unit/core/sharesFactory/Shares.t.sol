pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPoolShare, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";
import {ERC20Mock} from "test/new/forge/mocks/ERC20Mock.sol";

contract SharesTest is BaseTest {
    uint256 public constant depositAmount = 1 ether;
    uint256 public constant swapAmount = 0.123 ether;

    event Deposit(address indexed charlie, address indexed bob, uint256 assets, uint256 shares);
    event Withdraw(address indexed charlie, address indexed eve, address indexed bob, uint256 assets, uint256 shares);

    function setUp() public override {
        super.setUp();

        _createPool(block.timestamp + 1 days, 18, 18, false);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldWorkCorrectly() external {
        // deppsit to get some data
        _deposit(defaultPoolId, depositAmount, alice);

        // expiry
        assertEq(swapToken.expiry(), block.timestamp + 1 days);
        assertEq(swapToken.issuedAt(), block.timestamp);
        assertEq(swapToken.isExpired(), false);

        // PoolShare
        assertEq(swapToken.pairName(), "DWETH-DWETH1CST");
        assertEq(address(swapToken.poolManager()), address(corkPoolManager));
        assertEq(swapToken.factory(), address(sharesFactory));
        assertEq(address(swapToken.poolManager()), address(corkPoolManager));

        // ERC20
        assertEq(swapToken.totalSupply(), depositAmount);
        assertEq(swapToken.balanceOf(alice), depositAmount);
        assertEq(swapToken.allowance(alice, address(corkPoolManager)), 0);
        assertEq(swapToken.decimals(), 18);
        assertEq(swapToken.symbol(), "DWETH1CST");
        assertEq(swapToken.name(), "DWETH-DWETH1CST");
    }

    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- IsExpired ----------------------------------//
    function test_IsExpiredShouldReturnCorrectValue() external {
        assertFalse(swapToken.isExpired());

        vm.warp(block.timestamp + 10 days);
        assertTrue(swapToken.isExpired());
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------------------- Mint -------------------------------------------------//
    function test_MintShouldRevertWhenCalledByNonOwner() external {
        overridePrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        swapToken.mint(alice, 1 ether);
    }

    function test_MintShouldWorkCorrectly() external {
        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 0);

        overridePrank(address(corkPoolManager));
        swapToken.mint(DEFAULT_ADDRESS, 1.234 ether);

        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 1.234 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

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

    //----------------------------------------- TransferFrom -----------------------------------------//
    function test_TransferFromShouldRevertWhenCalledByNonOwner() external {
        overridePrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        swapToken.transferFrom(DEFAULT_ADDRESS, alice, address(this), 1 ether);
    }

    function test_TransferFromShouldWorkCorrectlyWhencharlieIsOwner() external {
        // Setup: mint some tokens to alice
        overridePrank(address(corkPoolManager));
        swapToken.mint(alice, 10 ether);

        assertEq(swapToken.balanceOf(alice), 10 ether);
        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 0);

        // Transfer from alice to DEFAULT_ADDRESS
        overridePrank(address(corkPoolManager));
        swapToken.transferFrom(alice, alice, DEFAULT_ADDRESS, 5 ether);

        assertEq(swapToken.balanceOf(alice), 5 ether);
        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 5 ether);
    }

    function test_TransferFromShouldSpendAllowanceWhencharlieNotOwner() external {
        // Setup: mint tokens and approve eve
        overridePrank(address(corkPoolManager));
        swapToken.mint(alice, 10 ether);

        overridePrank(alice);
        swapToken.approve(eve, 5 ether);

        assertEq(swapToken.allowance(alice, eve), 5 ether);

        overridePrank(address(corkPoolManager));
        // Transfer using eve address
        swapToken.transferFrom(eve, alice, DEFAULT_ADDRESS, 3 ether);

        assertEq(swapToken.allowance(alice, eve), 2 ether);
        assertEq(swapToken.balanceOf(alice), 7 ether);
        assertEq(swapToken.balanceOf(DEFAULT_ADDRESS), 3 ether);
    }

    function test_TransferFromShouldRevertWhenInsufficientAllowance() external {
        // Setup: mint tokens and approve eve
        overridePrank(address(corkPoolManager));
        swapToken.mint(alice, 10 ether);
        swapToken.approve(eve, 2 ether);

        // Try to transfer more than allowance
        overridePrank(alice);
        vm.expectRevert();
        swapToken.transferFrom(eve, alice, DEFAULT_ADDRESS, 3 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitDeposit -----------------------------------------//
    function test_EmitDepositShouldRevertWhenCalledByNonOwner() external {
        overridePrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        swapToken.emitDeposit(DEFAULT_ADDRESS, alice, 1 ether, 0.5 ether);
    }

    function test_EmitDepositShouldWorkCorrectlyAndEmitEvent() external {
        uint256 assets = 1.5 ether;
        uint256 shares = 0.75 ether;

        // Expect the Deposit event to be emitted with correct parameters
        vm.expectEmit(true, true, false, true);
        emit Deposit(charlie, eve, assets, shares);

        overridePrank(address(corkPoolManager));
        swapToken.emitDeposit(charlie, eve, assets, shares);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitWithdraw -----------------------------------------//
    function test_EmitWithdrawShouldRevertWhenCalledByNonOwner() external {
        overridePrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        swapToken.emitWithdraw(DEFAULT_ADDRESS, alice, DEFAULT_ADDRESS, 1 ether, 0.5 ether);
    }

    function test_EmitWithdrawShouldWorkCorrectlyAndEmitEvent() external {
        uint256 assets = 2 ether;
        uint256 shares = 1 ether;

        // Expect the Withdraw event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit Withdraw(charlie, eve, bob, assets, shares);

        overridePrank(address(corkPoolManager));
        swapToken.emitWithdraw(charlie, eve, bob, assets, shares);
    }

    function test_EmitWithdrawShouldEmitEventWithDifferentOwnerAndReceiver() external {
        uint256 assets = 1.25 ether;
        uint256 shares = 0.625 ether;

        // Expect the Withdraw event to be emitted with different bob and eve
        vm.expectEmit(true, true, true, true);
        emit Withdraw(charlie, eve, bob, assets, shares);

        overridePrank(address(corkPoolManager));
        swapToken.emitWithdraw(charlie, eve, bob, assets, shares);
    }
    // ----------------------------------------------------------------------------------------------------//
}
