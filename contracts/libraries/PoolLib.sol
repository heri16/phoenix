// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ConstraintAdapter} from "./../core/ConstraintAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Guard} from "contracts/libraries/Guard.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {Balances, CollateralAssetManager, CorkPoolPoolArchive, Shares, State} from "contracts/libraries/State.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title CorkPool Library Contract
 * @author Cork Team
 * @notice CorkPool Library implements functions for Cork Pool Core contract
 */
library PoolLibrary {
    using SafeERC20 for IERC20;

    /**
     *   This denotes maximum fee allowed in contract
     *   Here 1 ether = 1e18 so maximum 5% fee allowed
     */
    uint256 internal constant MAX_ALLOWED_FEES = 5 ether;

    ///======================================================///
    ///================ INITIALIZATION FUNCTIONS ============///
    ///======================================================///

    function initialize(State storage self, MarketId poolId, Market calldata market, address constraintAdapter) external {
        self.info = market;
        self.pool.balances.collateralAsset = CollateralAssetManager({_address: market.collateralAsset, locked: 0});

        ConstraintAdapter(constraintAdapter).bootstrap(poolId);
    }

    ///======================================================///
    ///================ PREVIEW FUNCTIONS ===================///
    ///======================================================///

    function previewRedeem(State storage self, uint256 amount) public view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        if (!_isExpired(self)) return (0, 0);
        if (amount == 0) return (0, 0);

        Shares storage tokens = self.shares;

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

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, IERC20(tokens.principal).totalSupply(), availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(self, amount, IERC20(tokens.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }
    }

    function previewWithdraw(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut) external view returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        // Either collateralAssetOut or referenceAssetOut must be zero, but not both
        if ((collateralAssetOut == 0 && referenceAssetOut == 0) || (collateralAssetOut != 0 && referenceAssetOut != 0)) revert IErrors.InvalidAmount();
        if (!_isExpired(self)) return (0, 0);

        Shares storage tokens = self.shares;

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;

            sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, IERC20(tokens.principal).totalSupply(), availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            sharesIn = _calcWithdrawAmount(self, collateralAssetOut, referenceAssetOut, IERC20(tokens.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }

        (actualReferenceAssetOut,) = previewRedeem(self, sharesIn);
    }

    function availableForUnwindSwap(State storage self) external view returns (uint256 referenceAsset, uint256 shares) {
        Shares storage _swapToken = self.shares;
        Guard.safeBeforeExpired(_swapToken);

        referenceAsset = self.pool.balances.referenceAssetBalance;
        shares = self.pool.balances.swapTokenBalance;
    }

    function previewExercise(State storage self, MarketId poolId, uint256 shares, uint256 compensation, address constraintAdapter) internal view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee, uint256 swapTokenProvided, uint256 referenceAssetProvided) {
        // Either shares or compensation MUST be 0
        if ((shares == 0 && compensation == 0) || (shares != 0 && compensation != 0)) return (0, 0, 0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0, 0, 0);

        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintAdapter);

        // Calculate amounts based on mode (shares > 0 = shares mode, otherwise compensation mode)
        // we need to provide swap token = compensation x swapRate
        // or we need to provide compensation = swap token / swapRate
        swapTokenProvided = shares > 0 ? shares : MathHelper.calculateEqualSwapAmount(TransferHelper.tokenNativeDecimalsToFixed(compensation, self.referenceDecimals), _swapRate);
        referenceAssetProvided = shares > 0 ? TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(MathHelper.calculateDepositAmountWithSwapRate(swapTokenProvided, _swapRate, true), self.referenceDecimals) : compensation;

        // Calculate collateral asset output (same calculation for both modes)
        uint256 assetsBeforeFee = TransferHelper.fixedToTokenNativeDecimals(swapTokenProvided, self.collateralDecimals);

        // Other asset spent is the non-primary asset (reference asset in shares mode, CST in compensation mode)
        otherAssetSpent = shares > 0 ? referenceAssetProvided : swapTokenProvided;

        // Calculate fee and final assets
        fee = MathHelper.calculatePercentageFee(self.pool.baseRedemptionFeePercentage, assetsBeforeFee);
        assets = assetsBeforeFee - fee;
    }

    function previewSwap(State storage self, MarketId poolId, uint256 assets, address constraintAdapter) public view returns (uint256 sharesOut, uint256 compensation, uint256 fee) {
        if (assets == 0) return (0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0);

        uint256 exchangeRates = _getLatestApplicableRate(poolId, constraintAdapter);

        // Calculate gross collateral amount needed before fee deduction
        uint256 grossCollateralAsset = MathHelper.calculateGrossAmountBeforeFee(assets, self.pool.baseRedemptionFeePercentage);

        // Convert gross collateral to fixed decimals to get CST shares needed
        sharesOut = TransferHelper.tokenNativeDecimalsToFixed(grossCollateralAsset, self.collateralDecimals);
        // fee in collateral assets. we basically mark up how much shares and compensation user should provide us in exchange for exact amount they requested.
        // but in reality there's a leftover collateral that hasn't been distributed
        // imagine : rate = 1, fee = 5%
        // 1. user provide ~1.052 shares and compensation with exact amount = 1
        // 2. user should get ~1.052 collateral but they get 1. ~0.052 collateral assets goes to treasury!
        fee = grossCollateralAsset - assets;

        // Calculate required reference asset using exchange rate (in fixed decimals)
        uint256 compensationFixed = MathHelper.calculateDepositAmountWithSwapRate(sharesOut, exchangeRates, true);
        compensation = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(compensationFixed, self.referenceDecimals);
    }

    function previewUnwindSwap(State storage self, MarketId poolId, uint256 amount, address constraintAdapter) public view returns (IUnwindSwap.UnwindSwapReturnParams memory returnParams) {
        Shares storage tokens = self.shares;

        if (amount == 0) {
            returnParams.feePercentage = self.pool.unwindSwapFeePercentage;
            return returnParams;
        }
        if (_isExpired(self)) return returnParams;

        returnParams.swapRate = _getLatestApplicableRate(poolId, constraintAdapter);

        returnParams.feePercentage = self.pool.unwindSwapFeePercentage;

        // the fee is taken directly from Collateral Asset before it's even converted to Swap Token
        {
            PoolShare _swapToken = PoolShare(tokens.swap);
            returnParams.fee = MathHelper.calculateTimeDecayFee(_swapToken.issuedAt(), _swapToken.expiry(), block.timestamp, amount, returnParams.feePercentage);
        }

        amount = amount - returnParams.fee;
        amount = TransferHelper.tokenNativeDecimalsToFixed(amount, self.collateralDecimals);

        // we use deposit here because technically the user deposit Collateral Asset to the Cork Pool when unwinding, except with swap rate applied
        returnParams.receivedReferenceAsset = MathHelper.calculateDepositAmountWithSwapRate(amount, returnParams.swapRate, false);
        returnParams.receivedReferenceAsset = TransferHelper.fixedToTokenNativeDecimals(returnParams.receivedReferenceAsset, self.referenceDecimals);
        returnParams.receivedSwapToken = amount;

        require(returnParams.receivedReferenceAsset <= self.pool.balances.referenceAssetBalance, IErrors.InsufficientLiquidity(self.pool.balances.referenceAssetBalance, returnParams.receivedReferenceAsset));

        require(returnParams.receivedSwapToken <= self.pool.balances.swapTokenBalance, IErrors.InsufficientLiquidity(amount, self.pool.balances.swapTokenBalance));
    }

    function previewUnwindExercise(State storage self, MarketId poolId, uint256 shares, address constraintAdapter) public view returns (uint256 assetIn, uint256 compensationOut, uint256 fee) {
        if (_isExpired(self)) return (0, 0, 0);

        Shares storage tokens = self.shares;

        {
            uint256 _swapRate = _getLatestApplicableRate(poolId, constraintAdapter);

            // Calculate compensation based on shares and swap rate
            uint256 compensationFixed = MathHelper.calculateDepositAmountWithSwapRate(shares, _swapRate, false);
            compensationOut = TransferHelper.fixedToTokenNativeDecimals(compensationFixed, self.referenceDecimals);
        }

        uint256 assetInWithoutFee = TransferHelper.fixedToTokenNativeDecimals(shares, self.collateralDecimals);

        {
            PoolShare _swapToken = PoolShare(tokens.swap);
            (fee, assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(_swapToken.issuedAt(), _swapToken.expiry(), block.timestamp, assetInWithoutFee, self.pool.unwindSwapFeePercentage);
        }
    }

    ///======================================================///
    ///================= MAX FUNCTIONS ======================///
    ///======================================================///

    function maxExercise(State storage self, address owner) external view returns (uint256 shares) {
        Shares storage tokens = self.shares;

        // Check if before expiry (exercise only works before expiry)
        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;

        // Get owner's CST balance
        uint256 ownerCstBalance = IERC20(tokens.swap).balanceOf(owner);
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

    function maxExerciseOther(State storage self, MarketId poolId, address owner, address constraintAdapter) external view returns (uint256 references) {
        Shares storage tokens = self.shares;

        // Check if before expiry (exercise only works before expiry)
        if (!isInitialized(self)) return 0;
        if (PoolShare(tokens.swap).isExpired()) return 0;

        uint256 ownerCstBalance = IERC20(tokens.swap).balanceOf(owner);
        uint256 ownerRefBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        if (ownerCstBalance == 0) return 0;

        uint8 refDecimals = IERC20Metadata(self.info.referenceAsset).decimals();
        uint8 collateralDecimals = IERC20Metadata(self.info.collateralAsset).decimals();

        // maxRef = pool collateral balance / rate
        // we need to cast the collateral to ref decimals. this will determine the upperbound of the accepted reference asset
        uint256 maxRefAccepted = TransferHelper.normalizeDecimals(self.pool.balances.collateralAsset.locked, collateralDecimals, refDecimals) * 1e18 / _getLatestApplicableRate(poolId, constraintAdapter);

        references = ownerRefBalance < maxRefAccepted ? ownerRefBalance : maxRefAccepted;

        (, uint256 cstSpent,,,) = previewExercise(self, poolId, 0, references, constraintAdapter);

        // owner have enough cst to cover the whole cost, return
        if (cstSpent < ownerCstBalance) return references;
        // find the optimal reference asset amount
        else (, references,,,) = previewExercise(self, poolId, ownerCstBalance, 0, constraintAdapter);
    }

    function maxUnwindExercise(State storage self, MarketId poolId, address constraintAdapter) external view returns (uint256 shares) {
        Shares storage tokens = self.shares;

        // Check if before expiry (unwindExercise only works before expiry)
        if (_isExpired(self)) return 0;

        // The maximum shares is limited by the available CST balance in the pool
        uint256 availableCstBalance = self.pool.balances.swapTokenBalance;
        if (availableCstBalance == 0) return 0;

        // Also limited by available reference asset balance for compensation
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        if (availableReferenceAsset == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintAdapter);
        if (_swapRate == 0) return 0;

        return availableCstBalance;
    }

    function maxUnwindExerciseOther(State storage self, MarketId poolId, address constraintAdapter) external view returns (uint256 referenceAssets) {
        Shares storage tokens = self.shares;

        // Check if before expiry (unwindExercise only works before expiry)
        if (PoolShare(tokens.swap).isExpired()) return 0;

        // The maximum reference assets is limited by the available reference asset balance in the pool
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        if (availableReferenceAsset == 0) return 0;

        // Also limited by available CST balance
        uint256 availableCstBalance = self.pool.balances.swapTokenBalance;
        if (availableCstBalance == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintAdapter);
        if (_swapRate == 0) return 0;

        return availableReferenceAsset;
    }

    function maxSwap(State storage self, MarketId poolId, address owner, address constraintAdapter) external view returns (uint256 assets) {
        Shares storage tokens = self.shares;

        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;
        if (self.pool.isSwapPaused) return 0;

        // Get owner's CST and reference asset balances
        uint256 ownerCstBalance = IERC20(tokens.swap).balanceOf(owner);
        uint256 ownerReferenceBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        // Must have both CST shares and reference assets to swap
        if (ownerCstBalance == 0 || ownerReferenceBalance == 0) return 0;

        // Calculate the maximum CST shares we can use based on available reference assets
        uint256 otherAssetSpent;
        (assets, otherAssetSpent,,,) = previewExercise(self, poolId, 0, ownerReferenceBalance, constraintAdapter);
        uint256 effectiveShares = ownerCstBalance < otherAssetSpent ? ownerCstBalance : otherAssetSpent;

        // If no effective shares, can't swap
        if (effectiveShares == 0) return 0;

        (assets,,,,) = previewExercise(self, poolId, effectiveShares, 0, constraintAdapter);
    }

    function maxUnwindSwap(State storage self, MarketId poolId, address constraintAdapter) external view returns (uint256 amount) {
        Shares storage tokens = self.shares;

        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;
        if (self.pool.isUnwindSwapPaused) return 0;

        // Get available reference asset and swap token balances in the pool
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        uint256 availableSwapToken = self.pool.balances.swapTokenBalance;

        // If no available assets to unwind swap, return 0
        if (availableReferenceAsset == 0 || availableSwapToken == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintAdapter);
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
        (, amount) = MathHelper.calculateGrossAmountWithTimeDecayFee(PoolShare(tokens.swap).issuedAt(), PoolShare(tokens.swap).expiry(), block.timestamp, maxNetAmount, self.pool.unwindSwapFeePercentage);
    }

    ///======================================================///
    ///============= RATE & FEE RELATED FUNCTIONS ===========///
    ///======================================================///

    function updateBaseRedemptionFeePercentage(State storage self, uint256 newFees) external {
        require(newFees <= MAX_ALLOWED_FEES, IErrors.InvalidFees());
        self.pool.baseRedemptionFeePercentage = newFees;
    }

    function unwindSwapRate(State storage self, MarketId poolId, address constraintAdapter) external view returns (uint256 rate) {
        Shares storage tokens = self.shares;
        Guard.safeBeforeExpired(tokens);

        rate = _getLatestApplicableRate(poolId, constraintAdapter);
    }

    function unwindSwapFeePercentage(State storage self) external view returns (uint256 rate) {
        rate = self.pool.unwindSwapFeePercentage;
    }

    function updateUnwindSwapFeePercentage(State storage self, uint256 newFees) external {
        require(newFees <= MAX_ALLOWED_FEES, IErrors.InvalidFees());
        self.pool.unwindSwapFeePercentage = newFees;
    }

    ///======================================================///
    ///================== VIEW FUNCTIONS ====================///
    ///======================================================///

    /// @notice return the next depeg swap expiry
    function nextExpiry(State storage self) external view returns (uint256 expiry) {
        Shares storage tokens = self.shares;

        expiry = PoolShare(tokens.swap).expiry();
    }

    function isInitialized(State storage self) public view returns (bool status) {
        status = self.info.referenceAsset != address(0) && self.info.collateralAsset != address(0);
    }

    function valueLocked(State storage self, bool collateralAsset) external view returns (uint256) {
        if (collateralAsset) return self.pool.balances.collateralAsset.locked + self.pool.poolArchive.collateralAssetAccrued;
        else return self.pool.balances.referenceAssetBalance + self.pool.poolArchive.referenceAssetAccrued;
    }

    function swapRate(State storage self, MarketId poolId, address constraintAdapter) external view returns (uint256 rate) {
        rate = _getLatestApplicableRate(poolId, constraintAdapter);
    }

    ///======================================================///
    ///============== INTERNAL UTILITY FUNCTIONS ============///
    ///======================================================///

    function _getLatestApplicableRate(MarketId poolId, address constraintAdapter) internal view returns (uint256 rate) {
        return ConstraintAdapter(constraintAdapter).previewAdjustedRate(poolId);
    }

    // fetch and update the swap rate.
    function _getLatestApplicableRateAndUpdate(State storage self, MarketId poolId, address constraintAdapter) internal returns (uint256 rate) {
        rate = ConstraintAdapter(constraintAdapter).adjustedRate(poolId);
    }

    function _isExpired(State storage self) internal view returns (bool) {
        return block.timestamp >= self.info.expiryTimestamp;
    }

    function _calcWithdrawAmount(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal view returns (uint256 sharesIn) {
        // Calculate required shares based on which asset is being withdrawn
        if (collateralAssetOut > 0) sharesIn = MathHelper.calculateSharesNeeded(collateralAssetOut, availableCollateralAsset, totalPrincipalTokenIssued);
        else sharesIn = MathHelper.calculateSharesNeeded(referenceAssetOut, availableReferenceAsset, totalPrincipalTokenIssued);
    }

    function _calcSwapAmount(State storage self, uint256 amount, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        accruedReferenceAsset = MathHelper.calculateAccrued(amount, availableReferenceAsset, totalPrincipalTokenIssued);
        accruedCollateralAsset = MathHelper.calculateAccrued(amount, availableCollateralAsset, totalPrincipalTokenIssued);
    }
}
