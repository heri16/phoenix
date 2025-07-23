pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Shares} from "contracts/core/assets/Shares.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract SharesTest is Helper {
    DummyWETH collateralAsset;
    DummyWETH referenceAsset;
    Shares principalToken;
    Shares swapToken;
    Shares asset;

    MarketId marketId;

    address user1;

    uint256 public constant depositAmount = 1 ether;
    uint256 public constant swapAmount = 0.123 ether;

    function setUp() external {
        user1 = makeAddr("user1");

        vm.startPrank(DEFAULT_ADDRESS);

        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, marketId) = createMarket(block.timestamp + 1 days);
        vm.deal(DEFAULT_ADDRESS, 100_000_000_000 ether);
        collateralAsset.deposit{value: 1_000_000_000 ether}();
        referenceAsset.deposit{value: 1_000_000_000 ether}();

        collateralAsset.approve(address(corkPool), 100_000_000_000 ether);
        referenceAsset.approve(address(corkPool), 100_000_000_000 ether);

        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = Shares(_ct);
        swapToken = Shares(_swapToken);

        asset = new Shares("pairName", user1, block.timestamp + 1, 12_345);
    }

    function fetchProtocolGeneralInfo() internal {
        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = Shares(_ct);
        swapToken = Shares(_swapToken);
        swapToken.approve(address(corkPool), 100_000_000_000 ether);
    }

    function assertReserve(Shares token, uint256 expectedRa, uint256 expectedPa) internal {
        (uint256 collateralAsset, uint256 referenceAsset) = token.getReserves();

        vm.assertEq(collateralAsset, expectedRa);
        vm.assertEq(referenceAsset, expectedPa);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldRevertWhenPassedInvalidData() external {
        vm.warp(block.timestamp + 10);
        try new Shares("pairName", DEFAULT_ADDRESS, block.timestamp - 2, 1) {
            // should not reach here
            vm.assertEq(true, false);
        } catch (bytes memory reason) {
            // Verify it's the correct error
            bytes4 selector = bytes4(reason);
            vm.assertEq(selector, IErrors.Expired.selector);
        }
    }

    function test_ConstructorShouldRevertWhenPassedInvalidExpiry() external {
        vm.warp(block.timestamp + 10);
        try new Shares("pairName", DEFAULT_ADDRESS, 0, 1) {
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
        try new Shares("pairName", address(0), block.timestamp + 1, 1) {
            // should not reach here
            vm.assertEq(true, false);
        } catch (bytes memory reason) {
            // Verify it's the correct error
            bytes4 selector = bytes4(reason);
            vm.assertEq(selector, bytes4(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0))));
        }
    }

    function test_ConstructorShouldWorkCorrectly() external {
        // exchange rate
        assertEq(asset.exchangeRate(), 12_345);

        // expiry
        assertEq(asset.expiry(), block.timestamp + 1);
        assertEq(asset.issuedAt(), block.timestamp);
        assertEq(asset.isExpired(), false);

        // Shares
        assertEq(asset.pairName(), "pairName");
        assertEq(address(asset.corkPool()), address(0));
        assertEq(asset.factory(), DEFAULT_ADDRESS);
        assertEq(asset.owner(), user1);

        // ERC20
        assertEq(asset.totalSupply(), 0);
        assertEq(asset.balanceOf(DEFAULT_ADDRESS), 0);
        assertEq(asset.allowance(DEFAULT_ADDRESS, address(corkPool)), 0);
        assertEq(asset.decimals(), 18);
        assertEq(asset.symbol(), "pairName");
        assertEq(asset.name(), "pairName");
    }
    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- IsExpired ----------------------------------//
    function test_IsExpiredShouldReturnCorrectValue() external {
        assertFalse(asset.isExpired());

        vm.warp(block.timestamp + 10);
        assertTrue(asset.isExpired());
    }
    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- SetMarketId ----------------------------------//
    function test_SetMarketIdShouldRevertWhenCalledByNonFactory() external {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        asset.setMarketId(marketId);
        vm.stopPrank();
    }

    function test_SetMarketIdShouldWorkCorrectly() external {
        assertFalse(MarketId.unwrap(asset.marketId()) == MarketId.unwrap(marketId));

        vm.startPrank(DEFAULT_ADDRESS);
        asset.setMarketId(marketId);
        vm.stopPrank();

        // Compare MarketId values directly
        assertTrue(MarketId.unwrap(asset.marketId()) == MarketId.unwrap(marketId));
    }
    // ----------------------------------------------------------------------------------------------------//

    //---------------------------------- SetCorkPool ----------------------------------//
    function test_SetCorkPoolShouldRevertWhenCalledByNonFactory() external {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        asset.setCorkPool(address(0));
        vm.stopPrank();
    }

    function test_SetCorkPoolShouldWorkCorrectly() external {
        assertEq(address(asset.corkPool()), address(0));

        vm.startPrank(DEFAULT_ADDRESS);
        asset.setCorkPool(address(corkPool));
        vm.stopPrank();

        assertEq(address(asset.corkPool()), address(corkPool));
    }
    // -------------------------------------------------------------------------------------------------------//

    //------------------------------------------------- Mint -------------------------------------------------//
    function test_MintShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        asset.mint(user1, 1 ether);
        vm.stopPrank();
    }

    function test_MintShouldWorkCorrectly() external {
        assertEq(asset.balanceOf(DEFAULT_ADDRESS), 0);

        vm.startPrank(user1);
        asset.mint(DEFAULT_ADDRESS, 1.234 ether);
        vm.stopPrank();

        assertEq(asset.balanceOf(DEFAULT_ADDRESS), 1.234 ether);
    }

    function test_MintShouldRevertWhenAssetIsExpired() external {
        vm.warp(block.timestamp + 10);
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IErrors.Expired.selector));
        asset.mint(DEFAULT_ADDRESS, 1 ether);
        vm.stopPrank();
    }
    // ----------------------------------------------------------------------------------------------------//

    //-------------------------------------------- UpdateRate ---------------------------------------------//
    function test_UpdateRateShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        asset.updateRate(1.234 ether);
        vm.stopPrank();
    }

    function test_UpdateRateShouldWorkCorrectly() external {
        assertEq(asset.exchangeRate(), 12_345);

        vm.startPrank(user1);
        asset.updateRate(1.234 ether);
        vm.stopPrank();

        assertEq(asset.exchangeRate(), 1.234 ether);
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

        Shares(principalToken).approve(address(corkPool), type(uint128).max);
        corkPool.redeem(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        assertReserve(principalToken, 0, 0);
        assertReserve(swapToken, 0, 0);
    }
    // ----------------------------------------------------------------------------------------------------//

    //----------------------------------------- TransferFrom -----------------------------------------//
    function test_TransferFromShouldRevertWhenCalledByNonOwner() external {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEFAULT_ADDRESS));
        asset.transferFrom(DEFAULT_ADDRESS, user1, address(this), 1 ether);
        vm.stopPrank();
    }

    function test_TransferFromShouldWorkCorrectlyWhenSenderIsOwner() external {
        // Setup: mint some tokens to user1
        vm.startPrank(user1);
        asset.mint(user1, 10 ether);
        vm.stopPrank();

        assertEq(asset.balanceOf(user1), 10 ether);
        assertEq(asset.balanceOf(DEFAULT_ADDRESS), 0);

        // Transfer from user1 to DEFAULT_ADDRESS
        vm.prank(user1);
        asset.transferFrom(user1, user1, DEFAULT_ADDRESS, 5 ether);

        assertEq(asset.balanceOf(user1), 5 ether);
        assertEq(asset.balanceOf(DEFAULT_ADDRESS), 5 ether);
    }

    function test_TransferFromShouldSpendAllowanceWhenSenderNotOwner() external {
        address spender = makeAddr("spender");

        // Setup: mint tokens and approve spender
        vm.startPrank(user1);
        asset.mint(user1, 10 ether);
        asset.approve(spender, 5 ether);
        vm.stopPrank();

        assertEq(asset.allowance(user1, spender), 5 ether);

        // Transfer using spender address
        vm.prank(user1);
        asset.transferFrom(spender, user1, DEFAULT_ADDRESS, 3 ether);

        assertEq(asset.allowance(user1, spender), 2 ether);
        assertEq(asset.balanceOf(user1), 7 ether);
        assertEq(asset.balanceOf(DEFAULT_ADDRESS), 3 ether);
    }

    function test_TransferFromShouldRevertWhenInsufficientAllowance() external {
        address spender = makeAddr("spender");

        // Setup: mint tokens and approve spender
        vm.startPrank(user1);
        asset.mint(user1, 10 ether);
        asset.approve(spender, 2 ether);
        vm.stopPrank();

        // Try to transfer more than allowance
        vm.prank(user1);
        vm.expectRevert();
        asset.transferFrom(spender, user1, DEFAULT_ADDRESS, 3 ether);
    }
}
