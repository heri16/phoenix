// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {WhitelistManager} from "contracts/core/WhitelistManager.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {DummyWETH} from "test/old/mocks/DummyWETH.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract DefaultCorkControllerTest is Helper {
    DefaultCorkController private defaultCorkController1;
    WhitelistManager private testWhitelistManagerLocal;

    address private adminUserAddress;
    address private configurator;
    address private pauser;
    address private poolCreator;
    address private user;

    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    MarketId id;

    // events
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event TreasurySet(address treasury);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);
    event MarketActionPausedUpdate(MarketId indexed marketId, uint16 pausedAction);

    function setUp() public {
        adminUserAddress = address(1);
        configurator = address(2);
        pauser = address(3);
        poolCreator = address(4);
        user = address(5);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, id) = createMarket(block.timestamp + 1 days);
        vm.stopPrank();

        vm.startPrank(adminUserAddress);
        // Deploy WhitelistManager behind proxy
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(whitelistManagerImpl, abi.encodeWithSignature("initialize(address,address)", adminUserAddress, adminUserAddress));
        testWhitelistManagerLocal = WhitelistManager(address(whitelistManagerProxy));

        defaultCorkController1 = new DefaultCorkController(adminUserAddress, configurator, pauser, poolCreator, address(corkPoolManager), address(testWhitelistManagerLocal), DEFAULT_ADDRESS);
        vm.stopPrank();
    }

    // ----------------------- Tests for constant variables of DefaultCorkController contract -----------------------//
    function test_DefaultCorkControllerVariables() public {
        assertEq(defaultCorkController1.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(defaultCorkController1.POOL_CREATOR_ROLE(), keccak256("POOL_CREATOR_ROLE"));

        assertEq(address(defaultCorkController1.corkPoolManager()), address(corkPoolManager));
    }

    //-----------------------------------------------------------------------------------------------------//

    //---------------------------------- Tests for DefaultCorkController constructor ---------------------------------//
    function test_DefaultCorkControllerConstructorRevertWhenPassedZeroAddress() public {
        // Revert when all address parameters are zero
        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(address(0), address(0), address(0), address(0), address(0), address(0), address(0));

        // Revert when any address parameter is zero
        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(address(0), DEFAULT_ADDRESS, pauser, DEFAULT_ADDRESS, address(corkPoolManager), address(testWhitelistManagerLocal), currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, address(0), pauser, DEFAULT_ADDRESS, address(corkPoolManager), address(whitelistManager),currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, DEFAULT_ADDRESS, address(0), DEFAULT_ADDRESS, address(corkPoolManager), address(whitelistManager),currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, DEFAULT_ADDRESS, pauser, address(0), address(corkPoolManager), address(whitelistManager),currentCaller());

        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        new DefaultCorkController(DEFAULT_ADDRESS, DEFAULT_ADDRESS, pauser, DEFAULT_ADDRESS, address(0), address(whitelistManager),currentCaller());
    }

    function test_DefaultCorkControllerConstructorShouldWorkCorrectly() public {
        // Assign roles correctly
        assertEq(defaultCorkController1.hasRole(defaultCorkController1.DEFAULT_ADMIN_ROLE(), adminUserAddress), true);
        assertEq(defaultCorkController1.hasRole(defaultCorkController1.PAUSER_ROLE(), pauser), true);
        assertEq(defaultCorkController1.hasRole(defaultCorkController1.POOL_CREATOR_ROLE(), poolCreator), true);

        // Assign Role Hierarchy correctly
        assertEq(defaultCorkController1.getRoleAdmin(defaultCorkController1.PAUSER_ROLE()), defaultCorkController1.DEFAULT_ADMIN_ROLE());
        assertEq(defaultCorkController1.getRoleAdmin(defaultCorkController1.POOL_CREATOR_ROLE()), defaultCorkController1.DEFAULT_ADMIN_ROLE());
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for grantRole ------------------------------------------//
    function test_GrantRoleRevertWhenCalledByNonManager() public {
        bytes32 role = defaultCorkController1.POOL_CREATOR_ROLE();
        vm.startPrank(user);
        assertFalse(defaultCorkController1.hasRole(role, pauser));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController1.grantRole(role, pauser);

        assertFalse(defaultCorkController1.hasRole(role, pauser));
    }

    function test_GrantRoleShouldWorkCorrectly() public {
        bytes32 role = defaultCorkController1.POOL_CREATOR_ROLE();
        vm.startPrank(adminUserAddress);
        assertFalse(defaultCorkController1.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit RoleGranted(role, address(9), pauser);

        defaultCorkController1.grantRole(role, address(9));

        assertTrue(defaultCorkController1.hasRole(role, address(9)));
        assertTrue(defaultCorkController1.hasRole(role, poolCreator));
    }

    function test_GrantRoleShouldWorkCorrectlyWhenNoManagerRole() public {
        bytes32 role = defaultCorkController1.POOL_CREATOR_ROLE();
        vm.startPrank(adminUserAddress);
        defaultCorkController1.revokeRole(defaultCorkController1.PAUSER_ROLE(), pauser);
        assertFalse(defaultCorkController1.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit RoleGranted(role, address(9), pauser);
        defaultCorkController1.grantRole(role, address(9));
        assertTrue(defaultCorkController1.hasRole(role, address(9)));
        assertTrue(defaultCorkController1.hasRole(role, poolCreator));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for revokeRole ------------------------------------------//
    function test_RevokeRoleRevertWhenCalledByNonManager() public {
        bytes32 role = defaultCorkController1.POOL_CREATOR_ROLE();
        vm.startPrank(user);
        assertFalse(defaultCorkController1.hasRole(role, pauser));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController1.revokeRole(role, pauser);
        assertFalse(defaultCorkController1.hasRole(role, pauser));
    }

    function test_RevokeRoleShouldWorkCorrectly() public {
        bytes32 role = defaultCorkController1.POOL_CREATOR_ROLE();
        vm.startPrank(adminUserAddress);

        defaultCorkController1.grantRole(role, address(9));
        assertTrue(defaultCorkController1.hasRole(role, address(9)));

        vm.expectEmit(false, false, false, true);
        emit RoleRevoked(role, address(9), adminUserAddress);
        defaultCorkController1.revokeRole(role, address(9));

        assertFalse(defaultCorkController1.hasRole(role, address(9)));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for setTreasury ----------------------------------------//
    function test_SetTreasuryRevertWhenCalledByNonManager() public {
        address mockTreasury = address(5);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.setTreasury(mockTreasury);
    }

    function test_SetTreasuryRevertWhenPassedZeroAddress() public {
        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectRevert(IDefaultCorkController.InvalidAddress.selector);
        defaultCorkController.setTreasury(address(0));
    }

    function test_SetTreasuryShouldWorkCorrectly() public {
        address mockTreasury = address(5);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmitAnonymous(false, false, false, false, true);
        emit TreasurySet(mockTreasury);
        defaultCorkController.setTreasury(mockTreasury);
    }

    function test_SetTreasuryShouldRevertWhenZeroAddress() public {
        address mockTreasury = address(0);

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectPartialRevert(IErrors.InvalidAddress.selector);
        defaultCorkController.setTreasury(mockTreasury);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for createNewPool ----------------------------------------//
    function test_InitializeCorkPoolRevertWhenCalledByNonPoolDeployer() public {
        vm.startPrank(user);

        Market memory market = Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 0, rateOracle: address(0), rateMin: 0, rateMax: 0, rateChangePerDayMax: 0, rateChangeCapacityMax: 0});

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, 0, 0, false));
    }

    function test_initializeCorkPoolRevertWhenAdminIsPaused() external {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pause();
        assertTrue(defaultCorkController.paused());

        Market memory market = Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 0, rateOracle: address(0), rateMin: 0, rateMax: 0, rateChangePerDayMax: 0, rateChangeCapacityMax: 0});

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, 0, 0, false));
    }

    function test_initializeCorkPoolShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);

        DummyWETH collateral = new DummyWETH();
        DummyWETH references = new DummyWETH();

        uint256 expiry = block.timestamp + 1;

        Market memory market = Market({
            collateralAsset: address(collateral),
            referenceAsset: address(references),
            expiryTimestamp: expiry,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });

        MarketId id = MarketId.wrap(keccak256(abi.encode(market)));

        uint256 unwindSwapFee = 1.5 ether;
        uint256 swapFee = 2 ether;

        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, unwindSwapFee, swapFee, false));

        market = corkPoolManager.market(id);

        assertEq(market.collateralAsset, address(collateral));
        assertEq(market.referenceAsset, address(references));
        assertEq(market.expiryTimestamp, expiry);
        assertEq(market.rateMin, defaultRateMin());
        assertEq(market.rateMax, defaultRateMax());
        assertEq(market.rateChangePerDayMax, defaultRateChangePerDayMax());
        assertEq(market.rateChangeCapacityMax, defaultRateChangeCapacityMax());
        assertEq(market.rateOracle, address(testOracle));
        assertEq(corkPoolManager.unwindSwapFee(id), unwindSwapFee);
        assertEq(corkPoolManager.swapFee(id), swapFee);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateUnwindSwapFeeRate ----------------------------------------//
    function test_UpdateUnwindSwapFeeRateRevertWhenCalledByNonManager() public {
        assertEq(corkPoolManager.unwindSwapFee(id), DEFAULT_REVERSE_SWAP_FEE);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.updateUnwindSwapFeeRate(id, 1.234_567_89 ether);

        assertEq(corkPoolManager.unwindSwapFee(id), DEFAULT_REVERSE_SWAP_FEE);
    }

    function test_UpdateUnwindSwapFeeRateShouldWorkCorrectly() public {
        assertEq(corkPoolManager.unwindSwapFee(id), DEFAULT_REVERSE_SWAP_FEE);

        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.updateUnwindSwapFeeRate(id, 1.234_567_89 ether);

        assertEq(corkPoolManager.unwindSwapFee(id), 1.234_567_89 ether);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateSwapFeePercentage ----------------------------------------//
    function test_UpdateSwapFeePercentageRevertWhenCalledByNonManager() public {
        assertEq(corkPoolManager.swapFee(id), DEFAULT_BASE_REDEMPTION_FEE);

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.updateSwapFeePercentage(id, 1.234_567_89 ether);

        assertEq(corkPoolManager.swapFee(id), DEFAULT_BASE_REDEMPTION_FEE);
    }

    function test_UpdateSwapFeePercentageShouldWorkCorrectly() public {
        assertEq(corkPoolManager.swapFee(id), DEFAULT_BASE_REDEMPTION_FEE);

        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.updateSwapFeePercentage(id, 1.234_567_89 ether);

        assertEq(corkPoolManager.swapFee(id), 1.234_567_89 ether);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pause ----------------------------------------//
    function test_PauseShouldRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController1.paused());

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController1.pause();

        assertFalse(defaultCorkController1.paused());
    }

    function test_PauseShouldRevertWhenAlreadyPaused() public {
        vm.startPrank(pauser);
        defaultCorkController1.pause();
        assertTrue(defaultCorkController1.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        defaultCorkController1.pause();

        assertTrue(defaultCorkController1.paused());
    }

    function test_PauseShouldWorkCorrectly() public {
        assertFalse(defaultCorkController1.paused());

        vm.startPrank(pauser);
        vm.expectEmit(false, false, false, true);

        emit Paused(pauser);
        defaultCorkController1.pause();

        assertTrue(defaultCorkController1.paused());
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpause ----------------------------------------//
    function test_UnpauseShouldRevertWhenCalledByNonManager() public {
        vm.startPrank(pauser);
        defaultCorkController1.pause();
        assertTrue(defaultCorkController1.paused());

        vm.startPrank(address(8));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController1.unpause();
        assertTrue(defaultCorkController1.paused());
    }

    function test_UnpauseShouldRevertWhenNotPaused() public {
        assertFalse(defaultCorkController1.paused());

        vm.startPrank(adminUserAddress);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        defaultCorkController1.unpause();

        assertFalse(defaultCorkController1.paused());
    }

    function test_UnpauseShouldWorkCorrectly() public {
        vm.startPrank(pauser);
        defaultCorkController1.pause();
        assertTrue(defaultCorkController1.paused());

        vm.expectEmit(false, false, false, true);
        vm.startPrank(adminUserAddress);
        emit Unpaused(adminUserAddress);
        defaultCorkController1.unpause();
        assertFalse(defaultCorkController1.paused());
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseDeposits ----------------------------------------//
    function test_PauseDepositsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isDepositPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseDeposits(id);

        assertFalse(defaultCorkController.isDepositPaused(id));
    }

    function test_PauseDepositsShouldWorkCorrectly() public {
        assertFalse(defaultCorkController.isDepositPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 1);
        defaultCorkController.pauseDeposits(id);

        assertTrue(defaultCorkController.isDepositPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseDeposits ----------------------------------------//
    function test_UnpauseDepositsShouldRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isDepositPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseDeposits(id);
    }

    function test_UnpauseDepositsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseDeposits(id);

        assertTrue(defaultCorkController.isDepositPaused(id));

        vm.expectEmit(true, false, false, true);
        emit MarketActionPausedUpdate(id, 0);
        defaultCorkController.unpauseDeposits(id);

        assertFalse(defaultCorkController.isDepositPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseunwindSwap ----------------------------------------//
    function test_PauseUnwindSwapsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isDepositPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseUnwindSwaps(id);

        assertFalse(defaultCorkController.isDepositPaused(id));
    }

    function test_PauseUnwindSwapsShouldWorkCorrectly() public {
        assertFalse(defaultCorkController.isUnwindSwapPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 1 << 4);
        defaultCorkController.pauseUnwindSwaps(id);

        assertTrue(defaultCorkController.isUnwindSwapPaused(id));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(id, 0, address(8));
    }

    function test_PauseUnwindExerciseShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);

        (,, MarketId _id) = createMarket(10_000);
        assertFalse(defaultCorkController.isUnwindSwapPaused(id));

        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(_id, 1 << 4);
        defaultCorkController.pauseUnwindSwaps(_id);

        assertTrue(defaultCorkController.isUnwindSwapPaused(_id));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(_id, 1, address(8));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseunwindSwap ----------------------------------------//
    function test_UnpauseUnwindSwapsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isUnwindSwapPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseUnwindSwaps(id);

        assertFalse(defaultCorkController.isUnwindSwapPaused(id));
    }

    function test_UnpauseUnwindSwapsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseUnwindSwaps(id);

        assertTrue(defaultCorkController.isUnwindSwapPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 0);
        defaultCorkController.unpauseUnwindSwaps(id);

        assertFalse(defaultCorkController.isUnwindSwapPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseSwap ----------------------------------------//
    function test_PauseSwapRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isSwapPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseSwaps(id);

        assertFalse(defaultCorkController.isSwapPaused(id));
    }

    function test_PauseSwapShouldWorkCorrectly() public {
        assertFalse(defaultCorkController.isSwapPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 1 << 1);
        defaultCorkController.pauseSwaps(id);

        assertTrue(defaultCorkController.isSwapPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseSwap ----------------------------------------//
    function test_UnpauseSwapRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isSwapPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseSwaps(id);

        assertFalse(defaultCorkController.isSwapPaused(id));
    }

    function test_UnpauseSwapShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseSwaps(id);

        assertTrue(defaultCorkController.isSwapPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 0);
        defaultCorkController.unpauseSwaps(id);

        assertFalse(defaultCorkController.isSwapPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseWithdrawals ----------------------------------------//
    function test_PauseWithdrawalsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isWithdrawalPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseWithdrawals(id);

        assertFalse(defaultCorkController.isWithdrawalPaused(id));
    }

    function test_PauseWithdrawalsShouldWorkCorrectly() public {
        assertFalse(defaultCorkController.isWithdrawalPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 1 << 2);
        defaultCorkController.pauseWithdrawals(id);

        assertTrue(defaultCorkController.isWithdrawalPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseWithdrawals ----------------------------------------//
    function test_UnpauseWithdrawalsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isWithdrawalPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseWithdrawals(id);

        assertFalse(defaultCorkController.isWithdrawalPaused(id));
    }

    function test_UnpauseWithdrawalsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseWithdrawals(id);

        assertTrue(defaultCorkController.isWithdrawalPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 0);
        defaultCorkController.unpauseWithdrawals(id);

        assertFalse(defaultCorkController.isWithdrawalPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseUnwindDepositAndMints ----------------------------------------//
    function test_PauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseUnwindDepositAndMints(id);

        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(id));
    }

    function test_PauseUnwindDepositAndMintsShouldWorkCorrectly() public {
        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(id));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 1 << 3);
        defaultCorkController.pauseUnwindDepositAndMints(id);

        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseUnwindDepositAndMints ----------------------------------------//
    function test_UnpauseUnwindDepositAndMintsRevertWhenCalledByNonManager() public {
        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(id));

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseUnwindDepositAndMints(id);

        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(id));
    }

    function test_UnpauseUnwindDepositAndMintsShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseUnwindDepositAndMints(id);

        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(id));

        vm.expectEmit(true, true, true, true);
        emit MarketActionPausedUpdate(id, 0);
        defaultCorkController.unpauseUnwindDepositAndMints(id);

        assertFalse(defaultCorkController.isUnwindDepositAndMintPaused(id));
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseMarket ----------------------------------------//
    function test_PauseMarketShouldDisableAllPoolFunctions() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseMarket(id);

        assertTrue(defaultCorkController.isDepositPaused(id));
        assertTrue(defaultCorkController.isSwapPaused(id));
        assertTrue(defaultCorkController.isUnwindDepositAndMintPaused(id));
        assertTrue(defaultCorkController.isUnwindSwapPaused(id));
        assertTrue(defaultCorkController.isWithdrawalPaused(id));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.mint(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.swap(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exerciseOther(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindDeposit(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindMint(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExerciseOther(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for pauseAll ----------------------------------------//
    function test_PauseAllRevertWhenCalledByNonPauser() public {
        // Should be unpaused by default
        assertFalse(corkPoolManager.paused());

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.pauseAll();

        assertFalse(corkPoolManager.paused());
    }

    function test_PauseAllShouldWorkCorrectly() public {
        // Should be unpaused by default
        assertFalse(corkPoolManager.paused());

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Paused(address(defaultCorkController));
        defaultCorkController.pauseAll();

        assertTrue(corkPoolManager.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 1 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 1 ether, rateChangeCapacityMax: 1 ether}));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.mint(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.swap(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exerciseOther(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindDeposit(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindMint(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExercise(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindExerciseOther(id, 1 ether, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdraw(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.withdrawOther(id, 1 ether, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for unpauseAll ----------------------------------------//
    function test_UnpauseAllShouldRevertWhenCalledByNonDefaultAdmin() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseAll();

        // Should be paused by default
        assertTrue(corkPoolManager.paused());

        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        defaultCorkController.unpauseAll();

        assertTrue(corkPoolManager.paused());
    }

    function test_UnpauseAllShouldWorkCorrectly() public {
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.pauseAll();

        // Should be paused by default
        assertTrue(corkPoolManager.paused());

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Unpaused(address(defaultCorkController));
        defaultCorkController.unpauseAll();

        assertFalse(corkPoolManager.paused());

        vm.startPrank(address(defaultCorkController));
        // Create new pool should work
        corkPoolManager.createNewPool(Market({collateralAsset: address(collateralAsset), referenceAsset: address(referenceAsset), expiryTimestamp: 1 days, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 1 ether, rateChangeCapacityMax: 1 ether}));

        vm.startPrank(user);
        vm.deal(user, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        collateralAsset.approve(address(corkPoolManager), type(uint256).max);
        referenceAsset.approve(address(corkPoolManager), type(uint256).max);

        // Deposit should work
        corkPoolManager.deposit(id, 1000 ether, user);

        // Mint should work
        corkPoolManager.mint(id, 1000 ether, user);

        // Swap should work
        corkPoolManager.swap(id, 1 ether, user);

        // Exercise should work
        corkPoolManager.exercise(id, 1 ether, user);

        // Exercise other should work
        corkPoolManager.exerciseOther(id, 1 ether, user);

        // Unwind deposit should work
        corkPoolManager.unwindDeposit(id, 1 ether, user, user);

        // Unwind mint should work
        corkPoolManager.unwindMint(id, 1 ether, user, user);

        // Unwind swap should work
        corkPoolManager.unwindSwap(id, 1 ether, user);

        // Unwind exercise should work
        corkPoolManager.unwindExercise(id, 1 ether, user);

        // Unwind exercise other should work
        corkPoolManager.unwindExerciseOther(id, 1 ether, user);

        // Fast forward to expiry
        vm.warp(block.timestamp + 2 days);

        // Withdraw should work
        corkPoolManager.withdraw(id, 0.01 ether, user, user);

        // Withdraw other should work
        corkPoolManager.withdrawOther(id, 0.01 ether, user, user);
    }
    //-----------------------------------------------------------------------------------------------------//
}
