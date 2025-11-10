// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC4626} from "contracts/interfaces/IERC4626.sol";
import {MinimalAggregatorV3Interface} from "contracts/interfaces/MinimalAggregatorV3Interface.sol";
import {SourceParams} from "contracts/periphery/CompositeRateOracle.sol";

library CompositeRateOracleHelper {
    function makeSourceParamsArr(
        IERC4626 baseVault,
        uint256 baseVaultConversionSample,
        MinimalAggregatorV3Interface baseFeed1,
        MinimalAggregatorV3Interface baseFeed2,
        uint256 baseTokenDecimals,
        IERC4626 quoteVault,
        uint256 quoteVaultConversionSample,
        MinimalAggregatorV3Interface quoteFeed1,
        MinimalAggregatorV3Interface quoteFeed2,
        uint256 quoteTokenDecimals
    ) internal pure returns (SourceParams[] memory params) {
        params = new SourceParams[](1);
        params[0] = makeSourceParams(baseVault, baseVaultConversionSample, baseFeed1, baseFeed2, baseTokenDecimals, quoteVault, quoteVaultConversionSample, quoteFeed1, quoteFeed2, quoteTokenDecimals);
    }

    function makeSourceParams(
        IERC4626 baseVault,
        uint256 baseVaultConversionSample,
        MinimalAggregatorV3Interface baseFeed1,
        MinimalAggregatorV3Interface baseFeed2,
        uint256 baseTokenDecimals,
        IERC4626 quoteVault,
        uint256 quoteVaultConversionSample,
        MinimalAggregatorV3Interface quoteFeed1,
        MinimalAggregatorV3Interface quoteFeed2,
        uint256 quoteTokenDecimals
    ) internal pure returns (SourceParams memory) {
        return SourceParams({
            baseVault: baseVault,
            baseVaultConversionSample: baseVaultConversionSample,
            baseFeed1: baseFeed1,
            baseFeed2: baseFeed2,
            baseTokenDecimals: baseTokenDecimals,
            quoteVault: quoteVault,
            quoteVaultConversionSample: quoteVaultConversionSample,
            quoteFeed1: quoteFeed1,
            quoteFeed2: quoteFeed2,
            quoteTokenDecimals: quoteTokenDecimals
        });
    }
}
