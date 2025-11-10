// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract CorkAdapterExerciseTest is Helper {
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
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        deployPeriphery();
        vm.stopPrank();
    }

    function setupExerciseTest() internal {
        vm.startPrank(DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY);

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        swapToken = PoolShare(_swapToken);
        principalToken = PoolShare(_ct);

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        collateralAsset.deposit{value: type(uint256).max}();

        vm.deal(DEFAULT_ADDRESS, type(uint256).max);
        referenceAsset.deposit{value: type(uint256).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        swapToken.approve(address(corkPoolManager), type(uint256).max);
        principalToken.approve(address(corkPoolManager), type(uint256).max);

        // Deposit some collateral to get CST and CPT tokens
        uint256 depositAmount = 1000e18;
        corkPoolManager.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        // Transfer CST and reference tokens to OWNER for exercise testing
        uint256 cstBalance = swapToken.balanceOf(DEFAULT_ADDRESS);
        uint256 refBalance = referenceAsset.balanceOf(DEFAULT_ADDRESS);

        swapToken.transfer(OWNER, cstBalance / 2);
        referenceAsset.transfer(OWNER, refBalance / 2);

        vm.stopPrank();

        // Setup OWNER approvals
        vm.startPrank(OWNER);
        swapToken.approve(address(corkAdapter), type(uint256).max);
        referenceAsset.approve(address(corkAdapter), type(uint256).max);
        vm.stopPrank();
    }

    function test_safeExercise_success_withShares() public {
        setupExerciseTest();
        vm.startPrank(OWNER);

        swapToken.transfer(DEFAULT_ADDRESS, swapToken.balanceOf(OWNER));
        referenceAsset.transfer(DEFAULT_ADDRESS, referenceAsset.balanceOf(OWNER));

        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 100e18;
        uint256 minAssetsOut = 50e18;
        uint256 maxOtherAssetSpent = 200e18;

        // Get preview of the exercise for reference
        (uint256 previewAssets, uint256 previewOtherAssetSpent,) = corkPoolManager.previewExercise(defaultCurrencyId, sharesToExercise);

        // Record initial balances
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        // Transfer tokens to adapter and record balances
        swapToken.transfer(address(corkAdapter), sharesToExercise);
        referenceAsset.transfer(address(corkAdapter), maxOtherAssetSpent);

        uint256 adapterSwapTokenBefore = swapToken.balanceOf(address(corkAdapter));
        uint256 adapterRefTokenBefore = referenceAsset.balanceOf(address(corkAdapter));

        // Execute exercise
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

        // Verify results using scoped variables
        {
            uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
            uint256 actualSharesUsed = adapterSwapTokenBefore - swapToken.balanceOf(address(corkAdapter));
            uint256 actualOtherAssetSpent = adapterRefTokenBefore - referenceAsset.balanceOf(address(corkAdapter));
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

        uint256 compensationToExercise = 100e18;
        uint256 minAssetsOut = 50e18;
        uint256 maxOtherAssetSpent = 200e18;

        // Get preview of the exercise for reference
        (uint256 previewAssets, uint256 previewOtherAssetSpent,) = corkPoolManager.previewExerciseOther(defaultCurrencyId, compensationToExercise);

        // Record initial balances
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        // Transfer tokens to adapter and record balances
        swapToken.transfer(address(corkAdapter), maxOtherAssetSpent);
        referenceAsset.transfer(address(corkAdapter), compensationToExercise);

        uint256 adapterSwapTokenBefore = swapToken.balanceOf(address(corkAdapter));
        uint256 adapterRefTokenBefore = referenceAsset.balanceOf(address(corkAdapter));

        // Execute exercise
        corkAdapter.safeExerciseOther(ICorkAdapter.SafeExerciseOtherParams({poolId: defaultCurrencyId, referenceAssetsIn: compensationToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxCstSharesIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

        // Verify results using scoped variables
        {
            uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
            uint256 actualCompensationUsed = adapterRefTokenBefore - referenceAsset.balanceOf(address(corkAdapter));
            uint256 actualOtherAssetSpent = adapterSwapTokenBefore - swapToken.balanceOf(address(corkAdapter));
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
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp - 1}));

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
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: address(0), minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

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
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeExercise_revertsOnSharesZero() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 0;
        uint256 compensationToExercise = 0; // Both zero should revert
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeExerciseOther_revertsOnCompensationZero() public {
        setupExerciseTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 sharesToExercise = 0;
        uint256 compensationToExercise = 0; // Both zero should revert
        uint256 minAssetsOut = 25e18;
        uint256 maxOtherAssetSpent = 100e18;

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeExerciseOther(ICorkAdapter.SafeExerciseOtherParams({poolId: defaultCurrencyId, referenceAssetsIn: compensationToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxCstSharesIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

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
        swapToken.transfer(address(corkAdapter), 100e18);
        referenceAsset.transfer(address(corkAdapter), 100e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

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
        swapToken.transfer(address(corkAdapter), 100e18);
        referenceAsset.transfer(address(corkAdapter), 100e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));

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
        corkAdapter.safeExercise(ICorkAdapter.SafeExerciseParams({poolId: defaultCurrencyId, cstSharesIn: sharesToExercise, receiver: RECEIVER, minCollateralAssetsOut: minAssetsOut, maxReferenceAssetsIn: maxOtherAssetSpent, deadline: block.timestamp + 1 hours}));
    }
}
