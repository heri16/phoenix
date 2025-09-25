// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IErrors {
    /// @notice trying to initialize the pool more than once
    error AlreadyInitialized();

    /// @notice trying to swap/remove liquidity from non-initialized pool
    error NotInitialized();

    /// @notice trying to swap with invalid amount or adding liquidity without proportion, e.g 0
    error InvalidAmount();

    /// @notice Zero Address error, thrown when passed address is 0
    error ZeroAddress();

    /// @notice thrown when the caller is not the cork pool
    error NotCorkPool();

    error InvalidParams();

    /// @notice thrown when the user tries to unwindSwap more than the available Reference Asset + DSliquidity
    /// @param available the amount of available Reference Asset + Swap Token
    /// @param requested the amount of Reference Asset + Swap Token user will receive
    error InsufficientLiquidity(uint256 available, uint256 requested);

    /// @notice only config contract is allowed to call this function
    error OnlyConfigAllowed();

    /// @notice Share is already expired
    error Expired();

    /// @notice thrown when a functionality is paused.
    error Paused();

    /// @notice Thrown when user deposit with 0 amount
    error ZeroDeposit();

    /// @notice Thrown this error when fees are more than 5%
    error InvalidFees();

    /// @notice thrown when trying to update rate with invalid rate
    error InvalidRate();

    /// @notice insufficient output amount, e.g trying to swap 100 CT which you expect 100 Collateral Asset but only received 50 Collateral Asset
    error InsufficientOutputAmount(uint256 amountOutMin, uint256 received);

    /// @notice thrown when expiry is zero
    error InvalidExpiry();

    error NotExpired();

    error Uninitialized();

    error InvalidAddress();

    error SameStatus();

    error ZeroAmount();

    error DeadlineExceeded();

    error SlippageExceeded();

    /// @notice thrown when input amount exceeds maximum amount allowed
    error ExceedInput(uint256 inputAmount, uint256 maxAllowed);

    /// @notice Thrown when the shares amount is too small and would result in 0 output due to decimals rounding
    error InsufficientSharesAmount(uint256 minimumRequired, uint256 provided);

    /// @notice thrown when withdraw amount is invalid, e.g trying to withdraw 100 CPT/100 CST but only capable of withdrawing 50 CPT/50 CST
    error InvalidWithdrawAmount(uint256 expected, uint256 actual);

    /// @notice thrown when an input amount does not meet some minimum value requirements
    error InsufficientAmount();
}
