// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract WhitelistManagerCoreIntegrationTest is BaseTest {
    uint256 constant TEST_AMOUNT = 100e18;
    uint256 constant SMALL_AMOUNT = 1e18;

    // non whitelisted user
    address beta = makeAddr("beta");
    address gamma = makeAddr("gamma");

    function setUp() public override {
        super.setUp();

        createMarket(1 days, 18, 18, true);
        address[] memory addresses = new address[](5);

        addresses[0] = address(corkAdapter);
        addresses[1] = alice;
        addresses[2] = bob;
        addresses[3] = charlie;
        addresses[4] = bravo;

        vm.startPrank(whitelistAdder);
        defaultCorkController.addToGlobalWhitelist(addresses);

        // Give assets to test users
        _giveAssets(beta);
        _giveAssets(gamma);

        // Approve all tokens
        _approveAllTokens(gamma, address(corkPoolManager));
        _approveAllTokens(beta, address(corkPoolManager));
    }

    function test_deposit_WithWhitelistEnabled_WhitelistedUser() external {
        // Add user to global whitelist
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        // Deposit should work for whitelisted user
        overridePrank(gamma);
        uint256 shares = corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);
        assertGt(shares, 0);
    }

    function test_deposit_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Deposit should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);
    }

    function test_mint_WithWhitelistEnabled_WhitelistedUser() external {
        // Add user to market-specific whitelist
        overridePrank(address(defaultCorkController));
        whitelistManager.addToMarketWhitelist(defaultPoolId, _createUserArray(gamma));

        // Mint should work for whitelisted user
        overridePrank(gamma);
        uint256 assets = corkPoolManager.mint(defaultPoolId, TEST_AMOUNT, gamma);
        assertGt(assets, 0);
    }

    function test_mint_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Mint should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.mint(defaultPoolId, TEST_AMOUNT, beta);
    }

    function test_unwindDeposit_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit first as whitelisted user
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        // Unwind deposit should work for whitelisted user
        overridePrank(gamma);
        uint256 sharesIn = corkPoolManager.unwindDeposit(defaultPoolId, SMALL_AMOUNT, gamma, gamma);
        assertGt(sharesIn, 0);
    }

    function test_unwindDeposit_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.unwindDeposit(defaultPoolId, SMALL_AMOUNT, beta, beta);
    }

    function test_unwindMint_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: mint first as whitelisted user
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.mint(defaultPoolId, TEST_AMOUNT, gamma);

        // Unwind mint should work for whitelisted user
        overridePrank(gamma);
        uint256 assetsOut = corkPoolManager.unwindMint(defaultPoolId, SMALL_AMOUNT, gamma, gamma);
        assertGt(assetsOut, 0);
    }

    function test_unwindMint_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.unwindMint(defaultPoolId, SMALL_AMOUNT, beta, beta);
    }

    function test_redeem_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and let market expire
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        // Redeem should work for whitelisted user
        overridePrank(gamma);
        (uint256 refOut, uint256 collateralOut) = corkPoolManager.redeem(defaultPoolId, SMALL_AMOUNT, gamma, gamma);
        assertGt(refOut + collateralOut, 0);
    }

    function test_redeem_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        vm.warp(block.timestamp + 2 days);

        // Redeem should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.redeem(defaultPoolId, SMALL_AMOUNT, beta, beta);
    }

    function test_withdraw_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and let market expire
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        vm.warp(block.timestamp + 2 days);

        // Withdraw should work for whitelisted user
        overridePrank(gamma);
        (uint256 sharesIn, uint256 collateralOut, uint256 refOut) =
            corkPoolManager.withdraw(defaultPoolId, SMALL_AMOUNT, gamma, gamma);
        assertGt(sharesIn, 0);
    }

    function test_withdraw_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        vm.warp(block.timestamp + 2 days);

        // Withdraw should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.withdraw(defaultPoolId, SMALL_AMOUNT, beta, beta);
    }

    function test_withdrawOther_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and let market expire
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        corkPoolManager.swap(defaultPoolId, 1 ether, gamma);

        vm.warp(block.timestamp + 2 days);

        // WithdrawOther should work for whitelisted user
        overridePrank(gamma);
        // we don't care about the amount for now, just testing if the whitelist works as intended
        corkPoolManager.withdrawOther(defaultPoolId, SMALL_AMOUNT, gamma, gamma);
    }

    function test_withdrawOther_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        vm.warp(block.timestamp + 2 days);

        // WithdrawOther should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.withdrawOther(defaultPoolId, SMALL_AMOUNT, beta, beta);
    }

    function test_swap_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit to create liquidity and have swap tokens
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        // Swap should work for whitelisted user
        overridePrank(gamma);
        (uint256 cstSharesIn, uint256 refIn, uint256 fee) = corkPoolManager.swap(defaultPoolId, SMALL_AMOUNT, gamma);
        assertGt(cstSharesIn + refIn, 0);
    }

    function test_swap_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Swap should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.swap(defaultPoolId, SMALL_AMOUNT, beta);
    }

    function test_exercise_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit to get swap tokens
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        // Exercise should work for whitelisted user
        overridePrank(gamma);
        (uint256 collateralOut, uint256 refIn, uint256 fee) =
            corkPoolManager.exercise(defaultPoolId, SMALL_AMOUNT, gamma);
        assertGt(collateralOut + refIn, 0);
    }

    function test_exercise_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.exercise(defaultPoolId, SMALL_AMOUNT, beta);
    }

    function test_exerciseOther_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit to create liquidity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        // ExerciseOther should work for whitelisted user
        overridePrank(gamma);
        (uint256 collateralOut, uint256 cstSharesIn, uint256 fee) =
            corkPoolManager.exerciseOther(defaultPoolId, SMALL_AMOUNT, gamma);
        assertGt(collateralOut + cstSharesIn, 0);
    }

    function test_exerciseOther_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // ExerciseOther should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.exerciseOther(defaultPoolId, SMALL_AMOUNT, beta);
    }

    function test_unwindSwap_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and swap to create unwind opportunity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        overridePrank(gamma);
        corkPoolManager.swap(defaultPoolId, SMALL_AMOUNT, gamma);

        // UnwindSwap should work for whitelisted user
        overridePrank(gamma);
        (uint256 cstOut, uint256 refOut, uint256 fee) = corkPoolManager.unwindSwap(defaultPoolId, SMALL_AMOUNT, gamma);
        assertGt(cstOut + refOut, 0);
    }

    function test_unwindSwap_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // UnwindSwap should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.unwindSwap(defaultPoolId, SMALL_AMOUNT, beta);
    }

    function test_unwindExercise_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and exercise to create unwind opportunity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        overridePrank(gamma);
        corkPoolManager.exercise(defaultPoolId, SMALL_AMOUNT, gamma);

        // UnwindExercise should work for whitelisted user
        overridePrank(gamma);
        (uint256 collateralIn, uint256 refOut, uint256 fee) =
            corkPoolManager.unwindExercise(defaultPoolId, SMALL_AMOUNT, gamma);
        assertGt(collateralIn + refOut, 0);
    }

    function test_unwindExercise_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // UnwindExercise should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.unwindExercise(defaultPoolId, SMALL_AMOUNT, beta);
    }

    function test_unwindExerciseOther_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and exercise to create unwind opportunity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(gamma));

        overridePrank(gamma);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        overridePrank(gamma);
        corkPoolManager.exerciseOther(defaultPoolId, SMALL_AMOUNT, gamma);

        // UnwindExerciseOther should work for whitelisted user
        overridePrank(gamma);
        (uint256 collateralIn, uint256 cstOut, uint256 fee) =
            corkPoolManager.unwindExerciseOther(defaultPoolId, SMALL_AMOUNT, gamma);
        assertGt(collateralIn + cstOut, 0);
    }

    function test_unwindExerciseOther_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // UnwindExerciseOther should revert for non-whitelisted user
        overridePrank(beta);
        vm.expectRevert(
            abi.encodeWithSignature("NotWhitelisted(address,bytes32)", beta, MarketId.unwrap(defaultPoolId))
        );
        corkPoolManager.unwindExerciseOther(defaultPoolId, SMALL_AMOUNT, beta);
    }

    // Helper function to create user arrays for whitelist functions
    function _createUserArray(address user) internal pure returns (address[] memory) {
        address[] memory users = new address[](1);
        users[0] = user;
        return users;
    }
}
