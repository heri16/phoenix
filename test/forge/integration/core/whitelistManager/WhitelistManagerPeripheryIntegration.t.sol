// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract WhitelistManagerPeripheryIntegration is BaseTest {
    // non whitelisted user
    address beta = makeAddr("beta");
    address gamma = makeAddr("gamma");

    uint256 constant TEST_AMOUNT = 100e18;
    uint256 constant SMALL_AMOUNT = 1e18;
    uint256 constant DEADLINE = type(uint256).max;

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
        _giveAssets(address(corkAdapter));

        // Approve all tokens for the adapter
        _approveAllTokens(beta, address(corkAdapter));
        _approveAllTokens(beta, address(corkPoolManager));
        _approveAllTokens(gamma, address(corkAdapter));
        _approveAllTokens(gamma, address(corkPoolManager));

        vm.label(beta, "beta");
        vm.label(gamma, "gamma");
    }

    function test_safeMint_WithWhitelistEnabled_WhitelistedUser() external {
        // Add user to global whitelist
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        // Transfer collateral to adapter
        overridePrank(beta);
        collateralAsset.transfer(address(corkAdapter), TEST_AMOUNT);

        // SafeMint should work for whitelisted user
        bytes memory data = abi.encodeWithSignature(
            "safeMint((bytes32,uint256,address,uint256,uint256))",
            defaultPoolId,
            TEST_AMOUNT,
            beta,
            TEST_AMOUNT,
            DEADLINE
        );
        _bundlerCall(data);

        // Check shares were minted
        assertGt(IERC20(principalToken).balanceOf(beta), 0);
        assertGt(swapToken.balanceOf(beta), 0);
    }

    function test_safeMint_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Transfer collateral to adapter
        overridePrank(gamma);
        collateralAsset.transfer(address(corkAdapter), TEST_AMOUNT);

        // SafeMint should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeMint((bytes32,uint256,address,uint256,uint256))",
            defaultPoolId,
            TEST_AMOUNT,
            gamma,
            TEST_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeDeposit_WithWhitelistEnabled_WhitelistedUser() external {
        // Add user to market-specific whitelist
        overridePrank(address(defaultCorkController));
        whitelistManager.addToMarketWhitelist(defaultPoolId, _createUserArray(beta));

        // Transfer collateral to adapter
        overridePrank(beta);
        collateralAsset.transfer(address(corkAdapter), TEST_AMOUNT);

        // SafeDeposit should work for whitelisted user
        bytes memory data = abi.encodeWithSignature(
            "safeDeposit((bytes32,uint256,address,uint256,uint256))", defaultPoolId, TEST_AMOUNT, beta, 0, DEADLINE
        );
        _bundlerCall(data);

        // Check shares were minted
        assertGt(IERC20(principalToken).balanceOf(beta), 0);
        assertGt(swapToken.balanceOf(beta), 0);
    }

    function test_safeDeposit_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Transfer collateral to adapter
        overridePrank(gamma);
        collateralAsset.transfer(address(corkAdapter), TEST_AMOUNT);

        // SafeDeposit should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeDeposit((bytes32,uint256,address,uint256,uint256))", defaultPoolId, TEST_AMOUNT, gamma, 0, DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeUnwindDeposit_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit first as whitelisted user
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        // Transfer shares to adapter and approve
        overridePrank(beta);
        principalToken.transfer(address(corkAdapter), SMALL_AMOUNT);
        overridePrank(beta);
        swapToken.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeUnwindDeposit should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindDeposit((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT / 2,
            address(corkAdapter),
            beta,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCall(data);

        // Check collateral was received
        assertGt(collateralAsset.balanceOf(beta), 0);
    }

    function test_safeUnwindDeposit_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Setup: give shares to non-whitelisted user via admin
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(address(beta)));

        overridePrank(address(beta));
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        // SafeUnwindDeposit should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindDeposit((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            gamma,
            TEST_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeUnwindMint_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: mint first as whitelisted user
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.mint(defaultPoolId, TEST_AMOUNT, beta);

        // Transfer shares to adapter
        overridePrank(beta);
        principalToken.transfer(address(corkAdapter), SMALL_AMOUNT);
        overridePrank(beta);
        swapToken.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeUnwindMint should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindMint((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            address(corkAdapter),
            beta,
            0,
            DEADLINE
        );
        _bundlerCall(data);

        // Check collateral was received
        assertGt(collateralAsset.balanceOf(beta), 0);
    }

    function test_safeUnwindMint_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // SafeUnwindMint should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindMint((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            gamma,
            0,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeRedeem_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and let market expire
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        // Transfer shares to adapter

        overridePrank(beta);
        principalToken.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeRedeem should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeRedeem((bytes32,uint256,address,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            address(corkAdapter),
            beta,
            0,
            0,
            DEADLINE
        );
        _bundlerCall(data);

        // Check assets were received
        assertGt(collateralAsset.balanceOf(beta) + referenceAsset.balanceOf(beta), 0);
    }

    function test_safeRedeem_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // Setup: give shares and expire market
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(address(beta)));

        overridePrank(address(beta));
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, gamma);

        vm.warp(block.timestamp + 2 days);

        // SafeRedeem should revert for non-whitelisted user
        overridePrank(gamma);
        principalToken.transfer(address(corkAdapter), SMALL_AMOUNT);

        bytes memory data = abi.encodeWithSignature(
            "safeRedeem((bytes32,uint256,address,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            gamma,
            0,
            0,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeWithdraw_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and let market expire
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        vm.warp(block.timestamp + 2 days);

        // Transfer shares to adapter
        overridePrank(beta);
        principalToken.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeWithdraw should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeWithdraw((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT / 2,
            address(corkAdapter),
            beta,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCall(data);

        // Check collateral was received
        assertGt(collateralAsset.balanceOf(beta), 0);
    }

    function test_safeWithdraw_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // SafeWithdraw should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeWithdraw((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            gamma,
            TEST_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeWithdrawOther_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and let market expire
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        corkPoolManager.swap(defaultPoolId, 1 ether, beta);

        vm.warp(block.timestamp + 2 days);

        // Transfer shares to adapter

        overridePrank(beta);
        principalToken.transfer(address(corkAdapter), principalToken.balanceOf(beta));

        // SafeWithdrawOther should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeWithdrawOther((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            1 ether,
            address(corkAdapter),
            beta,
            type(uint256).max,
            DEADLINE
        );
        _bundlerCall(data);

        // Check reference asset was received
        assertGt(referenceAsset.balanceOf(beta), 0);
    }

    function test_safeWithdrawOther_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // SafeWithdrawOther should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeWithdrawOther((bytes32,uint256,address,address,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            gamma,
            TEST_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeSwap_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit to create liquidity and get swap tokens
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        // Transfer swap tokens and reference to adapter
        (, address swap) = corkPoolManager.shares(defaultPoolId);
        overridePrank(beta);
        swapToken.transfer(address(corkAdapter), SMALL_AMOUNT);
        overridePrank(beta);
        referenceAsset.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeSwap should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeSwap((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT / 10,
            beta,
            SMALL_AMOUNT,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCall(data);

        // Check collateral was received
        assertGt(collateralAsset.balanceOf(beta), 0);
    }

    function test_safeSwap_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // SafeSwap should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeSwap((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            SMALL_AMOUNT,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeExercise_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit to get swap tokens
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        // Transfer swap tokens and reference to adapter
        (, address swap) = corkPoolManager.shares(defaultPoolId);
        overridePrank(beta);
        swapToken.transfer(address(corkAdapter), SMALL_AMOUNT);
        overridePrank(beta);
        referenceAsset.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeExercise should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeExercise((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            beta,
            0,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCall(data);

        // Check collateral was received
        assertGt(collateralAsset.balanceOf(beta), 0);
    }

    function test_safeExercise_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        // SafeExercise should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeExercise((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            0,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeExerciseOther_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit to create liquidity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        // Transfer swap tokens and reference to adapter
        (, address swap) = corkPoolManager.shares(defaultPoolId);
        overridePrank(beta);
        swapToken.transfer(address(corkAdapter), SMALL_AMOUNT);
        overridePrank(beta);
        referenceAsset.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeExerciseOther should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeExerciseOther((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            beta,
            0,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCall(data);

        // Check collateral was received
        assertGt(collateralAsset.balanceOf(beta), 0);
    }

    function test_safeExerciseOther_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        ICorkAdapter.SafeExerciseOtherParams memory params = ICorkAdapter.SafeExerciseOtherParams({
            poolId: defaultPoolId,
            referenceAssetsIn: SMALL_AMOUNT,
            receiver: gamma,
            minCollateralAssetsOut: 0,
            maxCstSharesIn: SMALL_AMOUNT,
            deadline: DEADLINE
        });

        // Setup: deposit to create liquidity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        // SafeExerciseOther should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeExerciseOther((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            0,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeUnwindSwap_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and swap to create unwind opportunity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        overridePrank(beta);
        corkPoolManager.swap(defaultPoolId, SMALL_AMOUNT, beta);

        // Transfer collateral to adapter
        overridePrank(beta);
        collateralAsset.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeUnwindSwap should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindSwap((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            beta,
            0,
            0,
            DEADLINE
        );
        _bundlerCall(data);

        // Check assets were received
        (, address swap) = corkPoolManager.shares(defaultPoolId);
        assertGt(swapToken.balanceOf(beta) + referenceAsset.balanceOf(beta), 0);
    }

    function test_safeUnwindSwap_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        ICorkAdapter.SafeUnwindSwapParams memory params = ICorkAdapter.SafeUnwindSwapParams({
            poolId: defaultPoolId,
            collateralAssetsIn: SMALL_AMOUNT,
            receiver: gamma,
            minReferenceAssetsOut: 0,
            minCstSharesOut: 0,
            deadline: DEADLINE
        });

        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        overridePrank(beta);
        corkPoolManager.swap(defaultPoolId, SMALL_AMOUNT, beta);

        // SafeUnwindSwap should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindSwap((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            0,
            0,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeUnwindExercise_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and exercise to create unwind opportunity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        overridePrank(beta);
        corkPoolManager.exercise(defaultPoolId, SMALL_AMOUNT, beta);

        // Transfer collateral to adapter
        overridePrank(beta);
        collateralAsset.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeUnwindExercise should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindExercise((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            beta,
            0,
            type(uint256).max,
            DEADLINE
        );
        _bundlerCall(data);

        // Check assets were received
        (, address swap) = corkPoolManager.shares(defaultPoolId);
        assertGt(swapToken.balanceOf(beta) + referenceAsset.balanceOf(beta), 0);
    }

    function test_safeUnwindExercise_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        ICorkAdapter.SafeUnwindExerciseParams memory params = ICorkAdapter.SafeUnwindExerciseParams({
            poolId: defaultPoolId,
            cstSharesOut: SMALL_AMOUNT,
            receiver: gamma,
            minReferenceAssetsOut: 0,
            maxCollateralAssetsIn: SMALL_AMOUNT,
            deadline: DEADLINE
        });

        // SafeUnwindExercise should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindExercise((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            0,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    function test_safeUnwindExerciseOther_WithWhitelistEnabled_WhitelistedUser() external {
        // Setup: deposit and exercise to create unwind opportunity
        overridePrank(address(defaultCorkController));
        whitelistManager.addToGlobalWhitelist(_createUserArray(beta));

        overridePrank(beta);
        corkPoolManager.deposit(defaultPoolId, TEST_AMOUNT, beta);

        overridePrank(beta);
        corkPoolManager.exerciseOther(defaultPoolId, SMALL_AMOUNT, beta);

        // Transfer collateral to adapter
        overridePrank(beta);
        collateralAsset.transfer(address(corkAdapter), SMALL_AMOUNT);

        // SafeUnwindExerciseOther should work for whitelisted user
        overridePrank(beta);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindExerciseOther((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            beta,
            0,
            type(uint256).max,
            DEADLINE
        );
        _bundlerCall(data);

        // Check assets were received
        (, address swap) = corkPoolManager.shares(defaultPoolId);
        assertGt(swapToken.balanceOf(beta), 0);
    }

    function test_safeUnwindExerciseOther_WithWhitelistEnabled_NonWhitelistedUser_Reverts() external {
        ICorkAdapter.SafeUnwindExerciseOtherParams memory params = ICorkAdapter.SafeUnwindExerciseOtherParams({
            poolId: defaultPoolId,
            referenceAssetsOut: SMALL_AMOUNT,
            receiver: gamma,
            minCstSharesOut: 0,
            maxCollateralAssetsIn: SMALL_AMOUNT,
            deadline: DEADLINE
        });

        // SafeUnwindExerciseOther should revert for non-whitelisted user
        overridePrank(gamma);
        bytes memory data = abi.encodeWithSignature(
            "safeUnwindExerciseOther((bytes32,uint256,address,uint256,uint256,uint256))",
            defaultPoolId,
            SMALL_AMOUNT,
            gamma,
            0,
            SMALL_AMOUNT,
            DEADLINE
        );
        _bundlerCallExpectRevert(data, abi.encodeWithSignature("UnauthorizedSender()"));
    }

    // Helper function to create user arrays for whitelist functions
    function _createUserArray(address user) internal pure returns (address[] memory) {
        address[] memory users = new address[](1);
        users[0] = user;
        return users;
    }
}
