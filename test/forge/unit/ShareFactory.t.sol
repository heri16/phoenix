pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Shares} from "contracts/core/assets/Shares.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract SharesFactoryTest is Helper {
    using MarketLibrary for Market;

    DummyWETH collateralAsset;
    DummyWETH referenceAsset;
    Shares principalToken;
    Shares swapToken;
    Shares asset;

    MarketId marketId;

    address user1;
    address exchangeRateProvider;

    uint256 public constant depositAmount = 1 ether;
    uint256 public constant swapAmount = 0.123 ether;

    event CorkPoolChanged(address indexed oldCorkPool, address indexed newCorkPool);
    event Upgraded(address indexed implementation);
    event SharesDeployed(address indexed collateralAsset, address indexed principalToken, address indexed swapToken);

    function setUp() external {
        user1 = makeAddr("user1");

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);

        (collateralAsset, referenceAsset, marketId) = createMarket(block.timestamp + 1 days);
        vm.deal(DEFAULT_ADDRESS, 100_000_000_000 ether);
        collateralAsset.deposit{value: 1_000_000_000 ether}();
        referenceAsset.deposit{value: 1_000_000_000 ether}();

        collateralAsset.approve(address(corkPool), 100_000_000_000 ether);
        referenceAsset.approve(address(corkPool), 100_000_000_000 ether);

        corkPool.deposit(defaultCurrencyId, depositAmount, currentCaller());

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = Shares(_ct);
        swapToken = Shares(_swapToken);
        vm.stopPrank();

        exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());
    }

    function fetchProtocolGeneralInfo() internal {
        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        principalToken = Shares(_ct);
        swapToken = Shares(_swapToken);
        swapToken.approve(address(corkPool), 100_000_000_000 ether);
    }

    function assertReserve(Shares token, uint256 expectedRa, uint256 expectedPa) internal {
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
        assertEq(sharesFactory.isDeployed(address(asset)), false);
        assertEq(sharesFactory.isDeployed(address(principalToken)), true);
        assertEq(sharesFactory.isDeployed(address(swapToken)), true);
        assertEq(sharesFactory.isDeployed(address(collateralAsset)), false);
        assertEq(sharesFactory.isDeployed(address(referenceAsset)), false);

        (DummyWETH ra1, DummyWETH pa1, MarketId id1) = createNewMarketPair(100 days);
        assertEq(sharesFactory.isDeployed(address(ra1)), false);
        assertEq(sharesFactory.isDeployed(address(pa1)), false);

        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);
        assertEq(sharesFactory.isDeployed(expectedPrincipalToken), false);
        assertEq(sharesFactory.isDeployed(expectedSwapToken), false);

        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateCorkPoolRate(id1, DEFAULT_EXCHANGE_RATES);
        _createNewMarket(address(pa1), address(ra1), DEFAULT_BASE_REDEMPTION_FEE, 100 days, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

        (address _ct, address _swapToken) = corkPool.shares(defaultCurrencyId);
        assertEq(sharesFactory.isDeployed(address(_ct)), true);
        assertEq(sharesFactory.isDeployed(address(_swapToken)), true);
    }
    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- getDeployedSwapShares ----------------------------------- //
    function test_getDeployedSwapSharesShouldWorkCorrectly() external {
        (address principalToken, address swapToken) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 100 days, exchangeRateProvider);
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));

        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        createMarket();

        (address ct1, address ds1) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 100 days, exchangeRateProvider);
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldReturnZeroAddressWhenNoSharesDeployed() external {
        (address principalToken, address swapToken) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 30 days, exchangeRateProvider);
        assertEq(principalToken, address(0));
        assertEq(swapToken, address(0));
    }

    function test_getDeployedSwapSharesShouldWorkWithSingleShare() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        createMarket();

        (address principalToken, address swapToken) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 100 days, exchangeRateProvider);
        assertEq(principalToken, expectedPrincipalToken);
        assertEq(swapToken, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldWorkWithDifferentMarketParameters() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for first market
        MarketId marketId1 = Market(address(referenceAsset), address(collateralAsset), 100 days, exchangeRateProvider).toId();
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateCorkPoolRate(marketId1, DEFAULT_EXCHANGE_RATES);
        _createNewMarket(address(referenceAsset), address(collateralAsset), DEFAULT_BASE_REDEMPTION_FEE, 100 days, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

        (address principalToken, address swapToken) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 100 days, exchangeRateProvider);
        assertEq(principalToken, expectedPrincipalToken);
        assertEq(swapToken, expectedSwapToken);

        currentNonce = vm.getNonce(address(sharesFactory));
        expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for second market with different parameters
        MarketId marketId2 = Market(address(referenceAsset), address(collateralAsset), 200 days, exchangeRateProvider).toId();
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateCorkPoolRate(marketId2, DEFAULT_EXCHANGE_RATES);
        _createNewMarket(address(referenceAsset), address(collateralAsset), DEFAULT_BASE_REDEMPTION_FEE, 200 days, DEFAULT_REVERSE_SWAP_FEE);
        vm.stopPrank();

        // Get assets for second market
        (address ct2, address ds2) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 200 days, exchangeRateProvider);
        assertEq(ct2, expectedPrincipalToken);
        assertEq(ds2, expectedSwapToken);

        // Verify they are different assets
        assertNotEq(principalToken, expectedPrincipalToken);
        assertNotEq(swapToken, expectedSwapToken);
    }

    function test_getDeployedSwapSharesShouldWorkWithDifferentExchangeRateProvider() external {
        address exchangeRateProvider1 = exchangeRateProvider;
        address exchangeRateProvider2 = address(0x123);

        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);

        // Deploy assets for first market with first exchange rate provider
        createMarket();

        // Get assets for market with first exchange rate provider
        (address ct1, address ds1) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 100 days, exchangeRateProvider1);
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);

        // Get assets for market with second exchange rate provider (should be empty)
        (address ct2, address ds2) = sharesFactory.getDeployedSwapShares(address(collateralAsset), address(referenceAsset), 100 days, exchangeRateProvider2);
        assertEq(ct2, address(0));
        assertEq(ds2, address(0));
    }

    //-----------------------------------------------------------------------------------------------------//

    // ------------------------------- DeploySwapShares ----------------------------------- //
    function test_DeploySwapSharesShouldRevertIfCallerIsNotCorkPool() external {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotCorkPool.selector));
        sharesFactory.deploySwapShares(ISharesFactory.DeployParams({_collateralAsset: address(collateralAsset), _referenceAsset: address(referenceAsset), _owner: DEFAULT_ADDRESS, expiryTimestamp: 100 days, exchangeRateProvider: address(0), exchangeRate: DEFAULT_EXCHANGE_RATES}));
    }

    function test_DeploySwapSharesShouldRevertIfCorkPoolExchangeRateIsZero() external {
        vm.prank(address(corkPool));
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidRate.selector));
        sharesFactory.deploySwapShares(ISharesFactory.DeployParams({_collateralAsset: address(collateralAsset), _referenceAsset: address(referenceAsset), _owner: DEFAULT_ADDRESS, expiryTimestamp: 100 days, exchangeRateProvider: address(0), exchangeRate: 0}));
    }

    function test_DeploySwapSharesShouldWorkCorrectly() external {
        uint64 currentNonce = vm.getNonce(address(sharesFactory));
        address expectedPrincipalToken = vm.computeCreateAddress(address(sharesFactory), currentNonce);
        address expectedSwapToken = vm.computeCreateAddress(address(sharesFactory), currentNonce + 1);
        MarketId marketId1 = Market(address(referenceAsset), address(collateralAsset), 100 days, address(0)).toId();

        vm.prank(address(corkPool));
        vm.expectEmit(true, false, false, true);
        emit SharesDeployed(address(collateralAsset), expectedPrincipalToken, expectedSwapToken);
        (address ct1, address ds1) = sharesFactory.deploySwapShares(ISharesFactory.DeployParams({_collateralAsset: address(collateralAsset), _referenceAsset: address(referenceAsset), _owner: DEFAULT_ADDRESS, expiryTimestamp: 100 days, exchangeRateProvider: address(0), exchangeRate: 1.23456 ether}));
        assertEq(ct1, expectedPrincipalToken);
        assertEq(ds1, expectedSwapToken);

        assertEq(Shares(ct1).exchangeRate(), 1.23456 ether);
        assertEq(Shares(ds1).exchangeRate(), 1.23456 ether);

        assertEq(Shares(ct1).expiry(), 100 days);
        assertEq(Shares(ds1).expiry(), 100 days);

        assertEq(Shares(ct1).issuedAt(), block.timestamp);
        assertEq(Shares(ds1).issuedAt(), block.timestamp);

        assertEq(Shares(ct1).isExpired(), false);
        assertEq(Shares(ds1).isExpired(), false);

        assertEq(Shares(ct1).factory(), address(sharesFactory));
        assertEq(Shares(ds1).factory(), address(sharesFactory));

        assertEq(MarketId.unwrap(Shares(ct1).marketId()), MarketId.unwrap(marketId1));
        assertEq(MarketId.unwrap(Shares(ds1).marketId()), MarketId.unwrap(marketId1));

        assertEq(address(Shares(ct1).corkPool()), address(corkPool));
        assertEq(address(Shares(ds1).corkPool()), address(corkPool));

        assertEq(Shares(ct1).owner(), DEFAULT_ADDRESS);
        assertEq(Shares(ds1).owner(), DEFAULT_ADDRESS);

        assertEq(Shares(ct1).totalSupply(), 0);
        assertEq(Shares(ds1).totalSupply(), 0);

        assertEq(Shares(ct1).balanceOf(DEFAULT_ADDRESS), 0);
        assertEq(Shares(ds1).balanceOf(DEFAULT_ADDRESS), 0);

        assertEq(Shares(ct1).allowance(DEFAULT_ADDRESS, address(corkPool)), 0);
        assertEq(Shares(ds1).allowance(DEFAULT_ADDRESS, address(corkPool)), 0);
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

    function createMarket() internal returns (MarketId marketId1) {
        marketId1 = Market(address(referenceAsset), address(collateralAsset), 100 days, exchangeRateProvider).toId();
        vm.startPrank(DEFAULT_ADDRESS);
        corkConfig.updateCorkPoolRate(marketId1, DEFAULT_EXCHANGE_RATES);
        _createNewMarket(address(referenceAsset), address(collateralAsset), DEFAULT_BASE_REDEMPTION_FEE, 100 days, DEFAULT_REVERSE_SWAP_FEE);
    }
}
