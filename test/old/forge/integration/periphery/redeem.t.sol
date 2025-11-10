// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract CorkAdapterRedeemTest is Helper {
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
        uint256 cork;
    }

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        deployPeriphery();
        vm.stopPrank();
    }

    function setupDifferentDecimals(uint8 raDecimals, uint8 paDecimals) internal returns (uint8, uint8) {
        raDecimals = uint8(bound(raDecimals, TARGET_DECIMALS, MAX_DECIMALS));
        paDecimals = uint8(bound(paDecimals, TARGET_DECIMALS, MAX_DECIMALS));

        (collateralAsset, referenceAsset, defaultCurrencyId) = createMarket(EXPIRY, raDecimals, paDecimals);

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

        return (raDecimals, paDecimals);
    }

    function getBalances() internal view returns (Balances memory) {
        return Balances({
            periphery: collateralAsset.balanceOf(address(corkAdapter)),
            defaultAddress: collateralAsset.balanceOf(DEFAULT_ADDRESS),
            receiverCollateral: collateralAsset.balanceOf(RECEIVER),
            receiverReference: referenceAsset.balanceOf(RECEIVER),
            receiverPT: principalToken.balanceOf(RECEIVER),
            cork: collateralAsset.balanceOf(address(corkPoolManager))
        });
    }

    function testSafeRedeemBasic() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 100e18;
        uint256 redeemAmount = 50e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Transfer CPT tokens to adapter for redemption
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        // Preview the redeem to get expected amounts
        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, redeemAmount);

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Check that receiver got the expected amounts
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        assertEq(actualCollateralReceived, expectedCollateralOut, "Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Reference received should match preview");

        vm.stopPrank();
    }

    function testSafeRedeemWithOwner() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 100e18;
        uint256 redeemAmount = 50e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Approve adapter to spend CPT tokens from RECEIVER
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.approve(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        // Preview the redeem to get expected amounts
        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, redeemAmount);

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);
        mockBundler.setInitiator(RECEIVER);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: RECEIVER, receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Check that receiver got the expected amounts
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        assertEq(actualCollateralReceived, expectedCollateralOut, "Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Reference received should match preview");

        vm.stopPrank();
    }

    function testSafeRedeemMaxAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 100e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Transfer all CPT tokens to adapter
        uint256 cptBalance = principalToken.balanceOf(RECEIVER);
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), cptBalance);
        vm.stopPrank();

        // Preview the redeem to get expected amounts (using the actual balance that will be redeemed)
        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, cptBalance);

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: type(uint256).max, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Check that receiver got the expected amounts
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        assertEq(actualCollateralReceived, expectedCollateralOut, "Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Reference received should match preview");

        // Check that adapter's CPT balance is now 0
        assertEq(principalToken.balanceOf(address(corkAdapter)), 0);

        vm.stopPrank();
    }

    function testSafeRedeemMaxAmountWithOwner() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 100e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Approve adapter to spend all CPT tokens from RECEIVER
        uint256 cptBalance = principalToken.balanceOf(RECEIVER);
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.approve(address(corkAdapter), cptBalance);
        vm.stopPrank();

        // Preview the redeem to get expected amounts (using the actual balance that will be redeemed)
        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, cptBalance);

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);
        mockBundler.setInitiator(RECEIVER);

        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: type(uint256).max, owner: RECEIVER, receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Check that receiver got the expected amounts
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        assertEq(actualCollateralReceived, expectedCollateralOut, "Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Reference received should match preview");

        // Check that owner's CPT balance is now 0
        assertEq(principalToken.balanceOf(RECEIVER), 0);

        vm.stopPrank();
    }

    function testSafeRedeemSlippageProtection() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 100e18;
        uint256 redeemAmount = 50e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Transfer CPT tokens to adapter
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        // Should revert with unrealistic minimum amounts
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: type(uint256).max, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: type(uint256).max, deadline: block.timestamp + 1}));

        vm.stopPrank();
    }

    function testSafeRedeemDeadlineExceeded() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 100e18;
        uint256 redeemAmount = 50e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Transfer CPT tokens to adapter
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp - 1}));

        vm.stopPrank();
    }

    function testSafeRedeemZeroAddress() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: 100e18, owner: address(0), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: 100e18, owner: address(corkAdapter), receiver: address(0), minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        vm.stopPrank();
    }

    function testSafeRedeemZeroAmount() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: 0, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        vm.stopPrank();
    }

    function testSafeRedeemPreviewMatches() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        uint256 depositAmount = 200e18;
        uint256 redeemAmount = 75e18;

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Transfer CPT tokens to adapter for redemption
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        // Preview the redeem multiple times to ensure consistency
        (uint256 expectedReferenceOut1, uint256 expectedCollateralOut1) = corkPoolManager.previewRedeem(defaultCurrencyId, redeemAmount);
        (uint256 expectedReferenceOut2, uint256 expectedCollateralOut2) = corkPoolManager.previewRedeem(defaultCurrencyId, redeemAmount);

        // Preview should be consistent
        assertEq(expectedReferenceOut1, expectedReferenceOut2, "Preview reference should be consistent");
        assertEq(expectedCollateralOut1, expectedCollateralOut2, "Preview collateral should be consistent");

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Calculate actual amounts received
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        // Verify exact match with preview
        assertEq(actualCollateralReceived, expectedCollateralOut1, "Actual collateral must exactly match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut1, "Actual reference must exactly match preview");

        vm.stopPrank();
    }

    function testFuzzSafeRedeemDifferentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 depositSeed, uint256 redeemSeed) public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(raDecimals, paDecimals);

        // Bound deposit amount based on collateral asset decimals
        uint256 minDeposit = 10 ** collateralAsset.decimals(); // 1 unit in native decimals
        uint256 maxDeposit = 1000 * (10 ** collateralAsset.decimals()); // 1000 units in native decimals
        uint256 depositAmount = bound(depositSeed, minDeposit, maxDeposit);

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Get the CPT balance and bound redeem amount
        uint256 cptBalance = principalToken.balanceOf(RECEIVER);
        vm.assume(cptBalance > 0); // Skip if no tokens were minted

        uint256 minRedeem = 1; // At least 1 wei
        uint256 maxRedeem = cptBalance; // At most the full balance
        uint256 redeemAmount = bound(redeemSeed, minRedeem, maxRedeem);

        // Transfer CPT tokens to adapter for redemption
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        // Preview the redeem to get expected amounts
        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, redeemAmount);

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);

        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Calculate actual amounts received
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        // Verify exact match with preview
        assertEq(actualCollateralReceived, expectedCollateralOut, "Fuzz: Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Fuzz: Reference received should match preview");

        vm.stopPrank();
    }

    function testFuzzSafeRedeemMaxAmountDifferentDecimals(uint8 raDecimals, uint8 paDecimals, uint256 depositSeed) public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(raDecimals, paDecimals);

        // Bound deposit amount based on collateral asset decimals
        uint256 minDeposit = 10 ** collateralAsset.decimals(); // 1 unit in native decimals
        uint256 maxDeposit = 1000 * (10 ** collateralAsset.decimals()); // 1000 units in native decimals
        uint256 depositAmount = bound(depositSeed, minDeposit, maxDeposit);

        // First deposit to get CPT tokens
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Get the CPT balance
        uint256 cptBalance = principalToken.balanceOf(RECEIVER);
        vm.assume(cptBalance > 0); // Skip if no tokens were minted

        // Transfer all CPT tokens to adapter
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), cptBalance);
        vm.stopPrank();

        // Preview the redeem using the full balance
        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, cptBalance);

        Balances memory balancesBefore = getBalances();

        vm.startPrank(DEFAULT_ADDRESS);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: type(uint256).max, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        Balances memory balancesAfter = getBalances();

        // Calculate actual amounts received
        uint256 actualCollateralReceived = balancesAfter.receiverCollateral - balancesBefore.receiverCollateral;
        uint256 actualReferenceReceived = balancesAfter.receiverReference - balancesBefore.receiverReference;

        // Verify exact match with preview
        assertEq(actualCollateralReceived, expectedCollateralOut, "Fuzz Max: Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Fuzz Max: Reference received should match preview");

        // Check that adapter's CPT balance is now 0
        assertEq(principalToken.balanceOf(address(corkAdapter)), 0, "Adapter should have no CPT tokens left");

        // Additional sanity checks for different decimal scenarios
        if (expectedCollateralOut > 0) assertGt(actualCollateralReceived, 0, "Should receive some collateral if preview shows non-zero");
        if (expectedReferenceOut > 0) assertGt(actualReferenceReceived, 0, "Should receive some reference if preview shows non-zero");

        vm.stopPrank();
    }

    function testSafeRedeemHardcodedValuesAtExpiry() public {
        vm.startPrank(DEFAULT_ADDRESS);
        setupDifferentDecimals(18, 18);

        // Setup: Deposit exactly 10 ether to get 10 ether of CPT tokens
        uint256 depositAmount = 10 ether;
        collateralAsset.transfer(address(corkAdapter), depositAmount);
        corkAdapter.safeDeposit(ICorkAdapter.SafeDepositParams({poolId: defaultCurrencyId, collateralAssetsIn: depositAmount, receiver: RECEIVER, minCptAndCstSharesOut: 0, deadline: block.timestamp + 1}));

        // Verify initial state: RECEIVER should have 10 ether of CPT tokens
        uint256 cptBalance = principalToken.balanceOf(RECEIVER);
        assertEq(cptBalance, 10 ether, "Should have exactly 10 ether of CPT tokens");

        // Verify pool has 10 ether of collateral asset
        uint256 poolCollateralBalance = collateralAsset.balanceOf(address(corkPoolManager));
        assertEq(poolCollateralBalance, 10 ether, "Pool should have exactly 10 ether of collateral");

        // Fast forward to expiry
        vm.warp(block.timestamp + EXPIRY + 1);

        // Redeem exactly 5 ether worth of CPT tokens
        uint256 redeemAmount = 5 ether;

        // Transfer CPT tokens to adapter for redemption
        vm.stopPrank();
        vm.startPrank(RECEIVER);
        principalToken.transfer(address(corkAdapter), redeemAmount);
        vm.stopPrank();

        (uint256 expectedReferenceOut, uint256 expectedCollateralOut) = corkPoolManager.previewRedeem(defaultCurrencyId, redeemAmount);

        uint256 receiverCollateralBefore = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceBefore = referenceAsset.balanceOf(RECEIVER);

        vm.startPrank(DEFAULT_ADDRESS);
        corkAdapter.safeRedeem(ICorkAdapter.SafeRedeemParams({poolId: defaultCurrencyId, cptSharesIn: redeemAmount, owner: address(corkAdapter), receiver: RECEIVER, minReferenceAssetsOut: 0, minCollateralAssetsOut: 0, deadline: block.timestamp + 1}));

        uint256 receiverCollateralAfter = collateralAsset.balanceOf(RECEIVER);
        uint256 receiverReferenceAfter = referenceAsset.balanceOf(RECEIVER);

        uint256 actualCollateralReceived = receiverCollateralAfter - receiverCollateralBefore;
        uint256 actualReferenceReceived = receiverReferenceAfter - receiverReferenceBefore;

        assertEq(actualCollateralReceived, expectedCollateralOut, "Collateral received should match preview");
        assertEq(actualReferenceReceived, expectedReferenceOut, "Reference received should match preview");

        assertEq(actualCollateralReceived, 5 ether, "Should receive exactly 5 ether of collateral");
        assertEq(actualReferenceReceived, 0, "Should receive 0 reference asset at expiry");

        uint256 poolCollateralAfter = collateralAsset.balanceOf(address(corkPoolManager));
        assertEq(poolCollateralAfter, 5 ether, "Pool should have 5 ether of collateral remaining");

        uint256 cptBalanceAfter = principalToken.balanceOf(RECEIVER);
        assertEq(cptBalanceAfter, 5 ether, "Should have 5 ether of CPT tokens remaining");

        vm.stopPrank();
    }
}
