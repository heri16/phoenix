pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {WhitelistManager} from "contracts/core/WhitelistManager.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {SigUtils} from "test/old/forge/SigUtils.sol";
import {MockBundler3} from "test/old/forge/utils/MockBundler3.sol";
import {CorkPoolManagerMock} from "test/old/mocks/CorkPoolManagerMock.sol";
import {DummyERC20} from "test/old/mocks/DummyERC20.sol";
import {DummyWETH, ERC20Mock} from "test/old/mocks/DummyWETH.sol";
import {ERC20WithPermitMock} from "test/old/mocks/ERC20WithPermitMock.sol";
import {RateOracleMock} from "test/old/mocks/RateOracleMock.sol";

abstract contract Helper is SigUtils {
    CorkPoolManagerMock internal corkPoolManager;
    SharesFactory internal sharesFactory;
    DefaultCorkController internal defaultCorkController;
    CorkAdapter internal corkAdapter;
    address DEFAULT_ADDRESS = address(90);

    MockBundler3 internal mockBundler = MockBundler3(DEFAULT_ADDRESS);
    // EnvGetters internal env = new EnvGetters();

    ConstraintRateAdapter internal constraintRateAdapter;
    RateOracleMock internal testOracle = new RateOracleMock();
    WhitelistManager internal whitelistManager;

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

    uint8 internal constant MAX_DECIMALS = 18;

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

    function deployConstraintRateAdapter() internal {
        address _constraintRateAdapter = address(new ConstraintRateAdapter());

        ERC1967Proxy constraintRateAdapterProxy = new ERC1967Proxy(_constraintRateAdapter, "");
        constraintRateAdapter = ConstraintRateAdapter(address(constraintRateAdapterProxy));
    }

    function initializeConstraintRateAdapter() internal {
        constraintRateAdapter.initialize(DEFAULT_ADDRESS, address(corkPoolManager));
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

    function deploySharesFactory(address corkPoolManagerAddress) internal {
        sharesFactory = new SharesFactory(corkPoolManagerAddress);
    }

    function _createNewPool(Market memory market, uint256 swapFee, uint256 unwindSwapFeePercentage) internal {
        address rateOracle = address(testOracle);

        testOracle.setRate(defaultCurrencyId, defaultOracleRate());
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, unwindSwapFeePercentage, swapFee, false));
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

    function createMarket(uint256 expiryInSeconds, uint256 swapFee) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, swapFee, 18, 18);
    }

    function createMarket(uint256 expiryInSeconds, uint8 raDecimals, uint8 paDecimals) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, raDecimals, paDecimals);
    }

    function createMarket(uint256 expiryTimestamp, uint256 unwindSwapFeePercentage, uint256 swapFee, uint8 raDecimals, uint8 paDecimals) internal returns (ERC20Mock collateralAsset, ERC20Mock referenceAsset, MarketId poolId) {
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

        _createNewPool(marketParams, swapFee, unwindSwapFeePercentage);
    }

    function _calculateMinimumShares(uint8 decimals) internal pure returns (uint256 minimumShares) {
        // If collateral has fewer decimals than 18, calculate minimum shares amount to avoid rounding to 0
        return decimals < 18 ? 10 ** (18 - decimals) : 1;
    }

    function assumeMinimum(uint8 decimals, uint256 amount) internal {
        uint256 minimumShares = _calculateMinimumShares(decimals);
        vm.assume(amount % minimumShares == 0);
    }

    function deployDefaultCorkController(address admin, address configurator, address pauser, address poolDeployer, address corkPoolAddress) internal {
        // Deploy WhitelistManager behind proxy
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(whitelistManagerImpl, bytes(""));
        whitelistManager = WhitelistManager(address(whitelistManagerProxy));

        defaultCorkController = new DefaultCorkController(admin, configurator, pauser, poolDeployer, corkPoolAddress, address(whitelistManager), DEFAULT_ADDRESS);
    }

    function setupDefaultCorkController() internal {
        defaultCorkController.setTreasury(CORK_PROTOCOL_TREASURY);
    }

    function deployPeriphery() internal {
        // Deploy MockBundler3 at DEFAULT_ADDRESS to handle initiator() calls
        MockBundler3 bundler = new MockBundler3();
        vm.etch(DEFAULT_ADDRESS, address(bundler).code);
        mockBundler.setInitiator(DEFAULT_ADDRESS);

        corkAdapter = new CorkAdapter(BUNDLER3_ADDRESS, W_NATIVE_ADDRESS, address(corkPoolManager), address(whitelistManager));
    }

    function deployContracts(address admin, address configurator, address pauser, address poolDeployer) internal {
        // Pre-compute the CorkPool address
        address preComputeCorkPoolAddress = vm.computeCreateAddress(currentCaller(), vm.getNonce(currentCaller()) + 7);

        deployDefaultCorkController(admin, configurator, pauser, poolDeployer, preComputeCorkPoolAddress);
        deploySharesFactory(preComputeCorkPoolAddress);
        deployConstraintRateAdapter();

        corkPoolManager = new CorkPoolManagerMock();
        ERC1967Proxy corkPoolProxy = new ERC1967Proxy(address(corkPoolManager), abi.encodeWithSignature("initialize(address,address,address,address,address)", address(sharesFactory), address(defaultCorkController), address(constraintRateAdapter), CORK_PROTOCOL_TREASURY, address(whitelistManager)));
        corkPoolManager = CorkPoolManagerMock(address(corkPoolProxy));

        initializeConstraintRateAdapter();

        setupDefaultCorkController();

        whitelistManager.initialize(currentCaller(), address(defaultCorkController));
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
