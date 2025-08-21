// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

/**
 * @title ISwapRate Interface
 * @author Cork Team
 * @notice ISwapRate interface for providing swapRate
 */
interface ISwapRate {
    /// @notice returns the swap rate, if 0 then it means that there's no swap rate associated with the token
    function swapRate() external view returns (uint256 rate);

    function updateSwapRate(uint256 newRate) external;
}
