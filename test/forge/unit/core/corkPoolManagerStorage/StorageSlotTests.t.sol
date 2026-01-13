// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/forge/BaseTest.sol";

contract StorageSlotTests is BaseTest {
    function test_CorkPoolManagerStorage_ShouldHaveCorrectStorageSlot() public view {
        // Verify ERC-7201 storage position constant for CorkPoolManagerStorage
        // Expected: keccak256(abi.encode(uint256(keccak256("cork.storage.CorkPoolManagerStorage")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 expectedStoragePosition = 0xca60d71d44db08890954961692d4c0e9107284a789e12b27f483ad59d898d200;

        // Calculate the storage position using ERC-7201 formula
        bytes32 baseHash = keccak256("cork.storage.CorkPoolManagerStorage");
        bytes32 computedPosition = keccak256(abi.encode(uint256(baseHash) - 1)) & ~bytes32(uint256(0xff));

        // Verify the computed position matches the expected constant
        assertEq(computedPosition, expectedStoragePosition, "Computed storage position doesn't match expected constant");

        // Verify the storage position is actually being used in the contract
        // Storage struct layout:
        // - Slot 0: mapping(MarketId => State) states
        // - Slot 1: address SHARES_FACTORY
        // - Slot 2: address CONSTRAINT_ADAPTER
        // - Slot 3: address TREASURY
        // - Slot 4: address WHITELIST_MANAGER

        // Read SHARES_FACTORY (slot 1 offset from base)
        bytes32 sharesFactorySlot = bytes32(uint256(expectedStoragePosition) + 1);
        bytes32 storedSharesFactory = vm.load(address(corkPoolManager), sharesFactorySlot);
        address sharesFactoryFromStorage = address(uint160(uint256(storedSharesFactory)));
        assertEq(
            sharesFactoryFromStorage, address(sharesFactory), "SHARES_FACTORY not found at expected storage position"
        );

        // Read CONSTRAINT_ADAPTER (slot 2 offset from base)
        bytes32 constraintAdapterSlot = bytes32(uint256(expectedStoragePosition) + 2);
        bytes32 storedConstraintAdapter = vm.load(address(corkPoolManager), constraintAdapterSlot);
        address constraintAdapterFromStorage = address(uint160(uint256(storedConstraintAdapter)));
        assertEq(
            constraintAdapterFromStorage,
            address(constraintRateAdapter),
            "CONSTRAINT_ADAPTER not found at expected storage position"
        );

        // Read TREASURY (slot 3 offset from base)
        bytes32 treasurySlot = bytes32(uint256(expectedStoragePosition) + 3);
        bytes32 storedTreasury = vm.load(address(corkPoolManager), treasurySlot);
        address treasuryFromStorage = address(uint160(uint256(storedTreasury)));
        assertEq(treasuryFromStorage, CORK_PROTOCOL_TREASURY, "TREASURY not found at expected storage position");

        // Read WHITELIST_MANAGER (slot 4 offset from base)
        bytes32 whitelistManagerSlot = bytes32(uint256(expectedStoragePosition) + 4);
        bytes32 storedWhitelistManager = vm.load(address(corkPoolManager), whitelistManagerSlot);
        address whitelistManagerFromStorage = address(uint160(uint256(storedWhitelistManager)));
        assertEq(
            whitelistManagerFromStorage,
            address(whitelistManager),
            "WHITELIST_MANAGER not found at expected storage position"
        );
    }
}
