// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {CorkPoolAdapter} from "contracts/periphery/CorkPoolAdapter.sol";
import "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract CorkPoolAdapterTest is Helper {
    address constant RECEIVER = address(0x123);
    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant EXPIRY = 30 days;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare swapToken;
    PoolShare principalToken;

    struct Balances {
        uint256 periphery;
        uint256 defaultAddress;
        uint256 receiverCollateral;
        uint256 receiverPT;
        uint256 receiverDS;
        uint256 cork;
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

    function test_mint_success_18decimals() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shares = 100e18;
        collateralAsset.transfer(address(corkPoolAdapter), INITIAL_BALANCE);

        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSBefore = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        corkPoolAdapter.safeMint(defaultCurrencyId, shares, RECEIVER, type(uint256).max, block.timestamp);

        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSAfter = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);

        assertLt(peripheryBalanceAfter, peripheryBalanceBefore, "Periphery balance should decrease");
        assertEq(defaultAddressBalanceAfter, defaultAddressBalanceBefore, "DEFAULT_ADDRESS balance should remain same");
        assertEq(receiverCollateralAfter, receiverCollateralBefore, "Receiver collateral balance should remain same");
        assertGt(receiverPTAfter, receiverPTBefore, "Receiver CPT balance should increase");
        assertGt(receiverDSAfter, receiverDSBefore, "Receiver CST balance should increase");

        vm.stopPrank();
    }

    function testFuzz_mint_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 shares) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (uint8 boundedRA, uint8 boundedPA) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded share amount in 18 decimals
        uint256 hardcodedShares = 100e18;
        shares = bound(shares, 1e18, hardcodedShares);

        // Convert hardcoded 18-decimal amount to collateral asset's native decimals
        uint256 transferAmount = TransferHelper.fixedToTokenNativeDecimals(2000e18, collateralAsset.decimals());
        collateralAsset.transfer(address(corkPoolAdapter), transferAmount);

        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSBefore = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceBefore = collateralAsset.balanceOf(address(corkPool));

        corkPoolAdapter.safeMint(defaultCurrencyId, shares, RECEIVER, type(uint256).max, block.timestamp);

        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSAfter = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceAfter = collateralAsset.balanceOf(address(corkPool));

        assertLe(peripheryBalanceAfter, peripheryBalanceBefore, "Periphery balance should not increase");
        assertEq(defaultAddressBalanceAfter, defaultAddressBalanceBefore, "DEFAULT_ADDRESS balance should remain same");
        assertEq(receiverCollateralAfter, receiverCollateralBefore, "Receiver collateral balance should remain same");
        assertGe(receiverPTAfter, receiverPTBefore, "Receiver CPT balance should not decrease");
        assertGe(receiverDSAfter, receiverDSBefore, "Receiver CST balance should not decrease");
        assertGe(corkBalanceAfter, corkBalanceBefore, "Cork balance should not decrease");

        vm.stopPrank();
    }

    function test_mint_revertsOnZeroReceiver() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolAdapter.safeMint(defaultCurrencyId, 100e18, address(0), type(uint256).max, block.timestamp);

        vm.stopPrank();
    }

    function test_mint_revertsOnZeroShares() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkPoolAdapter.safeMint(defaultCurrencyId, 0, RECEIVER, type(uint256).max, block.timestamp);

        vm.stopPrank();
    }

    function test_mint_revertsOnUnauthorizedCaller() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);
        vm.stopPrank();

        vm.prank(address(0x999));
        vm.expectRevert(IErrors.UnauthorizedSender.selector);
        corkPoolAdapter.safeMint(defaultCurrencyId, 100e18, RECEIVER, type(uint256).max, block.timestamp);
    }

    function test_deposit_success_18decimals() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 assets = 100e18;
        collateralAsset.transfer(address(corkPoolAdapter), INITIAL_BALANCE);

        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSBefore = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceBefore = collateralAsset.balanceOf(address(corkPool));

        corkPoolAdapter.safeDeposit(defaultCurrencyId, assets, RECEIVER, 0, block.timestamp);

        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSAfter = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceAfter = collateralAsset.balanceOf(address(corkPool));

        assertEq(peripheryBalanceAfter, peripheryBalanceBefore - assets, "Periphery balance should decrease by assets");
        assertEq(defaultAddressBalanceAfter, defaultAddressBalanceBefore, "DEFAULT_ADDRESS balance should remain same");
        assertEq(receiverCollateralAfter, receiverCollateralBefore, "Receiver collateral balance should remain same");
        assertGt(receiverPTAfter, receiverPTBefore, "Receiver CPT balance should increase");
        assertGt(receiverDSAfter, receiverDSBefore, "Receiver CST balance should increase");
        assertGe(corkBalanceAfter, corkBalanceBefore, "Cork balance should not decrease");

        vm.stopPrank();
    }

    function testFuzz_deposit_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 assets) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (uint8 boundedRA, uint8 boundedPA) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded asset amount in 18 decimals, then convert to native decimals
        uint256 hardcodedAssets18 = 100e18;
        uint256 hardcodedAssetsNative = TransferHelper.fixedToTokenNativeDecimals(hardcodedAssets18, collateralAsset.decimals());
        assets = bound(assets, TransferHelper.fixedToTokenNativeDecimals(1e18, collateralAsset.decimals()), hardcodedAssetsNative);

        // Transfer amount in native decimals
        uint256 transferAmount = TransferHelper.fixedToTokenNativeDecimals(2000e18, collateralAsset.decimals());
        collateralAsset.transfer(address(corkPoolAdapter), transferAmount);

        Balances memory before = Balances({
            periphery: collateralAsset.balanceOf(address(corkPoolAdapter)),
            defaultAddress: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverDS: swapToken.balanceOf(RECEIVER),
            cork: collateralAsset.balanceOf(address(corkPool))
        });

        corkPoolAdapter.safeDeposit(defaultCurrencyId, assets, RECEIVER, 0, block.timestamp);

        Balances memory _after = Balances({
            periphery: collateralAsset.balanceOf(address(corkPoolAdapter)),
            defaultAddress: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            receiverDS: swapToken.balanceOf(RECEIVER),
            cork: collateralAsset.balanceOf(address(corkPool))
        });

        assertEq(_after.periphery, before.periphery - assets, "Periphery balance should decrease by exact assets");
        assertEq(_after.defaultAddress, before.defaultAddress, "DEFAULT_ADDRESS balance should remain same");
        assertEq(_after.receiverCollateral, before.receiverCollateral, "Receiver collateral balance should remain same");
        assertGe(_after.receiverPT, before.receiverPT, "Receiver CPT balance should not decrease");
        assertGe(_after.receiverDS, before.receiverDS, "Receiver CST balance should not decrease");
        assertGe(_after.cork, before.cork, "Cork balance should not decrease");

        vm.stopPrank();
    }

    function test_deposit_maxAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 mintAmount = 500e18;
        collateralAsset.transfer(address(corkPoolAdapter), mintAmount);

        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSBefore = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);

        corkPoolAdapter.safeDeposit(defaultCurrencyId, mintAmount, RECEIVER, 0, block.timestamp);

        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSAfter = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);

        assertEq(peripheryBalanceAfter, 0, "Periphery should have zero balance after max deposit");
        assertEq(defaultAddressBalanceAfter, defaultAddressBalanceBefore, "DEFAULT_ADDRESS balance should remain same");
        assertEq(receiverCollateralAfter, receiverCollateralBefore, "Receiver collateral balance should remain same");
        assertGt(receiverPTAfter, receiverPTBefore, "Receiver CPT balance should increase");
        assertGt(receiverDSAfter, receiverDSBefore, "Receiver CST balance should increase");

        vm.stopPrank();
    }

    function testFuzz_deposit_maxAmountDifferentDecimals(uint8 raDecimals, uint8 paDecimals) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (uint8 boundedRA, uint8 boundedPA) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded amount in 18 decimals, convert to native decimals
        uint256 transferAmount = TransferHelper.fixedToTokenNativeDecimals(500e18, collateralAsset.decimals());
        collateralAsset.transfer(address(corkPoolAdapter), transferAmount);

        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTBefore = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSBefore = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceBefore = collateralAsset.balanceOf(address(corkPool));

        corkPoolAdapter.safeDeposit(defaultCurrencyId, transferAmount, RECEIVER, 0, block.timestamp);

        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverPTAfter = principalToken.balanceOf(RECEIVER);
        uint256 receiverDSAfter = swapToken.balanceOf(RECEIVER);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceAfter = collateralAsset.balanceOf(address(corkPool));

        assertEq(peripheryBalanceAfter, 0, "Periphery should have zero balance after max deposit");
        assertEq(defaultAddressBalanceAfter, defaultAddressBalanceBefore, "DEFAULT_ADDRESS balance should remain same");
        assertEq(receiverCollateralAfter, receiverCollateralBefore, "Receiver collateral balance should remain same");
        assertGe(receiverPTAfter, receiverPTBefore, "Receiver CPT balance should not decrease");
        assertGe(receiverDSAfter, receiverDSBefore, "Receiver CST balance should not decrease");
        assertGe(corkBalanceAfter, corkBalanceBefore, "Cork balance should not decrease");

        vm.stopPrank();
    }

    function test_mint_revertsOnExpiredDeadline() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkPoolAdapter.safeMint(defaultCurrencyId, 100e18, RECEIVER, type(uint256).max, block.timestamp - 1);

        vm.stopPrank();
    }

    function test_mint_revertsOnSlippageExceeded() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shares = 100e18;
        collateralAsset.transfer(address(corkPoolAdapter), INITIAL_BALANCE);

        // Set maxAssetsIn to a very low value to trigger slippage
        uint256 maxAssetsIn = 1; // Much lower than expected cost

        vm.expectRevert(IErrors.SlippageExceeded.selector);
        corkPoolAdapter.safeMint(defaultCurrencyId, shares, RECEIVER, maxAssetsIn, block.timestamp);

        vm.stopPrank();
    }

    function test_deposit_revertsOnZeroReceiver() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkPoolAdapter.safeDeposit(defaultCurrencyId, 100e18, address(0), 0, block.timestamp);

        vm.stopPrank();
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.ZeroAmount.selector);
        corkPoolAdapter.safeDeposit(defaultCurrencyId, 0, RECEIVER, 0, block.timestamp);

        vm.stopPrank();
    }

    function test_deposit_revertsOnUnauthorizedCaller() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);
        vm.stopPrank();

        vm.prank(address(0x999));
        vm.expectRevert(IErrors.UnauthorizedSender.selector);
        corkPoolAdapter.safeDeposit(defaultCurrencyId, 100e18, RECEIVER, 0, block.timestamp);
    }

    function test_deposit_revertsOnSlippageExceeded() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 assets = 100e18;
        collateralAsset.transfer(address(corkPoolAdapter), INITIAL_BALANCE);

        // Set minSharesOut to a very high value to trigger slippage
        uint256 minSharesOut = assets * 2; // Expect double the shares than possible

        vm.expectRevert(IErrors.SlippageExceeded.selector);
        corkPoolAdapter.safeDeposit(defaultCurrencyId, assets, RECEIVER, minSharesOut, block.timestamp);

        vm.stopPrank();
    }

    function test_deposit_revertsOnExpiredDeadline() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkPoolAdapter.safeDeposit(defaultCurrencyId, 100e18, RECEIVER, 0, block.timestamp - 1);

        vm.stopPrank();
    }

    function test_balanceConsistency_mint() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 shares = 100e18;
        collateralAsset.transfer(address(corkPoolAdapter), INITIAL_BALANCE);

        uint256 totalSupplyBefore = collateralAsset.totalSupply();
        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverBalanceBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceBefore = collateralAsset.balanceOf(address(corkPool));

        corkPoolAdapter.safeMint(defaultCurrencyId, shares, RECEIVER, type(uint256).max, block.timestamp);

        uint256 totalSupplyAfter = collateralAsset.totalSupply();
        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverBalanceAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceAfter = collateralAsset.balanceOf(address(corkPool));

        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain constant");

        uint256 totalBalanceBefore = peripheryBalanceBefore + defaultAddressBalanceBefore + receiverBalanceBefore + corkBalanceBefore;
        uint256 totalBalanceAfter = peripheryBalanceAfter + defaultAddressBalanceAfter + receiverBalanceAfter + corkBalanceAfter;
        assertEq(totalBalanceAfter, totalBalanceBefore, "Sum of all balances should remain constant");

        vm.stopPrank();
    }

    function test_balanceConsistency_deposit() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 assets = 100e18;
        collateralAsset.transfer(address(corkPoolAdapter), INITIAL_BALANCE);

        uint256 totalSupplyBefore = collateralAsset.totalSupply();
        uint256 peripheryBalanceBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverBalanceBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceBefore = collateralAsset.balanceOf(address(corkPool));

        corkPoolAdapter.safeDeposit(defaultCurrencyId, assets, RECEIVER, 0, block.timestamp);

        uint256 totalSupplyAfter = collateralAsset.totalSupply();
        uint256 peripheryBalanceAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressBalanceAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverBalanceAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 corkBalanceAfter = collateralAsset.balanceOf(address(corkPool));

        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain constant");

        uint256 totalBalanceBefore = peripheryBalanceBefore + defaultAddressBalanceBefore + receiverBalanceBefore + corkBalanceBefore;
        uint256 totalBalanceAfter = peripheryBalanceAfter + defaultAddressBalanceAfter + receiverBalanceAfter + corkBalanceAfter;
        assertEq(totalBalanceAfter, totalBalanceBefore, "Sum of all balances should remain constant");

        vm.stopPrank();
    }

    function testFuzz_shareTokenBalances_mint(uint8 raDecimals, uint8 paDecimals, uint256 shares) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (uint8 boundedRA, uint8 boundedPA) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded share amount in 18 decimals
        uint256 hardcodedShares18 = 500e18;
        shares = bound(shares, 1e18, hardcodedShares18);

        // Convert hardcoded asset amount to native decimals for transfer
        uint256 transferAmount = TransferHelper.fixedToTokenNativeDecimals(1000e18, collateralAsset.decimals());
        collateralAsset.transfer(address(corkPoolAdapter), transferAmount);

        uint256 ptBalanceBefore = principalToken.balanceOf(RECEIVER);
        uint256 dsBalanceBefore = swapToken.balanceOf(RECEIVER);
        uint256 ptBalanceDefaultBefore = principalToken.balanceOf(DEFAULT_ADDRESS);
        uint256 dsBalanceDefaultBefore = swapToken.balanceOf(DEFAULT_ADDRESS);

        corkPoolAdapter.safeMint(defaultCurrencyId, shares, RECEIVER, type(uint256).max, block.timestamp);

        uint256 ptBalanceAfter = principalToken.balanceOf(RECEIVER);
        uint256 dsBalanceAfter = swapToken.balanceOf(RECEIVER);
        uint256 ptBalanceDefaultAfter = principalToken.balanceOf(DEFAULT_ADDRESS);
        uint256 dsBalanceDefaultAfter = swapToken.balanceOf(DEFAULT_ADDRESS);

        assertGt(ptBalanceAfter, ptBalanceBefore, "Receiver CPT balance should increase");
        assertGt(dsBalanceAfter, dsBalanceBefore, "Receiver CST balance should increase");
        assertEq(ptBalanceDefaultAfter, ptBalanceDefaultBefore, "DEFAULT_ADDRESS CPT balance should remain same");
        assertEq(dsBalanceDefaultAfter, dsBalanceDefaultBefore, "DEFAULT_ADDRESS CST balance should remain same");
        assertEq(ptBalanceAfter - ptBalanceBefore, dsBalanceAfter - dsBalanceBefore, "CPT and CST should be minted equally");

        vm.stopPrank();
    }

    function testFuzz_shareTokenBalances_deposit(uint8 raDecimals, uint8 paDecimals, uint256 assets) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (uint8 boundedRA, uint8 boundedPA) = setupDifferentDecimals(raDecimals, paDecimals);

        // Use hardcoded asset amount in 18 decimals, convert to native decimals
        uint256 hardcodedAssets18 = 500e18;
        uint256 hardcodedAssetsNative = TransferHelper.fixedToTokenNativeDecimals(hardcodedAssets18, collateralAsset.decimals());
        assets = bound(assets, TransferHelper.fixedToTokenNativeDecimals(1e18, collateralAsset.decimals()), hardcodedAssetsNative);

        // Transfer amount in native decimals
        uint256 transferAmount = TransferHelper.fixedToTokenNativeDecimals(1000e18, collateralAsset.decimals());
        collateralAsset.transfer(address(corkPoolAdapter), transferAmount);

        uint256 ptBalanceBefore = principalToken.balanceOf(RECEIVER);
        uint256 dsBalanceBefore = swapToken.balanceOf(RECEIVER);
        uint256 ptBalanceDefaultBefore = principalToken.balanceOf(DEFAULT_ADDRESS);
        uint256 dsBalanceDefaultBefore = swapToken.balanceOf(DEFAULT_ADDRESS);

        corkPoolAdapter.safeDeposit(defaultCurrencyId, assets, RECEIVER, 0, block.timestamp);

        uint256 ptBalanceAfter = principalToken.balanceOf(RECEIVER);
        uint256 dsBalanceAfter = swapToken.balanceOf(RECEIVER);
        uint256 ptBalanceDefaultAfter = principalToken.balanceOf(DEFAULT_ADDRESS);
        uint256 dsBalanceDefaultAfter = swapToken.balanceOf(DEFAULT_ADDRESS);

        assertGt(ptBalanceAfter, ptBalanceBefore, "Receiver CPT balance should increase");
        assertGt(dsBalanceAfter, dsBalanceBefore, "Receiver CST balance should increase");
        assertEq(ptBalanceDefaultAfter, ptBalanceDefaultBefore, "DEFAULT_ADDRESS CPT balance should remain same");
        assertEq(dsBalanceDefaultAfter, dsBalanceDefaultBefore, "DEFAULT_ADDRESS CST balance should remain same");
        assertEq(ptBalanceAfter - ptBalanceBefore, dsBalanceAfter - dsBalanceBefore, "CPT and CST should be minted equally");

        vm.stopPrank();
    }
}
