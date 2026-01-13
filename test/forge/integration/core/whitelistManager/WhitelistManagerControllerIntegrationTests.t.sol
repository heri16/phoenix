// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/forge/BaseTest.sol";
import {ERC20Mock} from "test/forge/mocks/DummyWETH.sol";

contract WhitelistManagerControllerIntegrationTests is BaseTest {
    address whitelistAdder1 = makeAddr("whitelistAdder1");
    address whitelistAdder2 = makeAddr("whitelistAdder2");
    address whitelistRemover1 = makeAddr("whitelistRemover1");
    address whitelistRemover2 = makeAddr("whitelistRemover2");
    address testUser1 = makeAddr("testUser1");
    address testUser2 = makeAddr("testUser2");
    address testUser3 = makeAddr("testUser3");
    address[] testUsers;

    function setUp() public override {
        super.setUp();

        address[] memory addresses = new address[](5);

        addresses[0] = address(corkAdapter);
        addresses[1] = alice;
        addresses[2] = bob;
        addresses[3] = charlie;
        addresses[4] = bravo;

        vm.startPrank(whitelistAdder);
        defaultCorkController.addToGlobalWhitelist(addresses);

        testUsers.push(testUser1);
        testUsers.push(testUser2);
        testUsers.push(testUser3);

        vm.startPrank(bravo);
        defaultCorkController.grantRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder1);
        defaultCorkController.grantRole(defaultCorkController.WHITELIST_REMOVER_ROLE(), whitelistRemover1);
    }

    function test_ControllerWhitelistManagement_GlobalWhitelist() public __as(whitelistAdder1) {
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

        overridePrank(whitelistRemover1);

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.GlobalWhitelistRemoved(usersToRemove[0]);

        defaultCorkController.removeFromGlobalWhitelist(usersToRemove);

        assertFalse(whitelistManager.isGlobalWhitelisted(testUser1));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser2));
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser3));
    }

    function test_ControllerWhitelistManagement_MarketWhitelist() public __as(whitelistAdder1) {
        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.MarketWhitelistAdded(defaultPoolId, testUsers[0]);

        defaultCorkController.addToMarketWhitelist(defaultPoolId, testUsers);

        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser1));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser3));

        address[] memory usersToRemove = new address[](2);
        usersToRemove[0] = testUser1;
        usersToRemove[1] = testUser2;

        overridePrank(whitelistRemover1);

        vm.expectEmit(true, true, true, true);

        emit IWhitelistManager.MarketWhitelistRemoved(defaultPoolId, usersToRemove[0]);

        defaultCorkController.removeFromMarketWhitelist(defaultPoolId, usersToRemove);

        assertFalse(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser1));
        assertFalse(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser2));
        assertTrue(whitelistManager.isMarketWhitelisted(defaultPoolId, testUser3));
    }

    function test_ControllerWhitelistManagement_DisableMarketWhitelist() public {
        (ERC20Mock newCollateral, ERC20Mock newReference, MarketId newPoolId) =
            createNewPoolPair(block.timestamp + 1 days);

        Market memory newMarket = Market({
            collateralAsset: address(newCollateral),
            referenceAsset: address(newReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        overridePrank(bravo);

        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams({
                pool: newMarket,
                unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE,
                swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE,
                isWhitelistEnabled: true
            })
        );

        assertTrue(whitelistManager.isMarketWhitelistEnabled(newPoolId));

        vm.expectEmit(true, true, true, true);
        emit IWhitelistManager.MarketWhitelistDisabled(newPoolId);

        defaultCorkController.disableMarketWhitelist(newPoolId);

        assertFalse(whitelistManager.isMarketWhitelistEnabled(newPoolId));
    }

    function test_ControllerWhitelistManagement_IsWhitelisted() public __as(whitelistAdder1) {
        defaultCorkController.addToGlobalWhitelist(testUsers);

        assertTrue(defaultCorkController.isWhitelisted(defaultPoolId, testUser1));
        assertTrue(defaultCorkController.isWhitelisted(defaultPoolId, testUser2));
        assertTrue(defaultCorkController.isWhitelisted(defaultPoolId, testUser3));
    }

    function test_ControllerWhitelistManagement_CreatePoolWithWhitelist() public __as(bravo) {
        (ERC20Mock newCollateral, ERC20Mock newReference, MarketId newPoolId) =
            createNewPoolPair(block.timestamp + 1 days);

        Market memory newMarket = Market({
            collateralAsset: address(newCollateral),
            referenceAsset: address(newReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams({
                pool: newMarket,
                unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE,
                swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE,
                isWhitelistEnabled: true
            })
        );

        assertTrue(whitelistManager.isMarketWhitelistEnabled(newPoolId));
    }

    function test_ControllerWhitelistManagement_CreatePoolWithoutWhitelist() public __as(bravo) {
        (ERC20Mock newCollateral, ERC20Mock newReference, MarketId newPoolId) =
            createNewPoolPair(block.timestamp + 1 days);

        Market memory newMarket = Market({
            collateralAsset: address(newCollateral),
            referenceAsset: address(newReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams({
                pool: newMarket,
                unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE,
                swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE,
                isWhitelistEnabled: false
            })
        );

        assertFalse(whitelistManager.isMarketWhitelistEnabled(newPoolId));
    }

    function test_Revert_ControllerWhitelistManagement_UnauthorizedCaller() public __as(testUser1) {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                testUser1,
                defaultCorkController.WHITELIST_ADDER_ROLE()
            )
        );
        defaultCorkController.addToGlobalWhitelist(testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                testUser1,
                defaultCorkController.WHITELIST_REMOVER_ROLE()
            )
        );
        defaultCorkController.removeFromGlobalWhitelist(testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                testUser1,
                defaultCorkController.WHITELIST_ADDER_ROLE()
            )
        );
        defaultCorkController.addToMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                testUser1,
                defaultCorkController.WHITELIST_REMOVER_ROLE()
            )
        );
        defaultCorkController.removeFromMarketWhitelist(defaultPoolId, testUsers);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                testUser1,
                defaultCorkController.DEFAULT_ADMIN_ROLE()
            )
        );
        defaultCorkController.disableMarketWhitelist(defaultPoolId);
    }

    function test_Revert_ControllerWhitelistManagement_DisableMarketWhitelist_UnauthorizedRole()
        public
        __as(whitelistAdder2)
    {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                whitelistAdder2,
                defaultCorkController.DEFAULT_ADMIN_ROLE()
            )
        );
        defaultCorkController.disableMarketWhitelist(defaultPoolId);
    }

    function test_MultipleWhitelistManagers() public {
        defaultCorkController.grantRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder2);

        overridePrank(whitelistAdder1);
        defaultCorkController.addToGlobalWhitelist(testUsers);

        address[] memory moreUsers = new address[](1);
        moreUsers[0] = makeAddr("testUser4");

        overridePrank(whitelistAdder2);
        defaultCorkController.addToGlobalWhitelist(moreUsers);

        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));
        assertTrue(whitelistManager.isGlobalWhitelisted(moreUsers[0]));

        vm.stopPrank();
        vm.startPrank(bravo);
    }

    function test_RoleManagement_GrantAndRevoke() public {
        assertFalse(defaultCorkController.hasRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder2));

        defaultCorkController.grantRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder2);
        assertTrue(defaultCorkController.hasRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder2));

        overridePrank(whitelistAdder2);
        defaultCorkController.addToGlobalWhitelist(testUsers);
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));

        overridePrank(bravo);
        defaultCorkController.revokeRole(defaultCorkController.WHITELIST_ADDER_ROLE(), bravo);
        assertFalse(defaultCorkController.hasRole(defaultCorkController.WHITELIST_ADDER_ROLE(), bravo));

        defaultCorkController.grantRole(defaultCorkController.WHITELIST_REMOVER_ROLE(), bravo);
        assertTrue(defaultCorkController.hasRole(defaultCorkController.WHITELIST_REMOVER_ROLE(), bravo));

        overridePrank(whitelistAdder2);
        defaultCorkController.addToGlobalWhitelist(testUsers);
        assertTrue(whitelistManager.isGlobalWhitelisted(testUser1));

        overridePrank(bravo);
        defaultCorkController.revokeRole(defaultCorkController.WHITELIST_REMOVER_ROLE(), whitelistRemover2);
        assertFalse(defaultCorkController.hasRole(defaultCorkController.WHITELIST_REMOVER_ROLE(), whitelistRemover2));

        overridePrank(whitelistRemover2);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                whitelistRemover2,
                defaultCorkController.WHITELIST_REMOVER_ROLE()
            )
        );
        defaultCorkController.removeFromGlobalWhitelist(testUsers);

        overridePrank(bravo);
        defaultCorkController.revokeRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder2);
        assertFalse(defaultCorkController.hasRole(defaultCorkController.WHITELIST_ADDER_ROLE(), whitelistAdder2));

        overridePrank(whitelistAdder2);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                whitelistAdder2,
                defaultCorkController.WHITELIST_ADDER_ROLE()
            )
        );
        defaultCorkController.addToGlobalWhitelist(testUsers);
    }
}
