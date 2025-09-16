// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {IConfig} from "contracts/interfaces/IConfig.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract CorkConfigTest is Helper {
    CorkConfig private config;
    address private admin;
    address private pauser;
    address private poolCreator;
    address private user;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
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
        pauser = address(2);
        poolCreator = address(3);
        user = address(5);

        vm.startPrank(admin);
        config = new CorkConfig(admin, pauser, poolCreator);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, id) = createMarket(block.timestamp + 1 days);
        vm.stopPrank();
    }

    // ----------------------- Tests for constant variables of CorkConfig contract -----------------------//
    function test_CorkConfigRolesVariables() public {
        assertEq(config.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(config.POOL_CREATOR_ROLE(), keccak256("POOL_CREATOR_ROLE"));
    }
    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- Tests for CorkConfig constructor ---------------------------------//
    function test_CorkConfigConstructorRevertWhenPassedZeroAddress() public {
        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(address(0), address(0), address(0));

        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(address(0), address(0), pauser);

        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(address(0), pauser, address(0));

        vm.expectRevert(IConfig.InvalidAddress.selector);
        new CorkConfig(pauser, address(0), address(0));
    }

    function test_CorkConfigConstructorShouldWorkCorrectly() public {
        // Assign roles correctly
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.PAUSER_ROLE(), pauser), true);
        assertEq(config.hasRole(config.POOL_CREATOR_ROLE(), poolCreator), true);

        // Assign Role Hierarchy correctly
        assertEq(config.getRoleAdmin(config.PAUSER_ROLE()), config.DEFAULT_ADMIN_ROLE());
        assertEq(config.getRoleAdmin(config.POOL_CREATOR_ROLE()), config.DEFAULT_ADMIN_ROLE());

        // Assign variables correctly
        assertEq(address(config.corkPool()), address(0));
        assertEq(address(config.treasury()), address(0));
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for grantRole ------------------------------------------//
    function test_GrantRoleRevertWhenCalledByNonManager() public {
        bytes32 role = config.POOL_CREATOR_ROLE();
        vm.startPrank(user);
        assertFalse(config.hasRole(role, pauser));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        config.grantRole(role, pauser);

        assertFalse(config.hasRole(role, pauser));
    }

    function test_GrantRoleRevertWhenAccountAlreadyHasThatRole() public {
        bytes32 poolDeployerRole = config.POOL_CREATOR_ROLE();
        bytes32 managerRole = config.PAUSER_ROLE();
        assertEq(config.hasRole(poolDeployerRole, poolCreator), true);

        vm.startPrank(admin);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.grantRole(poolDeployerRole, poolCreator);

        assertEq(config.hasRole(poolDeployerRole, poolCreator), true);
        assertEq(config.hasRole(managerRole, pauser), true);

        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.grantRole(managerRole, pauser);

        assertEq(config.hasRole(managerRole, pauser), true);
    }

    function test_GrantRoleShouldWorkCorrectly() public {
        bytes32 role = config.POOL_CREATOR_ROLE();
        vm.startPrank(admin);
        assertFalse(config.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit RoleGranted(role, address(9), pauser);

        config.grantRole(role, address(9));

        assertTrue(config.hasRole(role, address(9)));
        assertTrue(config.hasRole(role, poolCreator));
    }

    function test_GrantRoleShouldWorkCorrectlyWhenNoManagerRole() public {
        bytes32 role = config.POOL_CREATOR_ROLE();
        vm.startPrank(admin);
        config.revokeRole(config.PAUSER_ROLE(), pauser);
        assertFalse(config.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit RoleGranted(role, address(9), pauser);
        config.grantRole(role, address(9));
        assertTrue(config.hasRole(role, address(9)));
        assertTrue(config.hasRole(role, poolCreator));
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for revokeRole ------------------------------------------//
    function test_RevokeRoleRevertWhenCalledByNonManager() public {
        bytes32 role = config.POOL_CREATOR_ROLE();
        vm.startPrank(user);
        assertFalse(config.hasRole(role, pauser));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        config.revokeRole(role, pauser);
        assertFalse(config.hasRole(role, pauser));
    }

    function test_RevokeRoleRevertWhenAccountDoesNotHasThatRole() public {
        bytes32 poolDeployerRole = config.POOL_CREATOR_ROLE();
        bytes32 managerRole = config.PAUSER_ROLE();

        vm.startPrank(admin);
        config.revokeRole(poolDeployerRole, poolCreator);

        assertEq(config.hasRole(poolDeployerRole, poolCreator), false);

        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.revokeRole(poolDeployerRole, poolCreator);
    }

    function test_RevokeRoleShouldWorkCorrectly() public {
        bytes32 role = config.POOL_CREATOR_ROLE();
        vm.startPrank(admin);

        config.grantRole(role, address(9));
        assertTrue(config.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit RoleRevoked(role, address(9), admin);
        config.revokeRole(role, address(9));

        assertFalse(config.hasRole(role, address(9)));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for transferAdmin ----------------------------------------//
    function test_TransferAdminRevertWhenCalledByNonAdmin() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, config.DEFAULT_ADMIN_ROLE()));
        config.transferAdmin(poolCreator);

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);
    }

    function test_TransferAdminRevertWhenPassedZeroAddress() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);

        vm.startPrank(admin);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.transferAdmin(address(0));

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);
    }

    function test_TransferAdminRevertWhenPassedCurrentAdminAddress() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);

        vm.startPrank(admin);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.transferAdmin(admin);

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);
    }

    function test_TransferAdminShouldWorkCorrectly() public {
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), false);

        vm.startPrank(admin);
        vm.expectEmit(false, false, false, true);
        emit RoleGranted(config.DEFAULT_ADMIN_ROLE(), poolCreator, admin);
        config.transferAdmin(poolCreator);

        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), poolCreator), true);
        assertEq(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin), false);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setCorkPool ----------------------------------------//
    function test_SetCorkPoolRevertWhenCalledByNonManager() public {
        address mockCorkPool = address(5);
        assertEq(address(config.corkPool()), address(0));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        config.setCorkPool(mockCorkPool);

        assertEq(address(config.corkPool()), address(0));
    }

    function test_SetCorkPoolRevertWhenPassedZeroAddress() public {
        assertEq(address(config.corkPool()), address(0));

        vm.startPrank(admin);
        vm.expectPartialRevert(IConfig.InvalidAddress.selector);
        config.setCorkPool(address(0));

        assertEq(address(config.corkPool()), address(0));
    }

    function test_SetCorkPoolShouldWorkCorrectly() public {
        assertEq(address(config.corkPool()), address(0));
        address mockCorkPool = address(5);

        vm.startPrank(admin);
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
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        config.setTreasury(mockTreasury);

        assertEq(address(config.treasury()), address(0));
    }

    function test_SetTreasuryRevertWhenPassedZeroAddress() public {
        assertEq(address(config.treasury()), address(0));

        vm.startPrank(admin);
        vm.expectRevert(IConfig.InvalidAddress.selector);
        config.setTreasury(address(0));

        assertEq(address(config.treasury()), address(0));
    }

    function test_SetTreasuryShouldWorkCorrectly() public {
        assertEq(address(config.treasury()), address(0));
        address mockTreasury = address(5);

        vm.startPrank(admin);
        vm.expectEmit(false, false, false, true);
        emit TreasurySet(mockTreasury);
        config.setTreasury(mockTreasury);

        assertEq(address(config.treasury()), mockTreasury);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for createNewPool ----------------------------------------//
    function test_InitializeCorkPoolRevertWhenCalledByNonPoolDeployer() public {
        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 0, rateOracle: address(0), rateMin: 0, rateMax: 0, rateChangePerDayMax: 0, rateChangeCapacityMax: 0}));
    }

    function test_initializeCorkPoolRevertWhenConfigIsPaused() external {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pause();
        assertTrue(corkConfig.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        corkConfig.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 0, rateOracle: address(0), rateMin: 0, rateMax: 0, rateChangePerDayMax: 0, rateChangeCapacityMax: 0}));
    }

    function test_initializeCorkPoolShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, id) = createNewPoolPair(block.timestamp + 1 days);

        address paAddress;
        address raAddress;
        uint256 expiryTimestamp;
        address rateOracle;
        uint256 rateMin;
        uint256 rateMax;
        uint256 rateChangePerDayMax;
        uint256 rateChangeCapacityMax;
        (paAddress, raAddress, expiryTimestamp, rateOracle, rateMin, rateMax, rateChangePerDayMax, rateChangeCapacityMax) = corkPool.marketDetails(id);

        assertEq(paAddress, address(0));
        assertEq(raAddress, address(0));
        assertEq(expiryTimestamp, 0);
        assertEq(rateOracle, address(0));
        assertEq(rateMin, 0);
        assertEq(rateMax, 0);
        assertEq(rateChangePerDayMax, 0);
        assertEq(rateChangeCapacityMax, 0);

        Market memory market = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: 1 days,
            rateOracle: address(testOracle),
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
        MarketId id = corkPool.getId(market);
        testOracle.setRate(id, defaultOracleRate());
        corkConfig.createNewPool(market);

        Market memory marketParams = corkPool.market(id);
        assertEq(marketParams.referenceAsset, address(referenceAsset));
        assertEq(marketParams.collateralAsset, address(collateralAsset));
        assertEq(marketParams.expiryTimestamp, 1 days);
        assertEq(marketParams.rateOracle, address(testOracle));
        assertEq(marketParams.rateMin, DEFAULT_RATE_MIN);
        assertEq(marketParams.rateMax, DEFAULT_RATE_MAX);
        assertEq(marketParams.rateChangePerDayMax, DEFAULT_RATE_CHANGE_PER_DAY_MAX);
        assertEq(marketParams.rateChangeCapacityMax, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateUnwindSwapFeeRate ----------------------------------------//
    function test_UpdateUnwindSwapFeeRateRevertWhenCalledByNonManager() public {
        assertEq(corkPool.unwindSwapFee(id), DEFAULT_REVERSE_SWAP_FEE);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.updateUnwindSwapFeeRate(id, 1.23456789 ether);

        assertEq(corkPool.unwindSwapFee(id), DEFAULT_REVERSE_SWAP_FEE);
    }

    function test_UpdateUnwindSwapFeeRateShouldWorkCorrectly() public {
        assertEq(corkPool.unwindSwapFee(id), DEFAULT_REVERSE_SWAP_FEE);

        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateUnwindSwapFeeRate(id, 1.23456789 ether);

        assertEq(corkPool.unwindSwapFee(id), 1.23456789 ether);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateBaseRedemptionFeePercentage ----------------------------------------//
    function test_UpdateBaseRedemptionFeePercentageRevertWhenCalledByNonManager() public {
        assertEq(corkPool.baseRedemptionFee(id), DEFAULT_BASE_REDEMPTION_FEE);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.updateBaseRedemptionFeePercentage(id, 1.23456789 ether);

        assertEq(corkPool.baseRedemptionFee(id), DEFAULT_BASE_REDEMPTION_FEE);
    }

    function test_UpdateBaseRedemptionFeePercentageShouldWorkCorrectly() public {
        assertEq(corkPool.baseRedemptionFee(id), DEFAULT_BASE_REDEMPTION_FEE);

        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateBaseRedemptionFeePercentage(id, 1.23456789 ether);

        assertEq(corkPool.baseRedemptionFee(id), 1.23456789 ether);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pause ----------------------------------------//
    function test_PauseShouldRevertWhenCalledByNonManager() public {
        assertFalse(config.paused());

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        config.pause();

        assertFalse(config.paused());
    }

    function test_PauseShouldRevertWhenAlreadyPaused() public {
        vm.startPrank(pauser);
        config.pause();
        assertTrue(config.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        config.pause();

        assertTrue(config.paused());
    }

    function test_PauseShouldWorkCorrectly() public {
        assertFalse(config.paused());

        vm.startPrank(pauser);
        vm.expectEmit(false, false, false, true);

        emit Paused(pauser);
        config.pause();

        assertTrue(config.paused());
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpause ----------------------------------------//
    function test_UnpauseShouldRevertWhenCalledByNonManager() public {
        vm.startPrank(pauser);
        config.pause();
        assertTrue(config.paused());

        vm.startPrank(address(8));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        config.unpause();
        assertTrue(config.paused());
    }

    function test_UnpauseShouldRevertWhenNotPaused() public {
        assertFalse(config.paused());

        vm.startPrank(admin);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        config.unpause();

        assertFalse(config.paused());
    }

    function test_UnpauseShouldWorkCorrectly() public {
        vm.startPrank(pauser);
        config.pause();
        assertTrue(config.paused());

        vm.expectEmit(false, false, false, true);
        vm.startPrank(admin);
        emit Unpaused(admin);
        config.unpause();
        assertFalse(config.paused());
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseDeposits ----------------------------------------//
    function test_PauseDepositsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.depositPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.pauseDeposits(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.depositPaused);
    }

    function test_PauseDepositsShouldWorkCorrectly() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.depositPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit DepositPaused(id);
        corkConfig.pauseDeposits(id);

        pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.depositPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseDeposits ----------------------------------------//
    function test_UnpauseDepositsShouldRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.depositPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.unpauseDeposits(id);
    }

    function test_UnpauseDepositsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseDeposits(id);

        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.depositPaused);

        vm.expectEmit(false, false, false, true);
        emit DepositUnpaused(id);
        corkConfig.unpauseDeposits(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.depositPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseunwindSwap ----------------------------------------//
    function test_PauseUnwindSwapsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindSwapPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.pauseUnwindSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindSwapPaused);
    }

    function test_PauseUnwindSwapsShouldWorkCorrectly() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindSwapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit UnwindSwapPaused(id);
        corkConfig.pauseUnwindSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.unwindSwapPaused);

        vm.expectRevert(IErrors.Paused.selector);
        corkPool.unwindSwap(id, 0, address(8));
    }

    function test_PauseUnwindExerciseShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);

        (,, MarketId _id) = createMarket(10_000);
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(_id);
        assertFalse(pausedStates.unwindSwapPaused);

        vm.expectEmit(true, true, true, true);
        emit UnwindSwapPaused(_id);
        corkConfig.pauseUnwindSwaps(_id);

        pausedStates = corkPool.pausedStates(_id);
        assertTrue(pausedStates.unwindSwapPaused);

        vm.expectRevert(IErrors.Paused.selector);
        corkPool.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: _id, shares: 0, receiver: address(8), minCompensationOut: 0, maxAssetsIn: 0}));
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseunwindSwap ----------------------------------------//
    function test_UnpauseUnwindSwapsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindSwapPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.unpauseUnwindSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindSwapPaused);
    }

    function test_UnpauseUnwindSwapsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseUnwindSwaps(id);

        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.unwindSwapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit UnwindSwapUnpaused(id);
        corkConfig.unpauseUnwindSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindSwapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseSwap ----------------------------------------//
    function test_PauseSwapRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.swapPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.pauseSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.swapPaused);
    }

    function test_PauseSwapShouldWorkCorrectly() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.swapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit SwapPaused(id);
        corkConfig.pauseSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.swapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseSwap ----------------------------------------//
    function test_UnpauseSwapRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.swapPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.unpauseSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.swapPaused);
    }

    function test_UnpauseSwapShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseSwaps(id);

        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.swapPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit SwapUnpaused(id);
        corkConfig.unpauseSwaps(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.swapPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseWithdrawals ----------------------------------------//
    function test_PauseWithdrawalsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.withdrawalPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.pauseWithdrawals(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.withdrawalPaused);
    }

    function test_PauseWithdrawalsShouldWorkCorrectly() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.withdrawalPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalPaused(id);
        corkConfig.pauseWithdrawals(id);

        pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.withdrawalPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseWithdrawals ----------------------------------------//
    function test_UnpauseWithdrawalsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.withdrawalPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.unpauseWithdrawals(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.withdrawalPaused);
    }

    function test_UnpauseWithdrawalsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseWithdrawals(id);

        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.withdrawalPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalUnpaused(id);
        corkConfig.unpauseWithdrawals(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.withdrawalPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseUnwindDepositAndMints ----------------------------------------//
    function test_PauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindDepositAndMintPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.pauseUnwindDepositAndMints(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindDepositAndMintPaused);
    }

    function test_PauseUnwindDepositAndMintsShouldWorkCorrectly() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindDepositAndMintPaused);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit ReturnPaused(id);
        corkConfig.pauseUnwindDepositAndMints(id);

        pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.unwindDepositAndMintPaused);
    }
    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseUnwindDepositAndMints ----------------------------------------//
    function test_UnpauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public {
        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindDepositAndMintPaused);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        corkConfig.unpauseUnwindDepositAndMints(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindDepositAndMintPaused);
    }

    function test_UnpauseUnwindDepositAndMintsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.pauseUnwindDepositAndMints(id);

        IPoolManager.PausedStates memory pausedStates = corkPool.pausedStates(id);
        assertTrue(pausedStates.unwindDepositAndMintPaused);

        vm.expectEmit(true, true, true, true);
        emit ReturnUnpaused(id);
        corkConfig.unpauseUnwindDepositAndMints(id);

        pausedStates = corkPool.pausedStates(id);
        assertFalse(pausedStates.unwindDepositAndMintPaused);
    }
    //-----------------------------------------------------------------------------------------------------//
}
