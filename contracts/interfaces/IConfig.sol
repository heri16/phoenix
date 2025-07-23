// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IConfig Interface
 * @author Cork Team
 * @notice Interface for Config contract
 */
interface IConfig {
    /// @notice thrown when caller is not manager/Admin of Cork Protocol
    error CallerNotManager();

    /// @notice thrown when caller is not market admin
    error CallerNotMarketAdmin();

    /// @notice thrown when passed Invalid/Zero Address
    error InvalidAddress();

    /// @notice thrown when passed Invalid Admin Role
    error InvalidAdminRole();

    /// @notice thrown when passed Invalid Role
    error InvalidRole();

    /// @notice Emitted when a corkPool variable set
    /// @param corkPool Address of CorkPool contract
    event CorkPoolSet(address corkPool);

    /// @notice Emitted when a treasury is set
    /// @param treasury Address of treasury contract/address
    event TreasurySet(address treasury);

    /**
     * @dev Sets new CorkPool contract address
     * @param _corkPool new corkPool contract address
     */
    function setCorkPool(address _corkPool) external;

    /**
     * @dev Sets new treasury contract address
     * @param _treasury new treasury contract address
     */
    function setTreasury(address _treasury) external;

    /**
     * @dev Initialize cork pool
     * @param referenceAsset Address of Reference Asset
     * @param collateralAsset Address of Collateral Asset
     */
    function createNewMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address exchangeRateProvider) external;

    /**
     * @notice Updates fee rates for pool unwindSwap
     * @param id id of Cork Pool
     * @param newUnwindSwapFeePercentage new value of unwindSwap fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external;

    /**
     * @notice Updates base redemption fee percentage
     * @param newBaseRedemptionFeePercentage new value of fees, make sure it has 18 decimals(e.g 1% = 1e18)
     */
    function updateBaseRedemptionFeePercentage(MarketId id, uint256 newBaseRedemptionFeePercentage) external;

    /**
     * @notice Updates the rate of the Cork Pool
     * @param id the id of Cork Pool
     * @param newRate the new rate to update
     */
    function updateCorkPoolRate(MarketId id, uint256 newRate) external;

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
}
