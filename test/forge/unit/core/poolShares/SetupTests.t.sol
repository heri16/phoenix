pragma solidity ^0.8.30;

import {BaseTest} from "test/forge/BaseTest.sol";

contract SetupTests is BaseTest {
    uint256 public constant depositAmount = 1 ether;

    function setUp() public override {
        super.setUp();

        _createPool(block.timestamp + 1 days, 18, 18, false);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldWorkCorrectly() external {
        // deppsit to get some data
        _deposit(defaultPoolId, depositAmount, alice);

        // cST expiry
        assertEq(swapToken.expiry(), block.timestamp + 1 days);
        assertEq(swapToken.issuedAt(), block.timestamp);
        assertEq(swapToken.isExpired(), false);

        // cST PoolShare
        assertEq(swapToken.pairName(), "DWETH-DWETH1cST");
        assertEq(address(swapToken.poolManager()), address(corkPoolManager));
        assertEq(swapToken.factory(), address(sharesFactory));
        assertEq(address(swapToken.poolManager()), address(corkPoolManager));

        // cST ERC20
        assertEq(swapToken.totalSupply(), depositAmount);
        assertEq(swapToken.balanceOf(alice), depositAmount);
        assertEq(swapToken.allowance(alice, address(corkPoolManager)), 0);
        assertEq(swapToken.decimals(), 18);
        assertEq(swapToken.symbol(), "DWETH1cST");
        assertEq(swapToken.name(), "DWETH-DWETH1cST");

        // cPT expiry
        assertEq(principalToken.expiry(), block.timestamp + 1 days);
        assertEq(principalToken.issuedAt(), block.timestamp);
        assertEq(principalToken.isExpired(), false);

        // cPT PoolShare
        assertEq(principalToken.pairName(), "DWETH-DWETH1cPT");
        assertEq(address(principalToken.poolManager()), address(corkPoolManager));
        assertEq(principalToken.factory(), address(sharesFactory));
        assertEq(address(principalToken.poolManager()), address(corkPoolManager));

        // cPT ERC20
        assertEq(principalToken.totalSupply(), depositAmount);
        assertEq(principalToken.balanceOf(alice), depositAmount);
        assertEq(principalToken.allowance(alice, address(corkPoolManager)), 0);
        assertEq(principalToken.decimals(), 18);
        assertEq(principalToken.symbol(), "DWETH1cPT");
        assertEq(principalToken.name(), "DWETH-DWETH1cPT");
    }

    //-----------------------------------------------------------------------------------------------------//
}
