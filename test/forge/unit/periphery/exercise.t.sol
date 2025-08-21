// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {CorkPoolAdapter} from "contracts/periphery/CorkPoolAdapter.sol";
import "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract CorkPoolAdapterExerciseTest is Helper {
    address constant RECEIVER = address(0x123);
    address constant OWNER = address(0x456);
    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant EXPIRY = 30 days;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare swapToken;
    PoolShare principalToken;

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        deployPeriphery();
        vm.stopPrank();
    }

    function setupExerciseTest() internal {
        vm.startPrank(DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY);

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        collateralAsset.deposit{value: type(uint256).max}();

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        referenceAsset.deposit{value: type(uint256).max}();

        collateralAsset.approve(address(corkPool), type(uint256).max);
        referenceAsset.approve(address(corkPool), type(uint256).max);

        swapToken.approve(address(corkPool), type(uint256).max);
        principalToken.approve(address(corkPool), type(uint256).max);

        // Deposit some collateral to get CST and CPT tokens
        uint256 depositAmount = 1000e18;
        corkPool.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        // Transfer CST and reference tokens to OWNER for exercise testing
        uint256 cstBalance = swapToken.balanceOf(DEFAULT_ADDRESS);
        uint256 refBalance = referenceAsset.balanceOf(DEFAULT_ADDRESS);

        swapToken.transfer(OWNER, cstBalance / 2);
        referenceAsset.transfer(OWNER, refBalance / 2);

        vm.stopPrank();

        // Setup OWNER approvals
        vm.startPrank(OWNER);
        swapToken.approve(address(corkPoolAdapter), type(uint256).max);
        referenceAsset.approve(address(corkPoolAdapter), type(uint256).max);
        vm.stopPrank();
    }

    function test_safeExercise_success_withShares() public {
        setupExerciseTest();
        vm.startPrank(OWNER);

        swapToken.transfer(DEFAULT_ADDRESS, swapToken.balanceOf(OWNER));
        referenceAsset.transfer(DEFAULT_ADDRESS, referenceAsset.balanceOf(OWNER));

        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 100e18;
        uint256 compensationToExercise = 0; // Using shares, not compensation
        uint256 minAssetsOut = 50e18;
        uint256 maxOtherAssetSpent = 200e18;

        // Get preview of the exercise for reference
        (uint256 previewAssets, uint256 previewOtherAssetSpent,) = corkPool.previewExercise(defaultCurrencyId, sharesToExercise, compensationToExercise);

        // Record initial balances
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        // Transfer tokens to adapter and record balances
        swapToken.transfer(address(corkPoolAdapter), sharesToExercise);
        referenceAsset.transfer(address(corkPoolAdapter), maxOtherAssetSpent);

        uint256 adapterSwapTokenBefore = swapToken.balanceOf(address(corkPoolAdapter));
        uint256 adapterRefTokenBefore = referenceAsset.balanceOf(address(corkPoolAdapter));

        // Execute exercise
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        // Verify results using scoped variables
        {
            uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
            uint256 actualSharesUsed = adapterSwapTokenBefore - swapToken.balanceOf(address(corkPoolAdapter));
            uint256 actualOtherAssetSpent = adapterRefTokenBefore - referenceAsset.balanceOf(address(corkPoolAdapter));
            uint256 actualAssetsReceived = receiverCollateralAfter - receiverCollateralBefore;

            assertEq(actualSharesUsed, sharesToExercise, "Should use exactly the specified shares");
            assertEq(actualAssetsReceived, previewAssets, "Should receive preview assets amount");
            assertEq(actualOtherAssetSpent, previewOtherAssetSpent, "Should spend preview other asset amount");
            assertEq(actualOtherAssetSpent, sharesToExercise, "Should spend exact other asset amount");
            assertGe(actualAssetsReceived, minAssetsOut, "Should receive at least minimum assets");
            assertLe(actualOtherAssetSpent, maxOtherAssetSpent, "Should not exceed max other asset spent");
        }

        vm.stopPrank();
    }

    function test_safeExercise_success_withCompensation() public {
        setupExerciseTest();
        vm.startPrank(OWNER);

        swapToken.transfer(DEFAULT_ADDRESS, swapToken.balanceOf(OWNER));
        referenceAsset.transfer(DEFAULT_ADDRESS, referenceAsset.balanceOf(OWNER));

        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 0; // Using compensation, not shares
        uint256 compensationToExercise = 100e18;
        uint256 minAssetsOut = 50e18;
        uint256 maxOtherAssetSpent = 200e18;

        // Get preview of the exercise for reference
        (uint256 previewAssets, uint256 previewOtherAssetSpent,) = corkPool.previewExercise(defaultCurrencyId, sharesToExercise, compensationToExercise);

        // Record initial balances
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        // Transfer tokens to adapter and record balances
        swapToken.transfer(address(corkPoolAdapter), maxOtherAssetSpent);
        referenceAsset.transfer(address(corkPoolAdapter), compensationToExercise);

        uint256 adapterSwapTokenBefore = swapToken.balanceOf(address(corkPoolAdapter));
        uint256 adapterRefTokenBefore = referenceAsset.balanceOf(address(corkPoolAdapter));

        // Execute exercise
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        // Verify results using scoped variables
        {
            uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
            uint256 actualCompensationUsed = adapterRefTokenBefore - referenceAsset.balanceOf(address(corkPoolAdapter));
            uint256 actualOtherAssetSpent = adapterSwapTokenBefore - swapToken.balanceOf(address(corkPoolAdapter));
            uint256 actualAssetsReceived = receiverCollateralAfter - receiverCollateralBefore;

            assertEq(actualCompensationUsed, compensationToExercise, "Should use exactly the specified compensation");
            assertEq(actualAssetsReceived, previewAssets, "Should receive preview assets amount");
            assertEq(actualOtherAssetSpent, previewOtherAssetSpent, "Should spend preview other asset amount");
            assertGe(actualAssetsReceived, minAssetsOut, "Should receive at least minimum assets");
            assertLe(actualOtherAssetSpent, maxOtherAssetSpent, "Should not exceed max other asset spent");
        }

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnDeadlineExceeded() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 0;
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert(ErrorsLib.DeadlineExceeded.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp - 1);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnZeroReceiver() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 0;
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), address(0), minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnZeroOwner() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 0;
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert();
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(0), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnBothSharesAndCompensationNonZero() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 50e18; // Both non-zero should revert
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnBothSharesAndCompensationZero() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 0;
        uint256 compensationToExercise = 0; // Both zero should revert
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnSlippageExceeded_minAssetsOut() public {
        setupExerciseTest();

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 0;
        uint256 minAssetsOut = type(uint256).max; // Very high minimum to trigger slippage
        uint256 maxOtherAssetSpent = 100e18;

        // Transfer enough tokens to adapter
        vm.startPrank(OWNER);
        swapToken.transfer(address(corkPoolAdapter), 100e18);
        referenceAsset.transfer(address(corkPoolAdapter), 100e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnSlippageExceeded_maxOtherAssetSpent() public {
        setupExerciseTest();

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 0;
        uint256 minAssetsOut = 1;
        uint256 maxOtherAssetSpent = 1; // Very low limit to trigger slippage

        // Transfer enough tokens to adapter
        vm.startPrank(OWNER);
        swapToken.transfer(address(corkPoolAdapter), 100e18);
        referenceAsset.transfer(address(corkPoolAdapter), 100e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnUnauthorizedCaller() public {
        setupExerciseTest();

        uint256 sharesToExercise = 50e18;
        uint256 compensationToExercise = 0;
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.prank(address(0x999));
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkPoolAdapter.safeExercise(defaultCurrencyId, sharesToExercise, compensationToExercise, address(corkPoolAdapter), RECEIVER, minAssetsOut, maxOtherAssetSpent, block.timestamp + 1 hours);
    }
}
