pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {WhitelistManager} from "contracts/core/WhitelistManager.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {State} from "contracts/libraries/State.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {SigUtils} from "test/new/forge/helpers/SigUtils.sol";
import {CorkPoolManagerMock} from "test/new/forge/mocks/CorkPoolManagerMock.sol";
import {DummyERC20} from "test/new/forge/mocks/DummyERC20.sol";
import {DummyWETH, ERC20Mock} from "test/new/forge/mocks/DummyWETH.sol";
import {MockBundler3} from "test/new/forge/mocks/MockBundler3.sol";
import {RateOracleMock} from "test/new/forge/mocks/RateOracleMock.sol";

// TODO add helpers
abstract contract BaseTest is SigUtils {
    address internal CORK_PROTOCOL_TREASURY = address(789);
    // by default, all admin privileges are held by this address
    // TODO maybe rename this to something else? delta?
    address internal DEFAULT_ADDRESS = address(90);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal eve = makeAddr("eve");
    address internal pauser = makeAddr("pauser");
    address internal overridenAddress;

    CorkPoolManagerMock internal corkPoolManager;
    SharesFactory internal sharesFactory;
    DefaultCorkController internal defaultCorkController;
    CorkAdapter internal corkAdapter;
    MockBundler3 internal mockBundler = MockBundler3(DEFAULT_ADDRESS);
    ConstraintRateAdapter internal constraintRateAdapter;
    RateOracleMock internal testOracle = new RateOracleMock();
    WhitelistManager internal whitelistManager;
    MarketId internal defaultPoolId;
    ERC20Mock internal collateralAsset;
    ERC20Mock internal referenceAsset;
    PoolShare internal principalToken;
    PoolShare internal swapToken;

    // 1% base redemption fee
    uint256 internal DEFAULT_BASE_REDEMPTION_FEE = 1 ether;
    uint256 internal DEFAULT_ORACLE_RATE = 1 ether;
    uint256 internal DEFAULT_RATE_MIN = 0.9 ether;
    uint256 internal DEFAULT_RATE_MAX = 1.1 ether;
    uint256 internal DEFAULT_RATE_CHANGE_PER_DAY_MAX = 1 ether;
    uint256 internal DEFAULT_RATE_CHANGE_CAPACITY_MAX = 1 ether;
    // 1% unwindSwap fee
    uint256 internal DEFAULT_REVERSE_SWAP_FEE = 1 ether;

    // we're doing test in an isolated environment.
    // the current tests already uses `DEFAULT_ADDRESS` as the bundler3 address.
    // this is to simplify the testing processes.
    address internal BUNDLER3_ADDRESS = DEFAULT_ADDRESS;

    // Wrapped Native Token Addresses
    address internal W_NATIVE_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint8 internal TARGET_DECIMALS = 18;
    uint8 internal MAX_DECIMALS = 18;
    uint8 internal collateralDecimal;
    uint8 internal referenceDecimal;

    uint256 internal snapshotId;

    struct StateSnapshot {
        uint256 userRef;
        uint256 userCollateral;
        uint256 userPrincipalToken;
        uint256 userSwapToken;
        uint256 contractRef;
        uint256 contractCollateral;
        uint256 contractSwapToken;
        uint256 contractPrincipalToken;
        uint256 principalTokenTotalSupply;
        uint256 swapTokenTotalSupply;
        uint256 poolCollateral;
        uint256 poolRef;
        uint256 treasuryCollateral;
        State internalState;
    }

    function setUp() public virtual {
        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, pauser, DEFAULT_ADDRESS);
        createMarket(1 days);

        _giveAssets(alice);
        _giveAssets(bob);
        _giveAssets(charlie);
        _giveAssets(DEFAULT_ADDRESS);

        _approveAllTokens(alice, address(corkPoolManager));
        _approveAllTokens(bob, address(corkPoolManager));
        _approveAllTokens(charlie, address(corkPoolManager));
        _approveAllTokens(DEFAULT_ADDRESS, address(corkPoolManager));

        vm.label(DEFAULT_ADDRESS, "DEFAULT_ADDRESS");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
    }

    // modifier has two "_" so that we can still declare an internal function on the helper using one "_"
    modifier __as(address __as) {
        overridePrank(__as);
        _;
    }

    modifier __createPool(uint256 expiryInSeconds, uint8 _collateralDecimal, uint8 _referenceDecimal) {
        createMarket(expiryInSeconds, _collateralDecimal, _referenceDecimal, false);

        collateralDecimal = collateralAsset.decimals();
        referenceDecimal = referenceAsset.decimals();

        _;
    }

    modifier __createPoolWithWhitelist(uint256 expiryInSeconds) {
        createMarket(expiryInSeconds, 18, 18, true);
        _;
    }

    modifier __createPoolBounded(uint256 expiryInSeconds, uint8 _collateralDecimal, uint8 _referenceDecimal) {
        createMarketBounded(expiryInSeconds, _collateralDecimal, _referenceDecimal);

        collateralDecimal = collateralAsset.decimals();
        referenceDecimal = referenceAsset.decimals();

        _;
    }

    modifier __approveAllTokens(address user, address spender) {
        _approveAllTokens(user, spender);
        _;
    }

    modifier __giveAssets(address who) {
        _giveAssets(who);
        _;
    }

    modifier __deposit(uint256 amount, address receiver) {
        _deposit(defaultPoolId, amount, receiver);
        _;
    }

    modifier __depositAndSwap(uint256 depositAmount, uint256 swapAmount, address receiver) {
        _deposit(defaultPoolId, depositAmount, receiver);
        _swap(defaultPoolId, swapAmount, receiver);
        _;
    }

    function _deposit(MarketId _poolId, uint256 amount, address receiver) internal returns (uint256 shares) {
        shares = corkPoolManager.deposit(_poolId, amount, receiver);
    }

    function _swap(MarketId _poolId, uint256 amount, address receiver) internal {
        corkPoolManager.swap(_poolId, amount, receiver);
    }

    function overridePrank(address __as) public {
        address _currentCaller = currentCaller();
        overridenAddress = _currentCaller;
        vm.startPrank(__as);
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

    // TODO remove all of this default functions. Since it's now an internal variable. tests should directly assign
    function defaultOracleRate() internal view virtual returns (uint256) {
        return DEFAULT_ORACLE_RATE;
    }

    function defaultRateMin() internal view virtual returns (uint256) {
        return DEFAULT_RATE_MIN;
    }

    function defaultRateMax() internal view virtual returns (uint256) {
        return DEFAULT_RATE_MAX;
    }

    function defaultRateChangePerDayMax() internal view virtual returns (uint256) {
        return DEFAULT_RATE_CHANGE_PER_DAY_MAX;
    }

    function defaultRateChangeCapacityMax() internal view virtual returns (uint256) {
        return DEFAULT_RATE_CHANGE_CAPACITY_MAX;
    }

    function defaultAdapterCorkPool() internal view virtual returns (address) {
        return DEFAULT_ADDRESS;
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

    function _setupMarketAssets(uint8 collateralDecimal, uint8 referenceDecimal) internal {
        if (collateralDecimal == 18 && referenceDecimal == 18) {
            collateralAsset = new DummyWETH();
            referenceAsset = new DummyWETH();
        } else {
            collateralAsset = new DummyERC20("Collateral Asset", "CA", collateralDecimal);
            referenceAsset = new DummyERC20("Reference Asset", "REF", referenceDecimal);
        }
    }

    function _createPool(uint256 expiryTimestamp, uint256 unwindSwapFeePercentage, uint256 swapFee, bool whitelist) internal returns (MarketId poolId) {
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

        defaultPoolId = poolId;

        testOracle.setRate(defaultPoolId, defaultOracleRate());
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(marketParams, unwindSwapFeePercentage, swapFee, whitelist));

        (address principal, address swap) = corkPoolManager.shares(defaultPoolId);
        principalToken = PoolShare(principal);
        swapToken = PoolShare(swap);
    }

    function createMarket(uint256 expiryInSeconds) internal returns (ERC20Mock, ERC20Mock, MarketId poolId) {
        _setupMarketAssets(18, 18);
        poolId = _createPool(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false);
        return (collateralAsset, referenceAsset, poolId);
    }

    function createMarket(uint256 expiryInSeconds, uint8 collateralDecimal, uint8 referenceDecimal, bool whitelistEnabled) internal returns (ERC20Mock, ERC20Mock, MarketId poolId) {
        _setupMarketAssets(collateralDecimal, referenceDecimal);
        poolId = _createPool(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, whitelistEnabled);
        return (collateralAsset, referenceAsset, poolId);
    }

    function createMarketBounded(uint256 expiryInSeconds, uint8 _collateralDecimal, uint8 _referenceDecimal) internal returns (ERC20Mock, ERC20Mock, MarketId poolId) {
        _collateralDecimal = uint8(bound(_collateralDecimal, TARGET_DECIMALS, MAX_DECIMALS));
        _referenceDecimal = uint8(bound(_referenceDecimal, TARGET_DECIMALS, MAX_DECIMALS));

        return createMarket(expiryInSeconds, _collateralDecimal, _referenceDecimal, false);
    }

    function createMarket(uint256 expiryTimestamp, uint256 unwindSwapFeePercentage, uint256 swapFee, uint8 collateralDecimal, uint8 referenceDecimal) internal returns (ERC20Mock, ERC20Mock, MarketId poolId) {
        _setupMarketAssets(collateralDecimal, referenceDecimal);
        poolId = _createPool(expiryTimestamp, unwindSwapFeePercentage, swapFee, false);
        return (collateralAsset, referenceAsset, poolId);
    }

    function _calculateMinimumShares(uint8 decimals) internal pure returns (uint256 minimumShares) {
        // If collateral has fewer decimals than 18, calculate minimum shares amount to avoid rounding to 0
        return decimals < 18 ? 10 ** (18 - decimals) : 1;
    }

    function assumeMinimum(uint8 decimals, uint256 amount) internal {
        uint256 minimumShares = _calculateMinimumShares(decimals);
        vm.assume(amount % minimumShares == 0);
    }

    function _giveAssets(address who) internal __as(who) {
        vm.deal(who, type(uint256).max);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();
    }

    function _approveAllTokens(address user, address spender) internal __as(user) {
        collateralAsset.approve(spender, type(uint248).max);
        referenceAsset.approve(spender, type(uint248).max);
        principalToken.approve(spender, type(uint248).max);
        swapToken.approve(spender, type(uint248).max);
    }

    function _approveToken(address user, address token, address spender) internal __as(user) {
        IERC20(token).approve(spender, type(uint256).max);
    }

    function _getStateSnapshot(address user, MarketId poolId) internal view returns (StateSnapshot memory snapshot) {
        snapshot.userRef = referenceAsset.balanceOf(user);
        snapshot.userCollateral = collateralAsset.balanceOf(user);
        snapshot.userPrincipalToken = principalToken.balanceOf(user);
        snapshot.userSwapToken = swapToken.balanceOf(user);
        snapshot.contractRef = referenceAsset.balanceOf(address(corkPoolManager));
        snapshot.contractCollateral = collateralAsset.balanceOf(address(corkPoolManager));
        snapshot.principalTokenTotalSupply = principalToken.totalSupply();
        snapshot.swapTokenTotalSupply = swapToken.totalSupply();
        (snapshot.poolCollateral, snapshot.poolRef) = corkPoolManager.assets(poolId);
        snapshot.treasuryCollateral = collateralAsset.balanceOf(CORK_PROTOCOL_TREASURY);
        snapshot.internalState = corkPoolManager.state(poolId);
        snapshot.contractSwapToken = swapToken.balanceOf(address(corkPoolManager));
        snapshot.contractPrincipalToken = principalToken.balanceOf(address(corkPoolManager));
    }

    function deployContracts(address admin, address configurator, address pauser, address poolDeployer) internal {
        // Pre-compute the CorkPool address
        address preComputeCorkPoolAddress = vm.computeCreateAddress(currentCaller(), vm.getNonce(currentCaller()) + 7);

        // Step 1: Deploy WhitelistManager behind proxy
        address whitelistManagerImpl = address(new WhitelistManager());
        ERC1967Proxy whitelistManagerProxy = new ERC1967Proxy(whitelistManagerImpl, bytes(""));
        whitelistManager = WhitelistManager(address(whitelistManagerProxy));

        // Step 2: Deploy DefaultCorkController contract
        defaultCorkController = new DefaultCorkController(admin, configurator, pauser, poolDeployer, preComputeCorkPoolAddress, address(whitelistManager), currentCaller());

        // Step 3: Deploy SharesFactory contract
        sharesFactory = new SharesFactory(preComputeCorkPoolAddress);

        // Step 4: Deploy ConstraintRateAdapter behind a proxy
        address _constraintRateAdapter = address(new ConstraintRateAdapter());
        ERC1967Proxy constraintRateAdapterProxy = new ERC1967Proxy(_constraintRateAdapter, "");
        constraintRateAdapter = ConstraintRateAdapter(address(constraintRateAdapterProxy));

        // Step 5: Deploy CorkPoolManagerMock implementation
        corkPoolManager = new CorkPoolManagerMock();

        // Step 6: Deploy CorkPoolManager behind a proxy with initialization
        ERC1967Proxy corkPoolProxy = new ERC1967Proxy(address(corkPoolManager), abi.encodeWithSignature("initialize(address,address,address,address,address)", address(sharesFactory), address(defaultCorkController), address(constraintRateAdapter), CORK_PROTOCOL_TREASURY, address(whitelistManager)));
        corkPoolManager = CorkPoolManagerMock(address(corkPoolProxy));

        whitelistManager.initialize(address(corkPoolManager), admin, address(defaultCorkController));

        // Step 7: Initialize ConstraintRateAdapter with bundler and corkPoolManager addresses
        constraintRateAdapter.initialize(DEFAULT_ADDRESS, address(corkPoolManager));

        // Step 8: Configure treasury address in DefaultCorkController
        defaultCorkController.setTreasury(CORK_PROTOCOL_TREASURY);

        // Step 9: Deploy MockBundler3 at DEFAULT_ADDRESS to handle initiator() calls
        MockBundler3 bundler = new MockBundler3();
        vm.etch(DEFAULT_ADDRESS, address(bundler).code);
        mockBundler.setInitiator(DEFAULT_ADDRESS);

        // Step 10: Deploy CorkAdapter with bundler, wrapped native token, and corkPoolManager addresses
        corkAdapter = new CorkAdapter(BUNDLER3_ADDRESS, W_NATIVE_ADDRESS, address(corkPoolManager), address(whitelistManager));

        address[] memory addresses = new address[](5);

        addresses[0] = address(corkAdapter);
        addresses[1] = alice;
        addresses[2] = bob;
        addresses[3] = charlie;
        addresses[4] = DEFAULT_ADDRESS;

        defaultCorkController.addToGlobalWhitelist(addresses);
    }
}
