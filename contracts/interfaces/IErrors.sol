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

    /// @notice thrown when the caller is not the CorkPoolManager contract
    error NotCorkPoolManager();

    error InvalidParams();

    /// @notice thrown when the user tries to unwindSwap more than the available Reference Asset + DSliquidity
    /// @param available the amount of available Reference Asset + Swap Token
    /// @param requested the amount of Reference Asset + Swap Token user will receive
    error InsufficientLiquidity(uint256 available, uint256 requested);

    /// @notice only controller contract is allowed to call this function
    error OnlyCorkControllerAllowed();

    /// @notice Share is already expired
    error Expired();

    /// @notice Thrown when user deposit with 0 amount
    error ZeroDeposit();

    /// @notice Thrown this error when fees are more than 5%
    error InvalidFees();

    /// @notice thrown when trying to update rate with invalid rate
    error InvalidRate();

    /// @notice thrown when expiry is zero
    error InvalidExpiry();

    error NotExpired();

    error InvalidAddress();

    error SameStatus();

    error ZeroAmount();

    error DeadlineExceeded();

    /// @notice Thrown when the shares amount is too small and would result in 0 output due to decimals rounding
    error InsufficientSharesAmount(uint256 minimumRequired, uint256 provided);

    /// @notice thrown when withdraw amount is invalid, e.g trying to withdraw 100 CPT/100 CST but only capable of withdrawing 50 CPT/50 CST
    error InvalidWithdrawAmount(uint256 expected, uint256 actual);

    /// @notice thrown when an input amount does not meet some minimum value requirements
    error InsufficientAmount();

    /// @notice thrown when an account is not whitelisted for a specific market
    /// @param account the account that is not whitelisted
    /// @param marketId the market for which the account is not whitelisted
    error NotWhitelisted(address account, bytes32 marketId);

    error WhitelistAlreadyDisabled();
}
