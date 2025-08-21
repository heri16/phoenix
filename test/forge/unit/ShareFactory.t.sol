pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract SharesFactoryTest is Helper {
    using MarketLibrary for Market;

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
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, poolId) = createMarket(block.timestamp + 1 days);
        vm.deal(DEFAULT_ADDRESS, 100_000_000_000 ether);
        collateralAsset.deposit{value: 1_000_000_000 ether}();
        referenceAsset.deposit{value: 1_000_000_000 ether}();

        collateralAsset.approve(address(corkPool), 100_000_000_000 ether);
        referenceAsset.approve(address(corkPool), 100_000_000_000 ether);

        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);
        vm.stopPrank();

        rateOracle = address(testOracle);
    }

    function fetchProtocolGeneralInfo() internal {
        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = PoolShare(_ct);
        swapToken = PoolShare(_swapToken);
        swapToken.approve(address(corkPool), 100_000_000_000 ether);
    }

    function assertReserve(PoolShare token, uint256 expectedRa, uint256 expectedPa) internal {
        (uint256 collateralAsset, uint256 referenceAsset) = token.getReserves();

        vm.assertEq(collateralAsset, expectedRa);
        vm.assertEq(referenceAsset, expectedPa);
    }

    // ------------------------------- Constructor ----------------------------------- //
    function test_ConstructorShouldWorkCorrectly() external {
        assertEq(address(sharesFactory.corkPool()), address(corkPool));
        assertEq(address(sharesFactory.owner()), DEFAULT_ADDRESS);
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- isDeployed ----------------------------------- //
    function test_IsDeployedShouldWorkCorrectly() external {
        // assertEq(sharesFactory.isDeployed(address(asset)), false);
        assertEq(sharesFactory.isDeployed(address(principalToken)), true);
        assertEq(sharesFactory.isDeployed(address(swapToken)), true);
        assertEq(sharesFactory.isDeployed(address(collateralAsset)), false);
        assertEq(sharesFactory.isDeployed(address(referenceAsset)), false);

        (ERC20Mock ra1, ERC20Mock pa1, MarketId id1) = createNewMarketPair(100 days);
        assertEq(sharesFactory.isDeployed(address(ra1)), false);
        assertEq(sharesFactory.isDeployed(address(pa1)), false);

        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);
        assertEq(sharesFactory.isDeployed(expectedPrincipalToken), false);
        assertEq(sharesFactory.isDeployed(expectedSwapToken), false);

        vm.startPrank(DEFAULT_ADDRESS);

        testOracle.setRate(id1, DEFAULT_ORACLE_RATE);
        // corkConfig.updateRateOfDefaultOracle(id1, DEFAULT_ORACLE_RATE);
        _createNewMarket(
            Market({collateralAsset: address(ra1), referenceAsset: address(pa1), expiryTimestamp: 100 days, rateMin: DEFAULT_RATE_MIN, rateMax: DEFAULT_RATE_MAX, rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX, rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX, rateOracle: address(0)}),
            DEFAULT_BASE_REDEMPTION_FEE,
            DEFAULT_REVERSE_SWAP_FEE
        );
        vm.stopPrank();

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        assertEq(sharesFactory.isDeployed(address(_ct)), true);
        assertEq(sharesFactory.isDeployed(address(_swapToken)), true);
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- getDeployedSwapShares ----------------------------------- //
    function test_getDeployedSwapSharesShouldWorkCorrectly() external {
        (address principalToken, address swapToken) = sharesFactory.poolShares(poolParams().toId());
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));

        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        MarketId poolId = createPool();

        (address ct1, address ds1) = sharesFactory.poolShares(poolId);
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldReturnZeroAddressWhenNoSharesDeployed() external {
        (address principalToken, address swapToken) = sharesFactory.poolShares(poolParams().toId());
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));
    }

    function test_getDeployedSwapSharesShouldWorkWithSingleShare() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        MarketId poolId = createPool();

        (address principalToken, address swapToken) = sharesFactory.poolShares(poolId);
        assertEq(principalToken, expectedPrincipalToken);
        assertEq(swapToken, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldWorkWithDifferentMarketParameters() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for first pool
        Market memory pool1 = MarketLibrary.initialize(address(referenceAsset), address(collateralAsset), 100 days, rateOracle, DEFAULT_RATE_MIN, DEFAULT_RATE_MAX, DEFAULT_RATE_CHANGE_PER_DAY_MAX, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(pool1.toId(), DEFAULT_ORACLE_RATE);
        _createNewMarket(pool1, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

        (address principalToken, address swapToken) = sharesFactory.poolShares(pool1.toId());
        assertEq(principalToken, expectedPrincipalToken);
        assertEq(swapToken, expectedSwapToken);

        currentNonce = vm.getNonce(address(sharesFactory));
        expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for second pool with different parameters
        Market memory pool2 = MarketLibrary.initialize(address(referenceAsset), address(collateralAsset), 200 days, rateOracle, DEFAULT_RATE_MIN, DEFAULT_RATE_MAX, DEFAULT_RATE_CHANGE_PER_DAY_MAX, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(pool2.toId(), DEFAULT_ORACLE_RATE);
        _createNewMarket(pool2, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

        // Get assets for second pool
        (address ct2, address ds2) = sharesFactory.poolShares(pool2.toId());
        assertEq(ct2, expectedPrincipalToken);
        assertEq(ds2, expectedSwapToken);

        // Verify they are different assets
        assertNotEq(principalToken, expectedPrincipalToken);
        assertNotEq(swapToken, expectedSwapToken);
    }

    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- DeploySwapShares ----------------------------------- //
    function test_DeploySwapSharesShouldRevertIfCallerIsNotCorkPool() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotCorkPool.selector));
        sharesFactory.deployPoolShares(
            ISharesFactory.DeployParams({
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
                }),
                swapRate: DEFAULT_ORACLE_RATE
            })
        );
    }

    function test_DeploySwapSharesShouldRevertIfSwapRateIsZero() external {
        vm.prank(address(corkPool));
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidRate.selector));
        sharesFactory.deployPoolShares(
            ISharesFactory.DeployParams({
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
                }),
                swapRate: 0
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
            rateOracle: address(0)
        });
        MarketId poolId1 = pool1.toId();

        vm.prank(address(corkPool));
        vm.expectEmit(true, false, false, true);
        emit SharesDeployed(address(collateralAsset), expectedPrincipalToken, expectedSwapToken);
        (address ct1, address ds1) = sharesFactory.deployPoolShares(ISharesFactory.DeployParams({poolParams: pool1, owner: DEFAULT_ADDRESS, swapRate: 1.23456 ether}));
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);

        assertEq(PoolShare(ct1).swapRate(), 1.23456 ether);
        assertEq(PoolShare(ds1).swapRate(), 1.23456 ether);

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

        assertEq(address(PoolShare(ct1).poolManager()), address(corkPool));
        assertEq(address(PoolShare(ds1).poolManager()), address(corkPool));

        assertEq(PoolShare(ct1).owner(), DEFAULT_ADDRESS);
        assertEq(PoolShare(ds1).owner(), DEFAULT_ADDRESS);

        assertEq(PoolShare(ct1).totalSupply(), 0);
        assertEq(PoolShare(ds1).totalSupply(), 0);

        assertEq(PoolShare(ct1).balanceOf(DEFAULT_ADDRESS), 0);
        assertEq(PoolShare(ds1).balanceOf(DEFAULT_ADDRESS), 0);

        assertEq(PoolShare(ct1).allowance(DEFAULT_ADDRESS, address(corkPool)), 0);
        assertEq(PoolShare(ds1).allowance(DEFAULT_ADDRESS, address(corkPool)), 0);
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- UpgradeToAndCall ----------------------------------- //
    function test_UpgradeToAndCallShouldRevertIfCallerIsNotOwner() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        sharesFactory.upgradeToAndCall(address(1234), bytes(""));
    }

    function test_UpgradeToAndCallShouldWorkCorrectly() external {
        SharesFactory newSharesFactory = new SharesFactory();

        vm.prank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(newSharesFactory));
        sharesFactory.upgradeToAndCall(address(newSharesFactory), bytes(""));
        assertEq(address(sharesFactory.corkPool()), address(corkPool));
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- SetCorkPool ----------------------------------- //
    function test_SetCorkPoolShouldRevertIfCallerIsNotOwner() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        sharesFactory.setCorkPool(address(0));
    }

    function test_SetCorkPoolShouldRevertIfCorkPoolIsZeroAddress() external {
        vm.prank(DEFAULT_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ZeroAddress.selector));
        sharesFactory.setCorkPool(address(0));
    }

    function test_SetCorkPoolShouldWorkCorrectly() external {
        assertEq(address(sharesFactory.corkPool()), address(corkPool));

        vm.prank(DEFAULT_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit CorkPoolChanged(address(corkPool), address(1234));
        sharesFactory.setCorkPool(address(1234));
        assertEq(address(sharesFactory.corkPool()), address(1234));
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- TransferOwnership ----------------------------------- //
    function test_TransferOwnershipShouldRevertIfCallerIsNotOwner() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        sharesFactory.transferOwnership(user1);
    }

    function test_TransferOwnershipShouldWorkCorrectly() external {
        assertEq(sharesFactory.owner(), DEFAULT_ADDRESS);

        vm.prank(DEFAULT_ADDRESS);
        sharesFactory.transferOwnership(user1);
        assertEq(sharesFactory.owner(), user1);
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- RenounceOwnership ----------------------------------- //
    function test_RenounceOwnershipShouldRevertIfCallerIsNotOwner() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        sharesFactory.renounceOwnership();
    }

    function test_RenounceOwnershipShouldWorkCorrectly() external {
        assertEq(sharesFactory.owner(), DEFAULT_ADDRESS);
        vm.prank(DEFAULT_ADDRESS);
        sharesFactory.renounceOwnership();
        assertEq(sharesFactory.owner(), address(0));
    }
    //-----------------------------------------------------------------------------------------------------//

    function poolParams() internal returns (Market memory) {
        return MarketLibrary.initialize(address(referenceAsset), address(collateralAsset), 100 days, rateOracle, DEFAULT_RATE_MIN, DEFAULT_RATE_MAX, DEFAULT_RATE_CHANGE_PER_DAY_MAX, DEFAULT_RATE_CHANGE_CAPACITY_MAX);
    }

    function createPool() internal returns (MarketId _poolId) {
        Market memory poolParams = poolParams();
        _poolId = poolParams.toId();
        vm.startPrank(DEFAULT_ADDRESS);
        testOracle.setRate(_poolId, DEFAULT_ORACLE_RATE);
        _createNewMarket(poolParams, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
    }
}
