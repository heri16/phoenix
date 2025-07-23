// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {CorkPool} from "contracts/core/CorkPool.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {State} from "contracts/libraries/State.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract ExtsloadTest is Helper {
    DummyWETH collateralAsset;
    DummyWETH referenceAsset;
    MarketId id;

    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        // Initialize the market to have some data in storage
        (collateralAsset, referenceAsset, id) = createMarket(1 days);

        vm.stopPrank();
    }

    //-------------------------- SINGLE SLOT TESTS ------------------------------//

    function test_ExtsloadSingleSlot_SwapSharesFactory() public {
        // Test reading SHARES_FACTORY slot (slot 1 based on storage layout)
        bytes32 swapSharesFactorySlot = bytes32(uint256(1));
        bytes32 value = corkPool.extsload(swapSharesFactorySlot);

        // The value should be the address of the sharesFactory
        assertEq(address(uint160(uint256(value))), address(sharesFactory));
    }

    function test_ExtsloadSingleSlot_Config() public {
        // Test reading CONFIG slot (slot 2 based on storage layout)
        bytes32 configSlot = bytes32(uint256(2));
        bytes32 value = corkPool.extsload(configSlot);

        // The value should be the address of the config
        assertEq(address(uint160(uint256(value))), address(corkConfig));
    }

    function test_ExtsloadSingleSlot_EmptySlot() public {
        // Test reading an empty/uninitialized slot
        bytes32 emptySlot = bytes32(uint256(999));
        bytes32 value = corkPool.extsload(emptySlot);
        assertEq(value, bytes32(0));
    }

    function test_ExtsloadSingleSlot_MaxSlot() public {
        // Test reading from maximum slot number
        bytes32 maxSlot = bytes32(type(uint256).max);
        bytes32 value = corkPool.extsload(maxSlot);
        assertEq(value, bytes32(0)); // Should be empty
    }

    //-------------------------- MULTIPLE CONSECUTIVE SLOTS TESTS ------------------------------//

    function test_ExtsloadMultipleConsecutiveSlots_ModuleStateFields() public {
        // Test reading consecutive slots that contain ModuleState fields
        bytes32 startSlot = bytes32(uint256(1)); // SHARES_FACTORY
        uint256 nSlots = 2; // SHARES_FACTORY and CONFIG

        bytes32[] memory values = corkPool.extsload(startSlot, nSlots);

        assertEq(values.length, 2);
        assertEq(address(uint160(uint256(values[0]))), address(sharesFactory)); // SHARES_FACTORY
        assertEq(address(uint160(uint256(values[1]))), address(corkConfig)); // CONFIG
    }

    function test_ExtsloadMultipleConsecutiveSlots_LargeRange() public {
        // Test reading a larger range of consecutive slots
        bytes32 startSlot = bytes32(uint256(0)); // Start from states mapping slot
        uint256 nSlots = 10;

        bytes32[] memory values = corkPool.extsload(startSlot, nSlots);

        assertEq(values.length, 10);
        // Slot 1 should have SHARES_FACTORY
        assertEq(address(uint160(uint256(values[1]))), address(sharesFactory));
        // Slot 2 should have CONFIG
        assertEq(address(uint160(uint256(values[2]))), address(corkConfig));
        // Slot 3 should have 0
        assertEq(uint256(values[3]), 0);
    }

    function test_ExtsloadMultipleConsecutiveSlots_EmptyRange() public {
        // Test reading consecutive slots that are all empty
        bytes32 startSlot = bytes32(uint256(100));
        uint256 nSlots = 5;

        bytes32[] memory values = corkPool.extsload(startSlot, nSlots);

        assertEq(values.length, 5);
        for (uint256 i = 0; i < values.length; i++) {
            assertEq(values[i], bytes32(0));
        }
    }

    function test_ExtsloadMultipleConsecutiveSlots_ZeroSlots() public {
        // Test edge case of reading 0 slots
        bytes32[] memory values = corkPool.extsload(bytes32(uint256(0)), 0);
        assertEq(values.length, 0);
    }

    function test_ExtsloadMultipleConsecutiveSlots_SingleSlot() public {
        // Test reading 1 slot using the consecutive function
        bytes32 startSlot = bytes32(uint256(1));
        uint256 nSlots = 1;

        bytes32[] memory values = corkPool.extsload(startSlot, nSlots);

        assertEq(values.length, 1);
        assertEq(address(uint160(uint256(values[0]))), address(sharesFactory));
    }

    //-------------------------- MULTIPLE SPECIFIC SLOTS TESTS ------------------------------//

    function test_ExtsloadMultipleSpecificSlots_MixedData() public {
        // Test reading specific slots with mixed data
        bytes32[] memory slots = new bytes32[](3);

        // SHARES_FACTORY slot
        slots[0] = bytes32(uint256(1));
        // CONFIG slot
        slots[1] = bytes32(uint256(2));
        // State mapping slot for our market
        slots[2] = keccak256(abi.encode(id, 0));

        bytes32[] memory values = corkPool.extsload(slots);

        assertEq(values.length, 3);
        assertEq(address(uint160(uint256(values[0]))), address(sharesFactory)); // SHARES_FACTORY
        assertEq(address(uint160(uint256(values[1]))), address(corkConfig)); // CONFIG
    }

    function test_ExtsloadMultipleSpecificSlots_EmptySlots() public {
        // Test reading specific slots that are all empty
        bytes32[] memory slots = new bytes32[](3);
        slots[0] = bytes32(uint256(999)); // Random empty slot
        slots[1] = bytes32(uint256(1000)); // Another empty slot
        slots[2] = bytes32(uint256(1001)); // Another empty slot

        bytes32[] memory values = corkPool.extsload(slots);

        assertEq(values.length, 3);
        assertEq(values[0], bytes32(0));
        assertEq(values[1], bytes32(0));
        assertEq(values[2], bytes32(0));
    }

    function test_ExtsloadMultipleSpecificSlots_EmptyArray() public {
        // Test edge case of reading empty slot array
        bytes32[] memory emptySlots = new bytes32[](0);
        bytes32[] memory values = corkPool.extsload(emptySlots);
        assertEq(values.length, 0);
    }

    function test_ExtsloadMultipleSpecificSlots_SingleSlot() public {
        // Test reading single slot using the specific slots function
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = bytes32(uint256(1)); // SHARES_FACTORY

        bytes32[] memory values = corkPool.extsload(slots);

        assertEq(values.length, 1);
        assertEq(address(uint160(uint256(values[0]))), address(sharesFactory));
    }

    function test_ExtsloadMultipleSpecificSlots_DuplicateSlots() public {
        // Test reading the same slot multiple times
        bytes32[] memory slots = new bytes32[](3);
        slots[0] = bytes32(uint256(1)); // SHARES_FACTORY
        slots[1] = bytes32(uint256(1)); // SHARES_FACTORY again
        slots[2] = bytes32(uint256(1)); // SHARES_FACTORY again

        bytes32[] memory values = corkPool.extsload(slots);

        assertEq(values.length, 3);
        assertEq(values[0], values[1]);
        assertEq(values[1], values[2]);
        assertEq(address(uint160(uint256(values[0]))), address(sharesFactory));
    }

    function test_ExtsloadMultipleSpecificSlots_NonSequentialSlots() public {
        // Test reading non-sequential slots
        bytes32[] memory slots = new bytes32[](4);
        slots[0] = bytes32(uint256(50)); // Gap slot
        slots[1] = bytes32(uint256(2)); // CONFIG
        slots[2] = bytes32(uint256(25)); // Gap slot
        slots[3] = bytes32(uint256(1)); // SHARES_FACTORY

        bytes32[] memory values = corkPool.extsload(slots);

        assertEq(values.length, 4);
        assertEq(values[0], bytes32(0)); // Gap slot should be 0
        assertEq(address(uint160(uint256(values[1]))), address(corkConfig)); // CONFIG
        assertEq(values[2], bytes32(0)); // Gap slot should be 0
        assertEq(address(uint160(uint256(values[3]))), address(sharesFactory)); // SHARES_FACTORY
    }

    //-------------------------- ADVANCED FUNCTIONALITY TESTS ------------------------------//

    function test_ExtsloadStateStructFields() public {
        // Test reading different fields from the State struct
        bytes32 baseSlot = keccak256(abi.encode(id, 0));

        // Test that we can read multiple consecutive slots from the state
        bytes32[] memory stateFields = corkPool.extsload(baseSlot, 3);
        assertEq(stateFields.length, 3);
    }

    function test_ExtsloadMarketValidation() public {
        // Test that we can read market data correctly using the public interface
        (address expectedRa, address expectedPa) = corkPool.underlyingAsset(id);

        // Use the actual addresses returned by the contract
        assertEq(expectedRa, address(collateralAsset));
        assertEq(expectedPa, address(referenceAsset));
    }

    function test_ExtsloadGapSlots() public {
        // Test reading from the __gap array (slots 3-50)
        bytes32[] memory gapSlots = new bytes32[](3);
        gapSlots[0] = bytes32(uint256(3)); // First gap slot
        gapSlots[1] = bytes32(uint256(25)); // Middle gap slot
        gapSlots[2] = bytes32(uint256(50)); // Last gap slot

        bytes32[] memory values = corkPool.extsload(gapSlots);

        assertEq(values.length, 3);
        // All gap slots should be empty (initialized to 0)
        assertEq(values[0], bytes32(0));
        assertEq(values[1], bytes32(0));
        assertEq(values[2], bytes32(0));
    }

    function test_ExtsloadCompareWithVmLoad() public {
        // Test that extsload returns the same values as vm.load
        bytes32 slot1 = bytes32(uint256(1)); // SHARES_FACTORY
        bytes32 slot2 = bytes32(uint256(2)); // CONFIG

        // Using extsload
        bytes32 extsloadValue1 = corkPool.extsload(slot1);
        bytes32 extsloadValue2 = corkPool.extsload(slot2);

        // Using vm.load
        bytes32 vmLoadValue1 = vm.load(address(corkPool), slot1);
        bytes32 vmLoadValue2 = vm.load(address(corkPool), slot2);

        // They should be identical
        assertEq(extsloadValue1, vmLoadValue1);
        assertEq(extsloadValue2, vmLoadValue2);

        // And they should be our expected values
        assertEq(address(uint160(uint256(extsloadValue1))), address(sharesFactory));
        assertEq(address(uint160(uint256(extsloadValue2))), address(corkConfig));
    }

    function test_ExtsloadVerifyInheritance() public {
        // Verify that CorkPool indeed inherits from Extsload by checking it has the functions

        // Test single slot function exists and works
        bytes32 slot = bytes32(uint256(1));
        bytes32 value = corkPool.extsload(slot);
        assertEq(address(uint160(uint256(value))), address(sharesFactory));

        // Test multiple consecutive slots function exists and works
        bytes32[] memory consecutiveValues = corkPool.extsload(slot, 2);
        assertEq(consecutiveValues.length, 2);
        assertEq(consecutiveValues[0], value);

        // Test multiple specific slots function exists and works
        bytes32[] memory specificSlots = new bytes32[](1);
        specificSlots[0] = slot;
        bytes32[] memory specificValues = corkPool.extsload(specificSlots);
        assertEq(specificValues.length, 1);
        assertEq(specificValues[0], value);
    }

    //-------------------------- EDGE CASES AND BOUNDARY TESTS ------------------------------//

    function test_ExtsloadLoopBranchCoverage_ConsecutiveSlots() public {
        // Test to ensure we hit both branches of the loop condition in consecutive slots function

        // Test 1: Loop that executes multiple iterations (continue branch)
        bytes32 startSlot = bytes32(uint256(1));
        uint256 nSlots = 3; // This should cause multiple loop iterations

        bytes32[] memory values = corkPool.extsload(startSlot, nSlots);
        assertEq(values.length, 3);

        // Test 2: Loop that executes exactly one iteration (break branch)
        bytes32[] memory singleValue = corkPool.extsload(startSlot, 1);
        assertEq(singleValue.length, 1);

        // Test 3: Loop that doesn't execute at all (immediate break)
        bytes32[] memory noValues = corkPool.extsload(startSlot, 0);
        assertEq(noValues.length, 0);

        // Test 4: Force multiple iterations to ensure loop continues
        bytes32[] memory manyValues = corkPool.extsload(startSlot, 10);
        assertEq(manyValues.length, 10);
    }

    function test_ExtsloadLoopBranchCoverage_SpecificSlots() public {
        // Test to ensure we hit both branches of the loop condition in specific slots function

        // Test 1: Loop that executes multiple iterations (continue branch)
        bytes32[] memory multipleSlots = new bytes32[](3);
        multipleSlots[0] = bytes32(uint256(1));
        multipleSlots[1] = bytes32(uint256(2));
        multipleSlots[2] = bytes32(uint256(3));

        bytes32[] memory multipleValues = corkPool.extsload(multipleSlots);
        assertEq(multipleValues.length, 3);

        // Test 2: Loop that executes exactly one iteration (break branch)
        bytes32[] memory singleSlot = new bytes32[](1);
        singleSlot[0] = bytes32(uint256(1));

        bytes32[] memory singleValue = corkPool.extsload(singleSlot);
        assertEq(singleValue.length, 1);

        // Test 3: Loop that doesn't execute at all (immediate break)
        bytes32[] memory noSlots = new bytes32[](0);
        bytes32[] memory noValues = corkPool.extsload(noSlots);
        assertEq(noValues.length, 0);

        // Test 4: Force many iterations to ensure loop continues
        bytes32[] memory manySlots = new bytes32[](10);
        for (uint256 i = 0; i < 10; i++) {
            manySlots[i] = bytes32(uint256(i + 1));
        }

        bytes32[] memory manyValues = corkPool.extsload(manySlots);
        assertEq(manyValues.length, 10);
    }

    function test_ExtsloadAssemblyLoopConditions() public {
        // Additional test to ensure we cover both branches of the assembly loop conditions

        // For consecutive slots - test the exact conditions in the assembly loop
        // The loop condition is: if iszero(lt(memptr, end)) { break }
        // This means: if (memptr >= end) break, else continue

        // Test with exactly 1 slot (should break immediately after first iteration)
        bytes32[] memory oneSlot = corkPool.extsload(bytes32(uint256(1)), 1);
        assertEq(oneSlot.length, 1);

        // Test with exactly 2 slots (should continue once, then break)
        bytes32[] memory twoSlots = corkPool.extsload(bytes32(uint256(1)), 2);
        assertEq(twoSlots.length, 2);

        // For specific slots - test the exact conditions
        bytes32[] memory specificSlots = new bytes32[](2);
        specificSlots[0] = bytes32(uint256(1));
        specificSlots[1] = bytes32(uint256(2));

        bytes32[] memory specificValues = corkPool.extsload(specificSlots);
        assertEq(specificValues.length, 2);

        // Test with large number to ensure multiple loop iterations
        bytes32[] memory largeSlots = new bytes32[](20);
        for (uint256 i = 0; i < 20; i++) {
            largeSlots[i] = bytes32(uint256(i + 1));
        }

        bytes32[] memory largeValues = corkPool.extsload(largeSlots);
        assertEq(largeValues.length, 20);
    }

    function test_ExtsloadForceAssemblyBranches() public {
        // Try to force both branches in the assembly loops
        // Branch 1: The loop condition that continues the loop
        // Branch 2: The loop condition that breaks the loop

        // Test consecutive slots with different scenarios
        // Scenario 1: Zero slots (should not enter loop)
        bytes32[] memory zeroSlots = corkPool.extsload(bytes32(uint256(1)), 0);
        assertEq(zeroSlots.length, 0);

        // Scenario 2: One slot (should enter loop once, then break)
        bytes32[] memory oneSlot = corkPool.extsload(bytes32(uint256(1)), 1);
        assertEq(oneSlot.length, 1);

        // Scenario 3: Multiple slots (should continue loop multiple times)
        bytes32[] memory multipleSlots = corkPool.extsload(bytes32(uint256(1)), 5);
        assertEq(multipleSlots.length, 5);

        // Test specific slots with different scenarios
        // Scenario 1: Empty array (should not enter loop)
        bytes32[] memory emptyArray = new bytes32[](0);
        bytes32[] memory emptyResult = corkPool.extsload(emptyArray);
        assertEq(emptyResult.length, 0);

        // Scenario 2: Single slot array (should enter loop once, then break)
        bytes32[] memory singleArray = new bytes32[](1);
        singleArray[0] = bytes32(uint256(1));
        bytes32[] memory singleResult = corkPool.extsload(singleArray);
        assertEq(singleResult.length, 1);

        // Scenario 3: Multiple slot array (should continue loop multiple times)
        bytes32[] memory multipleArray = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            multipleArray[i] = bytes32(uint256(i + 1));
        }
        bytes32[] memory multipleResult = corkPool.extsload(multipleArray);
        assertEq(multipleResult.length, 5);
    }

    function test_ExtsloadBoundaryConditions() public {
        // Test with slot 0
        bytes32 slot0 = bytes32(uint256(0));
        bytes32 value0 = corkPool.extsload(slot0);
        // Slot 0 is the states mapping root, should be 0
        assertEq(value0, bytes32(0));

        // Test with slot just before gap
        bytes32 slot2 = bytes32(uint256(2));
        bytes32 value2 = corkPool.extsload(slot2);
        assertEq(address(uint160(uint256(value2))), address(corkConfig));

        // Test with first gap slot
        bytes32 slot3 = bytes32(uint256(3));
        bytes32 value3 = corkPool.extsload(slot3);
        assertEq(value3, bytes32(0));
    }

    function test_ExtsloadLargeArrays() public {
        // Test reading a larger array of specific slots
        bytes32[] memory slots = new bytes32[](10);
        for (uint256 i = 0; i < 10; i++) {
            slots[i] = bytes32(uint256(100 + i)); // All should be empty
        }

        bytes32[] memory values = corkPool.extsload(slots);
        assertEq(values.length, 10);

        for (uint256 i = 0; i < values.length; i++) {
            assertEq(values[i], bytes32(0));
        }
    }

    function test_ExtsloadMixedSlotTypes() public {
        // Test reading a mix of empty and populated slots
        bytes32[] memory slots = new bytes32[](5);
        slots[0] = bytes32(uint256(1)); // SHARES_FACTORY (populated)
        slots[1] = bytes32(uint256(999)); // Empty slot
        slots[2] = bytes32(uint256(2)); // CONFIG (populated)
        slots[3] = bytes32(uint256(1000)); // Empty slot
        slots[4] = keccak256(abi.encode(id, 0)); // State mapping (populated)

        bytes32[] memory values = corkPool.extsload(slots);
        assertEq(values.length, 5);

        // Check populated slots
        assertEq(address(uint160(uint256(values[0]))), address(sharesFactory));
        assertEq(address(uint160(uint256(values[2]))), address(corkConfig));

        // Check empty slots
        assertEq(values[1], bytes32(0));
        assertEq(values[3], bytes32(0));
    }

    function test_ExtsloadAllFunctionVariants() public {
        // Test that all three function variants work correctly
        bytes32 targetSlot = bytes32(uint256(1)); // SHARES_FACTORY

        // Method 1: Single slot
        bytes32 singleResult = corkPool.extsload(targetSlot);

        // Method 2: Consecutive slots (1 slot)
        bytes32[] memory consecutiveResult = corkPool.extsload(targetSlot, 1);

        // Method 3: Specific slots (1 slot)
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = targetSlot;
        bytes32[] memory specificResult = corkPool.extsload(slots);

        // All should return the same value
        assertEq(singleResult, consecutiveResult[0]);
        assertEq(singleResult, specificResult[0]);
        assertEq(address(uint160(uint256(singleResult))), address(sharesFactory));
    }
}
