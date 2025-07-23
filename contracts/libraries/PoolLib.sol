// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable, Shares} from "contracts/core/assets/Shares.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IExchangeRateProvider} from "contracts/interfaces/IExchangeRateProvider.sol";
import {CollateralAssetManager, CollateralAssetManagerLibrary} from "contracts/libraries/CollateralAssetManager.sol";
import {Guard} from "contracts/libraries/Guard.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Balances, CorkPoolPoolArchive, State} from "contracts/libraries/State.sol";
import {SwapToken, SwapTokenLibrary} from "contracts/libraries/SwapToken.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title ExerciseParams
 * @notice ExerciseParams is a struct that contains the parameters for the exercise function
 */
struct ExerciseParams {
    address sender;
    address owner;
    address receiver;
    uint256 shares;
    uint256 compensation;
    uint256 minAssetsOut;
    uint256 maxOtherAssetSpent;
    address treasury;
}

/**
 * @title SwapParams
 * @notice SwapParams is a struct that contains the parameters for the swap function
 */
struct SwapParams {
    address sender;
    address owner;
    address receiver;
    uint256 assets;
}

/**
 * @title CorkPool Library Contract
 * @author Cork Team
 * @notice CorkPool Library implements functions for Cork Pool Core contract
 */
library PoolLibrary {
    using MarketLibrary for Market;
    using SwapTokenLibrary for SwapToken;
    using CollateralAssetManagerLibrary for CollateralAssetManager;
    using SafeERC20 for IERC20;

    /**
     *   This denotes maximum fee allowed in contract
     *   Here 1 ether = 1e18 so maximum 5% fee allowed
     */
    uint256 internal constant MAX_ALLOWED_FEES = 5 ether;

    // Core functions
    function isInitialized(State storage self) public view returns (bool status) {
        status = self.info.isInitialized();
    }

    function _getLatestRate(State storage self) internal view returns (uint256 rate) {
        MarketId id = self.info.toId();

        uint256 exchangeRates = IExchangeRateProvider(self.info.exchangeRateProvider).rate();

        if (exchangeRates == 0) exchangeRates = IExchangeRateProvider(self.info.exchangeRateProvider).rate(id);

        return exchangeRates;
    }

    function _getLatestApplicableRate(State storage self) internal view returns (uint256 rate) {
        uint256 externalExchangeRates = _getLatestRate(self);
        uint256 currentExchangeRates = Shares(self.swapToken._address).exchangeRate();

        // return the lower of the two
        return externalExchangeRates < currentExchangeRates ? externalExchangeRates : currentExchangeRates;
    }

    // fetch and update the exchange rate. will return the lowest rate
    function _getLatestApplicableRateAndUpdate(State storage self) internal returns (uint256 rate) {
        rate = _getLatestApplicableRate(self);
        self.swapToken.updateExchangeRate(rate);
    }

    function initialize(State storage self, Market calldata market) external {
        self.info = market;
        self.pool.balances.collateralAsset = CollateralAssetManagerLibrary.initialize(market.collateralAsset);
    }

    function _separateLiquidity(State storage self) internal {
        if (self.pool.liquiditySeparated) return;

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);

        self.pool.liquiditySeparated = true;
        CorkPoolPoolArchive storage archive = self.pool.poolArchive;

        uint256 availableCollateralAsset = self.pool.balances.collateralAsset.convertAllToFree();
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;

        archive.referenceAssetAccrued = availableReferenceAsset;
        archive.collateralAssetAccrued = availableCollateralAsset;
        archive.principalTokenAttributed = IERC20(swapToken.principalToken).totalSupply();

        // reset current balances
        self.pool.balances.collateralAsset.reset();
        self.pool.balances.referenceAssetBalance = 0;
    }

    /// @notice deposit Collateral Asset to the Cork Pool
    /// @dev the user must approve the Cork Pool to spend their Collateral Asset
    function deposit(State storage self, address depositor, address receiver, uint256 amount) external returns (uint256 received, uint256 _exchangeRate) {
        if (amount == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;

        Guard.safeBeforeExpired(swapToken);
        _exchangeRate = _getLatestApplicableRateAndUpdate(self);

        // we convert it 18 fixed decimals, since that's what the Swap Token uses
        received = TransferHelper.tokenNativeDecimalsToFixed(amount, self.info.collateralAsset);

        self.pool.balances.collateralAsset.lockFrom(amount, depositor);

        swapToken.issue(receiver, received);
    }

    function _unwindMint(State storage self, SwapToken storage swapToken, address owner, uint256 swapTokenAndPrincipalTokenIn) internal returns (uint256 collateralAsset) {
        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(swapTokenAndPrincipalTokenIn, self.info.collateralAsset);

        self.pool.balances.collateralAsset.unlockTo(owner, collateralAsset);

        ERC20Burnable(swapToken.principalToken).burnFrom(owner, swapTokenAndPrincipalTokenIn);
        ERC20Burnable(swapToken._address).burnFrom(owner, swapTokenAndPrincipalTokenIn);
    }

    function unwindMint(State storage self, address owner, uint256 swapTokenAndPrincipalTokenIn) external returns (uint256 collateralAsset) {
        if (swapTokenAndPrincipalTokenIn == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        collateralAsset = _unwindMint(self, swapToken, owner, swapTokenAndPrincipalTokenIn);
    }

    function availableForUnwindSwap(State storage self) external view returns (uint256 referenceAsset, uint256 swapToken) {
        SwapToken storage _swapToken = self.swapToken;
        Guard.safeBeforeExpired(_swapToken);

        referenceAsset = self.pool.balances.referenceAssetBalance;
        swapToken = self.pool.balances.swapTokenBalance;
    }

    function unwindSwapRates(State storage self) external view returns (uint256 rates) {
        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        rates = _getLatestApplicableRate(self);
    }

    function unwindSwapFeePercentage(State storage self) external view returns (uint256 rates) {
        rates = self.pool.unwindSwapFeePercentage;
    }

    function updateUnwindSwapFeePercentage(State storage self, uint256 newFees) external {
        if (newFees > MAX_ALLOWED_FEES) revert IErrors.InvalidFees();
        self.pool.unwindSwapFeePercentage = newFees;
    }

    function unwindSwap(State storage self, address buyer, address receiver, uint256 amount, address treasury) external returns (uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 exchangeRates) {
        if (amount == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken;

        _getLatestApplicableRateAndUpdate(self);

        (receivedReferenceAsset, receivedSwapToken, feePercentage, fee, exchangeRates, swapToken) = previewUnwindSwap(self, amount);

        // decrease Cork Pool balance
        // we also include the fee here to separate the accumulated fee from the unwindSwap
        self.pool.balances.referenceAssetBalance -= (receivedReferenceAsset);
        self.pool.balances.swapTokenBalance -= (receivedSwapToken);

        // transfer user Collateral Asset to the Cork Pool
        self.pool.balances.collateralAsset.lockFrom(amount, buyer);

        // decrease the locked balance with the fee(if any), since the fee is used to provide liquidity
        if (fee != 0) self.pool.balances.collateralAsset.decreaseLocked(fee);

        // transfer user attrubuted Swap Token + Reference Asset
        // Reference Asset
        (, address referenceAsset) = self.info.underlyingAsset();
        IERC20(referenceAsset).safeTransfer(receiver, receivedReferenceAsset);

        // Swap Token
        IERC20(swapToken._address).safeTransfer(receiver, receivedSwapToken);

        if (fee != 0) self.pool.balances.collateralAsset.unlockToUnchecked(fee, treasury);
    }

    function _swap(Balances storage self, uint256 referenceAsset, uint256 swapToken) internal {
        self.swapTokenBalance += swapToken;
        self.referenceAssetBalance += referenceAsset;
    }

    function _afterSwap(State storage self, SwapToken storage swapToken, ExerciseParams memory params, uint256 swapTokenProvided, uint256 referenceAssetProvided, uint256 collateralReceived, uint256 fee) internal {
        Shares(swapToken._address).transferFrom(params.sender, params.owner, address(this), swapTokenProvided);
        IERC20(self.info.referenceAsset).safeTransferFrom(params.owner, address(this), referenceAssetProvided);

        self.pool.balances.collateralAsset.unlockTo(params.receiver, collateralReceived);
        self.pool.balances.collateralAsset.unlockTo(params.treasury, fee);
    }

    // TODO : make invariant test for this
    function valueLocked(State storage self, bool collateralAsset) external view returns (uint256) {
        if (collateralAsset) return self.pool.balances.collateralAsset.locked + self.pool.poolArchive.collateralAssetAccrued;
        else return self.pool.balances.referenceAssetBalance + self.pool.poolArchive.referenceAssetAccrued;
    }

    function exchangeRate(State storage self) external view returns (uint256 rates) {
        rates = _getLatestApplicableRate(self);
    }

    function exercise(State storage self, address sender, address owner, address receiver, uint256 shares, uint256 compensation, uint256 minAssetsOut, uint256 maxOtherAssetSpent, address treasury) external returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        ExerciseParams memory params = ExerciseParams({sender: sender, owner: owner, receiver: receiver, shares: shares, compensation: compensation, minAssetsOut: minAssetsOut, maxOtherAssetSpent: maxOtherAssetSpent, treasury: treasury});

        return _exercise(self, params);
    }

    function previewExercise(State storage self, uint256 shares, uint256 compensation) public view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        (assets, otherAssetSpent, fee,,) = _previewExercise(self, shares, compensation);
    }

    function _exercise(State storage self, ExerciseParams memory params) internal returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        SwapToken storage swapToken = self.swapToken;

        // Update exchange rate before preview
        _getLatestApplicableRateAndUpdate(self);

        // Use previewExercise to get all calculated amounts
        uint256 swapTokenProvided;
        uint256 referenceAssetProvided;
        (assets, otherAssetSpent, fee, swapTokenProvided, referenceAssetProvided) = _previewExercise(self, params.shares, params.compensation);

        // Validate slippage protection
        if (assets < params.minAssetsOut) revert IErrors.InsufficientLiquidity(params.minAssetsOut, assets);
        if (otherAssetSpent > params.maxOtherAssetSpent) revert IErrors.InsufficientLiquidity(params.maxOtherAssetSpent, otherAssetSpent);
        if (assets > self.pool.balances.collateralAsset.locked) revert IErrors.InsufficientLiquidity(self.pool.balances.collateralAsset.locked, assets);

        // Update balances and transfer tokens
        _swap(self.pool.balances, referenceAssetProvided, swapTokenProvided);
        _afterSwap(self, swapToken, params, swapTokenProvided, referenceAssetProvided, assets, fee);
    }

    function _previewExercise(State storage self, uint256 shares, uint256 compensation) internal view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee, uint256 swapTokenProvided, uint256 referenceAssetProvided) {
        // Either shares or compensation MUST be 0
        if ((shares == 0 && compensation == 0) || (shares != 0 && compensation != 0)) revert IErrors.InvalidParams();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        uint256 _exchangeRate = _getLatestApplicableRate(self);

        // Calculate amounts based on mode (shares > 0 = shares mode, otherwise compensation mode)
        // we need to provide swap token = compensation x rates
        // or we need to provide compensation = swap token / rates
        swapTokenProvided = shares > 0 ? shares : MathHelper.calculateEqualSwapAmount(TransferHelper.tokenNativeDecimalsToFixed(compensation, self.info.referenceAsset), _exchangeRate);
        referenceAssetProvided = shares > 0 ? MathHelper.calculateDepositAmountWithExchangeRate(swapTokenProvided, _exchangeRate) : compensation;

        // Calculate collateral asset output (same calculation for both modes)
        uint256 assetsBeforeFee = TransferHelper.fixedToTokenNativeDecimals(swapTokenProvided, self.info.collateralAsset);

        // Other asset spent is the non-primary asset (reference asset in shares mode, CST in compensation mode)
        otherAssetSpent = shares > 0 ? referenceAssetProvided : swapTokenProvided;

        // Calculate fee and final assets
        fee = MathHelper.calculatePercentageFee(self.pool.baseRedemptionFeePercentage, assetsBeforeFee);
        assets = assetsBeforeFee - fee;
    }

    /// @notice return the next depeg swap expiry
    function nextExpiry(State storage self) external view returns (uint256 expiry) {
        SwapToken storage swapToken = self.swapToken;

        expiry = Shares(swapToken._address).expiry();
    }

    function _calcSwapAmount(State storage self, uint256 amount, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        availableReferenceAsset = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.info.referenceAsset);
        availableCollateralAsset = TransferHelper.tokenNativeDecimalsToFixed(availableCollateralAsset, self.info.collateralAsset);

        accruedReferenceAsset = MathHelper.calculateAccrued(amount, availableReferenceAsset, totalPrincipalTokenIssued);
        accruedCollateralAsset = MathHelper.calculateAccrued(amount, availableCollateralAsset, totalPrincipalTokenIssued);

        accruedReferenceAsset = TransferHelper.fixedToTokenNativeDecimals(accruedReferenceAsset, self.info.referenceAsset);
        accruedCollateralAsset = TransferHelper.fixedToTokenNativeDecimals(accruedCollateralAsset, self.info.collateralAsset);
    }

    function _beforePrincipalTokenSwap(State storage self, SwapToken storage swapToken, uint256 amount, uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) internal {
        swapToken.withdrawn += amount;
        self.pool.poolArchive.principalTokenAttributed -= amount;
        self.pool.poolArchive.referenceAssetAccrued -= accruedReferenceAsset;
        self.pool.poolArchive.collateralAssetAccrued -= accruedCollateralAsset;
    }

    function _afterPrincipalTokenSwap(State storage self, SwapToken storage swapToken, address sender, address owner, address receiver, uint256 withdrawnAmount, uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) internal {
        Shares(swapToken.principalToken).transferFrom(sender, owner, address(this), withdrawnAmount);
        ERC20Burnable(swapToken.principalToken).burn(withdrawnAmount);
        IERC20(self.info.referenceAsset).safeTransfer(receiver, accruedReferenceAsset);
        IERC20(self.info.collateralAsset).safeTransfer(receiver, accruedCollateralAsset);
    }

    /// @notice swap accrued Collateral Shares + Reference Shares with Principal Token on expiry
    function redeem(State storage self, address sender, address owner, address receiver, uint256 amount) public returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        if (amount == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);
        _separateLiquidity(self);

        uint256 totalPrincipalTokenIssued = self.pool.poolArchive.principalTokenAttributed;
        CorkPoolPoolArchive storage archive = self.pool.poolArchive;

        (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, totalPrincipalTokenIssued, archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        _beforePrincipalTokenSwap(self, swapToken, amount, accruedReferenceAsset, accruedCollateralAsset);

        _afterPrincipalTokenSwap(self, swapToken, sender, owner, receiver, amount, accruedReferenceAsset, accruedCollateralAsset);
    }

    function updateBaseRedemptionFeePercentage(State storage self, uint256 newFees) external {
        if (newFees > MAX_ALLOWED_FEES) revert IErrors.InvalidFees();
        self.pool.baseRedemptionFeePercentage = newFees;
    }

    function previewUnwindSwap(State storage self, uint256 amount) public view returns (uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 exchangeRates, SwapToken storage swapToken) {
        swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        exchangeRates = _getLatestApplicableRate(self);

        // the fee is taken directly from Collateral Asset before it's even converted to Swap Token
        {
            Shares _swapToken = Shares(swapToken._address);
            (fee,) = MathHelper.calculateUnwindSwapWithFee(_swapToken.issuedAt(), _swapToken.expiry(), block.timestamp, amount, self.pool.unwindSwapFeePercentage);
        }

        // TODO : verify this behaviour
        if (amount == 0) return (0, 0, self.pool.unwindSwapFeePercentage, fee, exchangeRates, swapToken);

        amount = amount - fee;
        amount = TransferHelper.tokenNativeDecimalsToFixed(amount, self.info.collateralAsset);

        // we use deposit here because technically the user deposit Collateral Asset to the Cork Pool when unwinding, except with exchange rate applied
        receivedReferenceAsset = MathHelper.calculateDepositAmountWithExchangeRate(amount, exchangeRates);
        receivedReferenceAsset = TransferHelper.fixedToTokenNativeDecimals(receivedReferenceAsset, self.info.referenceAsset);
        receivedSwapToken = amount;

        if (receivedReferenceAsset > self.pool.balances.referenceAssetBalance) revert IErrors.InsufficientLiquidity(self.pool.balances.referenceAssetBalance, receivedReferenceAsset);

        if (receivedSwapToken > self.pool.balances.swapTokenBalance) revert IErrors.InsufficientLiquidity(amount, self.pool.balances.swapTokenBalance);
    }

    function previewSwap(State storage self, uint256 amount) public view returns (uint256 collateralAsset, uint256 swapToken, uint256 fee, uint256 exchangeRates) {
        SwapToken storage _swapToken = self.swapToken;
        Guard.safeBeforeExpired(_swapToken);

        exchangeRates = _getLatestApplicableRate(self);
        // the amount here is the Reference Asset amount
        amount = TransferHelper.tokenNativeDecimalsToFixed(amount, self.info.referenceAsset);
        uint256 raSwapToken = MathHelper.calculateEqualSwapAmount(amount, exchangeRates);

        swapToken = raSwapToken;
        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(raSwapToken, self.info.collateralAsset);

        fee = MathHelper.calculatePercentageFee(collateralAsset, self.pool.baseRedemptionFeePercentage);
        collateralAsset -= fee;
    }

    function previewRedeem(State storage self, uint256 amount) public view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        if (amount == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            // This simulates what _separateLiquidity would do
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.free + self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
            uint256 totalPrincipalTokenIssued = IERC20(swapToken.principalToken).totalSupply();

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, totalPrincipalTokenIssued, availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            uint256 totalPrincipalTokenIssued = self.pool.poolArchive.principalTokenAttributed;
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, totalPrincipalTokenIssued, archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }
    }

    function _calcWithdrawAmount(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal view returns (uint256 sharesIn) {
        // Convert to fixed decimals for calculation
        uint256 collateralAssetOutFixed = TransferHelper.tokenNativeDecimalsToFixed(collateralAssetOut, self.info.collateralAsset);
        uint256 referenceAssetOutFixed = TransferHelper.tokenNativeDecimalsToFixed(referenceAssetOut, self.info.referenceAsset);
        uint256 availableRaFixed = TransferHelper.tokenNativeDecimalsToFixed(availableCollateralAsset, self.info.collateralAsset);
        uint256 availablePaFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.info.referenceAsset);

        // Calculate required shares based on which asset is being withdrawn
        if (collateralAssetOutFixed > 0) sharesIn = MathHelper.calculateSharesNeeded(collateralAssetOutFixed, availableRaFixed, totalPrincipalTokenIssued);
        else sharesIn = MathHelper.calculateSharesNeeded(referenceAssetOutFixed, availablePaFixed, totalPrincipalTokenIssued);
    }

    function previewWithdraw(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut) external view returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        // Either collateralAssetOut or referenceAssetOut must be zero, but not both
        if ((collateralAssetOut == 0 && referenceAssetOut == 0) || (collateralAssetOut != 0 && referenceAssetOut != 0)) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.free + self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
            uint256 totalPrincipalTokenIssued = IERC20(swapToken.principalToken).totalSupply();

            sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, totalPrincipalTokenIssued, availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            uint256 totalPrincipalTokenIssued = self.pool.poolArchive.principalTokenAttributed;
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, totalPrincipalTokenIssued, archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }

        (actualReferenceAssetOut,) = previewRedeem(self, sharesIn);
    }

    function withdraw(State storage self, address sender, address owner, address receiver, uint256 collateralAssetOut, uint256 referenceAssetOut) external returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        // Either collateralAssetOut or referenceAssetOut must be zero, but not both
        if ((collateralAssetOut == 0 && referenceAssetOut == 0) || (collateralAssetOut != 0 && referenceAssetOut != 0)) revert IErrors.InvalidParams();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);
        _separateLiquidity(self);

        // Calculate required shares
        uint256 totalPrincipalTokenIssued = self.pool.poolArchive.principalTokenAttributed;
        CorkPoolPoolArchive storage archive = self.pool.poolArchive;

        if (collateralAssetOut > archive.collateralAssetAccrued) revert IErrors.InsufficientLiquidity(archive.collateralAssetAccrued, collateralAssetOut);
        if (referenceAssetOut > archive.referenceAssetAccrued) revert IErrors.InsufficientLiquidity(archive.referenceAssetAccrued, referenceAssetOut);

        sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, totalPrincipalTokenIssued, archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        // Use the existing redeem function to do the actual withdrawal
        uint256 actualCollateralAssetOut;
        (actualReferenceAssetOut, actualCollateralAssetOut) = redeem(self, sender, owner, receiver, sharesIn);

        // Validate that the actual output matches the requested output for the non-zero asset
        if (collateralAssetOut != 0) assert(actualCollateralAssetOut == collateralAssetOut);
        if (referenceAssetOut != 0) assert(actualReferenceAssetOut == referenceAssetOut);
    }

    function maxExercise(State storage self, address owner) external view returns (uint256 shares) {
        SwapToken storage swapToken = self.swapToken;

        // Check if before expiry (exercise only works before expiry)
        if (!isInitialized(self)) return 0;
        if (Shares(swapToken._address).isExpired()) return 0;

        // Get owner's CST balance
        uint256 ownerCstBalance = IERC20(swapToken._address).balanceOf(owner);
        if (ownerCstBalance == 0) return 0;

        // Calculate how much collateral asset the user can get with their CST shares
        uint256 collateralAssetOut = TransferHelper.fixedToTokenNativeDecimals(ownerCstBalance, self.info.collateralAsset);

        // Apply fee to get the actual collateral they would receive
        uint256 fee = MathHelper.calculatePercentageFee(self.pool.baseRedemptionFeePercentage, collateralAssetOut);
        uint256 actualCollateralOut = collateralAssetOut - fee;

        // Check if enough collateral asset is available - this should always be true due to core invariants
        uint256 availableCollateral = self.pool.balances.collateralAsset.locked;
        assert(actualCollateralOut <= availableCollateral); // Core invariant: should always have enough collateral

        return ownerCstBalance;
    }

    function swap(State storage self, address sender, address owner, address receiver, uint256 assets) external returns (uint256 shares, uint256 compensation) {
        SwapParams memory params = SwapParams({sender: sender, owner: owner, receiver: receiver, assets: assets});

        return _swapInternal(self, params);
    }

    function _swapInternal(State storage self, SwapParams memory params) internal returns (uint256 shares, uint256 compensation) {
        if (params.assets == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        // Update exchange rate before calculations
        uint256 _exchangeRate = _getLatestApplicableRateAndUpdate(self);

        // Calculate gross collateral amount needed before fee deduction
        uint256 assetsFixed = TransferHelper.tokenNativeDecimalsToFixed(params.assets, self.info.collateralAsset);
        uint256 grossCollateralAsset = MathHelper.calculateGrossAmountBeforeFee(assetsFixed, self.pool.baseRedemptionFeePercentage);

        // Convert gross collateral to fixed decimals to get CST shares needed
        shares = grossCollateralAsset;

        // Calculate required reference asset using exchange rate (in fixed decimals)
        uint256 compensationFixed = MathHelper.calculateDepositAmountWithExchangeRate(shares, _exchangeRate);
        compensation = TransferHelper.fixedToTokenNativeDecimals(compensationFixed, self.info.referenceAsset);

        if (params.assets > self.pool.balances.collateralAsset.locked) revert IErrors.InsufficientLiquidity(self.pool.balances.collateralAsset.locked, params.assets);

        Shares(swapToken._address).transferFrom(params.sender, params.owner, address(this), shares);
        IERC20(self.info.referenceAsset).safeTransferFrom(params.owner, address(this), compensation);

        _swap(self.pool.balances, compensation, shares);

        self.pool.balances.collateralAsset.unlockTo(params.receiver, params.assets);
    }

    function previewUnwindExercise(State storage self, uint256 shares) public view returns (uint256 assetIn, uint256 compensationOut) {
        if (shares == 0) revert IErrors.ZeroDeposit();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        uint256 currentRate = _getLatestApplicableRate(self);

        // Calculate compensation based on shares and exchange rate
        uint256 compensationFixed = MathHelper.calculateDepositAmountWithExchangeRate(shares, currentRate);
        compensationOut = TransferHelper.fixedToTokenNativeDecimals(compensationFixed, self.info.referenceAsset);

        // Calculate asset input needed including fee
        uint256 fee;
        {
            Shares _swapToken = Shares(swapToken._address);
            (fee, assetIn) = MathHelper.calculateUnwindSwapWithFee(_swapToken.issuedAt(), _swapToken.expiry(), block.timestamp, shares, self.pool.unwindSwapFeePercentage);
        }
    }

    function maxUnwindExercise(State storage self, address) external view returns (uint256 shares) {
        SwapToken storage swapToken = self.swapToken;

        // Check if before expiry (unwindExercise only works before expiry)
        if (Shares(swapToken._address).isExpired()) return 0;

        // The maximum shares is limited by the available CST balance in the pool
        uint256 availableCstBalance = self.pool.balances.swapTokenBalance;
        if (availableCstBalance == 0) return 0;

        // Also limited by available reference asset balance for compensation
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        if (availableReferenceAsset == 0) return 0;

        // Get current exchange rate
        uint256 currentExchangeRate = _getLatestApplicableRate(self);
        if (currentExchangeRate == 0) return 0;

        // Convert available reference asset to fixed decimals
        uint256 availableReferenceAssetFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.info.referenceAsset);

        // Calculate max shares based on reference asset limit
        uint256 maxSharesByReferenceAsset = MathHelper.calculateDepositAmountWithExchangeRate(availableReferenceAssetFixed, currentExchangeRate);

        // The actual maximum is the minimum of the two constraints
        shares = availableCstBalance < maxSharesByReferenceAsset ? availableCstBalance : maxSharesByReferenceAsset;

        return shares;
    }

    function maxSwap(State storage self, address owner) external view returns (uint256 assets) {
        SwapToken storage swapToken = self.swapToken;

        if (!isInitialized(self)) return 0;
        if (Shares(swapToken._address).isExpired()) return 0;
        if (self.pool.isSwapPaused) return 0;

        // Get owner's CST and reference asset balances
        uint256 ownerCstBalance = IERC20(swapToken._address).balanceOf(owner);
        uint256 ownerReferenceBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        // Must have both CST shares and reference assets to swap
        if (ownerCstBalance == 0 || ownerReferenceBalance == 0) return 0;

        // Calculate the maximum CST shares we can use based on available reference assets
        uint256 otherAssetSpent;
        (assets, otherAssetSpent,) = previewExercise(self, 0, ownerReferenceBalance);
        uint256 effectiveShares = ownerCstBalance < otherAssetSpent ? ownerCstBalance : otherAssetSpent;

        // If no effective shares, can't swap
        if (effectiveShares == 0) return 0;

        (assets,,) = previewExercise(self, effectiveShares, 0);
    }

    function unwindExercise(State storage self, address sender, address receiver, uint256 shares, uint256 minCompensationOut, uint256 maxAssetIn) external returns (uint256 assetIn, uint256 compensationOut) {
        SwapToken storage swapToken = self.swapToken;

        // Update exchange rate before preview
        _getLatestApplicableRateAndUpdate(self);

        // Use previewUnwindExercise to get all calculated amounts
        (assetIn, compensationOut) = previewUnwindExercise(self, shares);

        if (compensationOut < minCompensationOut) revert IErrors.InsufficientOutputAmount(minCompensationOut, compensationOut);
        if (assetIn > maxAssetIn) revert IErrors.ExcessiveInput(assetIn, maxAssetIn);

        // Check sufficient liquidity
        if (compensationOut > self.pool.balances.referenceAssetBalance) revert IErrors.InsufficientLiquidity(self.pool.balances.referenceAssetBalance, compensationOut);
        if (shares > self.pool.balances.swapTokenBalance) revert IErrors.InsufficientLiquidity(self.pool.balances.swapTokenBalance, shares);

        // Transfer collateral asset from sender
        self.pool.balances.collateralAsset.lockFrom(assetIn, sender);

        // Decrease pool balances (opposite of unwindSwap)
        self.pool.balances.referenceAssetBalance -= compensationOut;
        self.pool.balances.swapTokenBalance -= shares;

        // Transfer unlocked tokens to receiver
        (, address referenceAsset) = self.info.underlyingAsset();
        IERC20(referenceAsset).safeTransfer(receiver, compensationOut);
        IERC20(swapToken._address).safeTransfer(receiver, shares);
    }

    function maxUnwindSwap(State storage self, address) external view returns (uint256 amount) {
        SwapToken storage swapToken = self.swapToken;

        if (!isInitialized(self)) return 0;
        if (Shares(swapToken._address).isExpired()) return 0;
        if (self.pool.isUnwindSwapPaused) return 0;

        // Get available reference asset and swap token balances in the pool
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        uint256 availableSwapToken = self.pool.balances.swapTokenBalance;

        // If no available assets to unwind swap, return 0
        if (availableReferenceAsset == 0 || availableSwapToken == 0) return 0;

        // Get current exchange rate
        uint256 _exchangeRate = _getLatestApplicableRate(self);
        if (_exchangeRate == 0) return 0;

        uint256 maxNetAmount;

        {
            // Calculate maximum net amounts based on pool constraints
            // Convert available reference asset to fixed decimals
            uint256 availableReferenceAssetFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.info.referenceAsset);

            // Calculate max net amount based on reference asset limit
            // receivedReferenceAsset = MathHelper.calculateDepositAmountWithExchangeRate(netAmountFixed, _exchangeRate)
            // So: netAmountFixed = receivedReferenceAsset * _exchangeRate
            uint256 maxNetFromReferenceAsset = MathHelper.calculateEqualSwapAmount(availableReferenceAssetFixed, _exchangeRate);

            // Calculate max net amount based on swap token limit (1:1 in fixed decimals)
            uint256 maxNetFromSwapToken = availableSwapToken;

            // Take the minimum of the two constraints
            uint256 maxNetAmountFixed = maxNetFromReferenceAsset < maxNetFromSwapToken ? maxNetFromReferenceAsset : maxNetFromSwapToken;

            // Convert to collateral asset decimals
            maxNetAmount = TransferHelper.fixedToTokenNativeDecimals(maxNetAmountFixed, self.info.collateralAsset);
        }

        // Use the inverse calculation from MathHelper.calculateUnwindSwapWithFee
        // The fee function calculates: grossAmount = netAmount / (1 - effectiveFeeRate)
        (, amount) = MathHelper.calculateUnwindSwapWithFee(Shares(swapToken._address).issuedAt(), Shares(swapToken._address).expiry(), block.timestamp, maxNetAmount, self.pool.unwindSwapFeePercentage);
    }
}
