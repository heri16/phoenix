pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {BaseTest} from "test/forge/BaseTest.sol";
import {InvalidERC20} from "test/forge/mocks/InvalidERC20.sol";
import {MockBundler3} from "test/forge/mocks/MockBundler3.sol";

contract SharesFactoryTest is BaseTest {
    uint256 public depositAmount = 1 ether;
    uint256 public swapAmount = 0.123 ether;

    function setUp() public override {
        // make default address alice so that alice deploys the contracts
        bravo = alice;
        // for convenience sake, since the setup will fail if we don't do this
        mockBundler = MockBundler3(bravo);

        super.setUp();

        _deposit(defaultPoolId, depositAmount, alice);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldWorkCorrectly() external {
        assertEq(address(sharesFactory.CORK_POOL_MANAGER()), address(corkPoolManager));
    }

    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- getDeployedSwapShares ----------------------------------- //
    function test_getDeployedSwapSharesShouldWorkCorrectly() external {
        MarketId poolId = corkPoolManager.getId(poolParams());
        (address principalToken, address swapToken) = corkPoolManager.shares(poolId);
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));

        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        poolId = createPool();

        (address ct1, address ds1) = corkPoolManager.shares(poolId);
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldReturnZeroAddressWhenNoSharesDeployed() external {
        MarketId newPoolId = corkPoolManager.getId(poolParams());
        (address principalToken, address swapToken) = corkPoolManager.shares(newPoolId);
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));
    }

    function test_getDeployedSwapSharesShouldWorkWithSingleShare() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        MarketId newPoolId = createPool();

        (address principalToken, address swapToken) = corkPoolManager.shares(newPoolId);
        assertEq(principalToken, expectedPrincipalToken);
        assertEq(swapToken, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldWorkWithDifferentMarketParameters() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for first pool
        Market memory pool1 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 100 days,
            rateOracle: address(testOracle),
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
        MarketId pool1Id = MarketId.wrap(keccak256(abi.encode(pool1)));

        overridePrank(alice);
        testOracle.setRate(pool1Id, DEFAULT_ORACLE_RATE);
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool1, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );

        (address principalToken, address swapToken) = corkPoolManager.shares(pool1Id);
        assertEq(principalToken, expectedPrincipalToken);
        assertEq(swapToken, expectedSwapToken);

        currentNonce = vm.getNonce(address(sharesFactory));
        expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for second pool with different parameters
        Market memory pool2 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 200 days,
            rateOracle: address(testOracle),
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
        MarketId pool2Id = MarketId.wrap(keccak256(abi.encode(pool2)));

        overridePrank(alice);
        testOracle.setRate(pool2Id, DEFAULT_ORACLE_RATE);
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool2, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );

        // Get assets for second pool
        (address ct2, address ds2) = corkPoolManager.shares(pool2Id);
        assertEq(ct2, expectedPrincipalToken);
        assertEq(ds2, expectedSwapToken);

        // Verify they are different assets
        assertNotEq(principalToken, expectedPrincipalToken);
        assertNotEq(swapToken, expectedSwapToken);
    }

    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- DeploySwapShares ----------------------------------- //
    function test_DeploySwapSharesShouldRevertIfCallerIsNotCorkPool() external __as(bob) {
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotCorkPoolManager.selector));
        sharesFactory.deployPoolShares(
            ISharesFactory.DeployParams({
                poolId: defaultPoolId,
                poolParams: Market({
                    collateralAsset: address(collateralAsset),
                    referenceAsset: address(referenceAsset),
                    expiryTimestamp: block.timestamp + 100 days,
                    rateMin: DEFAULT_RATE_MIN,
                    rateMax: DEFAULT_RATE_MAX,
                    rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
                    rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
                    rateOracle: address(0)
                })
            })
        );
    }

    function test_DeploySwapSharesShouldWorkCorrectly() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);
        Market memory pool1 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 100 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });
        MarketId poolId1 = MarketId.wrap(keccak256(abi.encode(pool1)));

        overridePrank(alice);
        vm.expectEmit(true, false, false, true);
        emit ISharesFactory.SharesDeployed(address(collateralAsset), expectedPrincipalToken, expectedSwapToken);
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool1, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );

        (address ct1, address ds1) = corkPoolManager.shares(poolId1);
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);

        assertEq(PoolShare(ct1).expiry(), block.timestamp + 100 days);
        assertEq(PoolShare(ds1).expiry(), block.timestamp + 100 days);

        assertEq(PoolShare(ct1).issuedAt(), block.timestamp);
        assertEq(PoolShare(ds1).issuedAt(), block.timestamp);

        assertEq(PoolShare(ct1).isExpired(), false);
        assertEq(PoolShare(ds1).isExpired(), false);

        assertEq(PoolShare(ct1).factory(), address(sharesFactory));
        assertEq(PoolShare(ds1).factory(), address(sharesFactory));

        assertEq(MarketId.unwrap(PoolShare(ct1).poolId()), MarketId.unwrap(poolId1));
        assertEq(MarketId.unwrap(PoolShare(ds1).poolId()), MarketId.unwrap(poolId1));

        assertEq(address(PoolShare(ct1).poolManager()), address(corkPoolManager));
        assertEq(address(PoolShare(ds1).poolManager()), address(corkPoolManager));

        assertEq(PoolShare(ct1).owner(), ensOwner);
        assertEq(PoolShare(ds1).owner(), ensOwner);

        assertEq(PoolShare(ct1).totalSupply(), 0);
        assertEq(PoolShare(ds1).totalSupply(), 0);

        assertEq(PoolShare(ct1).balanceOf(alice), 0);
        assertEq(PoolShare(ds1).balanceOf(alice), 0);

        assertEq(PoolShare(ct1).allowance(alice, address(corkPoolManager)), 0);
        assertEq(PoolShare(ds1).allowance(alice, address(corkPoolManager)), 0);
    }

    function test_DeploySwapSharesShouldCreateUniqueSymbols() external {
        // Test that different expiry dates create different symbols
        uint256 expiry1 = block.timestamp + 30 days; // Different month
        uint256 expiry2 = block.timestamp + 60 days; // Different month

        Market memory pool1 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: expiry1,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        Market memory pool2 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: expiry2,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        MarketId poolId1 = MarketId.wrap(keccak256(abi.encode(pool1)));
        MarketId poolId2 = MarketId.wrap(keccak256(abi.encode(pool2)));

        overridePrank(alice);
        testOracle.setRate(poolId1, DEFAULT_ORACLE_RATE);
        testOracle.setRate(poolId2, DEFAULT_ORACLE_RATE);

        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool1, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool2, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );

        (address ct1, address ds1) = corkPoolManager.shares(poolId1);
        (address ct2, address ds2) = corkPoolManager.shares(poolId2);

        // Verify different symbols were generated
        assertNotEq(PoolShare(ct1).symbol(), PoolShare(ct2).symbol());
        assertNotEq(PoolShare(ds1).symbol(), PoolShare(ds2).symbol());
    }

    function test_DeploySwapSharesShouldEmitCorrectEvent() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        Market memory pool1 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 100 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });
        MarketId poolId1 = MarketId.wrap(keccak256(abi.encode(pool1)));

        overridePrank(alice);
        testOracle.setRate(poolId1, DEFAULT_ORACLE_RATE);

        // Expect the exact event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ISharesFactory.SharesDeployed(address(collateralAsset), expectedPrincipalToken, expectedSwapToken);

        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool1, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );
    }

    function test_DeploySwapSharesShouldRevertWithInvalidERC20Metadata() external {
        // Create an invalid ERC20 that doesn't implement symbol() properly
        InvalidERC20 invalidAsset = new InvalidERC20();

        Market memory pool1 = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(invalidAsset), // Use invalid asset as reference
            expiryTimestamp: block.timestamp + 100 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });
        MarketId poolId1 = MarketId.wrap(keccak256(abi.encode(pool1)));

        overridePrank(alice);
        testOracle.setRate(poolId1, DEFAULT_ORACLE_RATE);

        // This should revert when trying to call symbol() on the invalid asset
        vm.expectRevert();
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                pool1, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );
    }

    // some local helpers because we need to test some things independently
    //-----------------------------------------------------------------------------------------------------//

    function poolParams() internal view returns (Market memory) {
        return Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 100 days,
            rateOracle: address(testOracle),
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
    }

    function createPool() internal returns (MarketId _poolId) {
        Market memory poolParams = poolParams();
        _poolId = MarketId.wrap(keccak256(abi.encode(poolParams)));
        overridePrank(alice);
        testOracle.setRate(_poolId, DEFAULT_ORACLE_RATE);
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                poolParams, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );
    }
}
