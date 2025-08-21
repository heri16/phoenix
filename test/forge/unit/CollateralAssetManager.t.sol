// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {CollateralAssetManager, CollateralAssetManagerLibrary} from "contracts/libraries/CollateralAssetManager.sol";
import {Test} from "forge-std/Test.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH, ERC20Mock} from "test/mocks/DummyWETH.sol";

// Helper contract to expose CollateralAssetManagerLibrary functions for testing
contract CollateralAssetManagerHelper {
    CollateralAssetManager public redemptionAssetManager;

    function setCollateralAssetManager(address _address, uint256 locked) external {
        redemptionAssetManager._address = _address;
        redemptionAssetManager.locked = locked;
    }

    // Exposed CollateralAssetManagerLibrary functions
    function initialize(address collateralAsset) external pure returns (CollateralAssetManager memory) {
        return CollateralAssetManagerLibrary.initialize(collateralAsset);
    }

    function reset() external {
        CollateralAssetManagerLibrary.reset(redemptionAssetManager);
    }

    function increaseLocked(uint256 amount) external {
        CollateralAssetManagerLibrary.increaseLocked(redemptionAssetManager, amount);
    }

    function convertAllToFree() external returns (uint256) {
        return CollateralAssetManagerLibrary.convertAllToFree(redemptionAssetManager);
    }

    function decreaseLocked(uint256 amount) external {
        CollateralAssetManagerLibrary.decreaseLocked(redemptionAssetManager, amount);
    }

    function lockFrom(uint256 amount, address from) external {
        CollateralAssetManagerLibrary.lockFrom(redemptionAssetManager, amount, from);
    }

    function lockUnchecked(uint256 amount, address from) external {
        CollateralAssetManagerLibrary.lockUnchecked(redemptionAssetManager, amount, from);
    }

    function unlockTo(address to, uint256 amount) external {
        CollateralAssetManagerLibrary.unlockTo(redemptionAssetManager, to, amount);
    }

    function unlockToUnchecked(uint256 amount, address to) external {
        CollateralAssetManagerLibrary.unlockToUnchecked(redemptionAssetManager, amount, to);
    }

    // Getter functions for testing
    function getAddress() external view returns (address) {
        return redemptionAssetManager._address;
    }

    function getLocked() external view returns (uint256) {
        return redemptionAssetManager.locked;
    }
}

