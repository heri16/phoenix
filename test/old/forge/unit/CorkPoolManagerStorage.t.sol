// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {CorkPoolManagerStorage} from "contracts/core/CorkPoolManagerStorage.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market} from "contracts/libraries/Market.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {Balances, CollateralAssetManager, CorkPoolPoolArchive, PoolState, State} from "contracts/libraries/State.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract CorkPoolManagerStorageHelper is CorkPoolManager {
    // Expose internal variables for testing
    function getStates(MarketId id) external view returns (State memory) {
        return data().states[id];
    }

    function getSwapSharesFactory() external view returns (address) {
        return data().SHARES_FACTORY;
    }

    // Expose internal functions for testing
    function exposedOnlyAdmin() external view {
        _onlyCorkController();
    }

    function exposedInitializeCorkPoolManagerStorage(address _swapSharesFactory, address _adapter, address _treasury, address _whitelistManager) external {
        initializeCorkPoolManagerStorage(_swapSharesFactory, _adapter, _treasury, _whitelistManager);
    }

    function exposedOnlyInitialized(MarketId id) external view {
        _onlyInitialized(id);
    }

    function exposedCorkPoolDepositAndMintNotPaused(MarketId id) external view {
        _corkPoolDepositAndMintNotPaused(id);
    }

    function exposedCorkPoolSwapNotPaused(MarketId id) external view {
        _corkPoolSwapNotPaused(id);
    }

    function exposedCorkPoolWithdrawalNotPaused(MarketId id) external view {
        _corkPoolWithdrawalNotPaused(id);
    }

    function exposedCorkPoolUnwindDepositNotPaused(MarketId id) external view {
        _corkPoolUnwindDepositAndMintNotPaused(id);
    }

    function exposedCorkPoolUnwindSwapNotPaused(MarketId id) external view {
        _corkPoolUnwindSwapAndExerciseNotPaused(id);
    }

    // Helper function to set state for testing
    function setState(MarketId id, State memory state) external {
        data().states[id] = state;
    }

    // Helper functions to set individual pause states for testing
    function setDepositPaused(MarketId id, bool paused) external {
        if (paused) data().states[id].pool.pauseBitMap |= 1;
        else data().states[id].pool.pauseBitMap &= ~uint16(1);
    }

    function setSwapPaused(MarketId id, bool paused) external {
        if (paused) data().states[id].pool.pauseBitMap |= 1 << 1;
        else data().states[id].pool.pauseBitMap &= ~(uint16(1) << 1);
    }

    function setWithdrawalPaused(MarketId id, bool paused) external {
        if (paused) data().states[id].pool.pauseBitMap |= 1 << 2;
        else data().states[id].pool.pauseBitMap &= ~(uint16(1) << 2);
    }

    function setUnwindDepositPaused(MarketId id, bool paused) external {
        if (paused) data().states[id].pool.pauseBitMap |= 1 << 3;
        else data().states[id].pool.pauseBitMap &= ~(uint16(1) << 3);
    }

    function setUnwindSwapPaused(MarketId id, bool paused) external {
        if (paused) data().states[id].pool.pauseBitMap |= 1 << 4;
        else data().states[id].pool.pauseBitMap &= ~(uint16(1) << 4);
    }

    // Helper to create initialized state
    function createInitializedState(MarketId id, address ca, address ra) external {
        State memory state;
        state.info.collateralAsset = ca;
        state.info.referenceAsset = ra;
        state.info.expiryTimestamp = block.timestamp + 1 days;
        data().states[id] = state;
    }
}

