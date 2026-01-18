pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConstraintRateAdapter} from "contracts/interfaces/IConstraintRateAdapter.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {Config} from "forge-std/Config.sol";
import {Test} from "forge-std/Test.sol";

abstract contract SmokeBase is Test, Config {
    string internal EVM_VERSION;

    uint256 internal SMOKE_TEST_CHAIN_ID;

    address internal CORK_POOL_MANAGER;
    address internal SHARES_FACTORY;
    address internal DEFAULT_CORK_CONTROLLER;
    address internal CONSTRAINT_RATE_ADAPTER;
    address internal ORACLE_ADDRESS;
    address internal WHITELIST_MANAGER;
    address internal POOL_CREATOR_ADDRESS;

    address internal EXPECTED_COLLATERAL_ADDRESS;
    address internal EXPECTED_REFERENCE_ADDRESS;
    uint256 internal EXPECTED_EXPIRY_TIMESTAMP;
    uint256 internal EXPECTED_RATE_MIN_BOUND;
    uint256 internal EXPECTED_RATE_MAX_BOUND;
    uint256 internal EXPECTED_RATE_CHANGE_PER_DAY_MAX;
    uint256 internal EXPECTED_RATE_CHANGE_CAPACITY_MAX;
    bool internal EXPECTED_WHITELIST_ENABLED;

    uint8 internal ACCEPTABLE_DECIMALS_MAX;
    uint8 internal ACCEPTABLE_DECIMALS_MIN;

    uint256 internal EXPECTED_MAX_EXPIRY_BOUND;
    uint256 internal EXPECTED_MIN_EXPIRY_BOUND;

    uint256 internal EXPECTED_ORACLE_RATE;
    uint8 internal EXPECTED_ORACLE_DECIMALS;

    uint256 internal EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE;
    uint256 internal EXPECTED_SWAP_FEE_PERCENTAGE;

    uint256 internal EXPECTED_CST_SHARES_SWAP_AMOUNT_IN;
    uint256 internal EXPECTED_REFERENCE_SWAP_AMOUNT_IN;
    uint256 internal EXPECTED_COLLATERAL_SWAP_AMOUNT_OUT;
    uint256 internal EXPECTED_SWAP_FEE;

    uint256 internal EXPECTED_CST_SHARES_EXERCISE_AMOUNT_IN;
    uint256 internal EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT;
    uint256 internal EXPECTED_REFERENCE_EXERCISE_AMOUNT_IN;
    uint256 internal EXPECTED_EXERCISE_FEE;

    uint256 internal EXPECTED_REFERENCE_EXERCISE_OTHER_AMOUNT_IN;
    uint256 internal EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT;
    uint256 internal EXPECTED_CST_SHARES_EXERCISE_OTHER_AMOUNT_IN;
    uint256 internal EXPECTED_EXERCISE_OTHER_FEE;

    uint256 internal EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN;
    uint256 internal EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT;
    uint256 internal EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT;
    uint256 internal EXPECTED_UNWIND_SWAP_FEE_INITIAL;

    uint256 internal EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN_BEFORE_EXPIRY;
    uint256 internal EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY;
    uint256 internal EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY;

    uint256 internal EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN;
    uint256 internal EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE;

    uint256 internal EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN_BEFORE_EXPIRY;
    uint256 internal EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY;

    uint256 internal EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN;
    uint256 internal EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE;

    uint256 internal EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN_BEFORE_EXPIRY;
    uint256 internal EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY;
    uint256 internal EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY;

    address[] internal EXPECTED_WHITELISTED_ADDRESSES;

    IPoolManager internal corkPoolManager;
    ISharesFactory internal sharesFactory;
    IDefaultCorkController internal defaultCorkController;
    IConstraintRateAdapter internal constraintRateAdapter;
    IRateOracle internal oracle;
    IWhitelistManager internal whitelistManager;
    MarketId internal defaultPoolId;

    function setUp() public virtual {
        string memory configPath = vm.envOr("SMOKE_CONFIG_PATH", string(""));

        if (bytes(configPath).length == 0) vm.skip(true);

        _loadConfig(configPath, false);

        _loadConfigValues();

        string memory forkUrl = config.getRpcUrl(SMOKE_TEST_CHAIN_ID);
        uint256 forkBlockNumber = config.get(SMOKE_TEST_CHAIN_ID, "fork_block_number").toUint256();

        if (bytes(forkUrl).length == 0 || forkBlockNumber == 0) vm.skip(true);

        vm.createSelectFork(forkUrl, forkBlockNumber);
        _setupForkEnvironment();
    }

    function _loadConfigValues() internal virtual {
        uint256[] memory chainIds = config.getChainIds();
        SMOKE_TEST_CHAIN_ID = chainIds[0];

        EVM_VERSION = config.get(SMOKE_TEST_CHAIN_ID, "evm_version").toString();

        CORK_POOL_MANAGER = config.get(SMOKE_TEST_CHAIN_ID, "cork_pool_manager").toAddress();
        SHARES_FACTORY = config.get(SMOKE_TEST_CHAIN_ID, "shares_factory").toAddress();
        DEFAULT_CORK_CONTROLLER = config.get(SMOKE_TEST_CHAIN_ID, "default_cork_controller").toAddress();
        CONSTRAINT_RATE_ADAPTER = config.get(SMOKE_TEST_CHAIN_ID, "constraint_rate_adapter").toAddress();
        ORACLE_ADDRESS = config.get(SMOKE_TEST_CHAIN_ID, "oracle_address").toAddress();
        WHITELIST_MANAGER = config.get(SMOKE_TEST_CHAIN_ID, "whitelist_manager").toAddress();
        POOL_CREATOR_ADDRESS = config.get(SMOKE_TEST_CHAIN_ID, "pool_creator_address").toAddress();

        EXPECTED_COLLATERAL_ADDRESS = config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_address").toAddress();
        EXPECTED_REFERENCE_ADDRESS = config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_address").toAddress();
        EXPECTED_WHITELISTED_ADDRESSES =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_whitelisted_addresses").toAddressArray();

        EXPECTED_WHITELIST_ENABLED = config.get(SMOKE_TEST_CHAIN_ID, "expected_whitelist_enabled").toBool();

        ACCEPTABLE_DECIMALS_MAX = config.get(SMOKE_TEST_CHAIN_ID, "acceptable_decimals_max").toUint8();
        ACCEPTABLE_DECIMALS_MIN = config.get(SMOKE_TEST_CHAIN_ID, "acceptable_decimals_min").toUint8();

        EXPECTED_EXPIRY_TIMESTAMP = config.get(SMOKE_TEST_CHAIN_ID, "expected_expiry_timestamp").toUint256();
        EXPECTED_RATE_MIN_BOUND = config.get(SMOKE_TEST_CHAIN_ID, "expected_rate_min_bound").toUint256();
        EXPECTED_RATE_MAX_BOUND = config.get(SMOKE_TEST_CHAIN_ID, "expected_rate_max_bound").toUint256();
        EXPECTED_RATE_CHANGE_PER_DAY_MAX =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_rate_change_per_day_max").toUint256();
        EXPECTED_RATE_CHANGE_CAPACITY_MAX =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_rate_change_capacity_max").toUint256();

        EXPECTED_ORACLE_RATE = config.get(SMOKE_TEST_CHAIN_ID, "expected_oracle_rate").toUint256();
        EXPECTED_ORACLE_DECIMALS = config.get(SMOKE_TEST_CHAIN_ID, "expected_oracle_decimals").toUint8();

        EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_unwind_swap_fee_percentage").toUint256();
        EXPECTED_SWAP_FEE_PERCENTAGE = config.get(SMOKE_TEST_CHAIN_ID, "expected_swap_fee_percentage").toUint256();

        EXPECTED_CST_SHARES_SWAP_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_swap_amount_in").toUint256();
        EXPECTED_REFERENCE_SWAP_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_swap_amount_in").toUint256();
        EXPECTED_COLLATERAL_SWAP_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_swap_amount_out").toUint256();
        EXPECTED_SWAP_FEE = config.get(SMOKE_TEST_CHAIN_ID, "expected_swap_fee").toUint256();

        EXPECTED_CST_SHARES_EXERCISE_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_exercise_amount_in").toUint256();
        EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_exercise_amount_out").toUint256();
        EXPECTED_REFERENCE_EXERCISE_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_exercise_amount_in").toUint256();
        EXPECTED_EXERCISE_FEE = config.get(SMOKE_TEST_CHAIN_ID, "expected_exercise_fee").toUint256();

        EXPECTED_REFERENCE_EXERCISE_OTHER_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_exercise_other_amount_in").toUint256();
        EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_exercise_other_amount_out").toUint256();
        EXPECTED_CST_SHARES_EXERCISE_OTHER_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_exercise_other_amount_in").toUint256();
        EXPECTED_EXERCISE_OTHER_FEE = config.get(SMOKE_TEST_CHAIN_ID, "expected_exercise_other_fee").toUint256();

        EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_swap_amount_in").toUint256();
        EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_unwind_swap_amount_out").toUint256();
        EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_unwind_swap_amount_out").toUint256();
        EXPECTED_UNWIND_SWAP_FEE_INITIAL =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_unwind_swap_fee_initial").toUint256();

        EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_swap_amount_in_before_expiry").toUint256();
        EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_unwind_swap_amount_out_before_expiry").toUint256();
        EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_unwind_swap_amount_out_before_expiry").toUint256();
        EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_swap_fee_before_expiry").toUint256();

        EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_unwind_exercise_amount_out").toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_amount_in").toUint256();
        EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_unwind_exercise_amount_out").toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_fee").toUint256();

        EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_unwind_exercise_amount_out_before_expiry").toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_amount_in_before_expiry").toUint256();
        EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_unwind_exercise_amount_out_before_expiry").toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_fee_before_expiry").toUint256();

        EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_reference_unwind_exercise_other_amount_out").toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_other_amount_in").toUint256();
        EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_cst_shares_unwind_exercise_other_amount_out").toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_other_fee").toUint256();

        EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY = config.get(
                SMOKE_TEST_CHAIN_ID, "expected_reference_unwind_exercise_other_amount_out_before_expiry"
            ).toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN_BEFORE_EXPIRY = config.get(
                SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_other_amount_in_before_expiry"
            ).toUint256();
        EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY = config.get(
                SMOKE_TEST_CHAIN_ID, "expected_cst_shares_unwind_exercise_other_amount_out_before_expiry"
            ).toUint256();
        EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY =
            config.get(SMOKE_TEST_CHAIN_ID, "expected_collateral_unwind_exercise_other_fee_before_expiry").toUint256();
    }

    function _setupForkEnvironment() internal virtual {
        _labelContracts();

        vm.setEvmVersion(EVM_VERSION);

        corkPoolManager = IPoolManager(CORK_POOL_MANAGER);
        sharesFactory = ISharesFactory(SHARES_FACTORY);
        defaultCorkController = IDefaultCorkController(DEFAULT_CORK_CONTROLLER);
        constraintRateAdapter = IConstraintRateAdapter(CONSTRAINT_RATE_ADAPTER);
        oracle = IRateOracle(ORACLE_ADDRESS);
        whitelistManager = IWhitelistManager(WHITELIST_MANAGER);

        EXPECTED_MAX_EXPIRY_BOUND = block.timestamp + (365 days * 2);
        EXPECTED_MIN_EXPIRY_BOUND = block.timestamp + 30 days;

        Market memory marketParams = Market(
            EXPECTED_COLLATERAL_ADDRESS,
            EXPECTED_REFERENCE_ADDRESS,
            EXPECTED_EXPIRY_TIMESTAMP,
            EXPECTED_RATE_MIN_BOUND,
            EXPECTED_RATE_MAX_BOUND,
            EXPECTED_RATE_CHANGE_PER_DAY_MAX,
            EXPECTED_RATE_CHANGE_CAPACITY_MAX,
            ORACLE_ADDRESS
        );

        // initialize with proper parameters in case it's not been initialized
        if (!isInitialized(marketParams)) {
            IDefaultCorkController.PoolCreationParams memory poolCreationParams =
                IDefaultCorkController.PoolCreationParams(
                    marketParams,
                    EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE,
                    EXPECTED_SWAP_FEE_PERCENTAGE,
                    EXPECTED_WHITELIST_ENABLED
                );

            vm.prank(POOL_CREATOR_ADDRESS);
            defaultCorkController.createNewPool(poolCreationParams);

            defaultPoolId = corkPoolManager.getId(marketParams);
        }

        defaultPoolId = corkPoolManager.getId(marketParams);
    }

    function isInitialized(Market memory params) internal view returns (bool) {
        MarketId poolId = corkPoolManager.getId(params);
        Market memory market = corkPoolManager.market(poolId);

        return market.collateralAsset != address(0);
    }

    function _labelContracts() internal virtual {
        vm.label(CORK_POOL_MANAGER, "Cork Pool Manager");
        vm.label(SHARES_FACTORY, "Shares Factory");
        vm.label(DEFAULT_CORK_CONTROLLER, "Default Cork Controller");
        vm.label(CONSTRAINT_RATE_ADAPTER, "Constraint Rate Adapter");
        vm.label(ORACLE_ADDRESS, "Composite Rate Oracle");
        vm.label(WHITELIST_MANAGER, "Whitelist Manager");
    }

    function delta(bool isForRef) internal view returns (uint256) {
        uint8 refDecimals = IERC20Metadata(EXPECTED_REFERENCE_ADDRESS).decimals();
        uint8 collateralDecimals = IERC20Metadata(EXPECTED_COLLATERAL_ADDRESS).decimals();

        if (refDecimals == collateralDecimals) return 1;

        if (isForRef && refDecimals > collateralDecimals) return 10 ** (refDecimals - collateralDecimals);

        if (isForRef && refDecimals < collateralDecimals) return 1;

        if (!isForRef && refDecimals < collateralDecimals) return 10 ** (collateralDecimals - refDecimals);

        if (!isForRef && refDecimals > collateralDecimals) return 1;

        return 1;
    }
}
