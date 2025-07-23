// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ModuleState} from "contracts/core/ModuleState.sol";
import {Shares} from "contracts/core/assets/Shares.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {IShares} from "contracts/interfaces/IShares.sol";
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
contract CorkPool is IPool, ModuleState, ContextUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using PoolLibrary for State;
    using MarketLibrary for Market;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer function for upgradeable contracts
    function initialize(address _swapSharesFactory, address _config) external initializer {
        if (_swapSharesFactory == address(0) || _config == address(0)) revert ZeroAddress();

        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
        initializeModuleState(_swapSharesFactory, _config);
    }

    /// @notice Authorization function for UUPS proxy upgrades
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @inheritdoc Initialize
    function getId(address referenceAsset, address collateralAsset, uint256 _expiry, address exchangeRateProvider) external pure returns (MarketId) {
        return MarketLibrary.initialize(referenceAsset, collateralAsset, _expiry, exchangeRateProvider).toId();
    }

    /// @inheritdoc Initialize
    function market(MarketId id) external view returns (Market memory _market) {
        _market = states[id].info;
    }

    /// @inheritdoc Initialize
    function marketDetails(MarketId id) external view returns (address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address exchangeRateProvider) {
        referenceAsset = states[id].info.referenceAsset;
        collateralAsset = states[id].info.collateralAsset;
        expiryTimestamp = states[id].info.expiryTimestamp;
        exchangeRateProvider = states[id].info.exchangeRateProvider;
    }

    /// @inheritdoc Initialize
    function createNewMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address exchangeRateProvider) external override nonReentrant {
        onlyConfig();

        if (expiryTimestamp == 0) revert InvalidExpiry();
        Market memory marketObj = MarketLibrary.initialize(referenceAsset, collateralAsset, expiryTimestamp, exchangeRateProvider);
        MarketId id = marketObj.toId();

        State storage state = states[id];

        if (state.isInitialized()) revert AlreadyInitialized();

        PoolLibrary.initialize(state, marketObj);

        uint256 exchangeRates = PoolLibrary._getLatestRate(state);

        (address principalToken, address swapToken) = ISharesFactory(SHARES_FACTORY).deploySwapShares(ISharesFactory.DeployParams(marketObj.collateralAsset, marketObj.referenceAsset, address(this), marketObj.expiryTimestamp, marketObj.exchangeRateProvider, exchangeRates));

        state.swapToken._address = swapToken;
        state.swapToken.principalToken = principalToken;

        emit MarketCreated(id, referenceAsset, collateralAsset, expiryTimestamp, exchangeRateProvider, principalToken, swapToken);
    }

    /// @inheritdoc Initialize
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external {
        onlyConfig();
        State storage state = states[id];
        PoolLibrary.updateUnwindSwapFeePercentage(state, newUnwindSwapFeePercentage);

        emit UnwindSwapFeeRateUpdated(id, newUnwindSwapFeePercentage);
    }

    /// @inheritdoc Initialize
    function underlyingAsset(MarketId id) external view override returns (address collateralAsset, address referenceAsset) {
        (collateralAsset, referenceAsset) = states[id].info.underlyingAsset();
    }

    /// @inheritdoc Initialize
    function shares(MarketId id) external view override returns (address principalToken, address swapToken) {
        principalToken = states[id].swapToken.principalToken;
        swapToken = states[id].swapToken._address;
    }

    /// @inheritdoc Initialize
    function updateBaseRedemptionFeePercentage(MarketId id, uint256 newBaseRedemptionFeePercentage) external {
        onlyConfig();
        State storage state = states[id];
        PoolLibrary.updateBaseRedemptionFeePercentage(state, newBaseRedemptionFeePercentage);
        emit BaseRedemptionFeePercentageUpdated(id, newBaseRedemptionFeePercentage);
    }

    /// @inheritdoc Initialize
    function expiry(MarketId id) external view override returns (uint256 _expiry) {
        _expiry = PoolLibrary.nextExpiry(states[id]);
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwapFee(MarketId id) external view override returns (uint256 fees) {
        State storage state = states[id];
        fees = state.unwindSwapFeePercentage();
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwap(MarketId id, uint256 amount, address receiver) external override nonReentrant returns (uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 exchangeRates) {
        corkPoolUnwindSwapNotPaused(id);

        State storage state = states[id];

        (receivedReferenceAsset, receivedSwapToken, feePercentage, fee, exchangeRates) = state.unwindSwap(_msgSender(), receiver, amount, getTreasuryAddress());

        // Emit deposit events - user deposits collateral (amount) and receives reference asset and swap tokens
        emit Deposit(id, _msgSender(), receiver, amount, receivedReferenceAsset + receivedSwapToken);
        // ERC4626-compatible event emitted by principal token
        IShares(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, amount, 0);
    }

    /// @inheritdoc IUnwindSwap
    function availableForUnwindSwap(MarketId id) external view override returns (uint256 referenceAsset, uint256 swapToken) {
        State storage state = states[id];
        (referenceAsset, swapToken) = state.availableForUnwindSwap();
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwapRates(MarketId id) external view returns (uint256 rates) {
        State storage state = states[id];
        rates = state.unwindSwapRates();
    }

    /// @inheritdoc IPool
    function deposit(MarketId id, uint256 amount, address receiver) external override nonReentrant returns (uint256 received) {
        onlyInitialized(id);
        corkPoolDepositAndMintNotPaused(id);

        State storage state = states[id];

        uint256 _exchangeRate;

        (received, _exchangeRate) = state.deposit(_msgSender(), receiver, amount);
        emit Deposit(id, _msgSender(), receiver, amount, received);
        // ERC4626-compatible event emitted by principal token
        IShares(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, amount, received);
    }

    /// @inheritdoc IPool
    function exercise(MarketId marketId, uint256 sharesAmount, uint256 compensation, address receiver, uint256 minAssetsOut, uint256 maxOtherAssetSpent) external override nonReentrant returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        onlyInitialized(marketId);
        corkPoolSwapNotPaused(marketId);

        State storage state = states[marketId];

        (assets, otherAssetSpent, fee) = state.exercise(_msgSender(), _msgSender(), receiver, sharesAmount, compensation, minAssetsOut, maxOtherAssetSpent, getTreasuryAddress());

        // Nothing is burned in exercise - we're transferring tokens to the pool, so shares burned = 0
        emit WithdrawExtended(marketId, _msgSender(), _msgSender(), assets, 0, 0, 0);
        // ERC4626-compatible event emitted by principal token
        IShares(states[marketId].swapToken.principalToken).emitWithdraw(_msgSender(), receiver, _msgSender(), assets, 0);
    }

    /// @inheritdoc IPool
    function exchangeRate(MarketId id) external view override returns (uint256 rates) {
        State storage state = states[id];
        rates = state.exchangeRate();
    }

    /// @inheritdoc IPool
    function redeem(MarketId id, uint256 amount, address owner, address receiver) external override nonReentrant returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        onlyInitialized(id);
        corkPoolWithdrawalNotPaused(id);

        State storage state = states[id];

        (accruedReferenceAsset, accruedCollateralAsset) = state.redeem(_msgSender(), owner, receiver, amount);

        // we emit standard ERC-4626 withdraw event and the complete extended event
        emit WithdrawExtended(id, _msgSender(), owner, accruedCollateralAsset, accruedReferenceAsset, amount, 0);
        // ERC4626-compatible event emitted by principal token
        IShares(state.swapToken.principalToken).emitWithdraw(_msgSender(), receiver, owner, accruedCollateralAsset, amount);
    }

    /// @inheritdoc IPool
    function valueLocked(MarketId id, bool collateralAsset) external view override returns (uint256 lockedAmount) {
        State storage state = states[id];
        lockedAmount = state.valueLocked(collateralAsset);
    }

    /// @inheritdoc IPool
    function unwindMint(MarketId id, uint256 cptAndCstAmountIn) external override nonReentrant returns (uint256 collateralAsset) {
        corkPoolUnwindDepositAndMintNotPaused(id);

        State storage state = states[id];

        collateralAsset = state.unwindMint(_msgSender(), cptAndCstAmountIn);

        // Emit both events as required by the spec - both CPT and CST are burned equally
        emit WithdrawExtended(id, _msgSender(), _msgSender(), collateralAsset, 0, cptAndCstAmountIn, cptAndCstAmountIn);
        // ERC4626-compatible event emitted by principal token
        IShares(state.swapToken.principalToken).emitWithdraw(_msgSender(), _msgSender(), _msgSender(), collateralAsset, cptAndCstAmountIn);
    }

    /// @inheritdoc IPool
    function swap(MarketId marketId, uint256 assets, address receiver) external override nonReentrant returns (uint256 sharesOut, uint256 compensation) {
        onlyInitialized(marketId);
        corkPoolSwapNotPaused(marketId);

        State storage state = states[marketId];

        (sharesOut, compensation) = state.swap(_msgSender(), _msgSender(), receiver, assets);

        // Emit both events as required by the spec
        emit WithdrawExtended(marketId, _msgSender(), _msgSender(), assets, 0, 0, 0);
        // ERC4626-compatible event emitted by principal token
        IShares(states[marketId].swapToken.principalToken).emitWithdraw(_msgSender(), receiver, _msgSender(), assets, 0);
    }

    /// @inheritdoc IPool
    function withdraw(MarketId id, uint256 collateralAssetOut, uint256 referenceAssetOut, address owner, address receiver) external override nonReentrant returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        onlyInitialized(id);
        corkPoolWithdrawalNotPaused(id);

        State storage state = states[id];

        (sharesIn, actualReferenceAssetOut) = state.withdraw(_msgSender(), owner, receiver, collateralAssetOut, referenceAssetOut);

        // we emit standard ERC-4626 withdraw event and the complete extended event
        emit WithdrawExtended(id, _msgSender(), owner, collateralAssetOut, actualReferenceAssetOut, sharesIn, 0);
        // ERC4626-compatible event emitted by principal token
        IShares(states[id].swapToken.principalToken).emitWithdraw(_msgSender(), receiver, owner, collateralAssetOut, sharesIn);
    }

    /// @inheritdoc IPool
    function mint(MarketId id, uint256 swapAndPricipalTokenAmountOut, address receiver) external nonReentrant returns (uint256 collateralAmountIn, uint256 _exchangeRate) {
        onlyInitialized(id);
        corkPoolDepositAndMintNotPaused(id);

        State storage state = states[id];

        // since the the cpt and cst is 18 decimals, that meanns the out amount is also 18 decimals
        collateralAmountIn = TransferHelper.fixedToTokenNativeDecimals(swapAndPricipalTokenAmountOut, state.info.collateralAsset);
        uint256 actualOut;

        (actualOut, _exchangeRate) = state.deposit(_msgSender(), receiver, collateralAmountIn);

        assert(actualOut == swapAndPricipalTokenAmountOut);

        emit Deposit(id, _msgSender(), receiver, collateralAmountIn, swapAndPricipalTokenAmountOut);
        // ERC4626-compatible event emitted by principal token
        IShares(state.swapToken.principalToken).emitDeposit(_msgSender(), receiver, collateralAmountIn, swapAndPricipalTokenAmountOut);
    }

    /// @inheritdoc IPool
    function unwindDeposit(MarketId id, uint256 collateralAmtOut) external nonReentrant returns (uint256 swapTokenAndPrincipalTokenIn) {
        onlyInitialized(id);
        corkPoolUnwindDepositAndMintNotPaused(id);

        State storage state = states[id];

        swapTokenAndPrincipalTokenIn = TransferHelper.tokenNativeDecimalsToFixed(collateralAmtOut, state.info.collateralAsset);

        uint256 actualCollateralAssetOut = state.unwindMint(_msgSender(), swapTokenAndPrincipalTokenIn);
        assert(collateralAmtOut == actualCollateralAssetOut);

        // Emit both events as required by the spec - both CPT and CST are burned equally
        emit WithdrawExtended(id, _msgSender(), _msgSender(), collateralAmtOut, 0, swapTokenAndPrincipalTokenIn, swapTokenAndPrincipalTokenIn);
        // ERC4626-compatible event emitted by principal token
        IShares(states[id].swapToken.principalToken).emitWithdraw(_msgSender(), _msgSender(), _msgSender(), collateralAmtOut, swapTokenAndPrincipalTokenIn);
    }

    /// @inheritdoc IPool
    function unwindExercise(MarketId poolId, uint256 sharesAmount, address receiver, uint256 minCompensationOut, uint256 maxAssetIn) external override nonReentrant returns (uint256 assetIn, uint256 compensationOut) {
        onlyInitialized(poolId);
        corkPoolDepositAndMintNotPaused(poolId);

        State storage state = states[poolId];

        (assetIn, compensationOut) = state.unwindExercise(_msgSender(), receiver, sharesAmount, minCompensationOut, maxAssetIn);

        emit Deposit(poolId, _msgSender(), receiver, assetIn, sharesAmount);
        // ERC4626-compatible event emitted by principal token
        IShares(states[poolId].swapToken.principalToken).emitDeposit(_msgSender(), receiver, assetIn, sharesAmount);
    }

    /// @inheritdoc IPool
    function baseRedemptionFee(MarketId id) external view override returns (uint256 fees) {
        fees = states[id].pool.baseRedemptionFeePercentage;
    }

    /// @inheritdoc IPool
    function pausedStates(MarketId marketId) external view returns (bool depositPaused, bool unwindSwapPaused, bool swapPaused, bool withdrawalPaused, bool unwindDepositAndMintPaused) {
        PoolState storage poolState = states[marketId].pool;
        return (poolState.isDepositPaused, poolState.isUnwindSwapPaused, poolState.isSwapPaused, poolState.isWithdrawalPaused, poolState.isReturnPaused);
    }

    /// @inheritdoc IPool
    function setPausedState(MarketId marketId, IPool.OperationType operationType, bool isPaused) external {
        onlyConfig();
        State storage state = states[marketId];

        if (operationType == OperationType.DEPOSIT) {
            if (state.pool.isDepositPaused == isPaused) revert SameStatus();
            state.pool.isDepositPaused = isPaused;

            if (isPaused) emit DepositPaused(marketId);
            else emit DepositUnpaused(marketId);
        } else if (operationType == OperationType.UNWIND_SWAP) {
            if (state.pool.isUnwindSwapPaused == isPaused) revert SameStatus();
            state.pool.isUnwindSwapPaused = isPaused;

            if (isPaused) emit UnwindSwapPaused(marketId);
            else emit UnwindSwapUnpaused(marketId);
        } else if (operationType == OperationType.SWAP) {
            if (state.pool.isSwapPaused == isPaused) revert SameStatus();
            state.pool.isSwapPaused = isPaused;

            if (isPaused) emit SwapPaused(marketId);
            else emit SwapUnpaused(marketId);
        } else if (operationType == OperationType.WITHDRAWAL) {
            if (state.pool.isWithdrawalPaused == isPaused) revert SameStatus();
            state.pool.isWithdrawalPaused = isPaused;

            if (isPaused) emit WithdrawalPaused(marketId);
            else emit WithdrawalUnpaused(marketId);
        } else if (operationType == OperationType.PREMATURE_WITHDRAWAL) {
            if (state.pool.isReturnPaused == isPaused) revert SameStatus();
            state.pool.isReturnPaused = isPaused;

            if (isPaused) emit ReturnPaused(marketId);
            else emit ReturnUnpaused(marketId);
        }
    }

    // ---------------------------------------------------------------------//
    // -------------------------- Preview Functions ------------------------//
    //----------------------------------------------------------------------//

    /// @inheritdoc IPool
    function previewDeposit(MarketId id, uint256 amount) external view returns (uint256 received) {
        onlyInitialized(id);

        // 1:1 rate
        received = TransferHelper.tokenNativeDecimalsToFixed(amount, states[id].info.collateralAsset);
    }

    /// @inheritdoc IPool
    function previewSwap(MarketId id, uint256 amount) external view returns (uint256 received, uint256 _exchangeRate, uint256 fee, uint256 cstUsed) {
        onlyInitialized(id);
        (received, cstUsed, fee, _exchangeRate) = states[id].previewSwap(amount);
    }

    /// @inheritdoc IPool
    function previewRedeem(MarketId id, uint256 amount) external view override returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        onlyInitialized(id);
        (accruedReferenceAsset, accruedCollateralAsset) = states[id].previewRedeem(amount);
    }

    /// @inheritdoc IPool
    function previewWithdraw(MarketId id, uint256 collateralAssetOut, uint256 referenceAssetOut) external view override returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        onlyInitialized(id);
        (sharesIn, actualReferenceAssetOut) = states[id].previewWithdraw(collateralAssetOut, referenceAssetOut);
    }

    /// @inheritdoc IPool
    function previewUnwindDeposit(MarketId id, uint256 collateralAssetAmountOut) external view returns (uint256 swapTokenAndPrincipalTokenIn) {
        onlyInitialized(id);

        // 1:1 rate
        swapTokenAndPrincipalTokenIn = TransferHelper.tokenNativeDecimalsToFixed(collateralAssetAmountOut, states[id].info.collateralAsset);
    }

    /// @inheritdoc IPool
    function previewUnwindSwap(MarketId id, uint256 amount) external view returns (uint256 receivedRef, uint256 receivedCst, uint256 feePercentage, uint256 fee, uint256 exchangeRates) {
        onlyInitialized(id);
        (receivedRef, receivedCst, feePercentage, fee, exchangeRates,) = states[id].previewUnwindSwap(amount);
    }

    /// @inheritdoc IPool
    function previewMint(MarketId id, uint256 swapAndPricipalTokenAmountOut) external view returns (uint256 collateralAmountIn, uint256 _exchangeRate) {
        onlyInitialized(id);

        _exchangeRate = states[id]._getLatestApplicableRate();

        // 1:1 rate
        collateralAmountIn = TransferHelper.fixedToTokenNativeDecimals(swapAndPricipalTokenAmountOut, states[id].info.collateralAsset);
    }

    /// @inheritdoc IPool
    function previewUnwindMint(MarketId id, uint256 cptAndCstAmountIn) external view returns (uint256 collateralAsset) {
        onlyInitialized(id);

        // 1:1 rate
        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(cptAndCstAmountIn, states[id].info.collateralAsset);
    }

    /// @inheritdoc IPool
    function previewUnwindExercise(MarketId poolId, uint256 sharesAmount) external view override returns (uint256 assetIn, uint256 compensationOut) {
        onlyInitialized(poolId);
        State storage state = states[poolId];
        (assetIn, compensationOut) = state.previewUnwindExercise(sharesAmount);
    }

    /// @inheritdoc IPool
    function previewExercise(MarketId marketId, uint256 sharesAmount, uint256 compensation) external view override returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        onlyInitialized(marketId);
        (assets, otherAssetSpent, fee) = states[marketId].previewExercise(sharesAmount, compensation);
    }

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be minted
     * @return amount The maximum amount (unlimited)
     */
    function maxMint(MarketId, address) external pure returns (uint256 amount) {
        amount = type(uint256).max;
    }

    /// @inheritdoc IPool
    function maxDeposit(MarketId, address) external pure returns (uint256 amount) {
        amount = type(uint256).max;
    }

    /// @inheritdoc IPool
    function maxUnwindDeposit(MarketId id, address owner) external view returns (uint256 collateralAssetAmountOut) {
        State storage state = states[id];

        uint256 ownerSwapTokenBalance = IERC20(state.swapToken.principalToken).balanceOf(owner);
        uint256 ownerPrincipalTokenBalance = IERC20(state.swapToken._address).balanceOf(owner);

        // since you need an equal amount of  swap token and principal token to unwind, we use whateever the smallest owner have
        collateralAssetAmountOut = ownerSwapTokenBalance < ownerPrincipalTokenBalance ? ownerSwapTokenBalance : ownerPrincipalTokenBalance;

        // we normalize the decimal to the collateral asset decimals since both the swap and principal token operates has 18 decimals
        collateralAssetAmountOut = TransferHelper.fixedToTokenNativeDecimals(collateralAssetAmountOut, state.info.collateralAsset);
    }

    /// @inheritdoc IPool
    function maxUnwindMint(MarketId id, address owner) external view returns (uint256 swapTokenAndPrincipalTokenIn) {
        State storage state = states[id];

        uint256 ownerSwapTokenBalance = IERC20(state.swapToken.principalToken).balanceOf(owner);
        uint256 ownerPrincipalTokenBalance = IERC20(state.swapToken._address).balanceOf(owner);

        // since you need an equal amount of  swap token and principal token to unwind, we use whateever the smallest owner have
        swapTokenAndPrincipalTokenIn = ownerSwapTokenBalance < ownerPrincipalTokenBalance ? ownerSwapTokenBalance : ownerPrincipalTokenBalance;
    }

    /// @inheritdoc IPool
    function maxWithdraw(MarketId marketId, address owner) external view override returns (uint256 assets) {
        State storage state = states[marketId];

        // If withdrawals are paused, return 0
        if (state.pool.isWithdrawalPaused) return 0;

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
        if (ownerShares < TransferHelper.tokenNativeDecimalsToFixed(poolCollateralBalance, state.info.collateralAsset)) {
            (, uint256 maxCollateralOut) = state.previewRedeem(ownerShares);
            return maxCollateralOut;
        } else {
            return poolCollateralBalance;
        }
    }

    /// @inheritdoc IPool
    function maxExercise(MarketId marketId, address owner) external view override returns (uint256 maxShares) {
        State storage state = states[marketId];
        // If swaps are paused, return 0
        if (state.pool.isSwapPaused) return 0;
        return state.maxExercise(owner);
    }

    /// @inheritdoc IPool
    function maxUnwindExercise(MarketId poolId, address receiver) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);
        State storage state = states[poolId];
        maxShares = state.maxUnwindExercise(receiver);
    }

    /// @inheritdoc IPool
    function maxRedeem(MarketId marketId, address owner) external view override returns (uint256 maxShares) {
        State storage state = states[marketId];

        if (!state.isInitialized() || state.pool.isWithdrawalPaused || !Shares(state.swapToken.principalToken).isExpired()) return 0;
        maxShares = IERC20(state.swapToken.principalToken).balanceOf(owner);
    }

    /// @inheritdoc IPool
    function maxSwap(MarketId marketId, address owner) external view override returns (uint256 assets) {
        State storage state = states[marketId];

        assets = state.maxSwap(owner);
    }

    /// @inheritdoc IUnwindSwap
    function maxUnwindSwap(MarketId id, address receiver) external view returns (uint256 amount) {
        State storage state = states[id];
        amount = state.maxUnwindSwap(receiver);
    }
}
