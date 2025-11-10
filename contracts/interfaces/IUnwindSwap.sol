// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title IUnwindSwap Interface
 * @author Cork Team
 * @notice IUnwindSwap interface for supporting unwindSwap features through CorkPoolManager
 */
interface IUnwindSwap is IErrors {
    /**
     * @notice emitted when unwindSwap is done
     * @param id the id of Cork Pool
     * @param buyer the address of the buyer
     * @param raUsed the amount of Collateral Asset used
     * @param receivedReferenceAsset the amount of Reference Asset received
     * @param receivedSwapToken the amount of Swap Token received
     * @param fee the fee charged
     * @param feePercentage the fee in percentage
     * @param swapRate the effective swap rate of the Swap Token at the time of unwindSwap
     */
    event UnwindSwap(MarketId indexed id, address indexed buyer, uint256 raUsed, uint256 receivedReferenceAsset, uint256 receivedSwapToken, uint256 feePercentage, uint256 fee, uint256 swapRate);

    /// @notice Emitted when a unwindSwapFee is updated for a given Cork Pool
    /// @param id The Cork Pool id
    /// @param unwindSwapFeeRate The new unwindSwapFee rate
    event UnwindSwapFeeRateUpdated(MarketId indexed id, uint256 indexed unwindSwapFeeRate);

    /**
     * @notice returns the fee percentage for repurchasing(1e18 = 1%)
     * @param id the id of Cork Pool
     * @return fees the fee percentage for repurchasing(1e18 = 1%)
     */
    function unwindSwapFee(MarketId id) external view returns (uint256 fees);

    /**
     * @notice unwindSwap using Collateral Asset
     * @param id the id of Cork Pool
     * @param collateralAssetsIn the amount of Collateral Asset to use
     * @param receiver the address to receive the Reference Asset and Swap Token
     * @return cstSharesOut The amount of CST tokens that would be received
     * @return referenceAssetsOut The amount of reference asset that would be received
     * @return fee The fee amount that would be charged
     */
    function unwindSwap(MarketId id, uint256 collateralAssetsIn, address receiver) external returns (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee);

    /**
     * @notice Returns the maximum amount of assets that could be transferred through `unwindSwap` and not cause a revert.
     * @dev MUST return the maximum amount of assets that could be transferred through `unwindSwap` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * @dev MUST factor in both global and user-specific limits, for example, global caps and available balance of CST to repurchase. MUST factor in other restrictive conditions, like if reverse-swaps (i.e. repurchase) are entirely disabled (even temporarily) it MUST return 0.
     * @dev This assumes that the user has infinite collateral assets, i.e. MUST NOT rely on `balanceOf` of `asset`.
     * @dev MUST NOT revert.
     * @dev Address parameter is not used for calculation, but is required to match the interface as well as in future it will allow support for owner parameter
     * @param id the id of Cork Pool
     * @return maxCollateralAssetsIn The maximum amount of collateral assets that could be transferred through unwindSwap
     */
    function maxUnwindSwap(MarketId id, address) external view returns (uint256 maxCollateralAssetsIn);
}
