// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ConstraintAdapter} from "./../core/ConstraintAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
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
    uint256 shares;
    uint256 compensation;
    address receiver;
    uint256 minAssetsOut;
    uint256 maxOtherAssetSpent;
    address sender;
    address owner;
    address treasury;
}

/**
 * @title SwapParams
 * @notice SwapParams is a struct that contains the parameters for the swap function
 */
struct SwapParams {
    uint256 assets;
    address receiver;
    address sender;
    address owner;
    address treasury;
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

    function _getLatestApplicableRate(State storage self, address constraintAdapter) internal view returns (uint256 rate) {
        return ConstraintAdapter(constraintAdapter).previewAdjustedRate(self.info.toId());
    }

    // fetch and update the swap rate. will return the lowest rate
    function _getLatestApplicableRateAndUpdate(State storage self, address constraintAdapter) internal returns (uint256 rate) {
        rate = ConstraintAdapter(constraintAdapter).adjustedRate(self.info.toId());
        self.swapToken.updateSwapRate(rate);
    }

    function initialize(State storage self, Market calldata market, address constraintAdapter) external {
        self.info = market;
        self.pool.balances.collateralAsset = CollateralAssetManagerLibrary.initialize(market.collateralAsset);

        ConstraintAdapter(constraintAdapter).bootstrap(self.info.toId());
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

        // reset current balances
        self.pool.balances.collateralAsset.reset();
        self.pool.balances.referenceAssetBalance = 0;
    }

    /// @notice deposit Collateral Asset to the Cork Pool
    /// @dev the user must approve the Cork Pool to spend their Collateral Asset
    function deposit(State storage self, uint256 amount, address receiver, address depositor) external returns (uint256 received) {
        require(amount != 0, IErrors.ZeroDeposit());

        SwapToken storage swapToken = self.swapToken;

        Guard.safeBeforeExpired(swapToken);

        // we convert it 18 fixed decimals, since that's what the Swap Token uses
        received = TransferHelper.tokenNativeDecimalsToFixed(amount, self.collateralDecimals);

        self.pool.balances.collateralAsset.lockFrom(amount, depositor);

        swapToken.issue(receiver, received);
    }

    function _unwindMint(State storage self, SwapToken storage swapToken, address owner, address receiver, uint256 cptAndCstSharesIn) internal returns (uint256 collateralAsset) {
        // Calculate the minimum shares required to get at least 1 unit of collateral asset
        uint256 minimumShares = 0;
        if (self.collateralDecimals < 18) {
            // If collateral has fewer decimals than 18, calculate minimum shares amount to avoid rounding to 0
            minimumShares = 10 ** (18 - self.collateralDecimals);
        }

        // Ensure the input amount is at least the minimum required
        if (cptAndCstSharesIn < minimumShares && cptAndCstSharesIn > 0) revert IErrors.InsufficientSharesAmount(minimumShares, cptAndCstSharesIn);

        collateralAsset = TransferHelper.fixedToTokenNativeDecimals(cptAndCstSharesIn, self.collateralDecimals);

        // Ensure we're not returning 0 assets for a non-zero shares input
        if (collateralAsset == 0 && cptAndCstSharesIn > 0) revert IErrors.ZeroOutput();

        self.pool.balances.collateralAsset.unlockTo(receiver, collateralAsset);

        ERC20Burnable(swapToken.principalToken).burnFrom(owner, cptAndCstSharesIn);
        ERC20Burnable(swapToken._address).burnFrom(owner, cptAndCstSharesIn);
    }

    function unwindMint(State storage self, address owner, address receiver, uint256 cptAndCstSharesIn) external returns (uint256 collateralAsset) {
        require(cptAndCstSharesIn != 0, IErrors.InvalidAmount());

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        collateralAsset = _unwindMint(self, swapToken, owner, receiver, cptAndCstSharesIn);
    }

