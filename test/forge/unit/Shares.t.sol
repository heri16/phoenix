pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPoolShare, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract SharesTest is Helper {
    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare principalToken;
    PoolShare swapToken;
    PoolShare share;

    MarketId poolId;
    IPoolShare.ConstructorParams constructorParams;

    address user1;

    uint256 public constant depositAmount = 1 ether;
    uint256 public constant swapAmount = 0.123 ether;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function setUp() external {
        user1 = makeAddr("user1");

        vm.startPrank(DEFAULT_ADDRESS);

        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        constructorParams.poolId = MarketId.wrap(bytes32(""));
        constructorParams.expiry = block.timestamp + 1 days;
        constructorParams.pairName = "Swap Token";
        constructorParams.symbol = "SWT";
        constructorParams.poolManager = address(1);

        (collateralAsset, referenceAsset, poolId) = createMarket(block.timestamp + 1 days);
        vm.deal(DEFAULT_ADDRESS, 100_000_000_000 ether);
        collateralAsset.deposit{value: 1_000_000_000 ether}();
        referenceAsset.deposit{value: 1_000_000_000 ether}();

        collateralAsset.approve(address(corkPool), 100_000_000_000 ether);
        referenceAsset.approve(address(corkPool), 100_000_000_000 ether);

        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);

        share = new PoolShare(constructorParams);
    }

    function fetchProtocolGeneralInfo() internal {
        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);
        swapToken.approve(address(corkPool), 100_000_000_000 ether);
    }

    function assertReserve(PoolShare token, uint256 expectedRa, uint256 expectedPa) internal {
        (uint256 collateralAsset, uint256 referenceAsset) = token.getReserves();

        vm.assertEq(collateralAsset, expectedRa);
        vm.assertEq(referenceAsset, expectedPa);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldRevertWhenPassedInvalidExpiry() external {
        vm.warp(block.timestamp + 10);
        constructorParams.expiry = block.timestamp;

        try new PoolShare(constructorParams) {
            // should not reach here
            vm.assertEq(true, false);
        } catch (bytes memory reason) {
            // Verify it's the correct error
            bytes4 selector = bytes4(reason);
            vm.assertEq(selector, IErrors.InvalidExpiry.selector);
        }
    }

    function test_ConstructorShouldRevertWhenPassedInvalidOwner() external {
        vm.warp(block.timestamp + 10);
        constructorParams.poolManager = address(0);
        try new PoolShare(constructorParams) {
            // should not reach here
            vm.assertEq(true, false);
        } catch (bytes memory reason) {
            // Verify it's the correct error
            bytes4 selector = bytes4(reason);
            vm.assertEq(selector, bytes4(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0))));
        }
    }

    function test_ConstructorShouldWorkCorrectly() external {
        // expiry
        assertEq(share.expiry(), block.timestamp + 1 days);
        assertEq(share.issuedAt(), block.timestamp);
        assertEq(share.isExpired(), false);

        // PoolShare
        assertEq(share.pairName(), "Swap Token");
        assertEq(address(share.poolManager()), address(1));
        assertEq(share.factory(), DEFAULT_ADDRESS);
        assertEq(share.owner(), address(1));

        // ERC20
        assertEq(share.totalSupply(), 0);
        assertEq(share.balanceOf(DEFAULT_ADDRESS), 0);
        assertEq(share.allowance(DEFAULT_ADDRESS, address(corkPool)), 0);
        assertEq(share.decimals(), 18);
        assertEq(share.symbol(), "SWT");
        assertEq(share.name(), "Swap Token");
    }
    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- IsExpired ----------------------------------//
    function test_IsExpiredShouldReturnCorrectValue() external {
        assertFalse(share.isExpired());

        vm.warp(block.timestamp + 10 days);
        assertTrue(share.isExpired());
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------------------- Mint -------------------------------------------------//
    function test_MintShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        share.mint(user1, 1 ether);
        vm.stopPrank();
    }

    function test_MintShouldWorkCorrectly() external {
        assertEq(share.balanceOf(DEFAULT_ADDRESS), 0);

        vm.startPrank(address(1));
        share.mint(DEFAULT_ADDRESS, 1.234 ether);
        vm.stopPrank();

        assertEq(share.balanceOf(DEFAULT_ADDRESS), 1.234 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //------------------------------------------------- getReserves -------------------------------------------------//
    function test_getReservesShouldReturnCorrectReserves() external {
        // principalToken, should return current reserve
        assertReserve(principalToken, depositAmount, 0);

        // swapToken, should return current reserve
        assertReserve(swapToken, depositAmount, 0);

        // fast forward to expiry
        uint256 expiry = swapToken.expiry();
        vm.warp(expiry);

        assertReserve(principalToken, depositAmount, 0);
        assertReserve(swapToken, depositAmount, 0);

        PoolShare(principalToken).approve(address(corkPool), type(uint128).max);
        corkPool.redeem(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        assertReserve(principalToken, 0, 0);
        assertReserve(swapToken, 0, 0);
    }
    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- TransferFrom -----------------------------------------//
    function test_TransferFromShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        share.transferFrom(DEFAULT_ADDRESS, user1, address(this), 1 ether);
        vm.stopPrank();
    }

    function test_TransferFromShouldWorkCorrectlyWhenSenderIsOwner() external {
        // Setup: mint some tokens to user1
        vm.startPrank(address(1));
        share.mint(user1, 10 ether);
        vm.stopPrank();

        assertEq(share.balanceOf(user1), 10 ether);
        assertEq(share.balanceOf(DEFAULT_ADDRESS), 0);

        // Transfer from user1 to DEFAULT_ADDRESS
        vm.prank(address(1));
        share.transferFrom(user1, user1, DEFAULT_ADDRESS, 5 ether);

        assertEq(share.balanceOf(user1), 5 ether);
        assertEq(share.balanceOf(DEFAULT_ADDRESS), 5 ether);
    }

    function test_TransferFromShouldSpendAllowanceWhenSenderNotOwner() external {
        address spender = makeAddr("spender");

        // Setup: mint tokens and approve spender
        vm.startPrank(address(1));
        share.mint(user1, 10 ether);
        vm.startPrank(user1);

        share.approve(spender, 5 ether);

        assertEq(share.allowance(user1, spender), 5 ether);

        vm.startPrank(address(1));
        // Transfer using spender address
        share.transferFrom(spender, user1, DEFAULT_ADDRESS, 3 ether);

        assertEq(share.allowance(user1, spender), 2 ether);
        assertEq(share.balanceOf(user1), 7 ether);
        assertEq(share.balanceOf(DEFAULT_ADDRESS), 3 ether);
    }

    function test_TransferFromShouldRevertWhenInsufficientAllowance() external {
        address spender = makeAddr("spender");

        // Setup: mint tokens and approve spender
        vm.startPrank(address(1));
        share.mint(user1, 10 ether);
        share.approve(spender, 2 ether);
        vm.stopPrank();

        // Try to transfer more than allowance
        vm.prank(user1);
        vm.expectRevert();
        share.transferFrom(spender, user1, DEFAULT_ADDRESS, 3 ether);
    }

    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitDeposit -----------------------------------------//
    function test_EmitDepositShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        share.emitDeposit(DEFAULT_ADDRESS, user1, 1 ether, 0.5 ether);
        vm.stopPrank();
    }

    function test_EmitDepositShouldWorkCorrectlyAndEmitEvent() external {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 assets = 1.5 ether;
        uint256 shares = 0.75 ether;

        // Expect the Deposit event to be emitted with correct parameters
        vm.expectEmit(true, true, false, true);
        emit Deposit(sender, receiver, assets, shares);

        vm.startPrank(address(1));
        share.emitDeposit(sender, receiver, assets, shares);
        vm.stopPrank();
    }
    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- EmitWithdraw -----------------------------------------//
    function test_EmitWithdrawShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        share.emitWithdraw(DEFAULT_ADDRESS, user1, DEFAULT_ADDRESS, 1 ether, 0.5 ether);
        vm.stopPrank();
    }

    function test_EmitWithdrawShouldWorkCorrectlyAndEmitEvent() external {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address owner = sender;
        uint256 assets = 2 ether;
        uint256 shares = 1 ether;

        // Expect the Withdraw event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit Withdraw(sender, receiver, owner, assets, shares);

        vm.startPrank(address(1));
        share.emitWithdraw(sender, receiver, owner, assets, shares);
        vm.stopPrank();
    }

    function test_EmitWithdrawShouldEmitEventWithDifferentOwnerAndReceiver() external {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        address owner = makeAddr("owner");
        uint256 assets = 1.25 ether;
        uint256 shares = 0.625 ether;

        // Expect the Withdraw event to be emitted with different owner and receiver
        vm.expectEmit(true, true, true, true);
        emit Withdraw(sender, receiver, owner, assets, shares);

        vm.startPrank(address(1));
        share.emitWithdraw(sender, receiver, owner, assets, shares);
        vm.stopPrank();
    }
    // ----------------------------------------------------------------------------------------------------//
}
