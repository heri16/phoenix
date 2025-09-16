// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {ModuleState} from "contracts/core/ModuleState.sol";
import {Market} from "contracts/libraries/Market.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {Balances, CollateralAssetManager, CorkPoolPoolArchive, PoolState, State} from "contracts/libraries/State.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract ModuleStateHelper is ModuleState {
    // Expose internal variables for testing
    function getStates(MarketId id) external view returns (State memory) {
        return data().states[id];
    }

    function getSwapSharesFactory() external view returns (address) {
        return data().SHARES_FACTORY;
    }

    function getConfig() external view returns (address) {
        return data().CONFIG;
    }

    // Expose internal functions for testing
    function exposedOnlyConfig() external view {
        onlyConfig();
    }

    function exposedInitializeModuleState(address _swapSharesFactory, address _config, address _adapter) external {
        initializeModuleState(_swapSharesFactory, _config, _adapter);
    }

    function exposedOnlyInitialized(MarketId id) external view {
        onlyInitialized(id);
    }

    function exposedCorkPoolDepositAndMintNotPaused(MarketId id) external view {
        corkPoolDepositAndMintNotPaused(id);
    }

    function exposedCorkPoolSwapNotPaused(MarketId id) external view {
        corkPoolSwapNotPaused(id);
    }

    function exposedCorkPoolWithdrawalNotPaused(MarketId id) external view {
        corkPoolWithdrawalNotPaused(id);
    }

    function exposedCorkPoolUnwindDepositNotPaused(MarketId id) external view {
        corkPoolUnwindDepositAndMintNotPaused(id);
    }

    function exposedCorkPoolUnwindSwapNotPaused(MarketId id) external view {
        corkPoolUnwindSwapAndExerciseNotPaused(id);
    }

    // Helper function to set state for testing
    function setState(MarketId id, State memory state) external {
        data().states[id] = state;
    }

    // Helper functions to set individual pause states for testing
    function setDepositPaused(MarketId id, bool paused) external {
        data().states[id].pool.isDepositPaused = paused;
    }

    function setSwapPaused(MarketId id, bool paused) external {
        data().states[id].pool.isSwapPaused = paused;
    }

    function setWithdrawalPaused(MarketId id, bool paused) external {
        data().states[id].pool.isWithdrawalPaused = paused;
    }

    function setReturnPaused(MarketId id, bool paused) external {
        data().states[id].pool.isReturnPaused = paused;
    }

    function setUnwindSwapPaused(MarketId id, bool paused) external {
        data().states[id].pool.isUnwindSwapPaused = paused;
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

contract ModuleStateTest is Helper {
    ModuleStateHelper private moduleState;
    address private admin;
    address private manager;
    address private rateUpdater;
    address private user;
    address private swapSharesFactory;
    address private configContract;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    MarketId id;

    function setUp() public {
        admin = address(1);
        manager = address(2);
        rateUpdater = address(3);
        user = address(5);
        swapSharesFactory = address(6);
        configContract = address(7);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, id) = createNewPoolPair(block.timestamp + 1 days);
        vm.stopPrank();

        vm.startPrank(admin);
        moduleState = new ModuleStateHelper();
        vm.stopPrank();
    }

    // ================================ Helper Functions Tests ================================ //
    function test_getStates_ShouldReturnEmptyState_WhenNotSet() external {
        State memory state = moduleState.getStates(id);
        assertEq(state.info.collateralAsset, address(0), "CA should be zero");
        assertEq(state.info.referenceAsset, address(0), "RA should be zero");
        assertEq(state.info.expiryTimestamp, 0, "Expiry should be zero");
    }

    function test_getStates_ShouldReturnCorrectState_WhenSet() external {
        State memory expectedState;
        expectedState.info.collateralAsset = address(collateralAsset);
        expectedState.info.referenceAsset = address(referenceAsset);
        expectedState.info.expiryTimestamp = block.timestamp + 1 days;
        expectedState.pool.isDepositPaused = true;

        moduleState.setState(id, expectedState);
        State memory actualState = moduleState.getStates(id);

        assertEq(actualState.info.collateralAsset, expectedState.info.collateralAsset, "CA should match");
        assertEq(actualState.info.referenceAsset, expectedState.info.referenceAsset, "RA should match");
        assertEq(actualState.info.expiryTimestamp, expectedState.info.expiryTimestamp, "Expiry should match");
        assertEq(actualState.pool.isDepositPaused, expectedState.pool.isDepositPaused, "Deposit paused should match");
    }

    function test_getSwapSharesFactory_ShouldReturnZero_WhenNotInitialized() external {
        assertEq(moduleState.getSwapSharesFactory(), address(0), "Factory should be zero");
    }

    function test_getSwapSharesFactory_ShouldReturnCorrectAddress_WhenInitialized() external {
        moduleState.exposedInitializeModuleState(swapSharesFactory, configContract, address(testOracle));
        assertEq(moduleState.getSwapSharesFactory(), swapSharesFactory, "Factory should match");
    }

    function test_getConfig_ShouldReturnZero_WhenNotInitialized() external {
        assertEq(moduleState.getConfig(), address(0), "Config should be zero");
    }

    function test_getConfig_ShouldReturnCorrectAddress_WhenInitialized() external {
        moduleState.exposedInitializeModuleState(swapSharesFactory, configContract, address(testOracle));
        assertEq(moduleState.getConfig(), configContract, "Config should match");
    }

    // ================================ Factory Function Tests ================================ //
    function test_factory_ShouldReturnZero_WhenNotInitialized() external {
        assertEq(moduleState.factory(), address(0), "Factory should be zero");
    }

    function test_factory_ShouldReturnCorrectAddress_WhenInitialized() external {
        moduleState.exposedInitializeModuleState(swapSharesFactory, configContract, address(testOracle));
        assertEq(moduleState.factory(), swapSharesFactory, "Factory should match");
    }

    // ================================ InitializeModuleState Tests ================================ //
    function test_exposedInitializeModuleState_ShouldRevert_WhenFactoryIsZero() external {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        moduleState.exposedInitializeModuleState(address(0), configContract, address(testOracle));
    }

    function test_exposedInitializeModuleState_ShouldRevert_WhenConfigIsZero() external {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        moduleState.exposedInitializeModuleState(swapSharesFactory, address(0), address(testOracle));
    }

    function test_exposedInitializeModuleState_ShouldRevert_WhenBothAreZero() external {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        moduleState.exposedInitializeModuleState(address(0), address(0), address(testOracle));
    }

    function test_exposedInitializeModuleState_ShouldSetVariables_WhenValidAddresses() external {
        moduleState.exposedInitializeModuleState(swapSharesFactory, configContract, address(testOracle));

        assertEq(moduleState.getSwapSharesFactory(), swapSharesFactory, "Factory should be set");
        assertEq(moduleState.getConfig(), configContract, "Config should be set");
    }

    // ================================ OnlyConfig Tests ================================ //
    function test_exposedOnlyConfig_ShouldRevert_WhenCallerIsNotConfig() external {
        moduleState.exposedInitializeModuleState(swapSharesFactory, configContract, address(testOracle));

        vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
        moduleState.exposedOnlyConfig();
    }

    function test_exposedOnlyConfig_ShouldPass_WhenCallerIsConfig() external {
        moduleState.exposedInitializeModuleState(swapSharesFactory, configContract, address(testOracle));

        vm.prank(configContract);
        moduleState.exposedOnlyConfig(); // Should not revert
    }

    function test_exposedOnlyConfig_ShouldRevert_WhenConfigNotSet() external {
        vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
        moduleState.exposedOnlyConfig();
    }

    // ================================ GetTreasuryAddress Tests ================================ //
    function test_getTreasuryAddress_ShouldReturnCorrectAddress_WhenConfigIsSet() external {
        moduleState.exposedInitializeModuleState(address(sharesFactory), address(corkConfig), address(testOracle));
        assertEq(moduleState.getTreasuryAddress(), CORK_PROTOCOL_TREASURY, "Treasury should match");
    }

    function test_getTreasuryAddress_ShouldRevert_WhenConfigNotSet() external {
        vm.expectRevert();
        moduleState.getTreasuryAddress();
    }

    // ================================ OnlyInitialized Tests ================================ //
    function test_exposedOnlyInitialized_ShouldRevert_WhenStateNotInitialized() external {
        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        moduleState.exposedOnlyInitialized(id);
    }

    function test_exposedOnlyInitialized_ShouldPass_WhenStateIsInitialized() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedOnlyInitialized(id); // Should not revert
    }

    function test_exposedOnlyInitialized_ShouldRevert_WhenOnlyCAIsSet() external {
        State memory state;
        state.info.collateralAsset = address(collateralAsset);
        moduleState.setState(id, state);

        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        moduleState.exposedOnlyInitialized(id);
    }

    function test_exposedOnlyInitialized_ShouldRevert_WhenOnlyRAIsSet() external {
        State memory state;
        state.info.referenceAsset = address(referenceAsset);
        moduleState.setState(id, state);

        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        moduleState.exposedOnlyInitialized(id);
    }

    // ================================ Pause State Tests ================================ //
    function test_exposedCorkPoolDepositAndMintNotPaused_ShouldPass_WhenNotPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedCorkPoolDepositAndMintNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolDepositAndMintNotPaused_ShouldRevert_WhenPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.setDepositPaused(id, true);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolDepositAndMintNotPaused(id);
    }

    function test_exposedCorkPoolSwapNotPaused_ShouldPass_WhenNotPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedCorkPoolSwapNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolSwapNotPaused_ShouldRevert_WhenPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.setSwapPaused(id, true);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolSwapNotPaused(id);
    }

    function test_exposedCorkPoolWithdrawalNotPaused_ShouldPass_WhenNotPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedCorkPoolWithdrawalNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolWithdrawalNotPaused_ShouldRevert_WhenPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.setWithdrawalPaused(id, true);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolWithdrawalNotPaused(id);
    }

    function test_exposedCorkPoolUnwindDepositNotPaused_ShouldPass_WhenNotPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedCorkPoolUnwindDepositNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolUnwindDepositNotPaused_ShouldRevert_WhenPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.setReturnPaused(id, true);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolUnwindDepositNotPaused(id);
    }

    function test_exposedCorkPoolUnwindSwapNotPaused_ShouldPass_WhenNotPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedCorkPoolUnwindSwapNotPaused(id); // Should not revert
    }

    function test_exposedCorkPoolUnwindSwapNotPaused_ShouldRevert_WhenPaused() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.setUnwindSwapPaused(id, true);

        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolUnwindSwapNotPaused(id);
    }

    // ================================ Edge Cases and Integration Tests ================================ //
    function test_allPauseStates_ShouldWorkIndependently() external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));

        // Test each pause state independently
        moduleState.setDepositPaused(id, true);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolDepositAndMintNotPaused(id);

        // Other operations should still work
        moduleState.exposedCorkPoolSwapNotPaused(id);
        moduleState.exposedCorkPoolWithdrawalNotPaused(id);
        moduleState.exposedCorkPoolUnwindDepositNotPaused(id);
        moduleState.exposedCorkPoolUnwindSwapNotPaused(id);
    }

    function test_multipleMarkets_ShouldWorkIndependently() external {
        MarketId id2 = MarketId.wrap(bytes32(uint256(2)));

        // Initialize both markets
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.createInitializedState(id2, address(collateralAsset), address(referenceAsset));

        // Pause one market
        moduleState.setDepositPaused(id, true);

        // First market should be paused
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolDepositAndMintNotPaused(id);

        // Second market should not be paused
        moduleState.exposedCorkPoolDepositAndMintNotPaused(id2);
    }

    // ================================ Fuzz Tests ================================ //
    function testFuzz_initializeModuleState_ShouldHandleValidAddresses(address factory, address config) external {
        vm.assume(factory != address(0) && config != address(0));

        moduleState.exposedInitializeModuleState(factory, config, address(testOracle));

        assertEq(moduleState.getSwapSharesFactory(), factory, "Factory should match");
        assertEq(moduleState.getConfig(), config, "Config should match");
    }

    function testFuzz_onlyConfig_ShouldOnlyAllowConfigCaller(address caller, address factory, address config) external {
        vm.assume(factory != address(0) && config != address(0));
        moduleState.exposedInitializeModuleState(factory, config, address(testOracle));

        if (caller == config) {
            vm.prank(caller);
            moduleState.exposedOnlyConfig(); // Should not revert
        } else {
            vm.prank(caller);
            vm.expectRevert(abi.encodeWithSignature("OnlyConfigAllowed()"));
            moduleState.exposedOnlyConfig();
        }
    }

    function testFuzz_pauseStates_ShouldToggleCorrectly(bool isDepositPaused, bool isSwapPaused, bool isWithdrawalPaused, bool isReturnPaused, bool isUnwindSwapPaused) external {
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));

        moduleState.setDepositPaused(id, isDepositPaused);
        moduleState.setSwapPaused(id, isSwapPaused);
        moduleState.setWithdrawalPaused(id, isWithdrawalPaused);
        moduleState.setReturnPaused(id, isReturnPaused);
        moduleState.setUnwindSwapPaused(id, isUnwindSwapPaused);

        // Test deposit pause
        if (isDepositPaused) {
            vm.expectRevert(abi.encodeWithSignature("Paused()"));
            moduleState.exposedCorkPoolDepositAndMintNotPaused(id);
        } else {
            moduleState.exposedCorkPoolDepositAndMintNotPaused(id);
        }

        // Test swap pause
        if (isSwapPaused) {
            vm.expectRevert(abi.encodeWithSignature("Paused()"));
            moduleState.exposedCorkPoolSwapNotPaused(id);
        } else {
            moduleState.exposedCorkPoolSwapNotPaused(id);
        }

        // Test withdrawal pause
        if (isWithdrawalPaused) {
            vm.expectRevert(abi.encodeWithSignature("Paused()"));
            moduleState.exposedCorkPoolWithdrawalNotPaused(id);
        } else {
            moduleState.exposedCorkPoolWithdrawalNotPaused(id);
        }

        // Test return pause
        if (isReturnPaused) {
            vm.expectRevert(abi.encodeWithSignature("Paused()"));
            moduleState.exposedCorkPoolUnwindDepositNotPaused(id);
        } else {
            moduleState.exposedCorkPoolUnwindDepositNotPaused(id);
        }

        // Test Unwind Swap pause
        if (isUnwindSwapPaused) {
            vm.expectRevert(abi.encodeWithSignature("Paused()"));
            moduleState.exposedCorkPoolUnwindSwapNotPaused(id);
        } else {
            moduleState.exposedCorkPoolUnwindSwapNotPaused(id);
        }
    }

    // ================================ State Transition Tests ================================ //
    function test_stateTransitions_ShouldMaintainConsistency() external {
        // Start with uninitialized state
        vm.expectRevert(abi.encodeWithSignature("NotInitialized()"));
        moduleState.exposedOnlyInitialized(id);

        // Initialize the state
        moduleState.createInitializedState(id, address(collateralAsset), address(referenceAsset));
        moduleState.exposedOnlyInitialized(id); // Should not revert

        // Verify state can be read
        State memory state = moduleState.getStates(id);
        assertEq(state.info.collateralAsset, address(collateralAsset), "CA should be set");
        assertEq(state.info.referenceAsset, address(referenceAsset), "RA should be set");
    }

    function test_complexStateManipulation_ShouldWorkCorrectly() external {
        // Create complex state
        State memory complexState;
        complexState.info.collateralAsset = address(collateralAsset);
        complexState.info.referenceAsset = address(referenceAsset);
        complexState.info.expiryTimestamp = block.timestamp + 1 days;
        complexState.pool.isDepositPaused = true;
        complexState.pool.isSwapPaused = false;
        complexState.pool.unwindSwapFeePercentage = 500; // 5%
        complexState.pool.baseRedemptionFeePercentage = 300; // 3%
        complexState.pool.liquiditySeparated = true;

        moduleState.setState(id, complexState);
        State memory retrievedState = moduleState.getStates(id);

        // Verify all fields are set correctly
        assertEq(retrievedState.info.collateralAsset, complexState.info.collateralAsset, "CA should match");
        assertEq(retrievedState.info.referenceAsset, complexState.info.referenceAsset, "RA should match");
        assertEq(retrievedState.info.expiryTimestamp, complexState.info.expiryTimestamp, "Expiry should match");
        assertEq(retrievedState.pool.isDepositPaused, complexState.pool.isDepositPaused, "Deposit pause should match");
        assertEq(retrievedState.pool.isSwapPaused, complexState.pool.isSwapPaused, "Swap pause should match");
        assertEq(retrievedState.pool.unwindSwapFeePercentage, complexState.pool.unwindSwapFeePercentage, "Unwind Swap fee should match");
        assertEq(retrievedState.pool.baseRedemptionFeePercentage, complexState.pool.baseRedemptionFeePercentage, "Redemption fee should match");
        assertEq(retrievedState.pool.liquiditySeparated, complexState.pool.liquiditySeparated, "Liquidity separated should match");

        // Test pause checks with this state
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        moduleState.exposedCorkPoolDepositAndMintNotPaused(id);

        moduleState.exposedCorkPoolSwapNotPaused(id); // Should not revert
    }
}