    function availableForUnwindSwap(State storage self) external view returns (uint256 referenceAsset, uint256 swapToken) {
        SwapToken storage _swapToken = self.swapToken;
        Guard.safeBeforeExpired(_swapToken);

        referenceAsset = self.pool.balances.referenceAssetBalance;
        swapToken = self.pool.balances.swapTokenBalance;
    }

    function unwindSwapRate(State storage self, address constraintAdapter) external view returns (uint256 rate) {
        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        rate = _getLatestApplicableRate(self, constraintAdapter);
    }

    function unwindSwapFeePercentage(State storage self) external view returns (uint256 rate) {
        rate = self.pool.unwindSwapFeePercentage;
    }

    function updateUnwindSwapFeePercentage(State storage self, uint256 newFees) external {
        require(newFees <= MAX_ALLOWED_FEES, IErrors.InvalidFees());
        self.pool.unwindSwapFeePercentage = newFees;
    }

    function unwindSwap(State storage self, uint256 amount, address receiver, address buyer, address treasury, address constraintAdapter) external returns (uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 _swapRate) {
        require(amount != 0, IErrors.InvalidAmount());

        SwapToken storage swapToken;

        _getLatestApplicableRateAndUpdate(self, constraintAdapter);

        (receivedReferenceAsset, receivedSwapToken, feePercentage, fee, _swapRate, swapToken) = previewUnwindSwap(self, amount, constraintAdapter);

        // decrease Cork Pool balance
        // we also include the fee here to separate the accumulated fee from the unwindSwap
        self.pool.balances.referenceAssetBalance -= (receivedReferenceAsset);
        self.pool.balances.swapTokenBalance -= (receivedSwapToken);

        // transfer user Collateral Asset to the Cork Pool
        self.pool.balances.collateralAsset.lockFrom(amount, buyer);

        // transfer the fee(if any) to treasury, since the fee is used to provide liquidity
        if (fee != 0) self.pool.balances.collateralAsset.unlockTo(treasury, fee);

        // transfer user attrubuted Swap Token + Reference Asset
        // Reference Asset
        IERC20(self.info.referenceAsset).safeTransfer(receiver, receivedReferenceAsset);

        // Swap Token
        IERC20(swapToken._address).safeTransfer(receiver, receivedSwapToken);
    }

    function _swap(Balances storage self, uint256 referenceAsset, uint256 swapToken) internal {
        self.swapTokenBalance += swapToken;
        self.referenceAssetBalance += referenceAsset;
    }

    function _afterExercise(State storage self, SwapToken storage swapToken, ExerciseParams memory params, uint256 swapTokenProvided, uint256 referenceAssetProvided, uint256 collateralReceived, uint256 fee) internal {
        PoolShare(swapToken._address).transferFrom(params.sender, params.owner, address(this), swapTokenProvided);
        IERC20(self.info.referenceAsset).safeTransferFrom(params.owner, address(this), referenceAssetProvided);

        self.pool.balances.collateralAsset.unlockTo(params.receiver, collateralReceived);
        self.pool.balances.collateralAsset.unlockTo(params.treasury, fee);
    }

    function valueLocked(State storage self, bool collateralAsset) external view returns (uint256) {
        if (collateralAsset) return self.pool.balances.collateralAsset.locked + self.pool.poolArchive.collateralAssetAccrued;
        else return self.pool.balances.referenceAssetBalance + self.pool.poolArchive.referenceAssetAccrued;
    }

    function swapRate(State storage self, address constraintAdapter) external view returns (uint256 rate) {
        rate = _getLatestApplicableRate(self, constraintAdapter);
    }

    function exercise(State storage self, uint256 shares, uint256 compensation, address receiver, uint256 minAssetsOut, uint256 maxOtherAssetSpent, address sender, address owner, address treasury, address constraintAdapter) external returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        ExerciseParams memory params = ExerciseParams({sender: sender, owner: owner, receiver: receiver, shares: shares, compensation: compensation, minAssetsOut: minAssetsOut, maxOtherAssetSpent: maxOtherAssetSpent, treasury: treasury});

