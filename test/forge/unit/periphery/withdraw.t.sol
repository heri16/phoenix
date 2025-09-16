// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Helper} from "../../Helper.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ICorkPoolAdapter} from "contracts/interfaces/ICorkPoolAdapter.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {CorkPoolAdapter} from "contracts/periphery/CorkPoolAdapter.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract CorkPoolAdapterWithdrawTest is Helper {
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
        uint256 receiverReference;
        uint256 receiverPT;
        uint256 ownerPT;
        uint256 cork;
    }

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
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

        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 2 ether);

        return (raDecimals, paDecimals);
    }

    function setupWithShares() internal {
        setupDifferentDecimals(18, 18);

        // Deposit some collateral to get CPT tokens for DEFAULT_ADDRESS
        uint256 depositAmount = 500e18;
        collateralAsset.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);
        principalToken.approve(address(corkPoolAdapter), type(uint256).max);

        // Perform some swaps to generate reference assets in the pool
        uint256 swapAmount = 100e18;
        referenceAsset.approve(address(corkPool), type(uint256).max);
        corkPool.swap(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        // Fast forward time to expire the pool
        vm.warp(block.timestamp + EXPIRY + 1);

        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, 2 ether);
    }

    function test_withdraw_collateralOnly_success_approval() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 100e18;
        uint256 referenceOut = 0;

        // Transfer CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(DEFAULT_ADDRESS);
        principalToken.approve(address(corkPoolAdapter), cptBalance);

        uint256 peripheryPTBefore = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceBefore = referenceAsset.balanceOf(RECEIVER);

        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: referenceOut, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: cptBalance, deadline: block.timestamp}));

        uint256 peripheryPTAfter = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceAfter = referenceAsset.balanceOf(RECEIVER);

        assertEq(receiverCollateralAfter, receiverCollateralBefore + collateralOut, "Receiver should receive collateral");
        assertGe(receiverReferenceAfter, receiverReferenceBefore, "Receiver reference balance should increase by some amount");

        vm.stopPrank();
    }

    function test_withdraw_collateralOnly_success_transferred() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 100e18;
        uint256 referenceOut = 0;

        // Transfer CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(DEFAULT_ADDRESS);
        principalToken.transfer(address(corkPoolAdapter), cptBalance);

        uint256 peripheryPTBefore = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceBefore = referenceAsset.balanceOf(RECEIVER);

        // because pool adapter have the balance, we set it as the owner
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: referenceOut, owner: address(corkPoolAdapter), receiver: RECEIVER, maxSharesIn: cptBalance, deadline: block.timestamp}));

        uint256 peripheryPTAfter = principalToken.balanceOf(address(corkPoolAdapter));
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceAfter = referenceAsset.balanceOf(RECEIVER);

        assertEq(receiverCollateralAfter, receiverCollateralBefore + collateralOut, "Receiver should receive collateral");
        assertGe(receiverReferenceAfter, receiverReferenceBefore, "Receiver reference balance should increase by some amount");

        vm.stopPrank();
    }

    function test_withdraw_referenceOnly_success() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 0;
        uint256 referenceOut = 10e18;

        // Transfer CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(DEFAULT_ADDRESS);
        principalToken.approve(address(corkPoolAdapter), cptBalance);

        uint256 defaultAddressPTBefore = principalToken.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceBefore = referenceAsset.balanceOf(RECEIVER);

        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: referenceOut, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: cptBalance, deadline: block.timestamp}));

        uint256 defaultAddressPTAfter = principalToken.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceAfter = referenceAsset.balanceOf(RECEIVER);

        assertLt(defaultAddressPTAfter, defaultAddressPTBefore, "DEFAULT_ADDRESS CPT balance should decrease");
        assertApproxEqAbs(receiverReferenceAfter, receiverReferenceBefore + referenceOut, 1, "Receiver should receive requested reference asset");
        assertGt(receiverCollateralAfter, receiverCollateralBefore, "Receiver should also receive some collateral asset");

        vm.stopPrank();
    }

    function test_withdraw_revertsOnBothAssetsNonZero() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 100e18;
        uint256 referenceOut = 50e18; // Both non-zero should fail

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: referenceOut, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: 1000e18, deadline: block.timestamp}));

        vm.stopPrank();
    }

    function test_withdraw_revertsOnBothAssetsZero() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 0;
        uint256 referenceOut = 0; // Both zero should fail

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: referenceOut, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: 1000e18, deadline: block.timestamp}));

        vm.stopPrank();
    }

    function test_withdraw_revertsOnZeroReceiver() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: 100e18, referenceAssets: 0, owner: DEFAULT_ADDRESS, receiver: address(0), maxSharesIn: 1000e18, deadline: block.timestamp}));

        vm.stopPrank();
    }

    function test_withdraw_revertsOnZeroOwner() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: 100e18, referenceAssets: 0, owner: address(0), receiver: RECEIVER, maxSharesIn: 1000e18, deadline: block.timestamp}));

        vm.stopPrank();
    }

    function test_withdraw_revertsOnExpiredDeadline() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        vm.expectRevert(ErrorsLib.DeadlineExceeded.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: 100e18, referenceAssets: 0, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: 1000e18, deadline: block.timestamp - 1}));

        vm.stopPrank();
    }

    function test_withdraw_revertsOnSlippageExceeded() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 100e18;
        uint256 referenceOut = 0;

        // Transfer CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(DEFAULT_ADDRESS);
        principalToken.approve(address(corkPoolAdapter), cptBalance);

        // Set maxSharesIn to a very low value to trigger slippage
        uint256 maxSharesIn = 1; // Much lower than expected shares needed

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: referenceOut, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: maxSharesIn, deadline: block.timestamp}));

        vm.stopPrank();
    }

    function test_withdraw_revertsOnUnauthorizedCaller() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();
        vm.stopPrank();

        vm.prank(address(0x999));
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: 100e18, referenceAssets: 0, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: 1000e18, deadline: block.timestamp}));
    }

    function testFuzz_withdraw_differentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 collateralOut) public {
        vm.startPrank(DEFAULT_ADDRESS);
        (raDecimals, paDecimals) = setupDifferentDecimals(raDecimals, paDecimals);

        // Deposit some collateral to get CPT tokens for DEFAULT_ADDRESS
        uint256 depositAmount = TransferHelper.fixedToTokenNativeDecimals(500e18, collateralAsset.decimals());
        collateralAsset.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);
        principalToken.approve(address(corkPoolAdapter), type(uint256).max);

        // Perform some swaps to generate reference assets in the pool
        uint256 swapAmount = TransferHelper.fixedToTokenNativeDecimals(100e18, collateralAsset.decimals());
        referenceAsset.approve(address(corkPool), type(uint256).max);
        corkPool.swap(defaultCurrencyId, swapAmount, DEFAULT_ADDRESS);

        // Fast forward time to expire the pool
        vm.warp(block.timestamp + EXPIRY + 1);

        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);

        // Bound collateral output to reasonable range
        uint256 maxCollateralOut = TransferHelper.fixedToTokenNativeDecimals(100e18, collateralAsset.decimals());
        collateralOut = bound(collateralOut, TransferHelper.fixedToTokenNativeDecimals(1e18, collateralAsset.decimals()), maxCollateralOut);

        // Transfer CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(DEFAULT_ADDRESS);
        principalToken.transfer(address(corkPoolAdapter), cptBalance);

        Balances memory before = Balances({
            periphery: principalToken.balanceOf(address(corkPoolAdapter)),
            defaultAddress: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverReference: referenceAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            ownerPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            cork: collateralAsset.balanceOf(address(corkPool))
        });

        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: 0, owner: address(corkPoolAdapter), receiver: RECEIVER, maxSharesIn: cptBalance, deadline: block.timestamp}));

        Balances memory _after = Balances({
            periphery: principalToken.balanceOf(address(corkPoolAdapter)),
            defaultAddress: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverReference: referenceAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            ownerPT: principalToken.balanceOf(DEFAULT_ADDRESS),
            cork: collateralAsset.balanceOf(address(corkPool))
        });

        assertLe(_after.periphery, before.periphery, "Adapter CPT balance should not increase");
        assertEq(_after.defaultAddress, before.defaultAddress, "DEFAULT_ADDRESS balance should remain same");
        assertApproxEqAbs(_after.receiverCollateral, before.receiverCollateral + collateralOut, TransferHelper.normalizeDecimals(2, 18, raDecimals), "Receiver should receive approximate collateral amount");
        assertGt(_after.receiverReference, before.receiverReference, "Receiver reference balance should increase");

        vm.stopPrank();
    }

    function test_balanceConsistency_withdraw() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupWithShares();

        uint256 collateralOut = 100e18;

        // Transfer CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(DEFAULT_ADDRESS);
        principalToken.approve(address(corkPoolAdapter), cptBalance);

        uint256 totalCollateralSupplyBefore = collateralAsset.totalSupply();
        uint256 peripheryCollateralBefore = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressCollateralBefore = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 corkCollateralBefore = collateralAsset.balanceOf(address(corkPool));

        corkPoolAdapter.safeWithdraw(ICorkPoolAdapter.SafeWithdrawParams({poolId: defaultCurrencyId, collateralAssets: collateralOut, referenceAssets: 0, owner: DEFAULT_ADDRESS, receiver: RECEIVER, maxSharesIn: cptBalance, deadline: block.timestamp}));

        uint256 totalCollateralSupplyAfter = collateralAsset.totalSupply();
        uint256 peripheryCollateralAfter = collateralAsset.balanceOf(address(corkPoolAdapter));
        uint256 defaultAddressCollateralAfter = collateralAsset.balanceOf(DEFAULT_ADDRESS);
        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 corkCollateralAfter = collateralAsset.balanceOf(address(corkPool));

        assertEq(totalCollateralSupplyAfter, totalCollateralSupplyBefore, "Total collateral supply should remain constant");

        uint256 totalCollateralBefore = peripheryCollateralBefore + defaultAddressCollateralBefore + receiverCollateralBefore + corkCollateralBefore;
        uint256 totalCollateralAfter = peripheryCollateralAfter + defaultAddressCollateralAfter + receiverCollateralAfter + corkCollateralAfter;
        assertEq(totalCollateralAfter, totalCollateralBefore, "Sum of all collateral balances should remain constant");

        vm.stopPrank();
    }
}
