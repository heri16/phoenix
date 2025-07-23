// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {IConfig} from "contracts/interfaces/IConfig.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract CorkConfigTest is Helper {
    CorkConfig private config;
    address private admin;
    address private manager;
    address private rateUpdater;
    address private user;

    DummyWETH collateralAsset;
    DummyWETH referenceAsset;
    MarketId id;

    // events
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event CorkPoolSet(address corkPool);
    event TreasurySet(address treasury);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);
    event DepositPaused(MarketId indexed marketId);
    event DepositUnpaused(MarketId indexed marketId);
    event UnwindSwapPaused(MarketId indexed marketId);
    event UnwindSwapUnpaused(MarketId indexed marketId);
    event SwapPaused(MarketId indexed marketId);
    event SwapUnpaused(MarketId indexed marketId);
    event WithdrawalPaused(MarketId indexed marketId);
    event WithdrawalUnpaused(MarketId indexed marketId);
    event ReturnPaused(MarketId indexed marketId);
    event ReturnUnpaused(MarketId indexed marketId);

    function setUp() public {
        admin = address(1);
        manager = address(2);
        rateUpdater = address(3);
        user = address(5);

        vm.startPrank(admin);
        config = new CorkConfig(admin, manager);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, id) = createNewMarketPair(block.timestamp + 1 days);
        vm.stopPrank();
    }

    // ----------------------- Tests for constant variables of CorkConfig contract -----------------------//
    function test_CorkConfigRolesVariables() public {
        assertEq(config.MANAGER_ROLE(), keccak256("MANAGER_ROLE"));
        assertEq(config.RATE_UPDATERS_ROLE(), keccak256("RATE_UPDATERS_ROLE"));
        assertEq(config.MARKET_ADMIN_ROLE(), keccak256("MARKET_ADMIN"));
    }
    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- Tests for CorkConfig constructor ---------------------------------//
    function test_CorkConfigConstructorRevertWhenPassedZeroAddress() public {
        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(address(0), address(0));

        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(address(0), manager);

        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(manager, address(0));
    }

    function test_CorkConfigConstructorShouldWorkCorrectly() public {
        // Assign roles correctly
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.MANAGER_ROLE(), manager), true);
        assertEq(config.hasRole(config.MARKET_ADMIN_ROLE(), manager), true);
        assertEq(config.hasRole(config.RATE_UPDATERS_ROLE(), manager), false);

        // Assign Role Hierarchy correctly
        assertEq(config.getRoleAdmin(config.MANAGER_ROLE()), config.DEFAULT_ADMIN_ROLE());
        assertEq(config.getRoleAdmin(config.RATE_UPDATERS_ROLE()), config.MANAGER_ROLE());
        assertEq(config.getRoleAdmin(config.MARKET_ADMIN_ROLE()), config.MANAGER_ROLE());

        // Assign variables correctly
        assertNotEq(address(config.defaultExchangeRateProvider()), address(0));
        assertEq(address(config.corkPool()), address(0));
        assertEq(address(config.treasury()), address(0));
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setRoleAdmin ----------------------------------------//
    function test_SetRoleAdminRevertWhenCalledByNonManagerRole() public {
        bytes32 updaterRole = config.RATE_UPDATERS_ROLE();
        bytes32 marketAdminRole = config.MARKET_ADMIN_ROLE();

        assertEq(config.getRoleAdmin(updaterRole), config.MANAGER_ROLE());

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, config.MANAGER_ROLE()));
        config.setRoleAdmin(updaterRole, marketAdminRole);

        assertEq(config.getRoleAdmin(updaterRole), config.MANAGER_ROLE());
    }

    function test_SetRoleAdminRevertWhenPassedSameRole() public {
        bytes32 updaterRole = config.RATE_UPDATERS_ROLE();
        bytes32 managerRole = config.MANAGER_ROLE();
        assertEq(config.getRoleAdmin(updaterRole), config.MANAGER_ROLE());

        vm.startPrank(manager);
        vm.expectRevert(IConfig.InvalidAdminRole.selector);
        config.setRoleAdmin(updaterRole, managerRole);

        assertEq(config.getRoleAdmin(updaterRole), config.MANAGER_ROLE());
    }

    function test_SetRoleAdminShouldWorkCorrectly() public {
        bytes32 updaterRole = config.RATE_UPDATERS_ROLE();
        bytes32 marketAdminRole = config.MARKET_ADMIN_ROLE();
        assertEq(config.getRoleAdmin(updaterRole), config.MANAGER_ROLE());

        vm.startPrank(manager);
        vm.expectEmit(false, false, false, true);
        emit RoleAdminChanged(updaterRole, config.MANAGER_ROLE(), marketAdminRole);
        config.setRoleAdmin(updaterRole, marketAdminRole);

        assertEq(config.getRoleAdmin(updaterRole), marketAdminRole);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for grantRole ------------------------------------------//
    function test_GrantRoleRevertWhenCalledByNonManager() public {
        bytes32 role = config.RATE_UPDATERS_ROLE();
        vm.startPrank(user);
        assertFalse(config.hasRole(role, rateUpdater));

        vm.expectRevert(IConfig.CallerNotManager.selector);
        config.grantRole(role, rateUpdater);
        assertFalse(config.hasRole(role, rateUpdater));
    }

    function test_GrantRoleRevertWhenAccountAlreadyHasThatRole() public {
        bytes32 marketAdminRole = config.MARKET_ADMIN_ROLE();
        bytes32 managerRole = config.MANAGER_ROLE();
        assertEq(config.hasRole(marketAdminRole, manager), true);

        vm.startPrank(manager);
        vm.expectRevert(IConfig.InvalidRole.selector);
        config.grantRole(marketAdminRole, manager);

        assertEq(config.hasRole(marketAdminRole, manager), true);
        assertEq(config.hasRole(managerRole, manager), true);

        vm.startPrank(manager);
        vm.expectRevert(IConfig.InvalidRole.selector);
        config.grantRole(managerRole, manager);

        assertEq(config.hasRole(managerRole, manager), true);
    }

    function test_GrantRoleShouldWorkCorrectly() public {
        bytes32 role = config.RATE_UPDATERS_ROLE();
        vm.startPrank(manager);
        assertFalse(config.hasRole(role, rateUpdater));

        vm.expectEmit(false, false, false, true);
        emit RoleGranted(role, rateUpdater, manager);
        config.grantRole(role, rateUpdater);
        assertTrue(config.hasRole(role, rateUpdater));
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for transferAdmin ----------------------------------------//
    function test_TransferAdminRevertWhenCalledByNonAdmin() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, config.DEFAULT_ADMIN_ROLE()));
        config.transferAdmin(rateUpdater);

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);
    }

    function test_TransferAdminRevertWhenPassedZeroAddress() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);

        vm.startPrank(admin);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.transferAdmin(address(0));

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);
    }

    function test_TransferAdminRevertWhenPassedCurrentAdminAddress() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);

        vm.startPrank(admin);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.transferAdmin(admin);

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);
    }

    function test_TransferAdminShouldWorkCorrectly() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), false);

        vm.startPrank(admin);
        vm.expectEmit(false, false, false, true);
        emit RoleGranted(config.DEFAULT_ADMIN_ROLE(), rateUpdater, admin);
        config.transferAdmin(rateUpdater);

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), rateUpdater), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), false);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setCorkPool ----------------------------------------//
    function test_SetCorkPoolRevertWhenCalledByNonManager() public {
        address mockCorkPool = address(5);
        assertEq(address(config.corkPool()), address(0));

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        config.setCorkPool(mockCorkPool);

        assertEq(address(config.corkPool()), address(0));
    }

    function test_SetCorkPoolRevertWhenPassedZeroAddress() public {
        assertEq(address(config.corkPool()), address(0));

        vm.startPrank(manager);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.setCorkPool(address(0));

        assertEq(address(config.corkPool()), address(0));
    }

    function test_SetCorkPoolShouldWorkCorrectly() public {
        assertEq(address(config.corkPool()), address(0));
        address mockCorkPool = address(5);

        vm.startPrank(manager);
        vm.expectEmit(false, false, false, true);
        emit CorkPoolSet(mockCorkPool);
        config.setCorkPool(mockCorkPool);

        assertEq(address(config.corkPool()), mockCorkPool);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setTreasury ----------------------------------------//
    function test_SetTreasuryRevertWhenCalledByNonManager() public {
        assertEq(address(config.treasury()), address(0));
        address mockTreasury = address(5);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        config.setTreasury(mockTreasury);

        assertEq(address(config.treasury()), address(0));
    }

    function test_SetTreasuryRevertWhenPassedZeroAddress() public {
        assertEq(address(config.treasury()), address(0));

        vm.startPrank(manager);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.setTreasury(address(0));

        assertEq(address(config.treasury()), address(0));
    }

    function test_SetTreasuryShouldWorkCorrectly() public {
        assertEq(address(config.treasury()), address(0));
        address mockTreasury = address(5);

        vm.startPrank(manager);
        vm.expectEmit(false, false, false, true);
        emit TreasurySet(mockTreasury);
        config.setTreasury(mockTreasury);

        assertEq(address(config.treasury()), mockTreasury);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for createNewMarket ----------------------------------------//
    function test_InitializeCorkPoolRevertWhenCalledByNonMarketAdmin() public {
        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotMarketAdmin.selector);
        corkConfig.createNewMarket(address(collateralAsset), address(referenceAsset), 0, address(0));
    }

    function test_initializeCorkPoolRevertWhenConfigIsPaused() external {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pause();
        assertTrue(corkConfig.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        corkConfig.createNewMarket(address(collateralAsset), address(referenceAsset), 0, address(0));
    }

    function test_initializeCorkPoolShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        address paAddress;
        address raAddress;
        uint256 expiryTimestamp;
        address exchangeRateProvider;
        (paAddress, raAddress, expiryTimestamp, exchangeRateProvider) = corkPool.marketDetails(id);

        assertEq(paAddress, address(0));
        assertEq(raAddress, address(0));
        assertEq(expiryTimestamp, 0);
        assertEq(exchangeRateProvider, address(0));

        MarketId id = corkPool.getId(address(referenceAsset), address(collateralAsset), 1 days, address(corkConfig.defaultExchangeRateProvider()));
        corkConfig.updateCorkPoolRate(id, defaultExchangeRate());
        corkConfig.createNewMarket(address(referenceAsset), address(collateralAsset), 1 days, address(corkConfig.defaultExchangeRateProvider()));

        (paAddress, raAddress, expiryTimestamp, exchangeRateProvider) = corkPool.marketDetails(id);
        assertEq(paAddress, address(referenceAsset));
        assertEq(raAddress, address(collateralAsset));
        assertEq(expiryTimestamp, 1 days);
        assertEq(exchangeRateProvider, address(corkConfig.defaultExchangeRateProvider()));
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateUnwindSwapFeeRate ----------------------------------------//
    function test_UpdateUnwindSwapFeeRateRevertWhenCalledByNonManager() public {
        assertEq(corkPool.unwindSwapFee(id), 0);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.updateUnwindSwapFeeRate(id, 1 ether);

        assertEq(corkPool.unwindSwapFee(id), 0);
    }

    function test_UpdateUnwindSwapFeeRateShouldWorkCorrectly() public {
        assertEq(corkPool.unwindSwapFee(id), 0);

        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateUnwindSwapFeeRate(id, 1.123 ether);

        assertEq(corkPool.unwindSwapFee(id), 1.123 ether);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateBaseRedemptionFeePercentage ----------------------------------------//
    function test_UpdateBaseRedemptionFeePercentageRevertWhenCalledByNonManager() public {
        assertEq(corkPool.baseRedemptionFee(id), 0);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.updateBaseRedemptionFeePercentage(id, 1 ether);

        assertEq(corkPool.baseRedemptionFee(id), 0);
    }

    function test_UpdateBaseRedemptionFeePercentageShouldWorkCorrectly() public {
        assertEq(corkPool.baseRedemptionFee(id), 0);

        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateBaseRedemptionFeePercentage(id, 1.123 ether);

        assertEq(corkPool.baseRedemptionFee(id), 1.123 ether);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateCorkPoolRate ----------------------------------------//
    function test_UpdateCorkPoolRateRevertWhenCalledByNonUpdaterOrManager() public {
        assertEq(corkConfig.defaultExchangeRateProvider().rate(id), 0);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.updateCorkPoolRate(id, 1 ether);

        assertEq(corkConfig.defaultExchangeRateProvider().rate(id), 0);
    }

    function test_UpdateCorkPoolRateShouldWorkCorrectly() public {
        assertEq(corkConfig.defaultExchangeRateProvider().rate(id), 0);

        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateCorkPoolRate(id, 1.123 ether);

        assertEq(corkConfig.defaultExchangeRateProvider().rate(id), 1.123 ether);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pause ----------------------------------------//
    function test_PauseShouldRevertWhenCalledByNonManager() public {
        assertFalse(config.paused());

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        config.pause();

        assertFalse(config.paused());
    }

    function test_PauseShouldRevertWhenAlreadyPaused() public {
        vm.startPrank(manager);
        config.pause();
        assertTrue(config.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        config.pause();

        assertTrue(config.paused());
    }

    function test_PauseShouldWorkCorrectly() public {
        assertFalse(config.paused());

        vm.startPrank(manager);
        vm.expectEmit(false, false, false, true);
        emit Paused(manager);
        config.pause();

        assertTrue(config.paused());
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpause ----------------------------------------//
    function test_UnpauseShouldRevertWhenCalledByNonManager() public {
        vm.startPrank(manager);
        config.pause();
        assertTrue(config.paused());

        vm.startPrank(address(8));
        vm.expectRevert(IConfig.CallerNotManager.selector);
        config.unpause();
        assertTrue(config.paused());
    }

    function test_UnpauseShouldRevertWhenNotPaused() public {
        assertFalse(config.paused());

        vm.startPrank(manager);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        config.unpause();

        assertFalse(config.paused());
    }

    function test_UnpauseShouldWorkCorrectly() public {
        vm.startPrank(manager);
        config.pause();
        assertTrue(config.paused());

        vm.expectEmit(false, false, false, true);
        emit Unpaused(manager);
        config.unpause();
        assertFalse(config.paused());
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseDeposits ----------------------------------------//
    function test_PauseDepositsRevertWhenCalledByNonManager() public {
        (bool depositPaused,,,,) = corkPool.pausedStates(id);
        assertFalse(depositPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.pauseDeposits(id);

        (depositPaused,,,,) = corkPool.pausedStates(id);
        assertFalse(depositPaused);
    }

    function test_PauseDepositsShouldWorkCorrectly() public {
        (bool depositPaused,,,,) = corkPool.pausedStates(id);
        assertFalse(depositPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit DepositPaused(id);
        corkConfig.pauseDeposits(id);

        (depositPaused,,,,) = corkPool.pausedStates(id);
        assertTrue(depositPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseDeposits ----------------------------------------//
    function test_UnpauseDepositsShouldRevertWhenCalledByNonManager() public {
        (bool depositPaused,,,,) = corkPool.pausedStates(id);
        assertFalse(depositPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.unpauseDeposits(id);
    }

    function test_UnpauseDepositsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseDeposits(id);

        (bool depositPaused,,,,) = corkPool.pausedStates(id);
        assertTrue(depositPaused);

        vm.expectEmit(false, false, false, true);
        emit DepositUnpaused(id);
        corkConfig.unpauseDeposits(id);

        (depositPaused,,,,) = corkPool.pausedStates(id);
        assertFalse(depositPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseunwindSwap ----------------------------------------//
    function test_PauseUnwindSwapsRevertWhenCalledByNonManager() public {
        (, bool UnwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertFalse(UnwindSwapPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.pauseUnwindSwaps(id);

        (, UnwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertFalse(UnwindSwapPaused);
    }

    function test_PauseUnwindSwapsShouldWorkCorrectly() public {
        (, bool unwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertFalse(unwindSwapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit UnwindSwapPaused(id);
        corkConfig.pauseUnwindSwaps(id);

        (, unwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertTrue(unwindSwapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseunwindSwap ----------------------------------------//
    function test_UnpauseUnwindSwapsRevertWhenCalledByNonManager() public {
        (, bool UnwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertFalse(UnwindSwapPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.unpauseUnwindSwaps(id);

        (, UnwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertFalse(UnwindSwapPaused);
    }

    function test_UnpauseUnwindSwapsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseUnwindSwaps(id);

        (, bool UnwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertTrue(UnwindSwapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit UnwindSwapUnpaused(id);
        corkConfig.unpauseUnwindSwaps(id);

        (, UnwindSwapPaused,,,) = corkPool.pausedStates(id);
        assertFalse(UnwindSwapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseSwap ----------------------------------------//
    function test_PauseSwapRevertWhenCalledByNonManager() public {
        (,, bool swapPaused,,) = corkPool.pausedStates(id);
        assertFalse(swapPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.pauseSwaps(id);

        (,, swapPaused,,) = corkPool.pausedStates(id);
        assertFalse(swapPaused);
    }

    function test_PauseSwapShouldWorkCorrectly() public {
        (,, bool swapPaused,,) = corkPool.pausedStates(id);
        assertFalse(swapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit SwapPaused(id);
        corkConfig.pauseSwaps(id);

        (,, swapPaused,,) = corkPool.pausedStates(id);
        assertTrue(swapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseSwap ----------------------------------------//
    function test_UnpauseSwapRevertWhenCalledByNonManager() public {
        (,, bool swapPaused,,) = corkPool.pausedStates(id);
        assertFalse(swapPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.unpauseSwaps(id);

        (,, swapPaused,,) = corkPool.pausedStates(id);
        assertFalse(swapPaused);
    }

    function test_UnpauseSwapShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseSwaps(id);

        (,, bool swapPaused,,) = corkPool.pausedStates(id);
        assertTrue(swapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit SwapUnpaused(id);
        corkConfig.unpauseSwaps(id);

        (,, swapPaused,,) = corkPool.pausedStates(id);
        assertFalse(swapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseWithdrawals ----------------------------------------//
    function test_PauseWithdrawalsRevertWhenCalledByNonManager() public {
        (,,, bool withdrawalPaused,) = corkPool.pausedStates(id);
        assertFalse(withdrawalPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.pauseWithdrawals(id);

        (,,, withdrawalPaused,) = corkPool.pausedStates(id);
        assertFalse(withdrawalPaused);
    }

    function test_PauseWithdrawalsShouldWorkCorrectly() public {
        (,,, bool withdrawalPaused,) = corkPool.pausedStates(id);
        assertFalse(withdrawalPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalPaused(id);
        corkConfig.pauseWithdrawals(id);

        (,,, withdrawalPaused,) = corkPool.pausedStates(id);
        assertTrue(withdrawalPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseWithdrawals ----------------------------------------//
    function test_UnpauseWithdrawalsRevertWhenCalledByNonManager() public {
        (,,, bool withdrawalPaused,) = corkPool.pausedStates(id);
        assertFalse(withdrawalPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.unpauseWithdrawals(id);

        (,,, withdrawalPaused,) = corkPool.pausedStates(id);
        assertFalse(withdrawalPaused);
    }

    function test_UnpauseWithdrawalsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseWithdrawals(id);

        (,,, bool withdrawalPaused,) = corkPool.pausedStates(id);
        assertTrue(withdrawalPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalUnpaused(id);
        corkConfig.unpauseWithdrawals(id);

        (,,, withdrawalPaused,) = corkPool.pausedStates(id);
        assertFalse(withdrawalPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseUnwindDepositAndMints ----------------------------------------//
    function test_PauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public {
        (,,,, bool unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertFalse(unwindDepositAndMintPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.pauseUnwindDepositAndMints(id);

        (,,,, unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertFalse(unwindDepositAndMintPaused);
    }

    function test_PauseUnwindDepositAndMintsShouldWorkCorrectly() public {
        (,,,, bool unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertFalse(unwindDepositAndMintPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit ReturnPaused(id);
        corkConfig.pauseUnwindDepositAndMints(id);

        (,,,, unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertTrue(unwindDepositAndMintPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseUnwindDepositAndMints ----------------------------------------//
    function test_UnpauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public {
        (,,,, bool unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertFalse(unwindDepositAndMintPaused);

        vm.startPrank(user);
        vm.expectRevert(IConfig.CallerNotManager.selector);
        corkConfig.unpauseUnwindDepositAndMints(id);

        (,,,, unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertFalse(unwindDepositAndMintPaused);
    }

    function test_UnpauseUnwindDepositAndMintsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseUnwindDepositAndMints(id);

        (,,,, bool unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertTrue(unwindDepositAndMintPaused);

        vm.expectEmit(true, true, true, true);
        emit ReturnUnpaused(id);
        corkConfig.unpauseUnwindDepositAndMints(id);

        (,,,, unwindDepositAndMintPaused) = corkPool.pausedStates(id);
        assertFalse(unwindDepositAndMintPaused);
    }
    //-----------------------------------------------------------------------------------------------------//
}
