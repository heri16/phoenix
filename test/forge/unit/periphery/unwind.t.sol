// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Helper} from "../../Helper.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {CorkPoolAdapter} from "contracts/periphery/CorkPoolAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract CorkPoolAdapterUnwindTest is Helper {
    address constant RECEIVER = address(0x123);
    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant EXPIRY = 30 days;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare swapToken;
    PoolShare principalToken;

    struct UnwindBalances {
        uint256 peripheryCollateral;
        uint256 peripheryPT;
        uint256 peripheryCST;
        uint256 defaultAddressCollateral;
        uint256 defaultAddressPT;
        uint256 defaultAddressCST;
        uint256 receiverCollateral;
        uint256 receiverPT;
        uint256 receiverCST;
        uint256 corkCollateral;
    }

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        deployPeriphery();
        vm.stopPrank();
    }

    function setupDifferentDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (uint8, uint8) {
        raDecimals = uint8(bound(raDecimals, TARGET_DECIMALS, MAX_DECIMALS));
        paDecimals = uint8(bound(paDecimals, TARGET_DECIMALS, MAX_DECIMALS));

        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY, raDecimals, paDecimals);

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

        return (raDecimals, paDecimals);
    }

    function setupShareTokens(uint256 shareAmount18) internal {
        // Convert to native decimals for collateral transfer
        uint256 collateralAssetAmount = TransferHelper.fixedToTokenNativeDecimals(shareAmount18 * 2, collateralAsset.decimals());

        // First deposit to get shares
        corkPool.deposit(defaultCurrencyId, collateralAssetAmount, DEFAULT_ADDRESS);

        // Transfer shares to periphery
        principalToken.transfer(address(corkPoolAdapter), shareAmount18);
        swapToken.transfer(address(corkPoolAdapter), shareAmount18);
    }

    function test_unwindDeposit_success_18decimals() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        UnwindBalances memory balancesBefore = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        UnwindBalances memory balancesAfter = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        assertEq(balancesAfter.peripheryCollateral, balancesBefore.peripheryCollateral, "Periphery collateral should not change");
        assertEq(balancesAfter.peripheryPT, balancesBefore.peripheryPT - shareAmount, "Periphery CPT balance should decrease by share amount");
        assertEq(balancesAfter.peripheryCST, balancesBefore.peripheryCST - shareAmount, "Periphery CST balance should decrease by share amount");
        assertEq(balancesAfter.defaultAddressCollateral, balancesBefore.defaultAddressCollateral, "DEFAULT_ADDRESS collateral should remain same");
        assertGt(balancesAfter.receiverCollateral, balancesBefore.receiverCollateral, "Receiver collateral should increase");
        assertEq(balancesAfter.receiverPT, balancesBefore.receiverPT, "Receiver CPT should remain same");
        assertEq(balancesAfter.receiverCST, balancesBefore.receiverCST, "Receiver CST should remain same");

        vm.stopPrank();
    }

    function testFuzz_unwindDeposit_differentDecimals(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded share amount in 18 decimals
        uint256 hardcodedShares18 = 50e18;

        setupShareTokens(hardcodedShares18);

        UnwindBalances memory before = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: collateralAsset.balanceOf(address(corkPool))
        });

        uint256 out = TransferHelper.normalizeDecimals(hardcodedShares18, 18, raDecimals);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, out, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        UnwindBalances memory _after = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: collateralAsset.balanceOf(address(corkPool))
        });

        assertEq(_after.peripheryCollateral, before.peripheryCollateral, "Periphery collateral should not change");
        assertEq(_after.peripheryPT, before.peripheryPT - hardcodedShares18, "Periphery CPT should decrease by share amount");
        assertEq(_after.peripheryCST, before.peripheryCST - hardcodedShares18, "Periphery CST should decrease by share amount");
        assertEq(_after.defaultAddressCollateral, before.defaultAddressCollateral, "DEFAULT_ADDRESS collateral should remain same");
        assertEq(_after.defaultAddressPT, before.defaultAddressPT, "DEFAULT_ADDRESS CPT should remain same");
        assertEq(_after.defaultAddressCST, before.defaultAddressCST, "DEFAULT_ADDRESS CST should remain same");
        assertEq(_after.receiverCollateral, before.receiverCollateral + out, "Receiver collateral should increase");
        assertGe(_after.receiverPT, before.receiverPT, "Receiver CPT should not decrease");
        assertGe(_after.receiverCST, before.receiverCST, "Receiver CST should not decrease");
        assertLe(_after.corkCollateral, before.corkCollateral, "Cork collateral should decrease or stay same");

        vm.stopPrank();
    }

    function test_unwindDeposit_maxAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        uint256 peripheryPTBefore = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 peripheryCSBefore = swapToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverCSBefore = swapToken.balanceOf(RECEIVER);

        // Use the minimum balance (which should be shareAmount since both CPT and CST have the same amount)
        uint256 minBalance = shareAmount < shareAmount ? shareAmount : shareAmount; // Both are equal, so use shareAmount
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        uint256 peripheryPTAfter = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 peripheryCSAfter = swapToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverCSAfter = swapToken.balanceOf(RECEIVER);

        // Should use minimum (50e18) and refund excess CPT
        assertEq(peripheryPTAfter, 0, "All CPT should be consumed or refunded");
        assertEq(peripheryCSAfter, 0, "All CST should be consumed");
        assertGt(receiverCollateralAfter, receiverCollateralBefore, "Receiver collateral should increase");
        assertEq(receiverCSAfter, receiverCSBefore, "Receiver CST should remain same");

        vm.stopPrank();
    }

    function testFuzz_unwindDeposit_maxAmountDifferentDecimals(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        UnwindBalances memory balancesBefore = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        // to get accurate value
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 0);
        // Calculate the amount in collateral decimals (since shares are 1:1 with collateral)
        uint256 collateralAmount = TransferHelper.fixedToTokenNativeDecimals(shareAmount, collateralAsset.decimals());
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, collateralAmount, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        UnwindBalances memory balancesAfter = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        assertEq(balancesAfter.peripheryPT, 0, "All CPT should be consumed or refunded");
        assertEq(balancesAfter.peripheryCST, 0, "All CST should be consumed");
        assertEq(balancesAfter.receiverCollateral, balancesBefore.receiverCollateral + TransferHelper.normalizeDecimals(shareAmount, 18, raDecimals), "Receiver collateral should increase");
        assertEq(balancesAfter.receiverCST, balancesBefore.receiverCST, "Receiver CST should remain same");

        vm.stopPrank();
    }

    function test_unwindMint_success_18decimals() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        UnwindBalances memory balancesBefore = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        UnwindBalances memory balancesAfter = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        assertEq(balancesAfter.peripheryCollateral, balancesBefore.peripheryCollateral, "Periphery collateral should not change");
        assertEq(balancesAfter.peripheryPT, balancesBefore.peripheryPT - shareAmount, "Periphery CPT balance should decrease by share amount");
        assertEq(balancesAfter.peripheryCST, balancesBefore.peripheryCST - shareAmount, "Periphery CST balance should decrease by share amount");
        assertEq(balancesAfter.defaultAddressCollateral, balancesBefore.defaultAddressCollateral, "DEFAULT_ADDRESS collateral should remain same");
        assertEq(balancesAfter.receiverCollateral, balancesBefore.receiverCollateral + shareAmount, "Receiver collateral should increase");
        assertEq(balancesAfter.receiverPT, balancesBefore.receiverPT, "Receiver CPT should remain same");
        assertEq(balancesAfter.receiverCST, balancesBefore.receiverCST, "Receiver CST should remain same");

        vm.stopPrank();
    }

    function testFuzz_unwindMint_differentDecimals(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (uint8 boundedRA, uint8 boundedPA) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded share amount in 18 decimals
        uint256 hardcodedShares18 = 50e18;
        setupShareTokens(hardcodedShares18);

        UnwindBalances memory before = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: collateralAsset.balanceOf(address(corkPool))
        });

        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, hardcodedShares18, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        UnwindBalances memory _after = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: collateralAsset.balanceOf(address(corkPool))
        });

        assertEq(_after.peripheryCollateral, before.peripheryCollateral, "Periphery collateral should not change");
        assertEq(_after.peripheryPT, before.peripheryPT - hardcodedShares18, "Periphery CPT should decrease by share amount");
        assertEq(_after.peripheryCST, before.peripheryCST - hardcodedShares18, "Periphery CST should decrease by share amount");
        assertEq(_after.defaultAddressCollateral, before.defaultAddressCollateral, "DEFAULT_ADDRESS collateral should remain same");
        assertEq(_after.defaultAddressPT, before.defaultAddressPT, "DEFAULT_ADDRESS CPT should remain same");
        assertEq(_after.defaultAddressCST, before.defaultAddressCST, "DEFAULT_ADDRESS CST should remain same");
        assertGt(_after.receiverCollateral, before.receiverCollateral, "Receiver collateral should increase");
        assertGe(_after.receiverPT, before.receiverPT, "Receiver CPT should not decrease");
        assertGe(_after.receiverCST, before.receiverCST, "Receiver CST should not decrease");
        assertLe(_after.corkCollateral, before.corkCollateral, "Cork collateral should decrease or stay same");

        vm.stopPrank();
    }

    function test_unwindMint_maxAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        uint256 peripheryPTBefore = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 peripheryCSBefore = swapToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverCSBefore = swapToken.balanceOf(RECEIVER);

        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, type(uint256).max, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        uint256 peripheryPTAfter = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 peripheryCSAfter = swapToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverCSAfter = swapToken.balanceOf(RECEIVER);

        // Should use minimum (50e18) and refund excess CST
        assertEq(peripheryPTAfter, 0, "All CPT should be consumed");
        assertEq(peripheryCSAfter, 0, "All CST should be consumed");
        assertEq(receiverCollateralAfter, shareAmount, "Receiver collateral should increase");
        assertEq(receiverPTAfter, receiverPTBefore, "Receiver CPT should remain same");

        vm.stopPrank();
    }

    function testFuzz_unwindMint_maxAmountDifferentDecimals(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);
        UnwindBalances memory balancesBefore = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, type(uint256).max, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        UnwindBalances memory balancesAfter = UnwindBalances({
            peripheryCollateral: collateralAsset.balanceOf(address(corkPoolAdapter)),
            peripheryPT: principalToken.balanceOf(address(corkPoolAdapter)),
            peripheryCST: swapToken.balanceOf(address(corkPoolAdapter)),
            defaultAddressCollateral: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            defaultAddressPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            defaultAddressCST: swapToken.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverCST: swapToken.balanceOf(RECEIVER),
            corkCollateral: 0
        });

        assertEq(balancesAfter.peripheryPT, 0, "All CPT should be consumed");
        assertEq(balancesAfter.peripheryCST, 0, "All CST should be consumed or refunded");
        assertEq(balancesAfter.receiverCollateral, balancesBefore.receiverCollateral + TransferHelper.normalizeDecimals(shareAmount, 18, raDecimals), "Receiver collateral should increase");
        assertEq(balancesAfter.receiverPT, balancesBefore.receiverPT, "Receiver CPT should remain same");

        vm.stopPrank();
    }

    // Error case tests for safeUnwindDeposit
    function test_unwindDeposit_revertsOnZeroReceiver() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, 50e18, address(corkPoolAdapter), address(0), type(uint256).max, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindDeposit_revertsOnZeroOwner() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, 50e18, address(0), RECEIVER, type(uint256).max, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindDeposit_revertsOnZeroAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAmount.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, 0, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindDeposit_revertsOnZeroAmountExplicit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAmount.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, 0, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindDeposit_revertsOnUnauthorizedCaller() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);
        vm.stopPrank();

        vm.prank(address(0x999));
        vm.expectRevert(IErrors.UnauthorizedSender.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, 50e18, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);
    }

    function test_unwindDeposit_revertsOnSlippageExceeded() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        // Set maxSharesIn to a very low value to trigger slippage
        uint256 maxSharesIn = shareAmount / 10; // Much lower than expected shares needed

        vm.expectRevert(IErrors.SlippageExceeded.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, maxSharesIn, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindDeposit_revertsOnExpiredDeadline() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, 50e18, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp - 1);

        vm.stopPrank();
    }

    // Error case tests for safeUnwindMint
    function test_unwindMint_revertsOnZeroReceiver() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, 50e18, address(corkPoolAdapter), address(0), 0, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindMint_revertsOnZeroOwner() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, 50e18, address(0), RECEIVER, 0, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindMint_revertsOnZeroAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, 0, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindMint_revertsOnZeroAmountWithMaxAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, type(uint256).max, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindMint_revertsOnUnauthorizedCaller() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);
        vm.stopPrank();

        vm.prank(address(0x999));
        vm.expectRevert(IErrors.UnauthorizedSender.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, 50e18, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);
    }

    function test_unwindMint_revertsOnSlippageExceeded() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        // Set minAssetsOut to a very high value to trigger slippage
        uint256 minAssetsOut = shareAmount * 2; // Expect double the collateral than possible

        vm.expectRevert(IErrors.SlippageExceeded.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, minAssetsOut, block.timestamp);

        vm.stopPrank();
    }

    function test_unwindMint_revertsOnExpiredDeadline() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, 50e18, address(corkPoolAdapter), RECEIVER, 0, block.timestamp - 1);

        vm.stopPrank();
    }

    // Balance consistency tests
    function test_balanceConsistency_unwindDeposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        uint256 totalSupplyBefore = collateralAsset.totalSupply();
        uint256 totalPTSupplyBefore = principalToken.totalSupply();
        uint256 totalCSTSupplyBefore = swapToken.totalSupply();

        corkPoolAdapter.safeUnwindDeposit(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, type(uint256).max, block.timestamp);

        uint256 totalSupplyAfter = collateralAsset.totalSupply();
        uint256 totalPTSupplyAfter = principalToken.totalSupply();
        uint256 totalCSTSupplyAfter = swapToken.totalSupply();

        assertEq(totalSupplyAfter, totalSupplyBefore, "Collateral total supply should remain constant");
        assertLt(totalPTSupplyAfter, totalPTSupplyBefore, "CPT total supply should decrease");
        assertLt(totalCSTSupplyAfter, totalCSTSupplyBefore, "CST total supply should decrease");
        assertEq(totalPTSupplyAfter, totalPTSupplyBefore - shareAmount, "CPT should decrease by exact amount");
        assertEq(totalCSTSupplyAfter, totalCSTSupplyBefore - shareAmount, "CST should decrease by exact amount");

        vm.stopPrank();
    }

    function test_balanceConsistency_unwindMint() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shareAmount = 50e18;
        setupShareTokens(shareAmount);

        uint256 totalSupplyBefore = collateralAsset.totalSupply();
        uint256 totalPTSupplyBefore = principalToken.totalSupply();
        uint256 totalCSTSupplyBefore = swapToken.totalSupply();

        corkPoolAdapter.safeUnwindMint(defaultCurrencyId, shareAmount, address(corkPoolAdapter), RECEIVER, 0, block.timestamp);

        uint256 totalSupplyAfter = collateralAsset.totalSupply();
        uint256 totalPTSupplyAfter = principalToken.totalSupply();
        uint256 totalCSTSupplyAfter = swapToken.totalSupply();

        assertEq(totalSupplyAfter, totalSupplyBefore, "Collateral total supply should remain constant");
        assertLt(totalPTSupplyAfter, totalPTSupplyBefore, "CPT total supply should decrease");
        assertLt(totalCSTSupplyAfter, totalCSTSupplyBefore, "CST total supply should decrease");
        assertEq(totalPTSupplyAfter, totalPTSupplyBefore - shareAmount, "CPT should decrease by exact amount");
        assertEq(totalCSTSupplyAfter, totalCSTSupplyBefore - shareAmount, "CST should decrease by exact amount");

        vm.stopPrank();
    }
}
