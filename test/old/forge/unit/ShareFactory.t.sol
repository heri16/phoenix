pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {Helper} from "test/old/forge/Helper.sol";
import {ERC20Mock} from "test/old/mocks/ERC20Mock.sol";

contract SharesFactoryTest is Helper {
    ERC20Mock collateralAsset;
    ERC20Mock referenceAsset;
    PoolShare principalToken;
    PoolShare swapToken;
    // PoolShare asset;

    MarketId poolId;

    address user1;
    address rateOracle;

    uint256 public constant depositAmount = 1 ether;
    uint256 public constant swapAmount = 0.123 ether;

    event CorkPoolChanged(address indexed oldCorkPool, address indexed newCorkPool);
    event Upgraded(address indexed implementation);
    event SharesDeployed(address indexed collateralAsset, address indexed principalToken, address indexed swapToken);

    function setUp() external {
        user1 = makeAddr("user1");

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, poolId) = createMarket(block.timestamp + 1 days);
        vm.deal(DEFAULT_ADDRESS, 100_000_000_000 ether);
        collateralAsset.deposit{value: 1_000_000_000 ether}();
        referenceAsset.deposit{value: 1_000_000_000 ether}();

        collateralAsset.approve(address(corkPoolManager), 100_000_000_000 ether);
        referenceAsset.approve(address(corkPoolManager), 100_000_000_000 ether);

        corkPoolManager.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);
        vm.stopPrank();

        rateOracle = address(testOracle);
    }

    function fetchProtocolGeneralInfo() internal {
        (address _ct, address _swapToken) = corkPoolManager.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);
        swapToken.approve(address(corkPoolManager), 100_000_000_000 ether);
    }

    function assertReserve(PoolShare token, uint256 expectedRa, uint256 expectedPa) internal {
        (uint256 collateralAsset, uint256 referenceAsset) = token.getReserves();

        vm.assertEq(collateralAsset, expectedRa);
        vm.assertEq(referenceAsset, expectedPa);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldWorkCorrectly() external {
        assertEq(address(sharesFactory.CORK_POOL_MANAGER()), address(corkPoolManager));
    }

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
        MarketId poolId = corkPoolManager.getId(poolParams());
        (address principalToken, address swapToken) = corkPoolManager.shares(poolId);
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));
    }

    function test_getDeployedSwapSharesShouldWorkWithSingleShare() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        MarketId poolId = createPool();

        (address principalToken, address swapToken) = corkPoolManager.shares(poolId);
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
            expiryTimestamp: 100 days,
            rateOracle: rateOracle,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
        MarketId pool1Id = MarketId.wrap(keccak256(abi.encode(pool1)));
        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(pool1Id, DEFAULT_ORACLE_RATE);
        _createNewPool(pool1, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

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
            expiryTimestamp: 200 days,
            rateOracle: rateOracle,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
        MarketId pool2Id = MarketId.wrap(keccak256(abi.encode(pool2)));
        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(pool2Id, DEFAULT_ORACLE_RATE);
        _createNewPool(pool2, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

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
    function test_DeploySwapSharesShouldRevertIfCallerIsNotCorkPoolManager() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotCorkPoolManager.selector));
        sharesFactory.deployPoolShares(
            ISharesFactory.DeployParams({
                poolId: poolId,
                owner: DEFAULT_ADDRESS,
                poolParams: Market({
                    collateralAsset: address(collateralAsset),
                    referenceAsset: address(referenceAsset),
                    expiryTimestamp: 100 days,
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
            expiryTimestamp: 100 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });
        MarketId poolId1 = MarketId.wrap(keccak256(abi.encode(pool1)));

        vm.startPrank(DEFAULT_ADDRESS);
        vm.expectEmit(true, false, false, true);
        emit SharesDeployed(address(collateralAsset), expectedPrincipalToken, expectedSwapToken);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(pool1, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false));

        (address ct1, address ds1) = corkPoolManager.shares(poolId1);
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);

        assertEq(PoolShare(ct1).expiry(), 100 days);
        assertEq(PoolShare(ds1).expiry(), 100 days);

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

        assertEq(PoolShare(ct1).owner(), address(corkPoolManager));
        assertEq(PoolShare(ds1).owner(), address(corkPoolManager));

        assertEq(PoolShare(ct1).totalSupply(), 0);
        assertEq(PoolShare(ds1).totalSupply(), 0);

        assertEq(PoolShare(ct1).balanceOf(DEFAULT_ADDRESS), 0);
        assertEq(PoolShare(ds1).balanceOf(DEFAULT_ADDRESS), 0);

        assertEq(PoolShare(ct1).allowance(DEFAULT_ADDRESS, address(corkPoolManager)), 0);
        assertEq(PoolShare(ds1).allowance(DEFAULT_ADDRESS, address(corkPoolManager)), 0);
    }

    //-----------------------------------------------------------------------------------------------------//

    function poolParams() internal returns (Market memory) {
        return Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: 100 days,
            rateOracle: rateOracle,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX
        });
    }

    function createPool() internal returns (MarketId _poolId) {
        Market memory poolParams = poolParams();
        _poolId = MarketId.wrap(keccak256(abi.encode(poolParams)));
        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(_poolId, DEFAULT_ORACLE_RATE);
        _createNewPool(poolParams, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
    }
}
