// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC4626} from "./IERC4626.sol";
import {IComposableRateOracle} from "./IRateOracle.sol";
import {MinimalAggregatorV3Interface} from "./MinimalAggregatorV3Interface.sol";

struct SourceParams {
    IERC4626 baseVault;
    uint256 baseVaultConversionSample;
    MinimalAggregatorV3Interface baseFeed1;
    MinimalAggregatorV3Interface baseFeed2;
    uint256 baseTokenDecimals;
    IERC4626 quoteVault;
    uint256 quoteVaultConversionSample;
    MinimalAggregatorV3Interface quoteFeed1;
    MinimalAggregatorV3Interface quoteFeed2;
    uint256 quoteTokenDecimals;
}

/// @title ICompositeRateOracle
/// @author Cork Team
/// @custom:contact security@cork.tech
/// @notice Interface of CompositeRateOracle.
interface ICompositeRateOracle is IComposableRateOracle {
    error VaultConversionSampleIsZero();
    error VaultConversionSampleIsNotOne();
}
