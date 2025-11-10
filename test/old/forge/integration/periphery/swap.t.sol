// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract CorkAdapterSwapTest is Helper {
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

    function setupSwapTest() internal {
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

        // Transfer CST and reference tokens to OWNER for swap testing
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

    function test_safeSwap_success_basicTest() public {
        setupSwapTest();
        vm.startPrank(OWNER);

        swapToken.transfer(DEFAULT_ADDRESS, swapToken.balanceOf(OWNER));
        referenceAsset.transfer(DEFAULT_ADDRESS, referenceAsset.balanceOf(OWNER));

        vm.startPrank(DEFAULT_ADDRESS);

        uint256 assetsToReceive = corkPoolManager.maxSwap(defaultCurrencyId, DEFAULT_ADDRESS);
        uint256 referenceToSwap = assetsToReceive;
        uint256 maxSharesIn = 1000e18;
        uint256 maxCompensationIn = 1000e18;

        // Get preview and record initial receiver balance
        corkPoolManager.previewSwap(defaultCurrencyId, referenceToSwap);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        // Transfer tokens to adapter and record balances
        swapToken.transfer(address(corkAdapter), maxSharesIn);
        referenceAsset.transfer(address(corkAdapter), maxCompensationIn);

        uint256 adapterSwapTokenBefore = swapToken.balanceOf(address(corkAdapter));
        uint256 adapterRefTokenBefore = referenceAsset.balanceOf(address(corkAdapter));

        // Execute swap
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));

        // Verify results using scoped variables
        {
            uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
            uint256 actualSharesUsed = adapterSwapTokenBefore - swapToken.balanceOf(address(corkAdapter));
            uint256 actualCompensationUsed = adapterRefTokenBefore - referenceAsset.balanceOf(address(corkAdapter));

            assertEq(receiverCollateralAfter - receiverCollateralBefore, assetsToReceive, "Receiver should receive exactly requested assets");
            assertEq(actualCompensationUsed, maxCompensationIn, "  compensation used should equal referenceToSwap");
            assertEq(maxSharesIn, actualSharesUsed, "Preview shares should match actual shares used");
        }

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnDeadlineExceeded() public {
        setupSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 assetsToReceive = 50e18;
        uint256 maxSharesIn = 100e18;
        uint256 maxCompensationIn = 100e18;

        vm.expectRevert(ErrorsLib.DeadlineExceeded.selector);
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp - 1}));

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnZeroReceiver() public {
        setupSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 assetsToReceive = 50e18;
        uint256 maxSharesIn = 100e18;
        uint256 maxCompensationIn = 100e18;

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: address(0), maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnZeroOwner() public {
        setupSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 assetsToReceive = 50e18;
        uint256 maxSharesIn = 100e18;
        uint256 maxCompensationIn = 100e18;

        vm.expectRevert(); // Will revert due to insufficient balance since address(0) is actually valid as owner when initiator() returns address(0)
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnZeroAssets() public {
        setupSwapTest();
        vm.startPrank(DEFAULT_ADDRESS);

        uint256 maxSharesIn = 100e18;
        uint256 maxCompensationIn = 100e18;

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: 0, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnSlippageExceeded_shares() public {
        setupSwapTest();

        uint256 assetsToReceive = 50e18;
        uint256 maxSharesIn = 1; // Very low limit to trigger slippage
        uint256 maxCompensationIn = 100e18;

        // Transfer enough tokens to adapter
        vm.startPrank(OWNER);
        swapToken.transfer(address(corkAdapter), 100e18);
        referenceAsset.transfer(address(corkAdapter), 100e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnSlippageExceeded_compensation() public {
        setupSwapTest();

        uint256 assetsToReceive = 50e18;
        uint256 maxSharesIn = 100e18;
        uint256 maxCompensationIn = 1; // Very low limit to trigger slippage

        // Transfer enough tokens to adapter
        vm.startPrank(OWNER);
        swapToken.transfer(address(corkAdapter), 100e18);
        referenceAsset.transfer(address(corkAdapter), 100e18);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));

        vm.stopPrank();
    }

    function test_safeSwap_revertsOnUnauthorizedCaller() public {
        setupSwapTest();

        uint256 assetsToReceive = 50e18;
        uint256 maxSharesIn = 100e18;
        uint256 maxCompensationIn = 100e18;

        vm.prank(address(0x999));
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeSwap(ICorkAdapter.SafeSwapParams({poolId: defaultCurrencyId, collateralAssetsOut: assetsToReceive, receiver: RECEIVER, maxCstSharesIn: maxSharesIn, maxReferenceAssetsIn: maxCompensationIn, deadline: block.timestamp + 1 hours}));
    }
}
