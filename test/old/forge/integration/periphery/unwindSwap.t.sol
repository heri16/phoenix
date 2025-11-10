// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract CorkAdapterUnwindSwapTest is Helper {
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

    function setupUnwindSwapTest() internal {
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

        // Perform a swap to create liquidity for unwind swap
        uint256 swapAmount = 500e18;
        corkPoolManager.swap(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        vm.stopPrank();
    }

    function test_safeUnwindSwap_success_basicTest() public {
        setupUnwindSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 unwindAmount = 100e18;
        uint256 minReferenceOut = 50e18;
        uint256 minSwapTokenOut = 50e18;

        // Get preview of the unwind swap for reference
        (uint256 previewReceivedCst, uint256 previewReceivedRef,) = corkPoolManager.previewUnwindSwap(defaultCurrencyId, unwindAmount);

        // Record initial balances
        uint256 receiverRefAssetBefore = referenceAsset.balanceOf(RECEIVER);
        uint256 receiverSwapTokenBefore = swapToken.balanceOf(RECEIVER);

        // Transfer collateral to adapter and record balances
        collateralAsset.transfer(address(corkAdapter), unwindAmount);

        uint256 adapterCollateralBefore = collateralAsset.balanceOf(address(corkAdapter));

        // Execute unwind swap
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        // Verify results using scoped variables
        {
            uint256 receiverRefAssetAfter = referenceAsset.balanceOf(RECEIVER);
            uint256 receiverSwapTokenAfter = swapToken.balanceOf(RECEIVER);
            uint256 adapterCollateralAfter = collateralAsset.balanceOf(address(corkAdapter));

            uint256 actualCollateralUsed = adapterCollateralBefore - adapterCollateralAfter;
            uint256 actualRefAssetReceived = receiverRefAssetAfter - receiverRefAssetBefore;
            uint256 actualSwapTokenReceived = receiverSwapTokenAfter - receiverSwapTokenBefore;

            assertEq(actualCollateralUsed, unwindAmount, "Should use exactly the specified collateral amount");
            assertEq(actualRefAssetReceived, previewReceivedRef, "Should receive preview reference asset amount");
            assertEq(actualSwapTokenReceived, previewReceivedCst, "Should receive preview swap token amount");
            assertGe(actualRefAssetReceived, minReferenceOut, "Should receive at least minimum reference assets");
            assertGe(actualSwapTokenReceived, minSwapTokenOut, "Should receive at least minimum swap tokens");
        }

        vm.stopPrank();
    }

    function test_safeUnwindSwap_success_withMaxAmount() public {
        setupUnwindSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 minReferenceOut = 50e18;
        uint256 minSwapTokenOut = 50e18;

        // Transfer collateral to adapter
        uint256 transferAmount = 200e18;
        collateralAsset.transfer(address(corkAdapter), transferAmount);

        uint256 adapterCollateralBefore = collateralAsset.balanceOf(address(corkAdapter));

        // Execute unwind swap with type(uint256).max to use all adapter balance
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: type(uint256).max, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        // Verify all collateral was used
        uint256 adapterCollateralAfter = collateralAsset.balanceOf(address(corkAdapter));
        uint256 actualCollateralUsed = adapterCollateralBefore - adapterCollateralAfter;

        assertEq(actualCollateralUsed, transferAmount, "Should use all available collateral when using max amount");
        assertEq(adapterCollateralAfter, 0, "Adapter should have no collateral left");

        vm.stopPrank();
    }

    function test_safeUnwindSwap_revertsOnDeadlineExceeded() public {
        setupUnwindSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 unwindAmount = 100e18;
        uint256 minReferenceOut = 50e18;
        uint256 minSwapTokenOut = 50e18;

        vm.expectRevert(ErrorsLib.DeadlineExceeded.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp - 1}));

        vm.stopPrank();
    }

    function test_safeUnwindSwap_revertsOnZeroReceiver() public {
        setupUnwindSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 unwindAmount = 100e18;
        uint256 minReferenceOut = 50e18;
        uint256 minSwapTokenOut = 50e18;

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: address(0), minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeUnwindSwap_revertsOnZeroAmount() public {
        setupUnwindSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 minReferenceOut = 50e18;
        uint256 minSwapTokenOut = 50e18;

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: 0, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeUnwindSwap_revertsOnSlippageExceeded_minReferenceOut() public {
        setupUnwindSwapTest();

        uint256 unwindAmount = 100e18;
        uint256 minReferenceOut = type(uint256).max; // Very high minimum to trigger slippage
        uint256 minSwapTokenOut = 1;

        // Transfer collateral to adapter
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.transfer(address(corkAdapter), unwindAmount);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeUnwindSwap_revertsOnSlippageExceeded_minSwapTokenOut() public {
        setupUnwindSwapTest();

        uint256 unwindAmount = 100e18;
        uint256 minReferenceOut = 1;
        uint256 minSwapTokenOut = type(uint256).max; // Very high minimum to trigger slippage

        // Transfer collateral to adapter
        vm.startPrank(DEFAULT_ADDRESS);
        collateralAsset.transfer(address(corkAdapter), unwindAmount);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeUnwindSwap_revertsOnUnauthorizedCaller() public {
        setupUnwindSwapTest();

        uint256 unwindAmount = 100e18;
        uint256 minReferenceOut = 50e18;
        uint256 minSwapTokenOut = 50e18;

        vm.prank(address(0x999));
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));
    }

    function test_safeUnwindSwap_revertsOnInsufficientBalance() public {
        setupUnwindSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 unwindAmount = 1000e18; // More than available
        uint256 minReferenceOut = 1;
        uint256 minSwapTokenOut = 1;

        // Don't transfer enough collateral to adapter
        collateralAsset.transfer(address(corkAdapter), 50e18);

        vm.expectRevert();
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultCurrencyId, collateralAssetsIn: unwindAmount, receiver: RECEIVER, minReferenceAssetsOut: minReferenceOut, minCstSharesOut: minSwapTokenOut, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }
}
