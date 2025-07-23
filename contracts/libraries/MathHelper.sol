// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {UD60x18, convert, div, mul, sub, ud, unwrap} from "@prb/math/src/UD60x18.sol";

/**
 * @title MathHelper Library Contract
 * @author Cork Team
 * @notice MathHelper Library which implements Helper functions for Math
 */
library MathHelper {
    /**
     * @dev amount = referenceAsset x exchangeRate
     * calculate how much Swap Token(need to be provided) and Collateral Asset(user will receive) in respect to the exchange rate
     * @param referenceAsset the amount of referenceAsset user provides
     * @param exchangeRate the current exchange rate between Collateral Asset:(Principal Token+Swap Token)
     * @return amount the amount of Collateral Asset user will receive & Swap Token needs to be provided
     */
    function calculateEqualSwapAmount(uint256 referenceAsset, uint256 exchangeRate) external pure returns (uint256 amount) {
        amount = unwrap(mul(ud(referenceAsset), ud(exchangeRate)));
    }

    /**
     * @dev calculate the fee amount in respect to the given fees percentage and asset amount
     * @param fee1e18 the fee percentage in 1e18
     * @param amount the amount for which the fee is calculated
     */
    function calculatePercentageFee(uint256 fee1e18, uint256 amount) external pure returns (uint256 feeAmount) {
        UD60x18 fee = calculatePercentage(ud(amount), ud(fee1e18));
        return unwrap(fee);
    }

    /**
     * @dev calculate how much reference asset + swapToken user will receive based on the amount of the current exchange rate
     * @param amount  the amount of user deposit
     * @param exchangeRate the current exchange rate between Collateral Asset:(Principal Token+Swap Token)
     */
    function calculateDepositAmountWithExchangeRate(uint256 amount, uint256 exchangeRate) public pure returns (uint256) {
        UD60x18 _amount = div(ud(amount), ud(exchangeRate));
        return unwrap(_amount);
    }

    /// @notice calculate the accrued Reference Asset & Collateral Asset
    /// @dev this function follow below equation :
    /// '#' refers to the total circulation supply of that token.
    /// '&' refers to the total amount of token in the Cork Pool.
    ///
    /// amount * (&Reference Asset or &Collateral Asset/#Principal Token)
    function calculateAccrued(uint256 amount, uint256 available, uint256 totalPrincipalTokenIssued) internal pure returns (uint256 accrued) {
        UD60x18 _accrued = mul(ud(amount), div(ud(available), ud(totalPrincipalTokenIssued)));
        return unwrap(_accrued);
    }

    /// @notice returns the normalized time to maturity from 1-0
    /// 1 means we're at the start of the period, 0 means we're at the end
    function computeT(UD60x18 start, UD60x18 end, UD60x18 current) public pure returns (UD60x18) {
        UD60x18 minimumElapsed = convert(1);

        UD60x18 elapsedTime = sub(current, start);
        elapsedTime = elapsedTime == convert(0) ? minimumElapsed : elapsedTime;
        UD60x18 totalDuration = sub(end, start);

        // we return 0 in case it's past maturity time
        if (elapsedTime >= totalDuration) return convert(0);

        // Return a normalized time between 0 and 1 (as a percentage in 18 decimals)
        return sub(convert(1), div(elapsedTime, totalDuration));
    }

    function calculateUnwindSwapWithFee(uint256 _start, uint256 _end, uint256 _current, uint256 _amount, uint256 _baseFeePercentage) internal pure returns (uint256 _fee, uint256 _assetIn) {
        if (_amount == 0) return (0, 0);

        UD60x18 t = computeT(convert(_start), convert(_end), convert(_current));

        UD60x18 feeFactor = mul(ud(_baseFeePercentage), t);

        // since the amount is already on 18 decimals, we don't need to convert it
        UD60x18 withFee = div(ud(_amount), sub(convert(1), div(feeFactor, convert(100))));

        _fee = unwrap(sub(withFee, ud(_amount)));
        _assetIn = unwrap(withFee);
    }

    function calculatePercentage(UD60x18 amount, UD60x18 percentage) internal pure returns (UD60x18 result) {
        result = div(mul(amount, percentage), convert(100));
    }

    /// @notice calculate the required shares needed to get a specific amount of assets
    /// @dev this function reverses the calculateAccrued equation:
    /// amount = shares * (available / totalPrincipalTokenIssued)
    /// therefore: shares = amount * (totalPrincipalTokenIssued / available)
    function calculateSharesNeeded(uint256 amount, uint256 available, uint256 totalPrincipalTokenIssued) internal pure returns (uint256 shares) {
        UD60x18 _shares = mul(ud(amount), div(ud(totalPrincipalTokenIssued), ud(available)));
        return unwrap(_shares);
    }

    /// @notice calculate the gross amount needed before fee deduction to achieve a desired net amount
    /// @dev grossAmount = desiredAmount ÷ (1 - feeRate)
    /// @param desiredAmount the amount you want to receive after fees
    /// @param feeRate the fee percentage in 1e18 format (e.g., 0.05e18 = 5%)
    /// @return grossAmount the gross amount needed before fee deduction
    function calculateGrossAmountBeforeFee(uint256 desiredAmount, uint256 feeRate) external pure returns (uint256 grossAmount) {
        // Calculate (1 - feeRate)
        UD60x18 oneMinusFeeRate = sub(convert(1), div(ud(feeRate), convert(100)));

        // Calculate grossAmount = desiredAmount ÷ (1 - feeRate)
        UD60x18 _grossAmount = div(ud(desiredAmount), oneMinusFeeRate);
        return unwrap(_grossAmount);
    }
}