contract CollateralAssetManagerTest is Helper {
    CollateralAssetManagerHelper internal ramHelper;
    ERC20Mock internal mockToken;

    address internal user1;
    address internal user2;
    address internal user3;

    uint256 internal constant INITIAL_BALANCE = 1000 ether;
    uint256 internal constant LOCK_AMOUNT = 100 ether;
    uint256 internal constant SMALL_AMOUNT = 1 ether;

    function setUp() external {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock token
        mockToken = new DummyWETH();

        // Deploy helper
        ramHelper = new CollateralAssetManagerHelper();

        // Initialize with mock token
        ramHelper.setCollateralAssetManager(address(mockToken), 0);

        // Give users some tokens
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);

        vm.prank(user1);
        mockToken.deposit{value: INITIAL_BALANCE}();
        vm.prank(user2);
        mockToken.deposit{value: INITIAL_BALANCE}();
        vm.prank(user3);
        mockToken.deposit{value: INITIAL_BALANCE}();

        // Approve helper contract to spend tokens
        vm.prank(user1);
        mockToken.approve(address(ramHelper), type(uint256).max);
        vm.prank(user2);
        mockToken.approve(address(ramHelper), type(uint256).max);
        vm.prank(user3);
        mockToken.approve(address(ramHelper), type(uint256).max);
    }

    // ------------------------------- initialize Tests ----------------------------------- //
    function test_initialize_ShouldCreateManagerWithCorrectAddress() external {
        CollateralAssetManager memory manager = ramHelper.initialize(address(mockToken));

        assertEq(manager._address, address(mockToken), "Address should be set correctly");
        assertEq(manager.locked, 0, "Locked should be zero initially");
    }

    function test_initialize_ShouldRevertWithZeroAddress() external {
        vm.expectRevert();
        CollateralAssetManager memory manager = ramHelper.initialize(address(0));
    }

    function test_initialize_ShouldWorkWithAnyAddress() external {
        CollateralAssetManager memory manager = ramHelper.initialize(user1);

        assertEq(manager._address, user1, "Should accept any address");
        assertEq(manager.locked, 0, "Locked should be zero initially");
    }

    // ------------------------------- reset Tests ----------------------------------- //
    function test_reset_ShouldZeroOutLocked() external {
        // Set some values first
        ramHelper.setCollateralAssetManager(address(mockToken), 100);
        assertEq(mockToken.balanceOf(address(ramHelper)), 0, "Helper should have 0 amount as it was directly initialized");

        assertEq(ramHelper.getLocked(), 100, "Locked should be set");

        ramHelper.reset();

        assertEq(ramHelper.getLocked(), 0, "Locked should be reset to zero");
        assertEq(ramHelper.getAddress(), address(mockToken), "Address should remain unchanged");

        assertEq(mockToken.balanceOf(address(ramHelper)), 0, "Helper should have 0 amount as it was directly initialized");
    }

    function test_reset_ShouldWorkWhenAlreadyZero() external {
        // Already at zero values
        assertEq(ramHelper.getLocked(), 0, "Locked should be zero");

        ramHelper.reset();

        assertEq(ramHelper.getLocked(), 0, "Locked should remain zero");
    }

    function test_reset_ShouldWorkWithMaxValues() external {
        uint256 maxValue = type(uint256).max;
        ramHelper.setCollateralAssetManager(address(mockToken), maxValue);

        ramHelper.reset();

        assertEq(ramHelper.getLocked(), 0, "Locked should be reset from max value");
    }

    // ------------------------------- increaseLocked Tests ----------------------------------- //
    function test_increaseLocked_ShouldIncreaseLockedAmount() external {
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.increaseLocked(LOCK_AMOUNT);

        assertEq(ramHelper.getLocked(), initialLocked + LOCK_AMOUNT, "Locked should increase by amount");
    }

    function test_increaseLocked_ShouldWorkWithZeroAmount() external {
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.increaseLocked(0);

        assertEq(ramHelper.getLocked(), initialLocked, "Locked should remain unchanged with zero amount");
    }

    function test_increaseLocked_ShouldWorkMultipleTimes() external {
        ramHelper.increaseLocked(LOCK_AMOUNT);
        ramHelper.increaseLocked(SMALL_AMOUNT);

        assertEq(ramHelper.getLocked(), LOCK_AMOUNT + SMALL_AMOUNT, "Should accumulate locked amounts");
    }

    function test_increaseLocked_ShouldHandleLargeNumbers() external {
        uint256 largeAmount = type(uint128).max;

        ramHelper.increaseLocked(largeAmount);

        assertEq(ramHelper.getLocked(), largeAmount, "Should handle large amounts");
    }

    // ------------------------------- decreaseLocked Tests ----------------------------------- //
    function test_decreaseLocked_ShouldDecreaseLockedAmount() external {
        // Set initial locked amount
        ramHelper.increaseLocked(LOCK_AMOUNT);

        ramHelper.decreaseLocked(SMALL_AMOUNT);

        assertEq(ramHelper.getLocked(), LOCK_AMOUNT - SMALL_AMOUNT, "Locked should decrease by amount");
    }

    function test_decreaseLocked_ShouldWorkWithZeroAmount() external {
        ramHelper.increaseLocked(LOCK_AMOUNT);
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.decreaseLocked(0);

        assertEq(ramHelper.getLocked(), initialLocked, "Locked should remain unchanged with zero amount");
    }

    function test_decreaseLocked_ShouldWorkWhenDecrementingToZero() external {
        ramHelper.increaseLocked(LOCK_AMOUNT);

        ramHelper.decreaseLocked(LOCK_AMOUNT);

        assertEq(ramHelper.getLocked(), 0, "Locked should become zero");
    }

    function test_decreaseLocked_ShouldRevert_WhenAmountGreaterThanLocked() external {
        ramHelper.increaseLocked(SMALL_AMOUNT);

        vm.expectRevert(IErrors.InvalidAmount.selector);
        ramHelper.decreaseLocked(LOCK_AMOUNT); // LOCK_AMOUNT > SMALL_AMOUNT
    }

    // ------------------------------- convertAllToFree Tests ----------------------------------- //
    function test_convertAllToFree_ShouldMoveAllLockedToFree() external {
        ramHelper.increaseLocked(LOCK_AMOUNT);

        uint256 result = ramHelper.convertAllToFree();

        assertEq(ramHelper.getLocked(), 0, "Locked should become zero");
        assertEq(result, LOCK_AMOUNT, "Should return new free amount");
    }

    function test_convertAllToFree_ShouldReturnExistingFree_WhenNoLocked() external {
        ramHelper.setCollateralAssetManager(address(mockToken), 0);

        uint256 result = ramHelper.convertAllToFree();

        assertEq(ramHelper.getLocked(), 0, "Locked should remain zero");
        assertEq(result, 0, "Should return existing free amount");
    }

    function test_convertAllToFree_ShouldWorkWhenBothAreZero() external {
        uint256 result = ramHelper.convertAllToFree();

        assertEq(ramHelper.getLocked(), 0, "Locked should remain zero");
        assertEq(result, 0, "Should return zero");
    }

    function test_convertAllToFree_ShouldHandleLargeNumbers() external {
        uint256 largeAmount = type(uint128).max;
        ramHelper.setCollateralAssetManager(address(mockToken), largeAmount);

        uint256 result = ramHelper.convertAllToFree();

        assertEq(ramHelper.getLocked(), 0, "Locked should become zero");
        assertEq(result, largeAmount, "Should return total");
    }

    // ------------------------------- lockFrom Tests ----------------------------------- //
    function test_lockFrom_ShouldTransferTokensAndIncreaseLocked() external {
        uint256 initialBalance = mockToken.balanceOf(user1);
        uint256 initialHelperBalance = mockToken.balanceOf(address(ramHelper));

        ramHelper.lockFrom(LOCK_AMOUNT, user1);

        assertEq(mockToken.balanceOf(user1), initialBalance - LOCK_AMOUNT, "User balance should decrease");
        assertEq(mockToken.balanceOf(address(ramHelper)), initialHelperBalance + LOCK_AMOUNT, "Helper balance should increase");
        assertEq(ramHelper.getLocked(), LOCK_AMOUNT, "Locked amount should increase");
    }

    function test_lockFrom_ShouldWorkMultipleTimes() external {
        ramHelper.lockFrom(LOCK_AMOUNT, user1);
        ramHelper.lockFrom(SMALL_AMOUNT, user2);

        assertEq(ramHelper.getLocked(), LOCK_AMOUNT + SMALL_AMOUNT, "Should accumulate locked amounts");
        assertEq(mockToken.balanceOf(address(ramHelper)), LOCK_AMOUNT + SMALL_AMOUNT, "Should accumulate token balance");
    }

    function test_lockFrom_ShouldWorkWithZeroAmount() external {
        uint256 initialBalance = mockToken.balanceOf(user1);
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.lockFrom(0, user1);

        assertEq(mockToken.balanceOf(user1), initialBalance, "User balance should remain unchanged");
        assertEq(ramHelper.getLocked(), initialLocked, "Locked should remain unchanged");
    }

    // ------------------------------- lockUnchecked Tests ----------------------------------- //
    function test_lockUnchecked_ShouldTransferTokensWithoutUpdatingLocked() external {
        uint256 initialBalance = mockToken.balanceOf(user1);
        uint256 initialHelperBalance = mockToken.balanceOf(address(ramHelper));
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.lockUnchecked(LOCK_AMOUNT, user1);

        assertEq(mockToken.balanceOf(user1), initialBalance - LOCK_AMOUNT, "User balance should decrease");
        assertEq(mockToken.balanceOf(address(ramHelper)), initialHelperBalance + LOCK_AMOUNT, "Helper balance should increase");
        assertEq(ramHelper.getLocked(), initialLocked, "Locked amount should remain unchanged");
    }

    // ------------------------------- unlockTo Tests ----------------------------------- //
    function test_unlockTo_ShouldTransferTokensAndDecreaseLocked() external {
        // First lock some tokens
        ramHelper.lockFrom(LOCK_AMOUNT, user1);

        uint256 initialUser2Balance = mockToken.balanceOf(user2);
        uint256 initialHelperBalance = mockToken.balanceOf(address(ramHelper));

        ramHelper.unlockTo(user2, SMALL_AMOUNT);

        assertEq(mockToken.balanceOf(user2), initialUser2Balance + SMALL_AMOUNT, "User2 balance should increase");
        assertEq(mockToken.balanceOf(address(ramHelper)), initialHelperBalance - SMALL_AMOUNT, "Helper balance should decrease");
        assertEq(ramHelper.getLocked(), LOCK_AMOUNT - SMALL_AMOUNT, "Locked amount should decrease");
    }

    function test_unlockTo_ShouldWorkWithZeroAmount() external {
        ramHelper.lockFrom(LOCK_AMOUNT, user1);

        uint256 initialUser2Balance = mockToken.balanceOf(user2);
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.unlockTo(user2, 0);

        assertEq(mockToken.balanceOf(user2), initialUser2Balance, "User2 balance should remain unchanged");
        assertEq(ramHelper.getLocked(), initialLocked, "Locked should remain unchanged");
    }

    // ------------------------------- unlockToUnchecked Tests ----------------------------------- //
    function test_unlockToUnchecked_ShouldTransferTokensWithoutUpdatingLocked() external {
        // First lock some tokens to have balance in helper
        ramHelper.lockFrom(LOCK_AMOUNT, user1);

        uint256 initialUser2Balance = mockToken.balanceOf(user2);
        uint256 initialHelperBalance = mockToken.balanceOf(address(ramHelper));
        uint256 initialLocked = ramHelper.getLocked();

        ramHelper.unlockToUnchecked(SMALL_AMOUNT, user2);

        assertEq(mockToken.balanceOf(user2), initialUser2Balance + SMALL_AMOUNT, "User2 balance should increase");
        assertEq(mockToken.balanceOf(address(ramHelper)), initialHelperBalance - SMALL_AMOUNT, "Helper balance should decrease");
        assertEq(ramHelper.getLocked(), initialLocked, "Locked amount should remain unchanged");
    }

    // ------------------------------- Edge Cases and Error Conditions ----------------------------------- //
    function test_lockFrom_ShouldRevert_WhenInsufficientBalance() external {
        // Try to lock more than user has
        uint256 userBalance = mockToken.balanceOf(user1);

        vm.expectRevert();
        ramHelper.lockFrom(userBalance + 1, user1);
    }

    function test_lockFrom_ShouldRevert_WhenInsufficientAllowance() external {
        // Reset allowance
        vm.prank(user1);
        mockToken.approve(address(ramHelper), 0);

        vm.expectRevert();
        ramHelper.lockFrom(LOCK_AMOUNT, user1);
    }

    function test_unlockTo_ShouldRevert_WhenInsufficientHelperBalance() external {
        // Try to unlock more than helper has
        vm.expectRevert();
        ramHelper.unlockTo(user2, LOCK_AMOUNT);
    }

    function test_decreaseLocked_ShouldRevert_OnUnderflow() external {
        // Try to decrease locked when it's zero
        vm.expectRevert(IErrors.InvalidAmount.selector);
        ramHelper.decreaseLocked(1);
    }

    // ------------------------------- Integration Tests ----------------------------------- //
    function test_completeWorkflow_LockConvertUnlock() external {
        uint256 initialUser1Balance = mockToken.balanceOf(user1);
        uint256 initialUser3Balance = mockToken.balanceOf(user3);

        // 1. Lock tokens from user1
        ramHelper.lockFrom(LOCK_AMOUNT, user1);
        assertEq(ramHelper.getLocked(), LOCK_AMOUNT, "Should have locked amount");

        // 2. Convert locked to free
        uint256 freeAmount = ramHelper.convertAllToFree();
        assertEq(ramHelper.getLocked(), 0, "Locked should be zero after conversion");
        assertEq(freeAmount, LOCK_AMOUNT, "Return value should match");

        // 3. Lock more tokens (this time they go to locked, not free)
        ramHelper.lockFrom(SMALL_AMOUNT, user1);
        assertEq(ramHelper.getLocked(), SMALL_AMOUNT, "Should have new locked amount");

        // 4. Unlock some tokens to user3
        ramHelper.unlockTo(user3, SMALL_AMOUNT);
        assertEq(ramHelper.getLocked(), 0, "Locked should be zero after unlock");

        // 5. Verify final balances
        assertEq(mockToken.balanceOf(user1), initialUser1Balance - LOCK_AMOUNT - SMALL_AMOUNT, "User1 should have transferred total");
        assertEq(mockToken.balanceOf(user3), initialUser3Balance + SMALL_AMOUNT, "User3 should have received unlocked amount");
        assertEq(mockToken.balanceOf(address(ramHelper)), LOCK_AMOUNT, "Helper should retain the free amount");
    }

    function test_multipleUsersWorkflow() external {
        // Lock from multiple users
        ramHelper.lockFrom(LOCK_AMOUNT, user1);
        ramHelper.lockFrom(SMALL_AMOUNT, user2);
        ramHelper.lockFrom(LOCK_AMOUNT / 2, user3);

        uint256 totalLocked = LOCK_AMOUNT + SMALL_AMOUNT + LOCK_AMOUNT / 2;
        assertEq(ramHelper.getLocked(), totalLocked, "Should accumulate all locked amounts");

        // Unlock to different users
        ramHelper.unlockTo(user1, SMALL_AMOUNT);
        ramHelper.unlockTo(user2, LOCK_AMOUNT / 2);

        assertEq(ramHelper.getLocked(), totalLocked - SMALL_AMOUNT - LOCK_AMOUNT / 2, "Should decrease locked correctly");
    }

    function test_resetAfterOperations() external {
        // Perform various operations
        ramHelper.lockFrom(LOCK_AMOUNT, user1);
        ramHelper.convertAllToFree();
        ramHelper.lockFrom(SMALL_AMOUNT, user2);

        assertEq(ramHelper.getLocked(), SMALL_AMOUNT, "Should have some locked");

        // Reset should zero everything
        ramHelper.reset();

        assertEq(ramHelper.getLocked(), 0, "Locked should be reset");
        // Note: Tokens remain in the contract, only accounting is reset
    }

    // ------------------------------- Test Helper Functions ----------------------------------- //

    function test_HelperSetup() external view {
        assertEq(ramHelper.getAddress(), address(mockToken), "Helper should be set up with mock token");
        assertEq(ramHelper.getLocked(), 0, "Initial locked should be zero");
    }

    function test_TokenSetup() external view {
        assertGe(mockToken.balanceOf(user1), INITIAL_BALANCE, "User1 should have initial balance");
        assertGe(mockToken.balanceOf(user2), INITIAL_BALANCE, "User2 should have initial balance");
        assertGe(mockToken.balanceOf(user3), INITIAL_BALANCE, "User3 should have initial balance");
    }
}
