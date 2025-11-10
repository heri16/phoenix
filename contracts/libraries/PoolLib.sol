// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ConstraintRateAdapter} from "./../core/ConstraintRateAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {CollateralAssetManager, CorkPoolPoolArchive, Shares, State} from "contracts/libraries/State.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title CorkPoolManager Library Contract
 * @author Cork Team
 * @notice CorkPoolManager Library implements functions for Cork Pool Core contract
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

    function initialize(State storage self, MarketId poolId, Market calldata market, address constraintRateAdapter) external {
        self.info = market;
        self.pool.balances.collateralAsset = CollateralAssetManager({_address: market.collateralAsset, locked: 0});

        // slither-disable-next-line reentrancy-no-eth
        ConstraintRateAdapter(constraintRateAdapter).bootstrap(poolId);
    }

    ///======================================================///
    ///================ PREVIEW FUNCTIONS ===================///
    ///======================================================///

    function previewRedeem(State storage self, uint256 amount) public view returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        if (!_isExpired(self)) return (0, 0);
        if (amount == 0) return (0, 0);
        if (_isWithdrawalPaused(self)) return (0, 0);

        Shares storage tokens = self.shares;

        // Calculate minimum shares to avoid rounding issues for low decimal tokens
        uint8 collateralDecimals = IERC20Metadata(self.info.collateralAsset).decimals();
        uint8 referenceDecimals = IERC20Metadata(self.info.referenceAsset).decimals();

        // Use the asset with the lowest decimals to calculate minimum shares
        uint8 lowestDecimals = collateralDecimals < referenceDecimals ? collateralDecimals : referenceDecimals;
        uint256 minimumShares = 10 ** (18 - lowestDecimals);

        // Check if amount is less than minimum shares
        if (amount < minimumShares) return (0, 0); // Return 0 for preview to indicate it's below minimum

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            // This simulates what _separateLiquidity would do
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(amount, IERC20(tokens.principal).totalSupply(), availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            (accruedReferenceAsset, accruedCollateralAsset) = _calcSwapAmount(amount, IERC20(tokens.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }
    }

    function previewWithdraw(State storage self, uint256 collateralAssetOut) external view returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) {
        // collateralAssetOut MUST be non-zero
        if (collateralAssetOut == 0) revert IErrors.InvalidAmount();

        return _previewWithdraw(self, collateralAssetOut, 0);
    }

    function previewWithdrawOther(State storage self, uint256 referenceAssetOut) external view returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) {
        // referenceAssetOut MUST be non-zero
        if (referenceAssetOut == 0) revert IErrors.InvalidAmount();

        return _previewWithdraw(self, 0, referenceAssetOut);
    }

    function availableForUnwindSwap(State storage self) external view returns (uint256 referenceAsset, uint256 shares) {
        _safeBeforeExpired(self);

        referenceAsset = self.pool.balances.referenceAssetBalance;
        shares = self.pool.balances.swapTokenBalance;
    }

    function previewExercise(State storage self, MarketId poolId, uint256 shares, address constraintRateAdapter) internal view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee, uint256 swapTokenProvided, uint256 referenceAssetProvided) {
        // shares MUST be non-zero
        // slither-disable-next-line incorrect-equality
        if (shares == 0) return (0, 0, 0, 0, 0);
        if (_isSwapPaused(self)) return (0, 0, 0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0, 0, 0);

        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);

        // Calculate amounts based on shares mode
        // we need to provide compensation = swap token / swapRate
        swapTokenProvided = shares;
        referenceAssetProvided = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(MathHelper.calculateDepositAmountWithSwapRate(swapTokenProvided, _swapRate, true), self.referenceDecimals);

        // Other asset spent is the non-primary asset (reference asset in shares mode, CST in compensation mode)
        otherAssetSpent = referenceAssetProvided;

        (assets, fee) = _getPreviewExerciseFeeAndAssets(self, swapTokenProvided);
    }

    function previewExerciseOther(State storage self, MarketId poolId, uint256 compensation, address constraintRateAdapter) internal view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee, uint256 swapTokenProvided, uint256 referenceAssetProvided) {
        // compensation MUST be non-zero
        // slither-disable-next-line incorrect-equality
        if (compensation == 0) return (0, 0, 0, 0, 0);
        if (_isSwapPaused(self)) return (0, 0, 0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0, 0, 0);

        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);

        // Calculate amounts based on compensation mode
        // we need to provide swap token = compensation x swapRate
        swapTokenProvided = MathHelper.calculateEqualSwapAmount(TransferHelper.tokenNativeDecimalsToFixed(compensation, self.referenceDecimals), _swapRate);
        referenceAssetProvided = compensation;

        // Other asset spent is the non-primary asset (reference asset in shares mode, CST in compensation mode)
        otherAssetSpent = swapTokenProvided;

        (assets, fee) = _getPreviewExerciseFeeAndAssets(self, swapTokenProvided);
    }

    function previewSwap(State storage self, MarketId poolId, uint256 assets, address constraintRateAdapter) public view returns (uint256 sharesOut, uint256 compensation, uint256 fee) {
        if (assets == 0) return (0, 0, 0);
        if (_isSwapPaused(self)) return (0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0);

        uint256 exchangeRates = _getLatestApplicableRate(poolId, constraintRateAdapter);

        // Calculate gross collateral amount needed before fee deduction
        uint256 grossCollateralAsset = MathHelper.calculateGrossAmountBeforeFee(assets, self.pool.swapFeePercentage);

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

    function previewUnwindSwap(State storage self, MarketId poolId, uint256 amount, address constraintRateAdapter) public view returns (uint256 swapAssetOut, uint256 compensationOut, uint256 fee) {
        // slither-disable-next-line incorrect-equality
        if (amount == 0) return (0, 0, 0);
        if (_isUnwindSwapPaused(self)) return (0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0);

        // the fee is taken directly from Collateral Asset before it's even converted to Swap Token
        fee = MathHelper.calculateTimeDecayFee(PoolShare(self.shares.swap).issuedAt(), self.info.expiryTimestamp, block.timestamp, amount, self.pool.unwindSwapFeePercentage);

        amount = amount - fee;
        amount = TransferHelper.tokenNativeDecimalsToFixed(amount, self.collateralDecimals);

        // we use deposit here because technically the user deposit Collateral Asset to the Cork Pool when unwinding, except with swap rate applied
        compensationOut = MathHelper.calculateDepositAmountWithSwapRate(amount, _getLatestApplicableRate(poolId, constraintRateAdapter), false);
        compensationOut = TransferHelper.fixedToTokenNativeDecimals(compensationOut, self.referenceDecimals);
        swapAssetOut = amount;
    }

    function previewUnwindExercise(State storage self, MarketId poolId, uint256 shares, address constraintRateAdapter) public view returns (uint256 assetIn, uint256 fee, uint256 compensationOut) {
        // shares MUST be non-zero
        // slither-disable-next-line incorrect-equality
        if (shares == 0) return (0, 0, 0);
        if (_isUnwindSwapPaused(self)) return (0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0);

        {
            uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);

            compensationOut = TransferHelper.fixedToTokenNativeDecimals(MathHelper.calculateDepositAmountWithSwapRate(shares, _swapRate, false), self.referenceDecimals);
        }

        (assetIn, fee) = _getPreviewUnwindExerciseFeeAndAssets(self, shares);
    }

    function previewUnwindExerciseOther(State storage self, MarketId poolId, uint256 referenceAsset, address constraintRateAdapter) public view returns (uint256 assetIn, uint256 fee, uint256 sharesOut) {
        // referenceAsset MUST be non-zero
        // slither-disable-next-line incorrect-equality
        if (referenceAsset == 0) return (0, 0, 0);
        if (_isUnwindSwapPaused(self)) return (0, 0, 0);
        if (_isExpired(self)) return (0, 0, 0);

        {
            uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);

            sharesOut = MathHelper.calculateEqualSwapAmount(TransferHelper.tokenNativeDecimalsToFixed(referenceAsset, self.referenceDecimals), _swapRate);
        }

        (assetIn, fee) = _getPreviewUnwindExerciseFeeAndAssets(self, sharesOut);
    }

    ///======================================================///
    ///================= MAX FUNCTIONS ======================///
    ///======================================================///

    function maxExercise(State storage self, MarketId poolId, address owner, address constraintRateAdapter) external view returns (uint256 shares) {
        Shares storage tokens = self.shares;

        // Check if before expiry (exercise only works before expiry)
        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;
        if (_isSwapPaused(self)) return 0;

        // Get owner's CST and reference asset balances
        uint256 ownerCstBalance = IERC20(tokens.swap).balanceOf(owner);
        uint256 ownerRefBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        // slither-disable-next-line incorrect-equality
        if (ownerCstBalance == 0 || ownerRefBalance == 0) return 0;

        // Check how much reference asset is required for the CST shares
        (, uint256 referenceAssetRequired,,,) = previewExercise(self, poolId, ownerCstBalance, constraintRateAdapter);

        // If user doesn't have enough reference assets, calculate max shares they can afford
        if (referenceAssetRequired > ownerRefBalance) {
            // Find the max CST shares based on available reference assets
            // We use previewExerciseOther to find how much CST is needed for the available reference assets
            (, uint256 cstNeeded,,,) = previewExerciseOther(self, poolId, ownerRefBalance, constraintRateAdapter);

            shares = cstNeeded < ownerCstBalance ? cstNeeded : ownerCstBalance;
        } else {
            shares = ownerCstBalance;
        }
    }

    function maxExerciseOther(State storage self, MarketId poolId, address owner, address constraintRateAdapter) external view returns (uint256 references) {
        Shares storage tokens = self.shares;

        // Check if before expiry (exercise only works before expiry)
        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;
        if (_isSwapPaused(self)) return 0;

        uint256 ownerCstBalance = IERC20(tokens.swap).balanceOf(owner);
        uint256 ownerRefBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        // slither-disable-next-line incorrect-equality
        if (ownerCstBalance == 0 || ownerRefBalance == 0) return 0;

        uint8 refDecimals = IERC20Metadata(self.info.referenceAsset).decimals();
        uint8 collateralDecimals = IERC20Metadata(self.info.collateralAsset).decimals();

        // maxRef = pool collateral balance / rate
        // we need to cast the collateral to ref decimals. this will determine the upperbound of the accepted reference asset
        uint256 maxRefAccepted = TransferHelper.normalizeDecimals(self.pool.balances.collateralAsset.locked, collateralDecimals, refDecimals) * 1e18 / _getLatestApplicableRate(poolId, constraintRateAdapter);

        references = ownerRefBalance < maxRefAccepted ? ownerRefBalance : maxRefAccepted;

        (, uint256 cstSpent,,,) = previewExerciseOther(self, poolId, references, constraintRateAdapter);

        // owner have enough cst to cover the whole cost, return
        if (cstSpent < ownerCstBalance) return references;
        // find the optimal reference asset amount
        else (, references,,,) = previewExercise(self, poolId, ownerCstBalance, constraintRateAdapter);
    }

    function maxUnwindExercise(State storage self, MarketId poolId, address constraintRateAdapter) external view returns (uint256 shares) {
        // Check if before expiry (unwindExercise only works before expiry)
        if (_isExpired(self)) return 0;
        if (_isUnwindSwapPaused(self)) return 0;

        // The maximum shares is limited by the available CST balance in the pool
        uint256 availableCstBalance = self.pool.balances.swapTokenBalance;
        if (availableCstBalance == 0) return 0;

        // Also limited by available reference asset balance for compensation
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        if (availableReferenceAsset == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);
        if (_swapRate == 0) return 0;

        uint256 referenceFixed = MathHelper.calculateDepositAmountWithSwapRate(availableCstBalance, _swapRate, false);
        uint256 references = TransferHelper.fixedToTokenNativeDecimals(referenceFixed, self.referenceDecimals);

        // If Reference Asset balance is insufficient, calculate max cst assets based on available Reference Asset
        if (references > availableReferenceAsset) {
            // shares = (availableReferenceAsset * swapRate) / 1e18
            referenceFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.referenceDecimals);
            shares = MathHelper.calculateEqualSwapAmount(referenceFixed, _swapRate);
        } else {
            shares = availableCstBalance;
        }
    }

    function maxUnwindExerciseOther(State storage self, MarketId poolId, address constraintRateAdapter) external view returns (uint256 referenceAssets) {
        // Check if before expiry (unwindExercise only works before expiry)
        if (_isExpired(self)) return 0;
        if (_isUnwindSwapPaused(self)) return 0;

        // The maximum reference assets is limited by the available reference asset balance in the pool
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        if (availableReferenceAsset == 0) return 0;

        // Also limited by available CST balance
        uint256 availableCstBalance = self.pool.balances.swapTokenBalance;
        if (availableCstBalance == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);
        if (_swapRate == 0) return 0;

        uint256 referenceFixed = TransferHelper.tokenNativeDecimalsToFixed(availableReferenceAsset, self.referenceDecimals);
        uint256 shares = MathHelper.calculateEqualSwapAmount(referenceFixed, _swapRate);

        // If CST balance is insufficient, calculate max reference assets based on available CST
        if (shares > availableCstBalance) {
            // referenceFixed = (availableCstBalance * 1e18) / swapRate
            uint256 maxReferenceFixed = MathHelper.calculateDepositAmountWithSwapRate(availableCstBalance, _swapRate, false);
            referenceAssets = TransferHelper.fixedToTokenNativeDecimals(maxReferenceFixed, self.referenceDecimals);
        } else {
            referenceAssets = availableReferenceAsset;
        }
    }

    function maxSwap(State storage self, MarketId poolId, address owner, address constraintRateAdapter) external view returns (uint256 assets) {
        Shares storage tokens = self.shares;

        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;
        if (_isSwapPaused(self)) return 0;

        // Get owner's CST and reference asset balances
        uint256 ownerCstBalance = IERC20(tokens.swap).balanceOf(owner);
        uint256 ownerReferenceBalance = IERC20(self.info.referenceAsset).balanceOf(owner);

        // Must have both CST shares and reference assets to swap
        // slither-disable-next-line incorrect-equality
        if (ownerCstBalance == 0 || ownerReferenceBalance == 0) return 0;

        // Calculate the maximum CST shares we can use based on available reference assets
        uint256 otherAssetSpent;
        (assets, otherAssetSpent,,,) = previewExerciseOther(self, poolId, ownerReferenceBalance, constraintRateAdapter);
        uint256 effectiveShares = ownerCstBalance < otherAssetSpent ? ownerCstBalance : otherAssetSpent;

        // If no effective shares, can't swap
        // slither-disable-next-line incorrect-equality
        if (effectiveShares == 0) return 0;

        (assets,,,,) = previewExercise(self, poolId, effectiveShares, constraintRateAdapter);
    }

    function maxUnwindSwap(State storage self, MarketId poolId, address constraintRateAdapter) external view returns (uint256 amount) {
        if (!isInitialized(self)) return 0;
        if (_isExpired(self)) return 0;
        if (_isUnwindSwapPaused(self)) return 0;

        // Get available reference asset and swap token balances in the pool
        uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;
        uint256 availableSwapToken = self.pool.balances.swapTokenBalance;

        // If no available assets to unwind swap, return 0
        if (availableReferenceAsset == 0 || availableSwapToken == 0) return 0;

        // Get current swap rate
        uint256 _swapRate = _getLatestApplicableRate(poolId, constraintRateAdapter);
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
        // slither-disable-next-line unused-return
        (, amount) = MathHelper.calculateGrossAmountWithTimeDecayFee(PoolShare(self.shares.swap).issuedAt(), self.info.expiryTimestamp, block.timestamp, maxNetAmount, self.pool.unwindSwapFeePercentage);
    }

    ///======================================================///
    ///============= RATE & FEE RELATED FUNCTIONS ===========///
    ///======================================================///

    function updateSwapFeePercentage(State storage self, uint256 newFees) external {
        require(newFees <= MAX_ALLOWED_FEES, IErrors.InvalidFees());
        self.pool.swapFeePercentage = newFees;
    }

    function unwindSwapRate(State storage self, MarketId poolId, address constraintRateAdapter) external view returns (uint256 rate) {
        _safeBeforeExpired(self);

        rate = _getLatestApplicableRate(poolId, constraintRateAdapter);
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
        expiry = self.info.expiryTimestamp;
    }

    function isInitialized(State storage self) public view returns (bool status) {
        status = self.info.referenceAsset != address(0) && self.info.collateralAsset != address(0);
    }

    function swapRate(MarketId poolId, address constraintRateAdapter) external view returns (uint256 rate) {
        rate = _getLatestApplicableRate(poolId, constraintRateAdapter);
    }

    ///======================================================///
    ///============== INTERNAL UTILITY FUNCTIONS ============///
    ///======================================================///

    /// @dev Either collateralAssetOut or referenceAssetOut must be zero, but not both
    function _previewWithdraw(State storage self, uint256 collateralAssetOut, uint256 referenceAssetOut) internal view returns (uint256 sharesIn, uint256 actualCollateralAssetOut, uint256 actualReferenceAssetOut) {
        if (_isWithdrawalPaused(self)) return (0, 0, 0);
        if (!_isExpired(self)) return (0, 0, 0);

        Shares storage tokens = self.shares;

        // Check if liquidity has been separated for this Swap Token
        if (!self.pool.liquiditySeparated) {
            // If not separated, we need to simulate the separation to get accurate preview
            uint256 availableCollateralAsset = self.pool.balances.collateralAsset.locked;
            uint256 availableReferenceAsset = self.pool.balances.referenceAssetBalance;

            sharesIn = _calcWithdrawAmount(collateralAssetOut, referenceAssetOut, IERC20(tokens.principal).totalSupply(), availableCollateralAsset, availableReferenceAsset);
        } else {
            // Liquidity already separated, use archived values
            CorkPoolPoolArchive storage archive = self.pool.poolArchive;

            sharesIn = _calcWithdrawAmount(collateralAssetOut, referenceAssetOut, IERC20(tokens.principal).totalSupply(), archive.collateralAssetAccrued, archive.referenceAssetAccrued);
        }

        (actualReferenceAssetOut, actualCollateralAssetOut) = previewRedeem(self, sharesIn);
    }

    function _getPreviewExerciseFeeAndAssets(State storage self, uint256 swapTokenProvided) internal view returns (uint256 assets, uint256 fee) {
        // Calculate collateral asset output (same calculation for both modes)
        uint256 assetsBeforeFee = TransferHelper.fixedToTokenNativeDecimals(swapTokenProvided, self.collateralDecimals);

        // Calculate fee and final assets
        fee = MathHelper.calculatePercentageFee(self.pool.swapFeePercentage, assetsBeforeFee);
        assets = assetsBeforeFee - fee;
    }

    function _getPreviewUnwindExerciseFeeAndAssets(State storage self, uint256 sharesOut) internal view returns (uint256 assetIn, uint256 fee) {
        uint256 assetInWithoutFee = TransferHelper.fixedToTokenNativeDecimalsWithCeilDiv(sharesOut, self.collateralDecimals);

        (fee, assetIn) = MathHelper.calculateGrossAmountWithTimeDecayFee(PoolShare(self.shares.swap).issuedAt(), self.info.expiryTimestamp, block.timestamp, assetInWithoutFee, self.pool.unwindSwapFeePercentage);
    }

    function _getLatestApplicableRate(MarketId poolId, address constraintRateAdapter) internal view returns (uint256 rate) {
        return ConstraintRateAdapter(constraintRateAdapter).previewAdjustedRate(poolId);
    }

    // fetch and update the swap rate.
    function _getLatestApplicableRateAndUpdate(MarketId poolId, address constraintRateAdapter) internal returns (uint256 rate) {
        // slither-disable-next-line reentrancy-no-eth
        rate = ConstraintRateAdapter(constraintRateAdapter).adjustedRate(poolId);
    }

    function _isExpired(State storage self) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return block.timestamp >= self.info.expiryTimestamp;
    }

    function _safeBeforeExpired(State storage self) internal view {
        // slither-disable-next-line timestamp
        require(block.timestamp < self.info.expiryTimestamp, IErrors.Expired());
    }

    function _safeAfterExpired(State storage self) internal view {
        // slither-disable-next-line timestamp
        require(block.timestamp >= self.info.expiryTimestamp, IErrors.NotExpired());
    }

    function _calcWithdrawAmount(uint256 collateralAssetOut, uint256 referenceAssetOut, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal pure returns (uint256 sharesIn) {
        // Calculate required shares based on which asset is being withdrawn
        if (collateralAssetOut > 0) sharesIn = MathHelper.calculateSharesNeeded(collateralAssetOut, availableCollateralAsset, totalPrincipalTokenIssued);
        else sharesIn = MathHelper.calculateSharesNeeded(referenceAssetOut, availableReferenceAsset, totalPrincipalTokenIssued);
    }

    function _calcSwapAmount(uint256 amount, uint256 totalPrincipalTokenIssued, uint256 availableCollateralAsset, uint256 availableReferenceAsset) internal pure returns (uint256 accruedReferenceAsset, uint256 accruedCollateralAsset) {
        accruedReferenceAsset = MathHelper.calculateAccrued(amount, availableReferenceAsset, totalPrincipalTokenIssued);
        accruedCollateralAsset = MathHelper.calculateAccrued(amount, availableCollateralAsset, totalPrincipalTokenIssued);
    }

    function _isDepositPaused(State storage self) internal view returns (bool) {
        return (self.pool.pauseBitMap) & 1 != 0;
    }

    function _isSwapPaused(State storage self) internal view returns (bool) {
        return (self.pool.pauseBitMap) & (1 << 1) != 0;
    }

    function _isWithdrawalPaused(State storage self) internal view returns (bool) {
        return (self.pool.pauseBitMap) & (1 << 2) != 0;
    }

    function _isUnwindDepositPaused(State storage self) internal view returns (bool) {
        return (self.pool.pauseBitMap) & (1 << 3) != 0;
    }

    function _isUnwindSwapPaused(State storage self) internal view returns (bool) {
        return (self.pool.pauseBitMap) & (1 << 4) != 0;
    }
}
