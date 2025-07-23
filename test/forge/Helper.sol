pragma solidity ^0.8.30;

import {ExchangeRateProvider} from "./../../contracts/core/ExchangeRateProvider.sol";
import {SigUtils} from "./SigUtils.sol";
import {TestCorkPool} from "./TestCorkPool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DummyERCWithPermit} from "test/forge/utils/dummy/DummyERCWithPermit.sol";
import {DummyWETH} from "test/forge/utils/dummy/DummyWETH.sol";

contract CustomErc20 is DummyWETH {
    uint8 internal __decimals;

    constructor(uint8 _decimals) DummyWETH() {
        __decimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }
}

abstract contract Helper is SigUtils {
    TestCorkPool internal corkPool;
    SharesFactory internal sharesFactory;
    CorkConfig internal corkConfig;
    EnvGetters internal env = new EnvGetters();

    MarketId defaultCurrencyId;

    // 1% base redemption fee
    uint256 internal constant DEFAULT_BASE_REDEMPTION_FEE = 1 ether;

    uint256 internal constant DEFAULT_EXCHANGE_RATES = 1 ether;

    // 1% unwindSwap fee
    uint256 internal constant DEFAULT_REVERSE_SWAP_FEE = 1 ether;

    address DEFAULT_ADDRESS = address(1);

    // 10% initial swapToken price
    uint256 internal constant DEFAULT_INITIAL_DS_PRICE = 0.1 ether;

    uint8 internal constant TARGET_DECIMALS = 18;

    uint8 internal constant MAX_DECIMALS = 32;

    address internal constant CORK_PROTOCOL_TREASURY = address(789);

    address private overridenAddress;

    function overridePrank(address _as) public {
        (, address currentCaller,) = vm.readCallers();
        overridenAddress = currentCaller;
        vm.startPrank(_as);
    }

    function revertPrank() public {
        vm.stopPrank();
        vm.startPrank(overridenAddress);

        overridenAddress = address(0);
    }

    function currentCaller() internal returns (address currentCaller) {
        (, currentCaller,) = vm.readCallers();
    }

    function defaultExchangeRate() internal pure virtual returns (uint256) {
        return DEFAULT_EXCHANGE_RATES;
    }

    function deploySharesFactory() internal {
        ERC1967Proxy sharesFactoryProxy = new ERC1967Proxy(address(new SharesFactory()), abi.encodeWithSignature("initialize()"));
        sharesFactory = SharesFactory(address(sharesFactoryProxy));
    }

    function setupSharesFactory() internal {
        sharesFactory.setCorkPool(address(corkPool));
    }

    function _createNewMarket(address referenceAsset, address collateralAsset, uint256 baseRedemptionFee, uint256 expiryInSeconds, uint256 unwindSwapFeePercentage) internal {
        address exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());

        corkConfig.updateCorkPoolRate(defaultCurrencyId, defaultExchangeRate());
        corkConfig.createNewMarket(referenceAsset, collateralAsset, expiryInSeconds, exchangeRateProvider);
        corkConfig.updateBaseRedemptionFeePercentage(defaultCurrencyId, baseRedemptionFee);
        corkConfig.updateUnwindSwapFeeRate(defaultCurrencyId, unwindSwapFeePercentage);
    }

    function createNewMarket(address referenceAsset, address collateralAsset, uint256 expiryInSeconds) internal {
        _createNewMarket(referenceAsset, collateralAsset, DEFAULT_BASE_REDEMPTION_FEE, expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE);
    }

    function createNewMarketPair(uint256 expiryInSeconds) internal returns (DummyWETH collateralAsset, DummyWETH referenceAsset, MarketId id) {
        collateralAsset = new DummyWETH();
        referenceAsset = new DummyWETH();
        Market memory _id = MarketLibrary.initialize(address(referenceAsset), address(collateralAsset), expiryInSeconds, address(corkConfig.defaultExchangeRateProvider()));
        id = MarketLibrary.toId(_id);
    }

    function initializeAndIssueNewSwapTokenWithRaAsPermit(uint256 expiryInSeconds) internal returns (DummyERCWithPermit collateralAsset, DummyERCWithPermit referenceAsset, MarketId id) {
        if (block.timestamp + expiryInSeconds > block.timestamp + 100 days) revert("Expiry too far in the future, specify a default decay rate, this will cause the discount to exceed 100!");

        collateralAsset = new DummyERCWithPermit("Collateral Asset", "Collateral Asset");
        referenceAsset = new DummyERCWithPermit("Reference Asset", "Reference Asset");

        address exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());
        Market memory _id = MarketLibrary.initialize(address(referenceAsset), address(collateralAsset), expiryInSeconds, exchangeRateProvider);
        id = MarketLibrary.toId(_id);

        defaultCurrencyId = id;

        _createNewMarket(address(referenceAsset), address(collateralAsset), DEFAULT_BASE_REDEMPTION_FEE, expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE);
    }

    function createMarket(uint256 expiryInSeconds) internal returns (DummyWETH collateralAsset, DummyWETH referenceAsset, MarketId id) {
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, 18, 18);
    }

    function createMarket(uint256 expiryInSeconds, uint256 baseRedemptionFee) internal returns (DummyWETH collateralAsset, DummyWETH referenceAsset, MarketId id) {
        if (block.timestamp + expiryInSeconds > block.timestamp + 100 days) revert("Expiry too far in the future, specify a default decay rate, this will cause the discount to exceed 100!");
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, baseRedemptionFee, 18, 18);
    }

    function createMarket(uint256 expiryInSeconds, uint8 raDecimals, uint8 paDecimals) internal returns (DummyWETH collateralAsset, DummyWETH referenceAsset, MarketId id) {
        if (block.timestamp + expiryInSeconds > block.timestamp + 100 days) revert("Expiry too far in the future, specify a default decay rate, this will cause the discount to exceed 100!");
        return createMarket(expiryInSeconds, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, raDecimals, paDecimals);
    }

    function createMarket(uint256 expiryInSeconds, uint256 unwindSwapFeePercentage, uint256 baseRedemptionFee, uint8 raDecimals, uint8 paDecimals) internal returns (DummyWETH collateralAsset, DummyWETH referenceAsset, MarketId id) {
        if (raDecimals == 18 && paDecimals == 18) {
            collateralAsset = new DummyWETH();
            referenceAsset = new DummyWETH();
        } else {
            collateralAsset = new CustomErc20(raDecimals);
            referenceAsset = new CustomErc20(paDecimals);
        }

        address exchangeRateProvider = address(corkConfig.defaultExchangeRateProvider());

        Market memory _id = MarketLibrary.initialize(address(referenceAsset), address(collateralAsset), expiryInSeconds, exchangeRateProvider);
        id = MarketLibrary.toId(_id);

        defaultCurrencyId = id;

        _createNewMarket(address(referenceAsset), address(collateralAsset), baseRedemptionFee, expiryInSeconds, unwindSwapFeePercentage);
    }

    function deployConfig(address admin, address manager) internal {
        corkConfig = new CorkConfig(admin, manager);
    }

    function setupConfig() internal {
        corkConfig.setCorkPool(address(corkPool));
        corkConfig.setTreasury(CORK_PROTOCOL_TREASURY);
    }

    function createNewMarket() internal {
        corkPool.initialize(address(sharesFactory), address(corkConfig));
    }

    function deployContracts(address admin, address manager) internal {
        deployConfig(admin, manager);
        deploySharesFactory();

        ERC1967Proxy corkPoolProxy = new ERC1967Proxy(address(new TestCorkPool()), abi.encodeWithSignature("initialize(address,address)", address(sharesFactory), address(corkConfig)));
        corkPool = TestCorkPool(address(corkPoolProxy));
        setupSharesFactory();
        setupConfig();
    }

    function __workaround() internal {
        PrankWorkAround _contract = new PrankWorkAround();
        _contract.prankApply();
    }

    function envStringNoRevert(string memory key) internal view returns (string memory) {
        try env.envString(key) returns (string memory value) {
            return value;
        } catch {
            return "";
        }
    }

    function envUintNoRevert(string memory key) internal view returns (uint256) {
        try env.envUint(key) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }
}

contract EnvGetters is Test {
    function envString(string memory key) public view returns (string memory) {
        return vm.envString(key);
    }

    function envUint(string memory key) public view returns (uint256) {
        return vm.envUint(key);
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