        return _exercise(self, params, constraintAdapter);
    }

    function previewExercise(State storage self, uint256 shares, uint256 compensation, address constraintAdapter) public view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        (assets, otherAssetSpent, fee,,) = _previewExercise(self, shares, compensation, constraintAdapter);
    }

    function _exercise(State storage self, ExerciseParams memory params, address constraintAdapter) internal returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        SwapToken storage swapToken = self.swapToken;

        // Update swap rate before preview
        _getLatestApplicableRateAndUpdate(self, constraintAdapter);

        // Use previewExercise to get all calculated amounts
        uint256 swapTokenProvided;
        uint256 referenceAssetProvided;
        (assets, otherAssetSpent, fee, swapTokenProvided, referenceAssetProvided) = _previewExercise(self, params.shares, params.compensation, constraintAdapter);

        // Validate slippage protection
        require(assets >= params.minAssetsOut, IErrors.SlippageExceeded());
        require(otherAssetSpent <= params.maxOtherAssetSpent, IErrors.SlippageExceeded());
        require(assets <= self.pool.balances.collateralAsset.locked, IErrors.InsufficientLiquidity(self.pool.balances.collateralAsset.locked, assets));

        // Update balances and transfer tokens
        _swap(self.pool.balances, referenceAssetProvided, swapTokenProvided);
        _afterExercise(self, swapToken, params, swapTokenProvided, referenceAssetProvided, assets, fee);
    }

    function _previewExercise(State storage self, uint256 shares, uint256 compensation, address constraintAdapter) internal view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee, uint256 swapTokenProvided, uint256 referenceAssetProvided) {
        // Either shares or compensation MUST be 0
        if ((shares == 0 && compensation == 0) || (shares != 0 && compensation != 0)) revert IErrors.InvalidParams();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        uint256 _swapRate = _getLatestApplicableRate(self, constraintAdapter);

        // Calculate amounts based on mode (shares > 0 = shares mode, otherwise compensation mode)
        // we need to provide swap token = compensation x swapRate
        // or we need to provide compensation = swap token / swapRate
        swapTokenProvided = shares > 0 ? shares : MathHelper.calculateEqualSwapAmount(TransferHelper.tokenNativeDecimalsToFixed(compensation, self.referenceDecimals), _swapRate);
        referenceAssetProvided = shares > 0 ? TransferHelper.fixedToTokenNativeDecimals(MathHelper.calculateDepositAmountWithSwapRate(swapTokenProvided, _swapRate, true), self.referenceDecimals) : compensation;

        // Calculate collateral asset output (same calculation for both modes)
        uint256 assetsBeforeFee = TransferHelper.fixedToTokenNativeDecimals(swapTokenProvided, self.collateralDecimals);

        // Other asset spent is the non-primary asset (reference asset in shares mode, CST in compensation mode)
        otherAssetSpent = shares > 0 ? referenceAssetProvided : swapTokenProvided;

        // Calculate fee and final assets
        fee = MathHelper.calculatePercentageFee(self.pool.baseRedemptionFeePercentage, assetsBeforeFee);
        assets = assetsBeforeFee - fee;
    }

    /// @notice return the next depeg swap expiry
    function nextExpiry(State storage self) external view returns (uint256 expiry) {
        SwapToken storage swapToken = self.swapToken;

        expiry = PoolShare(swapToken._address).expiry();
    }

    function _calcSwapAmount(State storage self, uint256 amount, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        accruedReferenceAsset = MathHelper.calculateAccrued(amount, availableReferenceAsset, totalPrincipalTokenIssued);
        accruedCollateralAsset = MathHelper.calculateAccrued(amount, availableCollateralAsset, totalPrincipalTokenIssued);
    }

    function _beforePrincipalTokenSwap(State storage self, SwapToken storage swapToken, uint256 amount, uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) internal {
        swapToken.withdrawn += amount;
        self.pool.poolArchive.referenceAssetAccrued -= accruedReferenceAsset;
        self.pool.poolArchive.collateralAssetAccrued -= accruedCollateralAsset;
    }

    function _afterPrincipalTokenSwap(State storage self, SwapToken storage swapToken, address sender, address owner, address receiver, uint256 withdrawnAmount, uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) internal {
        PoolShare(swapToken.principalToken).transferFrom(sender, owner, address(this), withdrawnAmount);
        ERC20Burnable(swapToken.principalToken).burn(withdrawnAmount);
        IERC20(self.info.referenceAsset).safeTransfer(receiver, accruedReferenceAsset);
        IERC20(self.info.collateralAsset).safeTransfer(receiver, accruedCollateralAsset);
    }

    function _redeem(State storage self, SwapToken storage swapToken, address sender, address owner, address receiver, uint256 amount) internal returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        // Calculate minimum shares to avoid rounding issues for low decimal tokens
        uint256 minimumShares = 0;

        // Use the asset with the lowest decimals to calculate minimum shares
        uint8 lowestDecimals = self.collateralDecimals < self.referenceDecimals ? self.collateralDecimals : self.referenceDecimals;
        if (lowestDecimals < 18) minimumShares = 10 ** (18 - lowestDecimals);

        // Ensure the input amount is at least the minimum required
        if (amount < minimumShares) revert IErrors.InsufficientSharesAmount(minimumShares, amount);

        CorkPoolPoolArchive storage archive = self.pool.poolArchive;

        (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, IERC20(swapToken.principalToken).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        // Ensure we're not returning 0 assets for a non-zero shares input
        if ((accruedReferenceAsset == 0 && accruedCollateralAsset == 0) && amount > 0) revert IErrors.ZeroOutput();

        _beforePrincipalTokenSwap(self, swapToken, amount, accruedReferenceAsset, accruedCollateralAsset);

        _afterPrincipalTokenSwap(self, swapToken, sender, owner, receiver, amount, accruedReferenceAsset, accruedCollateralAsset);
    }

    function redeem(State storage self, uint256 amount, address owner, address receiver, address sender) public returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        require(amount != 0, IErrors.InvalidAmount());

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);
        _separateLiquidity(self);

        return _redeem(self, swapToken, sender, owner, receiver, amount);
    }

    function updateBaseRedemptionFeePercentage(State storage self, uint256 newFees) external {
        require(newFees <= MAX_ALLOWED_FEES, IErrors.InvalidFees());
        self.pool.baseRedemptionFeePercentage = newFees;
    }

    function previewUnwindSwap(State storage self, uint256 amount, address constraintAdapter) public view returns (uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 _swapRate, SwapToken storage swapToken) {
        swapToken = self.swapToken;
        if (amount == 0) return (0, 0, self.pool.unwindSwapFeePercentage, 0, 0, swapToken);

        Guard.safeBeforeExpired(swapToken);

        _swapRate = _getLatestApplicableRate(self, constraintAdapter);

        feePercentage = self.pool.unwindSwapFeePercentage;

        // the fee is taken directly from Collateral Asset before it's even converted to Swap Token
        {
            PoolShare _swapToken = PoolShare(swapToken._address);
            fee = MathHelper.calculateTimeDecayFee(_swapToken.issuedAt(), _swapToken.expiry(), block.timestamp, amount, feePercentage);
        }

        amount = amount - fee;
        amount = TransferHelper.tokenNativeDecimalsToFixed(amount, self.collateralDecimals);

        // we use deposit here because technically the user deposit Collateral Asset to the Cork Pool when unwinding, except with swap rate applied
        receivedReferenceAsset = MathHelper.calculateDepositAmountWithSwapRate(amount, _swapRate, false);
        receivedReferenceAsset = TransferHelper.fixedToTokenNativeDecimals(receivedReferenceAsset, self.referenceDecimals);
        receivedSwapToken = amount;

        require(receivedReferenceAsset <= self.pool.balances.referenceAssetBalance, IErrors.InsufficientLiquidity(self.pool.balances.referenceAssetBalance, receivedReferenceAsset));

        require(receivedSwapToken <= self.pool.balances.swapTokenBalance, IErrors.InsufficientLiquidity(amount, self.pool.balances.swapTokenBalance));
    }

    function previewSwap(State storage self, uint256 assets, address constraintAdapter) public view returns (uint256 sharesOut, uint256 compensation, uint256 fee) {
        SwapToken storage _swapToken = self.swapToken;
        Guard.safeBeforeExpired(_swapToken);

        uint256 exchangeRates = _getLatestApplicableRate(self, constraintAdapter);

        // Calculate gross collateral amount needed before fee deduction
        uint256 assetsFixed = TransferHelper.tokenNativeDecimalsToFixed(assets, self.collateralDecimals);
        uint256 grossCollateralAsset = MathHelper.calculateGrossAmountBeforeFee(assetsFixed, self.pool.baseRedemptionFeePercentage);

        // Convert gross collateral to fixed decimals to get CST shares needed
        sharesOut = grossCollateralAsset;
        // fee in collateral assets. we basically mark up how much shares and compensation user should provide us in exchange for exact amount they requested.
        // but in reality there's a leftover collateral that hasn't been distributed
        // imagine : rate = 1, fee = 5%
        // 1. user provide ~1.052 shares and compensation with exact amount = 1
        // 2. user should get ~1.052 collateral but they get 1. ~0.52 collateral assets goes to treasury!
        fee = TransferHelper.fixedToTokenNativeDecimals(grossCollateralAsset - assetsFixed, self.collateralDecimals);

        // Calculate required reference asset using exchange rate (in fixed decimals)
        uint256 compensationFixed = MathHelper.calculateDepositAmountWithSwapRate(sharesOut, exchangeRates, false);
        compensation = TransferHelper.fixedToTokenNativeDecimals(compensationFixed, self.referenceDecimals);
    }

    function previewRedeem(State storage self, uint256 amount) public view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        require(amount != 0, IErrors.InvalidAmount());

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);

        // Calculate minimum shares to avoid rounding issues for low decimal tokens
        uint8 collateralDecimals = IERC20Metadata(self.info.collateralAsset).decimals();
        uint8 referenceDecimals = IERC20Metadata(self.info.referenceAsset).decimals();
        uint256 minimumShares = 0;

        // Use the asset with the lowest decimals to calculate minimum shares
        uint8 lowestDecimals = collateralDecimals < referenceDecimals ? collateralDecimals : referenceDecimals;
        if (lowestDecimals < 18) minimumShares = 10 ** (18 - lowestDecimals);

        // Check if amount is less than minimum shares
        if (amount < minimumShares) return (0, 0); // Return 0 for preview to indicate it's below minimum

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            // This simulates what _separateLiquidity would do
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, IERC20(swapToken.principalToken).totalSupply(), availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, IERC20(swapToken.principalToken).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }
    }

    function _calcWithdrawAmount(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal view returns (uint256 sharesIn) {
        // Calculate required shares based on which asset is being withdrawn
        if (collateralAssetOut > 0) sharesIn = MathHelper.calculateSharesNeeded(collateralAssetOut, availableCollateralAsset, totalPrincipalTokenIssued);
        else sharesIn = MathHelper.calculateSharesNeeded(referenceAssetOut, availableReferenceAsset, totalPrincipalTokenIssued);
    }

    function previewWithdraw(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut) external view returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        // Either collateralAssetOut or referenceAssetOut must be zero, but not both
        if ((collateralAssetOut == 0 && referenceAssetOut == 0) || (collateralAssetOut != 0 && referenceAssetOut != 0)) revert IErrors.InvalidAmount();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;

            sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, IERC20(swapToken.principalToken).totalSupply(), availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, IERC20(swapToken.principalToken).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }

        (actualReferenceAssetOut,) = previewRedeem(self, sharesIn);
    }

    function withdraw(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut, address owner, address receiver, address sender) external returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) {
        // Either collateralAssetOut or referenceAssetOut must be zero, but not both
        if ((collateralAssetOut == 0 && referenceAssetOut == 0) || (collateralAssetOut != 0 && referenceAssetOut != 0)) revert IErrors.InvalidParams();

        SwapToken storage swapToken = self.swapToken;
        Guard.safeAfterExpired(swapToken);
        _separateLiquidity(self);

        // Calculate required shares
        CorkPoolPoolArchive storage archive = self.pool.poolArchive;

        require(collateralAssetOut <= archive.collateralAssetAccrued, IErrors.InsufficientLiquidity(archive.collateralAssetAccrued, collateralAssetOut));
        require(referenceAssetOut <= archive.referenceAssetAccrued, IErrors.InsufficientLiquidity(archive.referenceAssetAccrued, referenceAssetOut));

        sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, IERC20(swapToken.principalToken).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);

        // Use the existing redeem function to do the actual withdrawal
        (actualReferenceAssetOut, actualCollateralAssetOut) = _redeem(self, swapToken, sender, owner, receiver, sharesIn);

        // Validate that the actual output matches the requested output for the non-zero asset
        require(collateralAssetOut == 0 || actualCollateralAssetOut >= collateralAssetOut, IErrors.InvalidWithdrawAmount(collateralAssetOut, actualCollateralAssetOut));
        require(referenceAssetOut == 0 || actualReferenceAssetOut >= referenceAssetOut, IErrors.InvalidWithdrawAmount(referenceAssetOut, actualReferenceAssetOut));
    }

    function maxExercise(State storage self, address owner) external view returns (uint256 shares) {
        SwapToken storage swapToken = self.swapToken;

        // Check if before expiry (exercise only works before expiry)
        if (!isInitialized(self)) return 0;
        if (PoolShare(swapToken._address).isExpired()) return 0;

        // Get owner's CST balance
        uint256 ownerCstBalance = IERC20(swapToken._address).balanceOf(owner);
        if (ownerCstBalance == 0) return 0;

        // Calculate how much collateral asset the user can get with their CST shares
        uint256 collateralAssetOut = TransferHelper.fixedToTokenNativeDecimals(ownerCstBalance, self.collateralDecimals);

        // Apply fee to get the actual collateral they would receive
        uint256 fee = MathHelper.calculatePercentageFee(self.pool.baseRedemptionFeePercentage, collateralAssetOut);
        uint256 actualCollateralOut = collateralAssetOut - fee;

        // Check if enough collateral asset is available - this should always be true due to core invariants
        uint256 availableCollateral = self.pool.balances.collateralAsset.locked;
        require(actualCollateralOut <= availableCollateral, IErrors.InsufficientLiquidity(availableCollateral, actualCollateralOut)); // Core invariant: should always have enough collateral

        return ownerCstBalance;
    }

    function swap(State storage self, uint256 assets, address receiver, address sender, address owner, address treasury, address constraintAdapter) external returns (uint256 shares, uint256 compensation) {
        SwapParams memory params = SwapParams({sender: sender, owner: owner, receiver: receiver, assets: assets, treasury: treasury});

        return _swapInternal(self, params, constraintAdapter);
    }

    function _swapInternal(State storage self, SwapParams memory params, address constraintAdapter) internal returns (uint256 shares, uint256 compensation) {
        require(params.assets != 0, IErrors.InvalidAmount());

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        // Update exchange rate before calculations
        _getLatestApplicableRateAndUpdate(self, constraintAdapter);

        uint256 fee;
        // Use previewSwap to calculate required shares and compensation (includes fees)
        (shares, compensation, fee) = previewSwap(self, params.assets, constraintAdapter);

        require(params.assets <= self.pool.balances.collateralAsset.locked, IErrors.InsufficientLiquidity(self.pool.balances.collateralAsset.locked, params.assets));

        PoolShare(swapToken._address).transferFrom(params.sender, params.owner, address(this), shares);
        IERC20(self.info.referenceAsset).safeTransferFrom(params.owner, address(this), compensation);

        _swap(self.pool.balances, compensation, shares);

        self.pool.balances.collateralAsset.unlockTo(params.receiver, params.assets);

        // Transfer fee to treasury
        if (fee != 0) self.pool.balances.collateralAsset.unlockTo(params.treasury, fee);
    }

    function previewUnwindExercise(State storage self, uint256 shares, address constraintAdapter) public view returns (uint256 assetIn, uint256 compensationOut, uint256 fee) {
        require(shares != 0, IErrors.InvalidAmount());

        SwapToken storage swapToken = self.swapToken;
        Guard.safeBeforeExpired(swapToken);

        uint256 _swapRate = _getLatestApplicableRate(self, constraintAdapter);

        // Calculate compensation based on shares and swap rate
        uint256 compensationFixed = MathHelper.calculateDepositAmountWithSwapRate(shares, _swapRate, false);
        compensationOut = TransferHelper.fixedToTokenNativeDecimals(compensationFixed, self.referenceDecimals);

        {
            PoolShare _swapToken = PoolShare(swapToken._address);
            (fee, assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(_swapToken.issuedAt(), _swapToken.expiry(), block.timestamp, shares, self.pool.unwindSwapFeePercentage);
        }

        assetIn = TransferHelper.fixedToTokenNativeDecimals(assetIn, self.collateralDecimals);
        fee = TransferHelper.fixedToTokenNativeDecimals(fee, self.collateralDecimals);
    }

    function maxUnwindExercise(State storage self, address, address constraintAdapter) external view returns (uint256 shares) {
        SwapToken storage swapToken = self.swapToken;

        // Check if before expiry (unwindExercise only works before expiry)
        if (PoolShare(swapToken._address).isExpired()) return 0;

        // The maximum shares is limited by the available CST balance in the pool
        uint256 availableCstBalance = self.pool.balances.swapTokenBalance;
        if (availableCstBalance == 0) return 0;

        // Also limited by available reference asset balance for compensation
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        if (availableReferenceAsset == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(self, constraintAdapter);
        if (_swapRate == 0) return 0;

        // Convert available reference asset to fixed decimals
        uint256 availableReferenceAssetFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.referenceDecimals);

        // Calculate max shares based on reference asset limit
        uint256 maxSharesByReferenceAsset = MathHelper.calculateDepositAmountWithSwapRate(availableReferenceAssetFixed, _swapRate, false);

        // The actual maximum is the minimum of the two constraints
        shares = availableCstBalance < maxSharesByReferenceAsset ? availableCstBalance : maxSharesByReferenceAsset;

        return shares;
    }

    function maxSwap(State storage self, address owner, address constraintAdapter) external view returns (uint256 assets) {
        SwapToken storage swapToken = self.swapToken;

        if (!isInitialized(self)) return 0;
        if (PoolShare(swapToken._address).isExpired()) return 0;
        if (self.pool.isSwapPaused) return 0;

        // Get owner's CST and reference asset balances
        uint256 ownerCstBalance = IERC20(swapToken._address).balanceOf(owner);
        uint256 ownerReferenceBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        // Must have both CST shares and reference assets to swap
        if (ownerCstBalance == 0 || ownerReferenceBalance == 0) return 0;

        // Calculate the maximum CST shares we can use based on available reference assets
        uint256 otherAssetSpent;
        (assets, otherAssetSpent,) = previewExercise(self, 0, ownerReferenceBalance, constraintAdapter);
        uint256 effectiveShares = ownerCstBalance < otherAssetSpent ? ownerCstBalance : otherAssetSpent;

        // If no effective shares, can't swap
        if (effectiveShares == 0) return 0;

        (assets,,) = previewExercise(self, effectiveShares, 0, constraintAdapter);
    }

    function unwindExercise(State storage self, uint256 shares, address receiver, uint256 minCompensationOut, uint256 maxAssetIn, address sender, address treasury, address constraintAdapter) external returns (uint256 assetIn, uint256 compensationOut) {
        SwapToken storage swapToken = self.swapToken;

        // Update swap rate before preview
        _getLatestApplicableRateAndUpdate(self, constraintAdapter);

        uint256 fee;
        // Use previewUnwindExercise to get all calculated amounts
        (assetIn, compensationOut, fee) = previewUnwindExercise(self, shares, constraintAdapter);

        require(compensationOut >= minCompensationOut, IErrors.InsufficientOutputAmount(minCompensationOut, compensationOut));
        require(assetIn <= maxAssetIn, IErrors.ExceedInput(assetIn, maxAssetIn));

        // Check sufficient liquidity
        require(compensationOut <= self.pool.balances.referenceAssetBalance, IErrors.InsufficientLiquidity(self.pool.balances.referenceAssetBalance, compensationOut));
        require(shares <= self.pool.balances.swapTokenBalance, IErrors.InsufficientLiquidity(self.pool.balances.swapTokenBalance, shares));

        // Transfer collateral asset from sender
        self.pool.balances.collateralAsset.lockFrom(assetIn, sender);

        // Transfer collateral asset fees to treasury
        self.pool.balances.collateralAsset.unlockTo(treasury, fee);

        // Decrease pool balances (opposite of unwindSwap)
        self.pool.balances.referenceAssetBalance -= compensationOut;
        self.pool.balances.swapTokenBalance -= shares;

        // Transfer unlocked tokens to receiver
        (, address referenceAsset) = self.info.underlyingAsset();
        IERC20(referenceAsset).safeTransfer(receiver, compensationOut);
        IERC20(swapToken._address).safeTransfer(receiver, shares);
    }

    function maxUnwindSwap(State storage self, address, address constraintAdapter) external view returns (uint256 amount) {
        SwapToken storage swapToken = self.swapToken;

        if (!isInitialized(self)) return 0;
        if (PoolShare(swapToken._address).isExpired()) return 0;
        if (self.pool.isUnwindSwapPaused) return 0;

        // Get available reference asset and swap token balances in the pool
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        uint256 availableSwapToken = self.pool.balances.swapTokenBalance;

        // If no available assets to unwind swap, return 0
        if (availableReferenceAsset == 0 || availableSwapToken == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(self, constraintAdapter);
        if (_swapRate == 0) return 0;

        uint256 maxNetAmount;

        {
            // Calculate maximum net amounts based on pool constraints
            // Convert available reference asset to fixed decimals
            uint256 availableReferenceAssetFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.referenceDecimals);

            // Calculate max net amount based on reference asset limit
            // receivedReferenceAsset = MathHelper.calculateDepositAmountWithSwapRate(netAmountFixed, _swapRate)
            // So: netAmountFixed = receivedReferenceAsset * _swapRate
            uint256 maxNetFromReferenceAsset = MathHelper.calculateEqualSwapAmount(availableReferenceAssetFixed, _swapRate);

            // Calculate max net amount based on swap token limit (1:1 in fixed decimals)
            uint256 maxNetFromSwapToken = availableSwapToken;

            // Take the minimum of the two constraints
            uint256 maxNetAmountFixed = maxNetFromReferenceAsset < maxNetFromSwapToken ? maxNetFromReferenceAsset : maxNetFromSwapToken;

            // Convert to collateral asset decimals
            maxNetAmount = TransferHelper.fixedToTokenNativeDecimals(maxNetAmountFixed, self.collateralDecimals);
        }

        // Use the inverse calculation from MathHelper.calculateGrossAmountWithTimeDecayFee
        // The fee function calculates: grossAmount = netAmount / (1 - effectiveFeeRate)
        (, amount) = MathHelper.calculateGrossAmountWithTimeDecayFee(PoolShare(swapToken._address).issuedAt(), PoolShare(swapToken._address).expiry(), block.timestamp, maxNetAmount, self.pool.unwindSwapFeePercentage);
    }
}
