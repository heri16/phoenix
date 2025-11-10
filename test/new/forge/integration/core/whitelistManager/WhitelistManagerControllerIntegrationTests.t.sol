// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";
import {ERC20Mock} from "test/new/forge/mocks/DummyWETH.sol";

contract WhitelistManagerControllerIntegrationTests is BaseTest {
    address whitelistManager1 = makeAddr("whitelistManager1");
    address whitelistManager2 = makeAddr("whitelistManager2");
    address testUser1 = makeAddr("testUser1");
    address testUser2 = makeAddr("testUser2");
    address testUser3 = makeAddr("testUser3");
    address[] testUsers;

    function setUp() public override {
        super.setUp();

        testUsers.push(testUser1);
        testUsers.push(testUser2);
        testUsers.push(testUser3);

        defaultCorkController.grantRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager1);
    }

    function test_ControllerWhitelistManagement_GlobalWhitelist() public __as(whitelistManager1) {
        vm.expectEmit(true, true, true, true);

        for (uint256 index = 0; index < testUsers.length; index++) {
            emit IWhitelistManager.GlobalWhitelistAdded(testUsers[index]);
        }

        defaultCorkController.addToGlobalWhitelist(testUsers);

        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser2));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser3));

        address[] memory usersToRemove = new address[](1);
        usersToRemove[0] = testUser1;

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.GlobalWhitelistRemoved(usersToRemove[0]);

        defaultCorkController.removeFromGlobalWhitelist(usersToRemove);

        assertFalse(whitelistManager.isGlobalWhitelisted(testUser1));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser2));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser3));
    }

    function test_ControllerWhitelistManagement_MarketWhitelist() public __as(whitelistManager1) {
        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.MarketWhitelistAdded(defaultPoolId, testUsers[0]);

        defaultCorkController.addToMarketWhitelist(defaultPoolId, testUsers);

        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser3));

        address[] memory usersToRemove = new address[](2);
        usersToRemove[0] = testUser1;
        usersToRemove[1] = testUser2;

        vm.expectEmit(true, true, true, true);

        emit IWhitelistManager.MarketWhitelistRemoved(defaultPoolId, usersToRemove[0]);

        defaultCorkController.removeFromMarketWhitelist(defaultPoolId, usersToRemove);

        assertFalse(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser1));
        assertFalse(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser3));
    }

    function test_ControllerWhitelistManagement_DisableMarketWhitelist() public {
        (ERC20Mock newCollateral, ERC20Mock newReference, MarketId newPoolId) = createNewPoolPair(block.timestamp + 1 days);

        Market memory newMarket = Market({
            collateralAsset: address(newCollateral),
            referenceAsset: address(newReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });

        vm.stopPrank();
        vm.startPrank(DEFAULT_ADDRESS);

        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams({pool: newMarket, unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE, swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE, isWhitelistEnabled: true}));

        assertTrue(whitelistManager.isMarketWhitelistEnabled(newPoolId));

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.MarketWhitelistDisabled(newPoolId);

        defaultCorkController.disableMarketWhitelist(newPoolId);

        assertFalse(whitelistManager.isMarketWhitelistEnabled(newPoolId));
    }

    function test_ControllerWhitelistManagement_IsWhitelisted() public __as(whitelistManager1) {
        defaultCorkController.addToGlobalWhitelist(testUsers);

        assertTrue(defaultCorkController.isWhitelisted(defaultPoolId, testUser1));
        assertTrue(defaultCorkController.isWhitelisted(defaultPoolId, testUser2));
        assertTrue(defaultCorkController.isWhitelisted(defaultPoolId, testUser3));
    }

    function test_ControllerWhitelistManagement_CreatePoolWithWhitelist() public __as(DEFAULT_ADDRESS) {
        (ERC20Mock newCollateral, ERC20Mock newReference, MarketId newPoolId) = createNewPoolPair(block.timestamp + 1 days);

        Market memory newMarket = Market({
            collateralAsset: address(newCollateral),
            referenceAsset: address(newReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });

        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams({pool: newMarket, unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE, swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE, isWhitelistEnabled: true}));

        assertTrue(whitelistManager.isMarketWhitelistEnabled(newPoolId));
    }

    function test_ControllerWhitelistManagement_CreatePoolWithoutWhitelist() public __as(DEFAULT_ADDRESS) {
        (ERC20Mock newCollateral, ERC20Mock newReference, MarketId newPoolId) = createNewPoolPair(block.timestamp + 1 days);

        Market memory newMarket = Market({
            collateralAsset: address(newCollateral),
            referenceAsset: address(newReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });

        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams({pool: newMarket, unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE, swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE, isWhitelistEnabled: false}));

        assertFalse(whitelistManager.isMarketWhitelistEnabled(newPoolId));
    }

    function test_Revert_ControllerWhitelistManagement_UnauthorizedCaller() public __as(testUser1) {
        vm.expectRevert();
        defaultCorkController.addToGlobalWhitelist(testUsers);

        vm.expectRevert();
        defaultCorkController.removeFromGlobalWhitelist(testUsers);

        vm.expectRevert();
        defaultCorkController.addToMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert();
        defaultCorkController.removeFromMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert();
        defaultCorkController.disableMarketWhitelist(defaultPoolId);
    }

    function test_Revert_ControllerWhitelistManagement_DisableMarketWhitelist_UnauthorizedRole() public __as(whitelistManager1) {
        vm.expectRevert();
        defaultCorkController.disableMarketWhitelist(defaultPoolId);
    }

    function test_MultipleWhitelistManagers() public {
        defaultCorkController.grantRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager2);

        vm.stopPrank();
        vm.startPrank(whitelistManager1);
        defaultCorkController.addToGlobalWhitelist(testUsers);

        address[] memory moreUsers = new address[](1);
        moreUsers[0] = makeAddr("testUser4");

        vm.stopPrank();
        vm.startPrank(whitelistManager2);
        defaultCorkController.addToGlobalWhitelist(moreUsers);

        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));
        assertTrue(whitelistManager.isGlobalWhitelisted(moreUsers[0]));

        vm.stopPrank();
        vm.startPrank(DEFAULT_ADDRESS);
    }

    function test_RoleManagement_GrantAndRevoke() public {
        assertFalse(defaultCorkController.hasRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager2));

        defaultCorkController.grantRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager2);
        assertTrue(defaultCorkController.hasRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager2));

        vm.stopPrank();
        vm.startPrank(whitelistManager2);
        defaultCorkController.addToGlobalWhitelist(testUsers);
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));

        vm.stopPrank();
        vm.startPrank(DEFAULT_ADDRESS);
        defaultCorkController.revokeRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager2);
        assertFalse(defaultCorkController.hasRole(defaultCorkController.WHITELIST_MANAGER_ROLE(), whitelistManager2));

        vm.expectRevert();
        vm.stopPrank();
        vm.prank(whitelistManager2);
        defaultCorkController.removeFromGlobalWhitelist(testUsers);
        vm.startPrank(DEFAULT_ADDRESS);
    }
}
