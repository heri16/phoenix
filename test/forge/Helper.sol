pragma solidity ^0.8.30;

import {SigUtils} from "./SigUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConstraintAdapter} from "contracts/core/ConstraintAdapter.sol";
import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {CorkPoolAdapter} from "contracts/periphery/CorkPoolAdapter.sol";
import {MockBundler3} from "test/forge/utils/MockBundler3.sol";
import {CorkPoolMock} from "test/mocks/CorkPoolMock.sol";
import {DummyERC20} from "test/mocks/DummyERC20.sol";
import {DummyWETH, ERC20Mock} from "test/mocks/DummyWETH.sol";
import {ERC20WithPermitMock} from "test/mocks/ERC20WithPermitMock.sol";
import {RateOracleMock} from "test/mocks/RateOracleMock.sol";

abstract contract Helper is SigUtils {
    CorkPoolMock internal corkPool;
    SharesFactory internal sharesFactory;
    CorkConfig internal corkConfig;
    CorkPoolAdapter internal corkPoolAdapter;
    address DEFAULT_ADDRESS = address(90);

    MockBundler3 internal mockBundler = MockBundler3(DEFAULT_ADDRESS);
    // EnvGetters internal env = new EnvGetters();

    ConstraintAdapter internal constraintAdapter;
    RateOracleMock internal testOracle = new RateOracleMock();

    MarketId defaultCurrencyId;

    // 1% base redemption fee
    uint256 internal constant DEFAULT_BASE_REDEMPTION_FEE = 1 ether;

    uint256 internal constant DEFAULT_ORACLE_RATE = 1 ether;
    uint256 internal constant DEFAULT_RATE_MIN = 0.9 ether;
    uint256 internal constant DEFAULT_RATE_MAX = 1.1 ether;
    uint256 internal constant DEFAULT_RATE_CHANGE_PER_DAY_MAX = 1 ether;
    uint256 internal constant DEFAULT_RATE_CHANGE_CAPACITY_MAX = 1 ether;

    // 1% unwindSwap fee
    uint256 internal constant DEFAULT_REVERSE_SWAP_FEE = 1 ether;

    // we're doing test in an isolated environment.
    // the current tests already uses `DEFAULT_ADDRESS` as the bundler3 address.
    // this is to simplify the testing processes.
    address BUNDLER3_ADDRESS = DEFAULT_ADDRESS;

    // Wrapped Native Token Addresses
    address W_NATIVE_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // 10% initial swapToken price
    uint256 internal constant DEFAULT_INITIAL_DS_PRICE = 0.1 ether;

    uint8 internal constant TARGET_DECIMALS = 18;

    uint8 internal constant MAX_DECIMALS = 32;

    address internal constant CORK_PROTOCOL_TREASURY = address(789);

    address private overridenAddress;

    uint256 private snapshotId;

    function overridePrank(address _as) public {
        (, address _currentCaller,) = vm.readCallers();
        overridenAddress = _currentCaller;
        vm.startPrank(_as);
    }

    function revertPrank() public {
        vm.stopPrank();
        vm.startPrank(overridenAddress);

        overridenAddress = address(0);
    }

    function currentCaller() internal returns (address _currentCaller) {
        (, _currentCaller,) = vm.readCallers();
    }

    function snapshotState() internal {
        snapshotId = vm.snapshotState();
    }

    function revertState() internal {
        vm.revertToState(snapshotId);
    }

    function deployConstraintAdapter() internal {
        address _constraintAdapter = address(new ConstraintAdapter());

        ERC1967Proxy constraintAdapterProxy = new ERC1967Proxy(_constraintAdapter, "");
        constraintAdapter = ConstraintAdapter(address(constraintAdapterProxy));
    }

    function initializeConstraintAdapter() internal {
        constraintAdapter.initialize(DEFAULT_ADDRESS, address(corkPool));
    }

    function defaultOracleRate() internal pure virtual returns (uint256) {
        return DEFAULT_ORACLE_RATE;
    }

    function defaultRateMin() internal pure virtual returns (uint256) {
        return DEFAULT_RATE_MIN;
    }

    function defaultRateMax() internal pure virtual returns (uint256) {
        return DEFAULT_RATE_MAX;
    }

    function defaultRateChangePerDayMax() internal pure virtual returns (uint256) {
        return DEFAULT_RATE_CHANGE_PER_DAY_MAX;
    }

    function defaultRateChangeCapacityMax() internal pure virtual returns (uint256) {
        return DEFAULT_RATE_CHANGE_CAPACITY_MAX;
    }

    function defaultAdapterCorkPool() internal view virtual returns (address) {
        return DEFAULT_ADDRESS;
    }

    function deploySharesFactory() internal {
        ERC1967Proxy sharesFactoryProxy = new ERC1967Proxy(address(new SharesFactory()), abi.encodeWithSignature("initialize()"));
        sharesFactory = SharesFactory(address(sharesFactoryProxy));
    }

    function setupSharesFactory() internal {
        sharesFactory.setCorkPool(address(corkPool));
    }

    function _createNewPool(Market memory market, uint256 baseRedemptionFee, uint256 unwindSwapFeePercentage) internal {
        address rateOracle = address(testOracle);

        testOracle.setRate(defaultCurrencyId, defaultOracleRate());
        corkConfig.createNewPool(market);
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, baseRedemptionFee);
        corkConfig.updateUnwindSwapFeeRate(defaultCurrencyId, unwindSwapFeePercentage);
    }

    function createNewPoolPair(uint256 expiryInSeconds) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        collateralAsset = new DummyWETH();
        referenceAsset = new DummyWETH();
        Market memory marketObject = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: expiryInSeconds,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });
        poolId = MarketId.wrap(keccak256(abi.encode(marketObject)));
    }

    function initializeAndIssueNewSwapTokenWithRaAsPermit(uint256 expiryTimestamp) internal returns (ERC20WithPermitMock collateralAsset, ERC20WithPermitMock referenceAsset, MarketId poolId) {
        collateralAsset = new ERC20WithPermitMock("Collateral Asset", "CA");
        referenceAsset = new ERC20WithPermitMock("Reference Asset", "REF");

        address rateOracle = address(testOracle);
        Market memory marketParams = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: expiryTimestamp,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });
        poolId = MarketId.wrap(keccak256(abi.encode(marketParams)));

        defaultCurrencyId = poolId;

        _createNewPool(marketParams, DEFAULT_BASE_REDEMPTION_FEE, DEFAULT_REVERSE_SWAP_FEE);
    }

    function createMarket(uint256 expiryInSeconds) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, 18, 18);
    }

    function createMarket(uint256 expiryInSeconds, uint256 baseRedemptionFee) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, baseRedemptionFee, 18, 18);
    }

    function createMarket(uint256 expiryInSeconds, uint8 raDecimals, uint8 paDecimals) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, raDecimals, paDecimals);
    }

    function createMarket(uint256 expiryTimestamp, uint256 unwindSwapFeePercentage, uint256 baseRedemptionFee, uint8 raDecimals, uint8 paDecimals) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        if (raDecimals == 18 && paDecimals == 18) {
            collateralAsset = new DummyWETH();
            referenceAsset = new DummyWETH();
        } else {
            collateralAsset = new DummyERC20("Collateral Asset", "CA", raDecimals);
            referenceAsset = new DummyERC20("Reference Asset", "REF", paDecimals);
        }

        Market memory marketParams = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: expiryTimestamp,
            rateMin: defaultRateMin(),
            rateMax: defaultRateMax(),
            rateChangePerDayMax: defaultRateChangePerDayMax(),
            rateChangeCapacityMax: defaultRateChangeCapacityMax(),
            rateOracle: address(testOracle)
        });
        poolId = MarketId.wrap(keccak256(abi.encode(marketParams)));

        defaultCurrencyId = poolId;

        _createNewPool(marketParams, baseRedemptionFee, unwindSwapFeePercentage);
    }

    function deployConfig(address admin, address pauser, address poolDeployer) internal {
        corkConfig = new CorkConfig(admin, pauser, poolDeployer);
    }

    function setupConfig() internal {
        corkConfig.setCorkPool(address(corkPool));
        corkConfig.setTreasury(CORK_PROTOCOL_TREASURY);
    }

    function deployPeriphery() internal {
        // Deploy MockBundler3 at DEFAULT_ADDRESS to handle initiator() calls
        MockBundler3 bundler = new MockBundler3();
        vm.etch(DEFAULT_ADDRESS, address(bundler).code);
        mockBundler.setInitiator(DEFAULT_ADDRESS);

        corkPoolAdapter = new CorkPoolAdapter(BUNDLER3_ADDRESS, W_NATIVE_ADDRESS, address(corkPool));
    }

    function deployContracts(address admin, address pauser, address poolDeployer) internal {
        deployConfig(admin, pauser, poolDeployer);
        deploySharesFactory();

        corkPool = new CorkPoolMock();

        deployConstraintAdapter();

        ERC1967Proxy corkPoolProxy = new ERC1967Proxy(address(corkPool), abi.encodeWithSignature("initialize(address,address,address)", address(sharesFactory), address(corkConfig), address(constraintAdapter)));
        corkPool = CorkPoolMock(address(corkPoolProxy));

        initializeConstraintAdapter();

        setupSharesFactory();
        setupConfig();
    }

    function __workaround() internal {
        PrankWorkAround _contract = new PrankWorkAround();
        _contract.prankApply();
    }
}

contract PrankWorkAround {
    constructor() {
        // This is a workaround to apply the prank to the contract
        // since uniswap does whacky things with the contract creation
    }

    function prankApply() public {
        // This is a workaround to apply the prank to the contract
        // since uniswap does whacky things with the contract creation
    }
}
