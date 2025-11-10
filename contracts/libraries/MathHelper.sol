// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MathHelper Library Contract
 * @author Cork Team
 * @notice MathHelper Library which implements Helper functions for Math
 */
library MathHelper {
    using Math for uint256;

    /**
     * @dev amount = referenceAsset x swapRate
     * calculate how much Swap Token(need to be provided) and Collateral Asset(user will receive) in respect to the swap rate
     * @param referenceAsset the amount of referenceAsset user provides
     * @param swapRate the current swap rate
     * @return amount the amount of Collateral Asset user will receive & Swap Token needs to be provided
     */
    function calculateEqualSwapAmount(uint256 referenceAsset, uint256 swapRate) internal pure returns (uint256 amount) {
        amount = referenceAsset.mulDiv(swapRate, 1e18, Math.Rounding.Floor);
    }

    /**
     * @dev calculate the fee amount in respect to the given fees percentage and asset amount
     * @param fee1e18 the fee percentage in 1e18
     * @param amount the amount for which the fee is calculated
     */
    function calculatePercentageFee(uint256 fee1e18, uint256 amount) internal pure returns (uint256 feeAmount) {
        feeAmount = amount.mulDiv(fee1e18, 100e18, Math.Rounding.Ceil);
    }

    /**
     * @dev calculate how much reference asset + swapToken user will receive based on the current swap rate
     * @param amount  the amount of user deposit
     * @param swapRate the current swap rate
     */
    function calculateDepositAmountWithSwapRate(uint256 amount, uint256 swapRate, bool isRoundUp) internal pure returns (uint256) {
        if (isRoundUp) return amount.mulDiv(1e18, swapRate, Math.Rounding.Ceil);
        else return amount.mulDiv(1e18, swapRate, Math.Rounding.Floor);
    }

    /// @notice calculate the accrued Reference Asset & Collateral Asset
    /// @dev this function follow below equation :
    /// '#' refers to the total circulation supply of that token.
    /// '&' refers to the total amount of token in the Cork Pool.
    /// amount * &Reference Asset or &Collateral Asset / #Principal Token
    function calculateAccrued(uint256 amount, uint256 available, uint256 totalPrincipalTokenIssued) internal pure returns (uint256 accrued) {
        if (amount == 0 || totalPrincipalTokenIssued == 0) return 0;
        accrued = amount.mulDiv(available, totalPrincipalTokenIssued, Math.Rounding.Floor);
    }

    /// @notice returns the normalized time to maturity from 1-0
    /// 1 means we're at the start of the period, 0 means we're at the end
    function computeT(uint256 start, uint256 end, uint256 current) internal pure returns (uint256) {
        uint256 elapsedTime = current - start;
        elapsedTime = elapsedTime == 0 ? 1 : elapsedTime;
        uint256 totalDuration = end - start;

        // we return 0 in case it's past maturity time
        if (elapsedTime >= totalDuration) return 0;

        // Return a normalized time between 0 and 1 (as a percentage in 18 decimals)
        return ((totalDuration - elapsedTime) * 1e18) / totalDuration;
    }

    function calculateGrossAmountWithTimeDecayFee(uint256 start, uint256 end, uint256 current, uint256 amount, uint256 baseFeePercentage) internal pure returns (uint256 fee, uint256 assetIn) {
        if (amount == 0) return (0, 0);

        uint256 t = computeT(start, end, current);

        uint256 feeFactor = (baseFeePercentage * t) / 1e18;

        uint256 withFee = amount.mulDiv(100e18, (100e18 - feeFactor), Math.Rounding.Ceil);

        assetIn = withFee;
        fee = (assetIn - amount);
    }

    function calculateTimeDecayFee(uint256 start, uint256 end, uint256 current, uint256 amount, uint256 baseFeePercentage) internal pure returns (uint256 fee) {
        if (amount == 0) return 0;

        uint256 t = computeT(start, end, current);

        uint256 feeFactor = (baseFeePercentage * t) / 1e18;

        fee = amount.mulDiv(feeFactor, 100e18, Math.Rounding.Ceil);
    }

    /// @notice calculate the required shares needed to get a specific amount of assets
    /// @dev this function reverses the calculateAccrued equation:
    /// amount = shares * (available / totalPrincipalTokenIssued)
    /// therefore: shares = amount * (totalPrincipalTokenIssued / available)
    function calculateSharesNeeded(uint256 amount, uint256 available, uint256 totalPrincipalTokenIssued) internal pure returns (uint256 shares) {
        if (amount == 0 || totalPrincipalTokenIssued == 0 || available == 0) return 0;
        shares = amount.mulDiv(totalPrincipalTokenIssued, available, Math.Rounding.Ceil);
    }

    /// @notice calculate the gross amount needed before fee deduction to achieve a desired net amount
    /// @dev grossAmount = desiredAmount ÷ (1 - feeRate) => grossAmount = (desiredAmount * 100e18)÷ (100e18 - rate in 100e18)
    /// @param desiredAmount the amount you want to receive after fees
    /// @param feeRate the fee percentage in 1e18 format (e.g., 5e18 = 5%)
    /// @return grossAmount the gross amount needed before fee deduction
    function calculateGrossAmountBeforeFee(uint256 desiredAmount, uint256 feeRate) internal pure returns (uint256 grossAmount) {
        // grossAmount = desiredAmount ÷ (1 - feeRate)
        // So grossAmount = (desiredAmount * 100e18)÷ (100e18 - rate in 100e18)
        // Where rate in 100e18 means => 1% = 1e18
        grossAmount = desiredAmount.mulDiv(100e18, 100e18 - feeRate, Math.Rounding.Ceil);
    }
}
