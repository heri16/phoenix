// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ConstraintAdapter} from "./ConstraintAdapter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ModuleState} from "contracts/core/ModuleState.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {PoolState, State} from "contracts/libraries/State.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title CorkPool Abstract Contract
 * @author Cork Team
 * @notice Abstract CorkPool contract provides Cork Pool related logics
 */
contract CorkPool is IPoolManager, ModuleState, ContextUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using PoolLibrary for State;
    using MarketLibrary for Market;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer function for upgradeable contracts
    function initialize(address _swapSharesFactory, address _config, address _constraintAdapter) external initializer {
        require(_swapSharesFactory != address(0) && _config != address(0) && _constraintAdapter != address(0), InvalidParams());

        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
        initializeModuleState(_swapSharesFactory, _config, _constraintAdapter);
    }

    /// @notice Authorization function for UUPS proxy upgrades
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @inheritdoc Initialize
    function getId(address referenceAsset, address collateralAsset, uint256 _expiry, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax) external view returns (MarketId) {
        return MarketLibrary.initialize(referenceAsset, collateralAsset, _expiry, rateOracle, rateMin, rateMax, rateChangePerDayMax, rateChangeCapacityMax).toId();
    }

    /// @inheritdoc Initialize
    function market(MarketId poolId) external view returns (Market memory _market) {
        _market = data().states[poolId].info;
    }

    /// @inheritdoc Initialize
    function marketDetails(MarketId poolId) external view returns (address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax) {
        ModuleStateStorage storage ms = data();
        referenceAsset = ms.states[poolId].info.referenceAsset;
        collateralAsset = ms.states[poolId].info.collateralAsset;
        expiryTimestamp = ms.states[poolId].info.expiryTimestamp;
        rateOracle = ms.states[poolId].info.rateOracle;
        rateMin = ms.states[poolId].info.rateMin;
        rateMax = ms.states[poolId].info.rateMax;
        rateChangePerDayMax = ms.states[poolId].info.rateChangePerDayMax;
        rateChangeCapacityMax = ms.states[poolId].info.rateChangeCapacityMax;
    }

    /// @inheritdoc Initialize
    function createNewMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax) external override nonReentrant {
        onlyConfig();

        require(expiryTimestamp > block.timestamp, InvalidExpiry());
        Market memory poolParams = MarketLibrary.initialize(referenceAsset, collateralAsset, expiryTimestamp, rateOracle, rateMin, rateMax, rateChangePerDayMax, rateChangeCapacityMax);
        MarketId poolId = poolParams.toId();

        State storage state = data().states[poolId];

        require(!state.isInitialized(), AlreadyInitialized());

        PoolLibrary.initialize(state, poolParams, data().CONSTRAINT_ADAPTER);

        uint256 _swapRate = ConstraintAdapter(data().CONSTRAINT_ADAPTER).adjustedRate(poolId);

        (address principalToken, address swapToken) = ISharesFactory(data().SHARES_FACTORY).deployPoolShares(ISharesFactory.DeployParams({owner: address(this), poolParams: poolParams, swapRate: _swapRate}));

        state.swapToken._address = swapToken;
        state.swapToken.principalToken = principalToken;
        state.referenceDecimals = IERC20Metadata(referenceAsset).decimals();
        state.collateralDecimals = IERC20Metadata(collateralAsset).decimals();

        emit MarketCreated(poolId, referenceAsset, collateralAsset, expiryTimestamp, rateOracle, principalToken, swapToken);
    }

    /// @inheritdoc Initialize
    function updateUnwindSwapFeeRate(MarketId poolId, uint256 newUnwindSwapFeePercentage) external {
        onlyInitialized(poolId);
        onlyConfig();
        PoolLibrary.updateUnwindSwapFeePercentage(data().states[poolId], newUnwindSwapFeePercentage);

        emit UnwindSwapFeeRateUpdated(poolId, newUnwindSwapFeePercentage);
    }

    /// @inheritdoc Initialize
    function underlyingAsset(MarketId poolId) external view override returns (address collateralAsset, address referenceAsset) {
        (collateralAsset, referenceAsset) = data().states[poolId].info.underlyingAsset();
    }

    /// @inheritdoc Initialize
    function shares(MarketId poolId) external view override returns (address principalToken, address swapToken) {
        principalToken = data().states[poolId].swapToken.principalToken;
        swapToken = data().states[poolId].swapToken._address;
    }

    /// @inheritdoc Initialize
    function updateBaseRedemptionFeePercentage(MarketId poolId, uint256 newBaseRedemptionFeePercentage) external {
        onlyInitialized(poolId);
        onlyConfig();

        PoolLibrary.updateBaseRedemptionFeePercentage(data().states[poolId], newBaseRedemptionFeePercentage);
        emit BaseRedemptionFeePercentageUpdated(poolId, newBaseRedemptionFeePercentage);
    }

    /// @inheritdoc Initialize
    function expiry(MarketId poolId) external view override returns (uint256 _expiry) {
        _expiry = PoolLibrary.nextExpiry(data().states[poolId]);
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwapFee(MarketId poolId) external view override returns (uint256 fees) {
        fees = data().states[poolId].unwindSwapFeePercentage();
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwap(MarketId poolId, uint256 amount, address receiver) external override nonReentrant returns (uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 _swapRate) {
        onlyInitialized(poolId);
        corkPoolUnwindSwapAndExerciseNotPaused(poolId);

        State storage state = data().states[poolId];

        (receivedReferenceAsset, receivedSwapToken, feePercentage, fee, _swapRate) = state.unwindSwap(amount, receiver, _msgSender(), getTreasuryAddress(), data().CONSTRAINT_ADAPTER);

        emit PoolSwap(poolId, _msgSender(), receiver, amount, receivedReferenceAsset, fee, true);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, amount, 0);
        IPoolShare(state.swapToken.principalToken).emitWithdrawOther(_msgSender(), receiver, _msgSender(), address(state.info.referenceAsset), receivedReferenceAsset, receivedSwapToken);
    }

    /// @inheritdoc IUnwindSwap
    function availableForUnwindSwap(MarketId poolId) external view override returns (uint256 referenceAsset, uint256 swapToken) {
        (referenceAsset, swapToken) = data().states[poolId].availableForUnwindSwap();
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwapRate(MarketId poolId) external view returns (uint256 rate) {
        rate = data().states[poolId].unwindSwapRate(data().CONSTRAINT_ADAPTER);
    }

    /// @inheritdoc IPoolManager
    function deposit(MarketId poolId, uint256 amount, address receiver) external override nonReentrant returns (uint256 received) {
        onlyInitialized(poolId);
        corkPoolDepositAndMintNotPaused(poolId);

        State storage state = data().states[poolId];

        received = state.deposit(amount, receiver, _msgSender());
        emit PoolModifyLiquidity(poolId, _msgSender(), receiver, amount, 0, false);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, amount, received);
    }

    /// @inheritdoc IPoolManager
    function exercise(MarketId poolId, uint256 shares, uint256 compensation, address receiver, uint256 minAssetsOut, uint256 maxOtherAssetSpent) external override nonReentrant returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        onlyInitialized(poolId);
        corkPoolSwapNotPaused(poolId);

        State storage state = data().states[poolId];

        (assets, otherAssetSpent, fee) = state.exercise(shares, compensation, receiver, minAssetsOut, maxOtherAssetSpent, _msgSender(), _msgSender(), getTreasuryAddress(), data().CONSTRAINT_ADAPTER);

        emit PoolSwap(poolId, _msgSender(), _msgSender(), assets, compensation, 0, false);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, _msgSender(), assets, 0);
        IPoolShare(state.swapToken.principalToken).emitDepositOther(_msgSender(), receiver, address(state.info.referenceAsset), compensation, shares);
    }

    /// @inheritdoc IPoolManager
    function swapRate(MarketId poolId) external view override returns (uint256 rate) {
        rate = data().states[poolId].swapRate(data().CONSTRAINT_ADAPTER);
    }

    /// @inheritdoc IPoolManager
    function redeem(MarketId poolId, uint256 amount, address owner, address receiver) external override nonReentrant returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        onlyInitialized(poolId);
        corkPoolWithdrawalNotPaused(poolId);

        State storage state = data().states[poolId];

        (accruedReferenceAsset, accruedCollateralAsset) = state.redeem(amount, owner, receiver, _msgSender());

        emit PoolModifyLiquidity(poolId, _msgSender(), owner, accruedCollateralAsset, accruedReferenceAsset, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, owner, accruedCollateralAsset, amount);
        IPoolShare(state.swapToken.principalToken).emitWithdrawOther(_msgSender(), receiver, owner, address(state.info.referenceAsset), accruedReferenceAsset, amount);
    }

    /// @inheritdoc IPoolManager
    function valueLocked(MarketId poolId, bool collateralAsset) external view override returns (uint256 lockedAmount) {
        lockedAmount = data().states[poolId].valueLocked(collateralAsset);
    }

    /// @inheritdoc IPoolManager
    function unwindMint(MarketId poolId, uint256 cptAndCstSharesIn, address owner, address receiver) external override nonReentrant returns (uint256 collateralAsset) {
        onlyInitialized(poolId);
        corkPoolUnwindDepositAndMintNotPaused(poolId);

        State storage state = data().states[poolId];

        collateralAsset = state.unwindMint(owner, receiver, cptAndCstSharesIn);

        // Emit both events as required by the spec - both CPT and CST are burned equally
        emit PoolModifyLiquidity(poolId, _msgSender(), owner, collateralAsset, 0, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, owner, collateralAsset, cptAndCstSharesIn);
    }

    /// @inheritdoc IPoolManager
    function swap(MarketId poolId, uint256 assets, address receiver) external override nonReentrant returns (uint256 shares, uint256 compensation) {
        onlyInitialized(poolId);
        corkPoolSwapNotPaused(poolId);

        State storage state = data().states[poolId];

        (shares, compensation) = state.swap(assets, receiver, _msgSender(), _msgSender(), getTreasuryAddress(), data().CONSTRAINT_ADAPTER);

        emit PoolSwap(poolId, _msgSender(), _msgSender(), shares, compensation, 0, false);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, _msgSender(), assets, 0);
        IPoolShare(state.swapToken.principalToken).emitDepositOther(_msgSender(), receiver, address(state.info.referenceAsset), compensation, shares);
    }

    /// @inheritdoc IPoolManager
    function withdraw(MarketId poolId, uint256 collateralAssetOut, uint256 referenceAssetOut, address owner, address receiver) external override nonReentrant returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) {
        onlyInitialized(poolId);
        corkPoolWithdrawalNotPaused(poolId);

        State storage state = data().states[poolId];

        (sharesIn, actualCollateralAssetOut, actualReferenceAssetOut) = state.withdraw(collateralAssetOut, referenceAssetOut, owner, receiver, _msgSender());

        emit PoolModifyLiquidity(poolId, _msgSender(), owner, actualCollateralAssetOut, actualReferenceAssetOut, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, owner, actualCollateralAssetOut, sharesIn);
        IPoolShare(state.swapToken.principalToken).emitWithdrawOther(_msgSender(), receiver, owner, address(state.info.referenceAsset), actualReferenceAssetOut, sharesIn);
    }

    /// @inheritdoc IPoolManager
    function mint(MarketId poolId, uint256 swapAndPricipalTokenAmountOut, address receiver) external nonReentrant returns (uint256 collateralAmountIn) {
        onlyInitialized(poolId);
        corkPoolDepositAndMintNotPaused(poolId);

        State storage state = data().states[poolId];

        // since the the cpt and cst is 18 decimals, that meanns the out amount is also 18 decimals
        collateralAmountIn = TransferHelper.fixedToTokenNativeDecimals(swapAndPricipalTokenAmountOut, state.collateralDecimals);
        uint256 actualOut = state.deposit(collateralAmountIn, receiver, _msgSender());

        require(actualOut == swapAndPricipalTokenAmountOut, InvalidMintAmount(swapAndPricipalTokenAmountOut, actualOut));

        emit PoolModifyLiquidity(poolId, _msgSender(), receiver, collateralAmountIn, 0, false);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, collateralAmountIn, actualOut);
    }

    /// @inheritdoc IPoolManager
    function unwindDeposit(MarketId poolId, uint256 collateralAmtOut, address owner, address receiver) external nonReentrant returns (uint256 cptAndCstSharesIn) {
        onlyInitialized(poolId);
        corkPoolUnwindDepositAndMintNotPaused(poolId);

        State storage state = data().states[poolId];

        cptAndCstSharesIn = TransferHelper.tokenNativeDecimalsToFixed(collateralAmtOut, state.collateralDecimals);

        uint256 actualCollateralAssetOut = state.unwindMint(owner, receiver, cptAndCstSharesIn);
        require(collateralAmtOut == actualCollateralAssetOut, InvalidUnwindDepositAmount(collateralAmtOut, actualCollateralAssetOut));

        // Emit both events as required by the spec - both CPT and CST are burned equally
        emit PoolModifyLiquidity(poolId, _msgSender(), owner, actualCollateralAssetOut, 0, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, owner, actualCollateralAssetOut, cptAndCstSharesIn);
    }

    /// @inheritdoc IPoolManager
    function unwindExercise(MarketId poolId, uint256 shares, address receiver, uint256 minCompensationOut, uint256 maxAssetIn) external override nonReentrant returns (uint256 assetIn, uint256 compensationOut) {
        onlyInitialized(poolId);
        corkPoolUnwindSwapAndExerciseNotPaused(poolId);

        State storage state = data().states[poolId];

        (assetIn, compensationOut) = state.unwindExercise(shares, receiver, minCompensationOut, maxAssetIn, _msgSender(), getTreasuryAddress(), data().CONSTRAINT_ADAPTER);

        emit PoolSwap(poolId, _msgSender(), receiver, assetIn, compensationOut, 0, true);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, assetIn, 0);
        IPoolShare(state.swapToken.principalToken).emitWithdrawOther(_msgSender(), receiver, _msgSender(), address(state.info.referenceAsset), compensationOut, assetIn);
    }

    /// @inheritdoc IPoolManager
    function baseRedemptionFee(MarketId poolId) external view override returns (uint256 fees) {
        fees = data().states[poolId].pool.baseRedemptionFeePercentage;
    }

    /// @inheritdoc IPoolManager
    function pausedStates(MarketId poolId) external view returns (bool depositPaused, bool unwindSwapPaused, bool swapPaused, bool withdrawalPaused, bool unwindDepositAndMintPaused) {
        PoolState memory poolState = data().states[poolId].pool;
        return (poolState.isDepositPaused, poolState.isUnwindSwapPaused, poolState.isSwapPaused, poolState.isWithdrawalPaused, poolState.isReturnPaused);
    }

    /// @inheritdoc IPoolManager
    function setPausedState(MarketId poolId, IPoolManager.OperationType operationType, bool isPaused) external {
        onlyInitialized(poolId);
        onlyConfig();
        State storage state = data().states[poolId];

        if (operationType == OperationType.DEPOSIT) {
            require(state.pool.isDepositPaused != isPaused, SameStatus());
            state.pool.isDepositPaused = isPaused;

            if (isPaused) emit DepositPaused(poolId);
            else emit DepositUnpaused(poolId);
        } else if (operationType == OperationType.UNWIND_SWAP) {
            require(state.pool.isUnwindSwapPaused != isPaused, SameStatus());
            state.pool.isUnwindSwapPaused = isPaused;

            if (isPaused) emit UnwindSwapPaused(poolId);
            else emit UnwindSwapUnpaused(poolId);
        } else if (operationType == OperationType.SWAP) {
            require(state.pool.isSwapPaused != isPaused, SameStatus());
            state.pool.isSwapPaused = isPaused;

            if (isPaused) emit SwapPaused(poolId);
            else emit SwapUnpaused(poolId);
        } else if (operationType == OperationType.WITHDRAWAL) {
            require(state.pool.isWithdrawalPaused != isPaused, SameStatus());
            state.pool.isWithdrawalPaused = isPaused;

            if (isPaused) emit WithdrawalPaused(poolId);
            else emit WithdrawalUnpaused(poolId);
        } else if (operationType == OperationType.PREMATURE_WITHDRAWAL) {
            require(state.pool.isReturnPaused != isPaused, SameStatus());
            state.pool.isReturnPaused = isPaused;

            if (isPaused) emit ReturnPaused(poolId);
            else emit ReturnUnpaused(poolId);
        }
    }

    // ---------------------------------------------------------------------//
    // -------------------------- Preview Functions ------------------------//
    //----------------------------------------------------------------------//

    /// @inheritdoc IPoolManager
    function previewDeposit(MarketId poolId, uint256 amount) external view returns (uint256 received) {
        onlyInitialized(poolId);

        // 1:1 rate
        received = TransferHelper.tokenNativeDecimalsToFixed(amount, data().states[poolId].collateralDecimals);
    }

    /// @inheritdoc IPoolManager
    function previewSwap(MarketId poolId, uint256 assets) external view returns (uint256 sharesOut, uint256 compensation) {
        onlyInitialized(poolId);
        (sharesOut, compensation,) = data().states[poolId].previewSwap(assets, data().CONSTRAINT_ADAPTER);
    }

    /// @inheritdoc IPoolManager
    function previewRedeem(MarketId poolId, uint256 amount) external view override returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        onlyInitialized(poolId);
        (accruedReferenceAsset, accruedCollateralAsset) = data().states[poolId].previewRedeem(amount);
    }

    /// @inheritdoc IPoolManager
    function previewWithdraw(MarketId poolId, uint256 collateralAssetOut, uint256 referenceAssetOut) external view override returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        onlyInitialized(poolId);
        (sharesIn, actualReferenceAssetOut) = data().states[poolId].previewWithdraw(collateralAssetOut, referenceAssetOut);
    }

    /// @inheritdoc IPoolManager
    function previewUnwindDeposit(MarketId poolId, uint256 collateralAssetAmountOut) external view returns (uint256 cptAndCstSharesIn) {
        onlyInitialized(poolId);

        // 1:1 rate
        cptAndCstSharesIn = TransferHelper.tokenNativeDecimalsToFixed(collateralAssetAmountOut, data().states[poolId].collateralDecimals);
    }

    /// @inheritdoc IPoolManager
    function previewUnwindSwap(MarketId poolId, uint256 amount) external view returns (uint256 receivedRef, uint256 receivedCst, uint256 feePercentage, uint256 fee, uint256 _swapRate) {
        onlyInitialized(poolId);
        (receivedRef, receivedCst, feePercentage, fee, _swapRate,) = data().states[poolId].previewUnwindSwap(amount, data().CONSTRAINT_ADAPTER);
    }

    /// @inheritdoc IPoolManager
    function previewMint(MarketId poolId, uint256 swapAndPricipalTokenAmountOut) external view returns (uint256 collateralAmountIn) {
        onlyInitialized(poolId);

        // 1:1 rate
        collateralAmountIn = TransferHelper.fixedToTokenNativeDecimals(swapAndPricipalTokenAmountOut, data().states[poolId].collateralDecimals);
    }

    /// @inheritdoc IPoolManager
    function previewUnwindMint(MarketId poolId, uint256 cptAndCstAmountIn) external view returns (uint256 collateralAsset) {
        onlyInitialized(poolId);

        // Calculate minimum shares to avoid rounding issues
        uint256 minimumShares = 0;
        if (data().states[poolId].collateralDecimals < 18) minimumShares = 10 ** (18 - data().states[poolId].collateralDecimals);

        // Check if amount is less than minimum shares
        if (cptAndCstAmountIn < minimumShares && cptAndCstAmountIn > 0) return 0; // Return 0 for preview to indicate it's below minimum

        // 1:1 rate
        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(cptAndCstAmountIn, data().states[poolId].collateralDecimals);
    }

    /// @inheritdoc IPoolManager
    function previewUnwindExercise(MarketId poolId, uint256 shares) external view override returns (uint256 assetIn, uint256 compensationOut) {
        onlyInitialized(poolId);
        (assetIn, compensationOut,) = data().states[poolId].previewUnwindExercise(shares, getConstraintAdapter());
    }

    /// @inheritdoc IPoolManager
    function previewExercise(MarketId poolId, uint256 shares, uint256 compensation) external view override returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        onlyInitialized(poolId);
        (assets, otherAssetSpent, fee) = data().states[poolId].previewExercise(shares, compensation, getConstraintAdapter());
    }

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be minted
     * @return amount The maximum amount (unlimited)
     */
    function maxMint(MarketId poolId, address) external view returns (uint256 amount) {
        onlyInitialized(poolId);

        // If Minting is paused or the market is expired, return 0
        if (data().states[poolId].pool.isDepositPaused || PoolShare(data().states[poolId].swapToken.principalToken).isExpired()) return 0;

        amount = type(uint256).max;
    }

    /// @inheritdoc IPoolManager
    function maxDeposit(MarketId poolId, address) external view returns (uint256 amount) {
        onlyInitialized(poolId);

        // If Deposit is paused or the market is expired, return 0
        if (data().states[poolId].pool.isDepositPaused || PoolShare(data().states[poolId].swapToken.principalToken).isExpired()) return 0;

        amount = type(uint256).max;
    }

    /// @inheritdoc IPoolManager
    function maxUnwindDeposit(MarketId poolId, address owner) external view returns (uint256 collateralAssetAmountOut) {
        onlyInitialized(poolId);
        State storage state = data().states[poolId];

        // If Unwind Deposit is paused or the market is expired, return 0
        if (state.pool.isReturnPaused || PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        uint256 ownerSwapTokenBalance = IERC20(state.swapToken.principalToken).balanceOf(owner);
        uint256 ownerPrincipalTokenBalance = IERC20(state.swapToken._address).balanceOf(owner);

        // since you need an equal amount of  swap token and principal token to unwind, we use whatever the smallest owner have
        collateralAssetAmountOut = ownerSwapTokenBalance < ownerPrincipalTokenBalance ? ownerSwapTokenBalance : ownerPrincipalTokenBalance;

        // we normalize the decimal to the collateral asset decimals since both the swap and principal token operates has 18 decimals
        collateralAssetAmountOut = TransferHelper.fixedToTokenNativeDecimals(collateralAssetAmountOut, state.collateralDecimals);
    }

    /// @inheritdoc IPoolManager
    function maxUnwindMint(MarketId poolId, address owner) external view returns (uint256 cptAndCstSharesIn) {
        onlyInitialized(poolId);
        State storage state = data().states[poolId];

        // If Unwind Mint is paused or the market is expired, return 0
        if (state.pool.isReturnPaused || PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        uint256 ownerSwapTokenBalance = IERC20(state.swapToken.principalToken).balanceOf(owner);
        uint256 ownerPrincipalTokenBalance = IERC20(state.swapToken._address).balanceOf(owner);

        // since you need an equal amount of  swap token and principal token to unwind, we use whateever the smallest owner have
        cptAndCstSharesIn = ownerSwapTokenBalance < ownerPrincipalTokenBalance ? ownerSwapTokenBalance : ownerPrincipalTokenBalance;
    }

    /// @inheritdoc IPoolManager
    function maxWithdraw(MarketId poolId, address owner) external view override returns (uint256 assets) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If withdrawals are paused or the market is not expired yet, return 0
        if (state.pool.isWithdrawalPaused || !PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        // Get owner's CPT balance (shares)
        uint256 ownerShares = IERC20(state.swapToken.principalToken).balanceOf(owner);

        // If owner has no shares, return 0
        if (ownerShares == 0) return 0;

        // Get available collateral in the pool
        uint256 poolCollateralBalance = state.valueLocked(true);

        if (poolCollateralBalance == 0) return 0;

        // Return the minimum of owner's shares and available collateral
        // This ensures we don't return more than what can actually be withdrawn

        // we need to normalize the pool collateral balance when comparing otherwise it'll be skewed from the decimals.
        if (ownerShares < TransferHelper.tokenNativeDecimalsToFixed(poolCollateralBalance, state.collateralDecimals)) {
            (, uint256 maxCollateralOut) = state.previewRedeem(ownerShares);
            return maxCollateralOut;
        } else {
            return poolCollateralBalance;
        }
    }

    /// @inheritdoc IPoolManager
    function maxExercise(MarketId poolId, address owner) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Exercise is paused or the market is expired, return 0
        if (state.pool.isSwapPaused || PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        return state.maxExercise(owner);
    }

    /// @inheritdoc IPoolManager
    function maxUnwindExercise(MarketId poolId, address receiver) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);
        State storage state = data().states[poolId];

        // If Unwind Exercise is paused or the market is expired, return 0
        if (state.pool.isUnwindSwapPaused || PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        maxShares = state.maxUnwindExercise(receiver, getConstraintAdapter());
    }

    /// @inheritdoc IPoolManager
    function maxRedeem(MarketId poolId, address owner) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Redeem is paused, or the market is not expired yet, return 0
        if (state.pool.isWithdrawalPaused || !PoolShare(state.swapToken.principalToken).isExpired()) return 0;
        maxShares = IERC20(state.swapToken.principalToken).balanceOf(owner);
    }

    /// @inheritdoc IPoolManager
    function maxSwap(MarketId poolId, address owner) external view override returns (uint256 assets) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Swap is paused or the market is expired, return 0
        if (state.pool.isSwapPaused || PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        assets = state.maxSwap(owner, getConstraintAdapter());
    }

    /// @inheritdoc IUnwindSwap
    function maxUnwindSwap(MarketId poolId, address receiver) external view returns (uint256 amount) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Unwind Swap is paused or the market is expired, return 0
        if (state.pool.isUnwindSwapPaused || PoolShare(state.swapToken.principalToken).isExpired()) return 0;

        amount = state.maxUnwindSwap(receiver, getConstraintAdapter());
    }
}
