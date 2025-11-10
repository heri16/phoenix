// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IDefaultCorkController Interface
 * @author Cork Team
 * @notice Interface for DefaultCorkController contract
 */
interface IDefaultCorkController {
    /// @notice thrown when passed Invalid/Zero Address
    error InvalidAddress();

    /// @notice thrown when passed Invalid Admin Role
    error InvalidAdminRole();

    /// @notice thrown when passed Invalid Role
    error InvalidRole();

    /// @notice Emitted when a treasury is set
    /// @param treasury Address of treasury contract/address
    event TreasurySet(address treasury);

    /// @notice Parameters for creating a new pool
    /// this includes initializing the fee. Although it can still be modified later
    /// all fees are percentage in 18 decimals(e.g. 1% = 1e18)
    struct PoolCreationParams {
        Market pool;
        uint256 unwindSwapFeePercentage; // unwindSwap/unwindExercise fee percentage in 18 decimals (e.g. 1% = 1e18)
        uint256 swapFeePercentage; // swap/exercise fee percentage in 18 decimals (e.g. 1% = 1e18)
        bool isWhitelistEnabled; // is whitelist enabled for the new pool
    }

    /**
     * @dev Sets new treasury contract address
     * @param _treasury new treasury contract address
     */
    function setTreasury(address _treasury) external;

    /**
     * @dev Sets new shares factory contract address
     * @param _sharesFactory new shares factory contract address
     */
    function setSharesFactory(address _sharesFactory) external;

    /**
     * @dev Initialize cork pool
     * @param params Parameters for the new pool
     */
    function createNewPool(PoolCreationParams calldata params) external;

    /**
     * @notice Updates fee rate for pool unwindSwap
     * @param id id of Cork Pool
     * @param newUnwindSwapFeePercentage new value of unwindSwap fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external;

    /**
     * @notice Updates base redemption fee percentage
     * @param newSwapFeePercentage new value of fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateSwapFeePercentage(MarketId id, uint256 newSwapFeePercentage) external;

    /**
     * @notice Pause this contract
     */
    function pause() external;

    /**
     * @notice Unpause this contract
     */
    function unpause() external;

    /**
     * @notice Pauses deposits for a Cork Pool
     */
    function pauseDeposits(MarketId id) external;

    /**
     * @notice Unpauses deposits for a Cork Pool
     */
    function unpauseDeposits(MarketId id) external;

    /**
     * @notice Pauses unwindSwaps for a Cork Pool
     */
    function pauseUnwindSwaps(MarketId id) external;

    /**
     * @notice Unpauses unwindSwaps for a Cork Pool
     */
    function unpauseUnwindSwaps(MarketId id) external;

    /**
     * @notice Pauses swaps for a Cork Pool
     */
    function pauseSwaps(MarketId id) external;

    /**
     * @notice Unpauses swaps for a Cork Pool
     */
    function unpauseSwaps(MarketId id) external;

    /**
     * @notice Pauses withdrawals for a Cork Pool
     */
    function pauseWithdrawals(MarketId id) external;

    /**
     * @notice Unpauses withdrawals for a Cork Pool
     */
    function unpauseWithdrawals(MarketId id) external;

    /**
     * @notice Pauses premature withdrawals for a Cork Pool
     */
    function pauseUnwindDepositAndMints(MarketId id) external;

    /**
     * @notice Unpauses premature withdrawals for a Cork Pool
     */
    function unpauseUnwindDepositAndMints(MarketId id) external;

    /**
     * @notice Freeze a market, will disable ALL functionality on the given pool(swaps, withdraw, deposit, unwindExericise/mints)
     */
    function pauseMarket(MarketId id) external;

    /**
     * @notice Pause all markets at once
     */
    function pauseAll() external;

    /**
     * @notice Pause all markets at once
     */
    function unpauseAll() external;

    ///======================================================///
    ///================= WHITELIST FUNCTIONS ===============///
    ///======================================================///

    /**
     * @notice Disables whitelisting for a specific market (cannot be re-enabled)
     * @param marketId The market identifier
     */
    function disableMarketWhitelist(MarketId marketId) external;

    /**
     * @notice Adds accounts to the global whitelist
     * @param accounts Array of accounts to add
     */
    function addToGlobalWhitelist(address[] calldata accounts) external;

    /**
     * @notice Removes accounts from the global whitelist
     * @param accounts Array of accounts to remove
     */
    function removeFromGlobalWhitelist(address[] calldata accounts) external;

    /**
     * @notice Adds accounts to a market-specific whitelist
     * @param marketId The market identifier
     * @param accounts Array of accounts to add
     */
    function addToMarketWhitelist(MarketId marketId, address[] calldata accounts) external;

    /**
     * @notice Removes accounts from a market-specific whitelist
     * @param marketId The market identifier
     * @param accounts Array of accounts to remove
     */
    function removeFromMarketWhitelist(MarketId marketId, address[] calldata accounts) external;

    /**
     * @notice Checks if an account is whitelisted for a specific market
     * @param marketId The market identifier
     * @param account The account to check
     * @return true if the account is whitelisted, false otherwise
     */
    function isWhitelisted(MarketId marketId, address account) external view returns (bool);
}
