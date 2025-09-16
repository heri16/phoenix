// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ConstraintAdapter} from "./ConstraintAdapter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ModuleState} from "contracts/core/ModuleState.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {Guard} from "contracts/libraries/Guard.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {PoolLibrary} from "contracts/libraries/PoolLib.sol";
import {CorkPoolPoolArchive, PoolState, State} from "contracts/libraries/State.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title CorkPool Abstract Contract
 * @author Cork Team
 * @notice Abstract CorkPool contract provides Cork Pool related logics
 */
contract CorkPool is IPoolManager, ModuleState, ContextUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using PoolLibrary for State;
    using SafeERC20 for IERC20;

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

    function _unlockTo(State storage state, address to, uint256 amount) internal {
        // If amount is greater than locked amount, revert
        require(amount <= state.pool.balances.collateralAsset.locked, InvalidAmount());

        // Decrease locked amount
        state.pool.balances.collateralAsset.locked -= amount;

        // Transfer asset to receiver
        IERC20(state.info.collateralAsset).safeTransfer(to, amount);
    }

    /// @inheritdoc Initialize
    function getId(Market calldata market) external view returns (MarketId) {
        require(market.referenceAsset != address(0) && market.collateralAsset != address(0), ZeroAddress());
        require(market.referenceAsset != market.collateralAsset, InvalidAddress());
        require(market.expiryTimestamp != 0, InvalidExpiry());
        require(market.rateOracle != address(0), ZeroAddress());
        return MarketId.wrap(keccak256(abi.encode(market)));
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
    function createNewPool(Market calldata poolParams) external override nonReentrant {
        onlyConfig();

        require(poolParams.expiryTimestamp > block.timestamp, InvalidExpiry());
        require(poolParams.referenceAsset != address(0) && poolParams.collateralAsset != address(0), ZeroAddress());
        require(poolParams.referenceAsset != poolParams.collateralAsset, InvalidAddress());
        require(poolParams.rateOracle != address(0), ZeroAddress());

        MarketId poolId = MarketId.wrap(keccak256(abi.encode(poolParams)));

        State storage state = data().states[poolId];

        require(!state.isInitialized(), AlreadyInitialized());

        PoolLibrary.initialize(state, poolId, poolParams, data().CONSTRAINT_ADAPTER);

        uint256 _swapRate = ConstraintAdapter(data().CONSTRAINT_ADAPTER).adjustedRate(poolId);

        (address principalToken, address swapToken) = ISharesFactory(data().SHARES_FACTORY).deployPoolShares(ISharesFactory.DeployParams({owner: address(this), poolParams: poolParams, poolId: poolId}));

        state.shares.swap = swapToken;
        state.shares.principal = principalToken;
        state.referenceDecimals = IERC20Metadata(poolParams.referenceAsset).decimals();
        state.collateralDecimals = IERC20Metadata(poolParams.collateralAsset).decimals();

        emit MarketCreated(poolId, poolParams.referenceAsset, poolParams.collateralAsset, poolParams.expiryTimestamp, poolParams.rateOracle, principalToken, swapToken);
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
        State memory state = data().states[poolId];
        referenceAsset = state.info.referenceAsset;
        collateralAsset = state.info.collateralAsset;
    }

    /// @inheritdoc Initialize
    function shares(MarketId poolId) external view override returns (address principalToken, address swapToken) {
        State memory state = data().states[poolId];
        principalToken = state.shares.principal;
        swapToken = state.shares.swap;
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
    function unwindSwap(MarketId poolId, uint256 amount, address receiver) external override nonReentrant returns (IUnwindSwap.UnwindSwapReturnParams memory returnParams) {
        onlyInitialized(poolId);
        corkPoolUnwindSwapAndExerciseNotPaused(poolId);

        require(amount != 0, InvalidAmount());
        Guard.safeBeforeExpired(data().states[poolId].shares);

        State storage state = data().states[poolId];

        returnParams = state.previewUnwindSwap(poolId, amount, getConstraintAdapter());

        // actually update the rate, since preview only get the latest rate without updating.
        // the adjusted rate should be idempotent and is fine to call many times
        state._getLatestApplicableRateAndUpdate(poolId, getConstraintAdapter());

        // decrease Cork Pool balance
        // we also include the fee here to separate the accumulated fee from the unwindSwap
        state.pool.balances.referenceAssetBalance -= (returnParams.receivedReferenceAsset);
        state.pool.balances.swapTokenBalance -= (returnParams.receivedSwapToken);
        state.pool.balances.collateralAsset.locked += amount;

        // transfer the fee(if any) to treasury, since the fee is used to provide liquidity
        IERC20(state.info.collateralAsset).safeTransferFrom(_msgSender(), address(this), amount);

        if (returnParams.fee != 0) _unlockTo(state, getTreasuryAddress(), returnParams.fee);

        // transfer user attrubuted Swap Token + Reference Asset
        // Reference Asset
        IERC20(state.info.referenceAsset).safeTransfer(receiver, returnParams.receivedReferenceAsset);

        // Swap Token
        IERC20(state.shares.swap).safeTransfer(receiver, returnParams.receivedSwapToken);

        emit PoolSwap(poolId, _msgSender(), receiver, amount, returnParams.receivedReferenceAsset, 0, 0, true);
        emit PoolFee(poolId, _msgSender(), returnParams.fee, 0);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitDeposit(_msgSender(), receiver, amount, 0);
        IPoolShare(state.shares.principal).emitWithdrawOther(_msgSender(), receiver, _msgSender(), address(state.info.referenceAsset), returnParams.receivedReferenceAsset, 0);
    }

    /// @inheritdoc IUnwindSwap
    function availableForUnwindSwap(MarketId poolId) external view override returns (uint256 referenceAsset, uint256 swapToken) {
        (referenceAsset, swapToken) = data().states[poolId].availableForUnwindSwap();
    }

    /// @inheritdoc IUnwindSwap
    function unwindSwapRate(MarketId poolId) external view returns (uint256 rate) {
        rate = data().states[poolId].unwindSwapRate(poolId, data().CONSTRAINT_ADAPTER);
    }

    /// @inheritdoc IPoolManager
    function deposit(MarketId poolId, uint256 amount, address receiver) external override nonReentrant returns (uint256 received) {
        onlyInitialized(poolId);
        corkPoolDepositAndMintNotPaused(poolId);

        require(amount != 0, ZeroDeposit());

        Guard.safeBeforeExpired(data().states[poolId].shares);

        State storage state = data().states[poolId];

        // we convert it 18 fixed decimals, since that's what the Swap Token uses
        received = TransferHelper.tokenNativeDecimalsToFixed(amount, state.collateralDecimals);

        state.pool.balances.collateralAsset.locked += amount;

        IERC20(state.info.collateralAsset).safeTransferFrom(_msgSender(), address(this), amount);

        PoolShare(state.shares.principal).mint(receiver, received);
        PoolShare(state.shares.swap).mint(receiver, received);

        emit PoolModifyLiquidity(poolId, _msgSender(), receiver, amount, 0, false);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitDeposit(_msgSender(), receiver, amount, received);
    }

    /// @inheritdoc IPoolManager
    function exercise(ExerciseParams memory params) external override nonReentrant returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        onlyInitialized(params.poolId);
        corkPoolSwapNotPaused(params.poolId);

        // Either shares or compensation MUST be 0
        if ((params.shares == 0 && params.compensation == 0) || (params.shares != 0 && params.compensation != 0)) revert InvalidParams();

        State storage state = data().states[params.poolId];

        Guard.safeBeforeExpired(state.shares);

        uint256 swapTokenProvided;
        uint256 referenceAssetProvided;
        (assets, otherAssetSpent, fee, swapTokenProvided, referenceAssetProvided) = state.previewExercise(params.poolId, params.shares, params.compensation, getConstraintAdapter());

        params.compensation = params.compensation > 0 ? params.compensation : otherAssetSpent;
        params.shares = params.shares > 0 ? params.shares : otherAssetSpent;

        // Update swap rate since preview doesn't update the rate
        state._getLatestApplicableRateAndUpdate(params.poolId, getConstraintAdapter());

        // Validate slippage protection
        require(assets >= params.minAssetsOut, SlippageExceeded());
        require(otherAssetSpent <= params.maxOtherAssetSpent, SlippageExceeded());
        require(assets <= state.pool.balances.collateralAsset.locked, InsufficientLiquidity(state.pool.balances.collateralAsset.locked, assets));

        state.pool.balances.swapTokenBalance += params.shares;
        state.pool.balances.referenceAssetBalance += params.compensation;

        PoolShare(state.shares.swap).transferFrom(_msgSender(), _msgSender(), address(this), swapTokenProvided);
        IERC20(state.info.referenceAsset).safeTransferFrom(_msgSender(), address(this), referenceAssetProvided);

        _unlockTo(state, params.receiver, assets);
        if (fee != 0) _unlockTo(state, getTreasuryAddress(), fee);

        emit PoolSwap(params.poolId, _msgSender(), _msgSender(), assets, params.compensation, 0, 0, false);
        emit PoolFee(params.poolId, _msgSender(), fee, 0);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitWithdraw(_msgSender(), params.receiver, _msgSender(), assets, 0);
        IPoolShare(state.shares.principal).emitDepositOther(_msgSender(), params.receiver, address(state.info.referenceAsset), params.compensation, 0);
    }

    /// @inheritdoc IPoolManager
    function swapRate(MarketId poolId) external view override returns (uint256 rate) {
        rate = data().states[poolId].swapRate(poolId, data().CONSTRAINT_ADAPTER);
    }

    /// @inheritdoc IPoolManager
    function redeem(MarketId poolId, uint256 amount, address owner, address receiver) external override nonReentrant returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        onlyInitialized(poolId);
        corkPoolWithdrawalNotPaused(poolId);

        State storage state = data().states[poolId];

        require(amount != 0, InvalidAmount());
        Guard.safeAfterExpired(state.shares);

        // Calculate minimum shares to avoid rounding issues for low decimal tokens
        uint256 minimumShares = calculateMinimumSharesForAssets(state.collateralDecimals, state.referenceDecimals);

        // Ensure the input amount is at least the minimum required
        if (amount < minimumShares) revert InsufficientSharesAmount(minimumShares, amount);

        if (!state.pool.liquiditySeparated) {
            state.pool.liquiditySeparated = true;

            state.pool.poolArchive.collateralAssetAccrued = state.pool.balances.collateralAsset.locked;
            state.pool.poolArchive.referenceAssetAccrued = state.pool.balances.referenceAssetBalance;

            // reset current balances
            state.pool.balances.collateralAsset.locked = 0;
            state.pool.balances.referenceAssetBalance = 0;
        }

        CorkPoolPoolArchive storage archive = state.pool.poolArchive;

        (accruedReferenceAsset, accruedCollateralAsset) = state._calcSwapAmount(amount, IERC20(state.shares.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        state.shares.withdrawn += amount;
        state.pool.poolArchive.referenceAssetAccrued -= accruedReferenceAsset;
        state.pool.poolArchive.collateralAssetAccrued -= accruedCollateralAsset;

        PoolShare(state.shares.principal).burnFrom(_msgSender(), owner, amount);
        IERC20(state.info.referenceAsset).safeTransfer(receiver, accruedReferenceAsset);
        IERC20(state.info.collateralAsset).safeTransfer(receiver, accruedCollateralAsset);

        emit PoolModifyLiquidity(poolId, _msgSender(), owner, accruedCollateralAsset, accruedReferenceAsset, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitWithdraw(_msgSender(), receiver, owner, accruedCollateralAsset, amount);
        IPoolShare(state.shares.principal).emitWithdrawOther(_msgSender(), receiver, owner, address(state.info.referenceAsset), accruedReferenceAsset, amount);
    }

    /// @inheritdoc IPoolManager
    function valueLocked(MarketId poolId) external view override returns (uint256 collateralAssets, uint256 referenceAssets) {
        State storage state = data().states[poolId];

        collateralAssets = state.pool.balances.collateralAsset.locked;
        referenceAssets = state.pool.balances.referenceAssetBalance;
    }

    /// @inheritdoc IPoolManager
    function unwindMint(MarketId poolId, uint256 cptAndCstSharesIn, address owner, address receiver) external override nonReentrant returns (uint256 collateralAsset) {
        onlyInitialized(poolId);
        corkPoolUnwindDepositAndMintNotPaused(poolId);

        require(cptAndCstSharesIn != 0, InvalidAmount());

        Guard.safeBeforeExpired(data().states[poolId].shares);

        // Calculate the minimum shares required to get at least 1 unit of collateral asset
        uint256 minimumShares = calculateMinimumShares(data().states[poolId].collateralDecimals);

        // Ensure the input amount is at least the minimum required
        if (cptAndCstSharesIn < minimumShares && cptAndCstSharesIn > 0) revert InsufficientSharesAmount(minimumShares, cptAndCstSharesIn);

        State storage state = data().states[poolId];

        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(cptAndCstSharesIn, state.collateralDecimals);

        _unlockTo(state, receiver, collateralAsset);

        PoolShare(state.shares.principal).burnFrom(_msgSender(), owner, cptAndCstSharesIn);
        PoolShare(state.shares.swap).burnFrom(_msgSender(), owner, cptAndCstSharesIn);

        // Emit both events as required by the spec - both CPT and CST are burned equally
        emit PoolModifyLiquidity(poolId, _msgSender(), owner, collateralAsset, 0, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitWithdraw(_msgSender(), receiver, owner, collateralAsset, cptAndCstSharesIn);
    }

    /// @inheritdoc IPoolManager
    function swap(MarketId poolId, uint256 assets, address receiver) external override nonReentrant returns (uint256 shares, uint256 compensation, uint256 fee) {
        onlyInitialized(poolId);
        corkPoolSwapNotPaused(poolId);

        require(assets != 0, InvalidAmount());

        State storage state = data().states[poolId];

        Guard.safeBeforeExpired(state.shares);

        (shares, compensation, fee) = state.previewSwap(poolId, assets, getConstraintAdapter());

        require(assets <= state.pool.balances.collateralAsset.locked, InsufficientLiquidity(state.pool.balances.collateralAsset.locked, assets));

        // Update exchange rate because preview doesn't actually update the rate
        state._getLatestApplicableRateAndUpdate(poolId, getConstraintAdapter());

        state.pool.balances.swapTokenBalance += shares;
        state.pool.balances.referenceAssetBalance += compensation;

        PoolShare(state.shares.swap).transferFrom(_msgSender(), _msgSender(), address(this), shares);
        IERC20(state.info.referenceAsset).safeTransferFrom(_msgSender(), address(this), compensation);

        _unlockTo(state, receiver, assets);
        if (fee != 0) _unlockTo(state, getTreasuryAddress(), fee);

        emit PoolSwap(poolId, _msgSender(), _msgSender(), assets, compensation, 0, 0, false);
        emit PoolFee(poolId, _msgSender(), fee, 0);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitWithdraw(_msgSender(), receiver, _msgSender(), assets, 0);
        IPoolShare(state.shares.principal).emitDepositOther(_msgSender(), receiver, address(state.info.referenceAsset), compensation, 0);
    }

    /// @inheritdoc IPoolManager
    function withdraw(WithdrawParams calldata params) external override nonReentrant returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) {
        onlyInitialized(params.poolId);
        corkPoolWithdrawalNotPaused(params.poolId);

        // Either collateralAssetOut or referenceAssetOut must be zero, but not both
        if ((params.collateralAssetOut == 0 && params.referenceAssetOut == 0) || (params.collateralAssetOut != 0 && params.referenceAssetOut != 0)) revert InvalidParams();

        State storage state = data().states[params.poolId];

        Guard.safeAfterExpired(state.shares);

        if (!state.pool.liquiditySeparated) {
            state.pool.liquiditySeparated = true;

            state.pool.poolArchive.collateralAssetAccrued = state.pool.balances.collateralAsset.locked;
            state.pool.poolArchive.referenceAssetAccrued = state.pool.balances.referenceAssetBalance;

            // reset current balances
            state.pool.balances.collateralAsset.locked = 0;
            state.pool.balances.referenceAssetBalance = 0;
        }

        // Calculate required shares
        CorkPoolPoolArchive storage archive = state.pool.poolArchive;

        require(params.collateralAssetOut <= archive.collateralAssetAccrued, InsufficientLiquidity(archive.collateralAssetAccrued, params.collateralAssetOut));
        require(params.referenceAssetOut <= archive.referenceAssetAccrued, InsufficientLiquidity(archive.referenceAssetAccrued, params.referenceAssetOut));

        sharesIn = state._calcWithdrawAmount(params.collateralAssetOut, params.referenceAssetOut, IERC20(state.shares.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        // Calculate minimum shares to avoid rounding issues for low decimal tokens
        uint256 minimumShares = calculateMinimumSharesForAssets(state.collateralDecimals, state.referenceDecimals);

        // Ensure the input amount is at least the minimum required
        if (sharesIn < minimumShares) revert InsufficientSharesAmount(minimumShares, sharesIn);

        (actualReferenceAssetOut, actualCollateralAssetOut) = state._calcSwapAmount(sharesIn, IERC20(state.shares.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        state.shares.withdrawn += sharesIn;
        state.pool.poolArchive.referenceAssetAccrued -= actualReferenceAssetOut;
        state.pool.poolArchive.collateralAssetAccrued -= actualCollateralAssetOut;

        PoolShare(state.shares.principal).burnFrom(_msgSender(), params.owner, sharesIn);
        IERC20(state.info.referenceAsset).safeTransfer(params.receiver, actualReferenceAssetOut);
        IERC20(state.info.collateralAsset).safeTransfer(params.receiver, actualCollateralAssetOut);

        emit PoolModifyLiquidity(params.poolId, _msgSender(), params.owner, actualCollateralAssetOut, actualReferenceAssetOut, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitWithdraw(_msgSender(), params.receiver, params.owner, actualCollateralAssetOut, sharesIn);
        IPoolShare(state.shares.principal).emitWithdrawOther(_msgSender(), params.receiver, params.owner, address(state.info.referenceAsset), actualReferenceAssetOut, sharesIn);
    }

    /// @inheritdoc IPoolManager
    function mint(MarketId poolId, uint256 swapAndPricipalTokenAmountOut, address receiver) external nonReentrant returns (uint256 collateralAmountIn) {
        onlyInitialized(poolId);
        corkPoolDepositAndMintNotPaused(poolId);

        require(swapAndPricipalTokenAmountOut != 0, ZeroDeposit());

        Guard.safeBeforeExpired(data().states[poolId].shares);

        State storage state = data().states[poolId];

        // since the the cpt and cst is 18 decimals, that meanns the out amount is also 18 decimals
        collateralAmountIn = TransferHelper.fixedToTokenNativeDecimals(swapAndPricipalTokenAmountOut, state.collateralDecimals);

        state.pool.balances.collateralAsset.locked += collateralAmountIn;

        IERC20(state.info.collateralAsset).safeTransferFrom(_msgSender(), address(this), collateralAmountIn);

        PoolShare(state.shares.principal).mint(receiver, swapAndPricipalTokenAmountOut);
        PoolShare(state.shares.swap).mint(receiver, swapAndPricipalTokenAmountOut);

        emit PoolModifyLiquidity(poolId, _msgSender(), receiver, collateralAmountIn, 0, false);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitDeposit(_msgSender(), receiver, collateralAmountIn, swapAndPricipalTokenAmountOut);
    }

    /// @inheritdoc IPoolManager
    function unwindDeposit(MarketId poolId, uint256 collateralAmtOut, address owner, address receiver) external nonReentrant returns (uint256 cptAndCstSharesIn) {
        onlyInitialized(poolId);
        corkPoolUnwindDepositAndMintNotPaused(poolId);

        State storage state = data().states[poolId];

        cptAndCstSharesIn = TransferHelper.tokenNativeDecimalsToFixed(collateralAmtOut, state.collateralDecimals);

        require(cptAndCstSharesIn != 0, InvalidAmount());

        Guard.safeBeforeExpired(state.shares);

        // Calculate the minimum shares required to get at least 1 unit of collateral asset
        uint256 minimumShares = calculateMinimumShares(state.collateralDecimals);

        // Ensure the input amount is at least the minimum required
        if (cptAndCstSharesIn < minimumShares && cptAndCstSharesIn > 0) revert InsufficientSharesAmount(minimumShares, cptAndCstSharesIn);

        uint256 collateralAsset = TransferHelper.fixedToTokenNativeDecimals(cptAndCstSharesIn, state.collateralDecimals);

        _unlockTo(state, receiver, collateralAsset);

        PoolShare(state.shares.principal).burnFrom(_msgSender(), owner, cptAndCstSharesIn);
        PoolShare(state.shares.swap).burnFrom(_msgSender(), owner, cptAndCstSharesIn);

        // Emit both events as required by the spec - both CPT and CST are burned equally
        emit PoolModifyLiquidity(poolId, _msgSender(), owner, collateralAsset, 0, true);
        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitWithdraw(_msgSender(), receiver, owner, collateralAsset, cptAndCstSharesIn);
    }

    /// @inheritdoc IPoolManager
    function unwindExercise(UnwindExerciseParams calldata params) external override nonReentrant returns (uint256 assetIn, uint256 compensationOut, uint256 fee) {
        onlyInitialized(params.poolId);
        corkPoolUnwindSwapAndExerciseNotPaused(params.poolId);
        Guard.safeBeforeExpired(data().states[params.poolId].shares);

        require(params.shares != 0, InvalidAmount());

        State storage state = data().states[params.poolId];

        (assetIn, compensationOut, fee) = state.previewUnwindExercise(params.poolId, params.shares, getConstraintAdapter());

        // slippage
        require(compensationOut >= params.minCompensationOut, InsufficientOutputAmount(params.minCompensationOut, compensationOut));
        require(assetIn <= params.maxAssetsIn, ExceedInput(assetIn, params.maxAssetsIn));

        // Check sufficient liquidity
        require(compensationOut <= state.pool.balances.referenceAssetBalance, InsufficientLiquidity(state.pool.balances.referenceAssetBalance, compensationOut));
        require(params.shares <= state.pool.balances.swapTokenBalance, InsufficientLiquidity(state.pool.balances.swapTokenBalance, params.shares));

        // Decrease pool balances (opposite of unwindSwap)
        state.pool.balances.referenceAssetBalance -= compensationOut;
        state.pool.balances.swapTokenBalance -= params.shares;
        state.pool.balances.collateralAsset.locked += assetIn;

        // actually update the rate, since preview only get the latest rate without updating.
        // the adjusted rate should be idempotent and is fine to call many times
        state._getLatestApplicableRateAndUpdate(params.poolId, getConstraintAdapter());

        IERC20(state.info.collateralAsset).safeTransferFrom(_msgSender(), address(this), assetIn);

        // Transfer collateral asset fees to treasury
        if (fee != 0) _unlockTo(state, getTreasuryAddress(), fee);

        // Transfer unlocked tokens to receiver
        IERC20(state.info.referenceAsset).safeTransfer(params.receiver, compensationOut);
        IERC20(state.shares.swap).safeTransfer(params.receiver, params.shares);

        emit PoolSwap(params.poolId, _msgSender(), params.receiver, assetIn, compensationOut, 0, 0, true);
        emit PoolFee(params.poolId, _msgSender(), fee, 0);

        // ERC4626-compatible event emitted by principal token
        IPoolShare(state.shares.principal).emitDeposit(_msgSender(), params.receiver, assetIn, 0);
        IPoolShare(state.shares.principal).emitWithdrawOther(_msgSender(), params.receiver, _msgSender(), address(state.info.referenceAsset), compensationOut, 0);
    }

    /// @inheritdoc IPoolManager
    function baseRedemptionFee(MarketId poolId) external view override returns (uint256 fees) {
        fees = data().states[poolId].pool.baseRedemptionFeePercentage;
    }

    /// @inheritdoc IPoolManager
    function pausedStates(MarketId poolId) external view returns (IPoolManager.PausedStates memory pausedStates) {
        PoolState memory poolState = data().states[poolId].pool;
        pausedStates.depositPaused = poolState.isDepositPaused;
        pausedStates.unwindSwapPaused = poolState.isUnwindSwapPaused;
        pausedStates.swapPaused = poolState.isSwapPaused;
        pausedStates.withdrawalPaused = poolState.isWithdrawalPaused;
        pausedStates.unwindDepositAndMintPaused = poolState.isReturnPaused;
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
        (sharesOut, compensation,) = data().states[poolId].previewSwap(poolId, assets, data().CONSTRAINT_ADAPTER);
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
    function previewUnwindSwap(MarketId poolId, uint256 amount) external view returns (IUnwindSwap.UnwindSwapReturnParams memory returnParams) {
        onlyInitialized(poolId);
        returnParams = data().states[poolId].previewUnwindSwap(poolId, amount, data().CONSTRAINT_ADAPTER);
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
        uint256 minimumShares = calculateMinimumShares(data().states[poolId].collateralDecimals);

        // Check if amount is less than minimum shares
        if (cptAndCstAmountIn < minimumShares && cptAndCstAmountIn > 0) return 0; // Return 0 for preview to indicate it's below minimum

        // 1:1 rate
        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(cptAndCstAmountIn, data().states[poolId].collateralDecimals);
    }

    /// @inheritdoc IPoolManager
    function previewUnwindExercise(MarketId poolId, uint256 shares) external view override returns (uint256 assetIn, uint256 compensationOut) {
        onlyInitialized(poolId);
        (assetIn, compensationOut,) = data().states[poolId].previewUnwindExercise(poolId, shares, getConstraintAdapter());
    }

    /// @inheritdoc IPoolManager
    function previewExercise(MarketId poolId, uint256 shares, uint256 compensation) external view override returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        onlyInitialized(poolId);
        (assets, otherAssetSpent, fee,,) = data().states[poolId].previewExercise(poolId, shares, compensation, getConstraintAdapter());
    }

    /**
     * @notice Gets the maximum amount of CPT and CST tokens that can be minted
     * @return amount The maximum amount (unlimited)
     */
    function maxMint(MarketId poolId, address) external view returns (uint256 amount) {
        onlyInitialized(poolId);

        // If Minting is paused or the market is expired, return 0
        if (data().states[poolId].pool.isDepositPaused || PoolShare(data().states[poolId].shares.principal).isExpired()) return 0;

        amount = type(uint256).max;
    }

    /// @inheritdoc IPoolManager
    function maxDeposit(MarketId poolId, address) external view returns (uint256 amount) {
        onlyInitialized(poolId);

        // If Deposit is paused or the market is expired, return 0
        if (data().states[poolId].pool.isDepositPaused || PoolShare(data().states[poolId].shares.principal).isExpired()) return 0;

        amount = type(uint256).max;
    }

    /// @inheritdoc IPoolManager
    function maxUnwindDeposit(MarketId poolId, address owner) external view returns (uint256 collateralAssetAmountOut) {
        onlyInitialized(poolId);
        State storage state = data().states[poolId];

        // If Unwind Deposit is paused or the market is expired, return 0
        if (state.pool.isReturnPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        uint256 ownerSwapTokenBalance = IERC20(state.shares.principal).balanceOf(owner);
        uint256 ownerPrincipalTokenBalance = IERC20(state.shares.swap).balanceOf(owner);

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
        if (state.pool.isReturnPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        uint256 ownerSwapTokenBalance = IERC20(state.shares.principal).balanceOf(owner);
        uint256 ownerPrincipalTokenBalance = IERC20(state.shares.swap).balanceOf(owner);

        // since you need an equal amount of  swap token and principal token to unwind, we use whateever the smallest owner have
        cptAndCstSharesIn = ownerSwapTokenBalance < ownerPrincipalTokenBalance ? ownerSwapTokenBalance : ownerPrincipalTokenBalance;
    }

    /// @inheritdoc IPoolManager
    function maxWithdraw(MarketId poolId, address owner) external view override returns (uint256 assets) {
        onlyInitialized(poolId);
        (, assets) = _calculateMaxWithdraw(poolId, owner);
    }

    /// @inheritdoc IPoolManager
    function maxWithdrawOther(MarketId poolId, address owner) external view override returns (uint256 referenceAssets) {
        onlyInitialized(poolId);
        (referenceAssets,) = _calculateMaxWithdraw(poolId, owner);
    }

    function _calculateMaxWithdraw(MarketId poolId, address owner) private view returns (uint256 references, uint256 assets) {
        State storage state = data().states[poolId];

        // If withdrawals are paused or the market is not expired yet, return 0
        if (state.pool.isWithdrawalPaused || !PoolShare(state.shares.principal).isExpired()) return (0, 0);

        // Get owner's CPT balance (shares)
        uint256 ownerShares = IERC20(state.shares.principal).balanceOf(owner);

        if (ownerShares == 0) return (0, 0);

        // Get available collateral and reference in the pool
        uint256 poolCollateralBalance = state.valueLocked(true);
        uint256 poolReferenceBalance = state.valueLocked(false);

        // Return the minimum of owner's shares and available collateral
        // This ensures we don't return more than what can actually be withdrawn
        (references, assets) = state.previewRedeem(ownerShares);
    }

    /// @inheritdoc IPoolManager
    function maxExercise(MarketId poolId, address owner) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Exercise is paused or the market is expired, return 0
        if (state.pool.isSwapPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        return state.maxExercise(owner);
    }

    function maxExerciseOther(MarketId poolId, address owner) external view override returns (uint256 maxReferenceAssets) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Exercise is paused or the market is expired, return 0
        if (state.pool.isSwapPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        return state.maxExerciseOther(poolId, owner, getConstraintAdapter());
    }

    /// @inheritdoc IPoolManager
    function maxUnwindExercise(MarketId poolId, address receiver) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);
        State storage state = data().states[poolId];

        // If Unwind Exercise is paused or the market is expired, return 0
        if (state.pool.isUnwindSwapPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        maxShares = state.maxUnwindExercise(poolId, getConstraintAdapter());
    }

    /// @inheritdoc IPoolManager
    function maxUnwindExerciseOther(MarketId poolId, address receiver) external view override returns (uint256 maxReferenceAssets) {
        onlyInitialized(poolId);
        State storage state = data().states[poolId];

        // If Unwind Exercise is paused or the market is expired, return 0
        if (state.pool.isUnwindSwapPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        maxReferenceAssets = state.maxUnwindExerciseOther(poolId, getConstraintAdapter());
    }

    /// @inheritdoc IPoolManager
    function maxRedeem(MarketId poolId, address owner) external view override returns (uint256 maxShares) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Redeem is paused, or the market is not expired yet, return 0
        if (state.pool.isWithdrawalPaused || !PoolShare(state.shares.principal).isExpired()) return 0;
        maxShares = IERC20(state.shares.principal).balanceOf(owner);
    }

    /// @inheritdoc IPoolManager
    function maxSwap(MarketId poolId, address owner) external view override returns (uint256 assets) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Swap is paused or the market is expired, return 0
        if (state.pool.isSwapPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        assets = state.maxSwap(poolId, owner, getConstraintAdapter());
    }

    /// @inheritdoc IUnwindSwap
    function maxUnwindSwap(MarketId poolId, address receiver) external view returns (uint256 amount) {
        onlyInitialized(poolId);

        State storage state = data().states[poolId];

        // If Unwind Swap is paused or the market is expired, return 0
        if (state.pool.isUnwindSwapPaused || PoolShare(state.shares.principal).isExpired()) return 0;

        amount = state.maxUnwindSwap(poolId, getConstraintAdapter());
    }

    ///=================================================================///
    ///================== Internal Utility Functions ===================///
    ///=================================================================///

    /**
     * @notice Calculates minimum shares required to avoid rounding to zero
     * @dev Returns 10^(18-decimals) for tokens with <18 decimals, 0 otherwise
     * @param decimals The number of decimals for the token
     * @return minimumShares The minimum shares required
     */
    function calculateMinimumShares(uint8 decimals) internal pure returns (uint256 minimumShares) {
        // If collateral has fewer decimals than 18, calculate minimum shares amount to avoid rounding to 0
        return decimals < 18 ? 10 ** (18 - decimals) : 0;
    }

    /**
     * @notice Calculates minimum shares based on the lowest decimal count between two assets
     * @param collateralDecimals Decimals of collateral asset
     * @param referenceDecimals Decimals of reference asset
     * @return minimumShares Minimum shares required
     */
    function calculateMinimumSharesForAssets(uint8 collateralDecimals, uint8 referenceDecimals) internal pure returns (uint256 minimumShares) {
        // Use the asset with the lowest decimals to calculate minimum shares
        uint8 lowestDecimals = collateralDecimals < referenceDecimals ? collateralDecimals : referenceDecimals;
        return calculateMinimumShares(lowestDecimals);
    }
}