contract CorkPoolManagerStorageTest is Helper {
    CorkPoolManagerStorageHelper private CorkPoolManagerStorage;
    address private admin;
    address private manager;
    address private rateUpdater;
    address private user;
    address private swapSharesFactory;
    address private defaultCorkControllerContract;
    address private testWhitelistManager;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    MarketId id;

    function setUp() public {
        admin = address(1);
        manager = address(2);
        rateUpdater = address(3);
        user = address(5);
        swapSharesFactory = address(6);
        defaultCorkControllerContract = address(7);
        testWhitelistManager = address(8);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, id) = createNewPoolPair(block.timestamp + 1 days);
        vm.stopPrank();

        vm.startPrank(admin);
        CorkPoolManagerStorage = new CorkPoolManagerStorageHelper();
        vm.stopPrank();
    }

    // ================================ Helper Functions Tests ================================ //
    function test_getStates_ShouldReturnEmptyState_WhenNotSet() external {
        State memory state = CorkPoolManagerStorage.getStates(id);
        assertEq(state.info.collateralAsset, address(0), "CA should be zero");
        assertEq(state.info.referenceAsset, address(0), "RA should be zero");
        assertEq(state.info.expiryTimestamp, 0, "Expiry should be zero");
    }

    function test_getStates_ShouldReturnCorrectState_WhenSet() external {
        State memory expectedState;
        expectedState.info.collateralAsset = address(collateralAsset);
        expectedState.info.referenceAsset = address(referenceAsset);
        expectedState.info.expiryTimestamp = block.timestamp + 1 days;

        CorkPoolManagerStorage.setState(id, expectedState);
        State memory actualState = CorkPoolManagerStorage.getStates(id);

        assertEq(actualState.info.collateralAsset, expectedState.info.collateralAsset, "CA should match");
        assertEq(actualState.info.referenceAsset, expectedState.info.referenceAsset, "RA should match");
        assertEq(actualState.info.expiryTimestamp, expectedState.info.expiryTimestamp, "Expiry should match");
    }

    function test_getSwapSharesFactory_ShouldReturnZero_WhenNotInitialized() external {
        assertEq(CorkPoolManagerStorage.getSwapSharesFactory(), address(0), "Factory should be zero");
    }

    function test_getSwapSharesFactory_ShouldReturnCorrectAddress_WhenInitialized() external {
        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(swapSharesFactory, address(testOracle), CORK_PROTOCOL_TREASURY, testWhitelistManager);
        assertEq(CorkPoolManagerStorage.getSwapSharesFactory(), swapSharesFactory, "Factory should match");
    }

    // ================================ InitializeCorkPoolManagerStorage Tests ================================ //
    function test_exposedInitializeCorkPoolManagerStorage_ShouldRevert_WhenFactoryIsZero() external {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(address(0), address(testOracle), CORK_PROTOCOL_TREASURY, testWhitelistManager);
    }

    function test_exposedInitializeCorkPoolManagerStorage_ShouldRevert_WhenOracleIsZero() external {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(address(333), address(0), CORK_PROTOCOL_TREASURY, testWhitelistManager);
    }

    function test_exposedInitializeCorkPoolManagerStorage_ShouldSetVariables_WhenValidAddresses() external {
        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(swapSharesFactory, address(testOracle), CORK_PROTOCOL_TREASURY, testWhitelistManager);

        assertEq(CorkPoolManagerStorage.getSwapSharesFactory(), swapSharesFactory, "Factory should be set");
    }

    // ================================ OnlyAdmin Tests ================================ //
    function test_exposedOnlyAdmin_ShouldRevert_WhenCallerIsNotAdmin() external {
        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(swapSharesFactory, address(testOracle), CORK_PROTOCOL_TREASURY, testWhitelistManager);

        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        CorkPoolManagerStorage.exposedOnlyAdmin();
    }

    function test_exposedOnlyAdmin_ShouldRevert_WhenAdminNotSet() external {
        vm.expectRevert(abi.encodeWithSignature("OnlyCorkControllerAllowed()"));
        CorkPoolManagerStorage.exposedOnlyAdmin();
    }

    // ================================ OnlyInitialized Tests ================================ //
    function test_exposedOnlyInitialized_ShouldRevert_WhenStateNotInitialized() external {
        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        CorkPoolManagerStorage.exposedOnlyInitialized(id);
    }

    function test_exposedOnlyInitialized_ShouldPass_WhenStateIsInitialized() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedOnlyInitialized(id); // Should not revert
    }

    function test_exposedOnlyInitialized_ShouldRevert_WhenOnlyCAIsSet() external {
        State memory state;
        state.info.collateralAsset = address(collateralAsset);
        CorkPoolManagerStorage.setState(id, state);

        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        CorkPoolManagerStorage.exposedOnlyInitialized(id);
    }

    function test_exposedOnlyInitialized_ShouldRevert_WhenOnlyRAIsSet() external {
        State memory state;
        state.info.referenceAsset = address(referenceAsset);
        CorkPoolManagerStorage.setState(id, state);

        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        CorkPoolManagerStorage.exposedOnlyInitialized(id);
    }

    // ================================ Pause State Tests ================================ //
    function test_exposedCorkPoolDepositAndMintNotPaused_ShouldPass_WhenNotPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolDepositAndMintNotPaused_ShouldRevert_WhenPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.setDepositPaused(id, true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id);
    }

    function test_exposedCorkPoolSwapNotPaused_ShouldPass_WhenNotPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedCorkPoolSwapNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolSwapNotPaused_ShouldRevert_WhenPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.setSwapPaused(id, true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolSwapNotPaused(id);
    }

    function test_exposedCorkPoolWithdrawalNotPaused_ShouldPass_WhenNotPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedCorkPoolWithdrawalNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolWithdrawalNotPaused_ShouldRevert_WhenPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.setWithdrawalPaused(id, true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolWithdrawalNotPaused(id);
    }

    function test_exposedCorkPoolUnwindDepositNotPaused_ShouldPass_WhenNotPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedCorkPoolUnwindDepositNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolUnwindDepositNotPaused_ShouldRevert_WhenPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.setUnwindDepositPaused(id, true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolUnwindDepositNotPaused(id);
    }

    function test_exposedCorkPoolUnwindSwapNotPaused_ShouldPass_WhenNotPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedCorkPoolUnwindSwapNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolUnwindSwapNotPaused_ShouldRevert_WhenPaused() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.setUnwindSwapPaused(id, true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolUnwindSwapNotPaused(id);
    }

    // ================================ Edge Cases and Integration Tests ================================ //
    function test_allPauseStates_ShouldWorkIndependently() external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));

        // Test each pause state independently
        CorkPoolManagerStorage.setDepositPaused(id, true);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id);

        // Other operations should still work
        CorkPoolManagerStorage.exposedCorkPoolSwapNotPaused(id);
        CorkPoolManagerStorage.exposedCorkPoolWithdrawalNotPaused(id);
        CorkPoolManagerStorage.exposedCorkPoolUnwindDepositNotPaused(id);
        CorkPoolManagerStorage.exposedCorkPoolUnwindSwapNotPaused(id);
    }

    function test_multipleMarkets_ShouldWorkIndependently() external {
        MarketId id2 = MarketId.wrap(bytes32(uint256(2)));

        // Initialize both markets
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.createInitializedState(id2, address(collateralAsset), address(referenceAsset));

        // Pause one market
        CorkPoolManagerStorage.setDepositPaused(id, true);

        // First market should be paused
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id);

        // Second market should not be paused
        CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id2);
    }

    // ================================ Fuzz Tests ================================ //
    function testFuzz_initializeCorkPoolManagerStorage_ShouldHandleValidAddresses(address factory, address admin) external {
        vm.assume(factory != address(0) && admin != address(0));

        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(factory, address(testOracle), CORK_PROTOCOL_TREASURY, testWhitelistManager);

        assertEq(CorkPoolManagerStorage.getSwapSharesFactory(), factory, "Factory should match");
    }

    function testFuzz_onlyCorkController_ShouldOnlyAllowAdminCaller(address caller, address factory, address admin) external {
        vm.assume(factory != address(0) && admin != address(0));
        CorkPoolManagerStorage.exposedInitializeCorkPoolManagerStorage(factory, address(testOracle), CORK_PROTOCOL_TREASURY, testWhitelistManager);

        if (caller == defaultCorkControllerContract) {
            // vm.prank(caller);
            // CorkPoolManagerStorage.exposedOnlyAdmin(); // Should not revert
        } else {
            vm.prank(caller);
            vm.expectRevert(IErrors.OnlyCorkControllerAllowed.selector);
            CorkPoolManagerStorage.exposedOnlyAdmin();
        }
    }

    function testFuzz_pauseStates_ShouldToggleCorrectly(bool isDepositPaused, bool isSwapPaused, bool isWithdrawalPaused, bool isUnwindDepositPaused, bool isUnwindSwapPaused) external {
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));

        CorkPoolManagerStorage.setDepositPaused(id, isDepositPaused);
        CorkPoolManagerStorage.setSwapPaused(id, isSwapPaused);
        CorkPoolManagerStorage.setWithdrawalPaused(id, isWithdrawalPaused);
        CorkPoolManagerStorage.setUnwindDepositPaused(id, isUnwindDepositPaused);
        CorkPoolManagerStorage.setUnwindSwapPaused(id, isUnwindSwapPaused);

        // Test deposit pause
        if (isDepositPaused) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
            CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id);
        } else {
            CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id);
        }

        // Test swap pause
        if (isSwapPaused) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
            CorkPoolManagerStorage.exposedCorkPoolSwapNotPaused(id);
        } else {
            CorkPoolManagerStorage.exposedCorkPoolSwapNotPaused(id);
        }

        // Test withdrawal pause
        if (isWithdrawalPaused) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
            CorkPoolManagerStorage.exposedCorkPoolWithdrawalNotPaused(id);
        } else {
            CorkPoolManagerStorage.exposedCorkPoolWithdrawalNotPaused(id);
        }

        // Test return pause
        if (isUnwindDepositPaused) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
            CorkPoolManagerStorage.exposedCorkPoolUnwindDepositNotPaused(id);
        } else {
            CorkPoolManagerStorage.exposedCorkPoolUnwindDepositNotPaused(id);
        }

        // Test Unwind Swap pause
        if (isUnwindSwapPaused) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
            CorkPoolManagerStorage.exposedCorkPoolUnwindSwapNotPaused(id);
        } else {
            CorkPoolManagerStorage.exposedCorkPoolUnwindSwapNotPaused(id);
        }
    }

    // ================================ State Transition Tests ================================ //
    function test_stateTransitions_ShouldMaintainConsistency() external {
        // Start with uninitialized state
        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        CorkPoolManagerStorage.exposedOnlyInitialized(id);

        // Initialize the state
        CorkPoolManagerStorage.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        CorkPoolManagerStorage.exposedOnlyInitialized(id); // Should not revert

        // Verify state can be read
        State memory state = CorkPoolManagerStorage.getStates(id);
        assertEq(state.info.collateralAsset, address(collateralAsset), "CA should be set");
        assertEq(state.info.referenceAsset, address(referenceAsset), "RA should be set");
    }

    function test_complexStateManipulation_ShouldWorkCorrectly() external {
        // Create complex state
        State memory complexState;
        complexState.info.collateralAsset = address(collateralAsset);
        complexState.info.referenceAsset = address(referenceAsset);
        complexState.info.expiryTimestamp = block.timestamp + 1 days;
        complexState.pool.pauseBitMap = 1;
        complexState.pool.unwindSwapFeePercentage = 500; // 5%
        complexState.pool.swapFeePercentage = 300; // 3%
        complexState.pool.liquiditySeparated = true;

        CorkPoolManagerStorage.setState(id, complexState);
        State memory retrievedState = CorkPoolManagerStorage.getStates(id);

        // Verify all fields are set correctly
        assertEq(retrievedState.info.collateralAsset, complexState.info.collateralAsset, "CA should match");
        assertEq(retrievedState.info.referenceAsset, complexState.info.referenceAsset, "RA should match");
        assertEq(retrievedState.info.expiryTimestamp, complexState.info.expiryTimestamp, "Expiry should match");
        assertEq(retrievedState.pool.pauseBitMap, complexState.pool.pauseBitMap, "pause bitmaps should match");
        assertEq(retrievedState.pool.unwindSwapFeePercentage, complexState.pool.unwindSwapFeePercentage, "Unwind Swap fee should match");
        assertEq(retrievedState.pool.swapFeePercentage, complexState.pool.swapFeePercentage, "Redemption fee should match");
        assertEq(retrievedState.pool.liquiditySeparated, complexState.pool.liquiditySeparated, "Liquidity separated should match");

        // Test pause checks with this state
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        CorkPoolManagerStorage.exposedCorkPoolDepositAndMintNotPaused(id);

        CorkPoolManagerStorage.exposedCorkPoolSwapNotPaused(id); // Should not revert
    }
}
