// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import {ICompositeRateOracle, SourceParams} from "../interfaces/ICompositeRateOracle.sol";
import {IMorphoOracle} from "../interfaces/IMorphoOracle.sol";
import {IRateOracle} from "../interfaces/IRateOracle.sol";
import {ChainlinkDataFeedLib, MinimalAggregatorV3Interface} from "../libraries/ChainlinkDataFeedLib.sol";
import {ERC4626Lib, IERC4626} from "../libraries/ERC4626Lib.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title CompositeRateOracle
/// @author Cork Team
/// @custom:contact security@cork.tech
/// @notice Push oracle using Chainlink-compliant and ERC4626-compliant feeds.
contract CompositeRateOracle is ICompositeRateOracle, IMorphoOracle {
    using Math for uint256;
    using ERC4626Lib for IERC4626;
    using ChainlinkDataFeedLib for MinimalAggregatorV3Interface;

    /* IMMUTABLES or STORAGE */

    SourceParams[] public sourceParams;

    uint256[] public scaleFactors;

    /* CONSTRUCTOR */

    constructor(SourceParams[] memory _params) {
        // The ERC4626 vault parameters are used to price their respective conversion samples of their respective
        // shares, so it requires multiplying by `QUOTE_VAULT_CONVERSION_SAMPLE` and dividing
        // by `BASE_VAULT_CONVERSION_SAMPLE` in the `SCALE_FACTOR` definition.

        uint256 length = _params.length;
        for (uint256 i = 0; i < length; ++i) {
            SourceParams memory p = _params[i];

            // Verify that vault = address(0) => vaultConversionSample = 1 for each vault.
            require(address(p.baseVault) != address(0) || p.baseVaultConversionSample == 1, VaultConversionSampleIsNotOne());
            require(address(p.quoteVault) != address(0) || p.quoteVaultConversionSample == 1, VaultConversionSampleIsNotOne());
            require(p.baseVaultConversionSample != 0, VaultConversionSampleIsZero());
            require(p.quoteVaultConversionSample != 0, VaultConversionSampleIsZero());

            sourceParams.push(p);
            scaleFactors.push(_scaleFactor(p));
        }
    }

    /* RATE and PRICE */

    /// @inheritdoc IRateOracle
    function rate() public view returns (uint256) {
        return price() / 1 ether;
    }

    /// @inheritdoc IMorphoOracle
    function price() public view returns (uint256 nav) {
        uint256 length = sourceParams.length;
        for (uint256 i = 0; i < length; ++i) {
            SourceParams memory p = sourceParams[i];
            nav += scaleFactors[i].mulDiv(p.baseVault.getAssets(p.baseVaultConversionSample) * p.baseFeed1.getPrice() * p.baseFeed2.getPrice(), p.quoteVault.getAssets(p.quoteVaultConversionSample) * p.quoteFeed1.getPrice() * p.quoteFeed2.getPrice());
        }
    }

    /// @inheritdoc MinimalAggregatorV3Interface
    function latestRoundData() external view returns (uint80, int256 answer, uint256, uint256, uint80) {
        answer = int256(price());
        return (0, answer, 0, 0, 0);
    }

    /// @inheritdoc MinimalAggregatorV3Interface
    function decimals() public pure returns (uint8) {
        return 36;
    }

    function _scaleFactor(SourceParams memory p) internal view returns (uint256) {
        // Expects `price()` to be the quantity of 1 asset Q1 that can be exchanged for 1 asset B1,
        // scaled by 1e36:
        // 1e36 * (pB1 * 1e(dB2 - dB1)) * (pB2 * 1e(dC - dB2)) / ((pQ1 * 1e(dQ2 - dQ1)) * (pQ2 * 1e(dC - dQ2)))
        // = 1e36 * (pB1 * 1e(-dB1) * pB2) / (pQ1 * 1e(-dQ1) * pQ2)

        // Let fpB1, fpB2, fpQ1, fpQ2 be the feed precision of the respective prices pB1, pB2, pQ1, pQ2.
        // Feeds return pB1 * 1e(fpB1), pB2 * 1e(fpB2), pQ1 * 1e(fpQ1) and pQ2 * 1e(fpQ2).

        // Based on the implementation of `price()` below, the value of `SCALE_FACTOR` should thus satisfy:
        // (pB1 * 1e(fpB1)) * (pB2 * 1e(fpB2)) * SCALE_FACTOR / ((pQ1 * 1e(fpQ1)) * (pQ2 * 1e(fpQ2)))
        // = 1e36 * (pB1 * 1e(-dB1) * pB2) / (pQ1 * 1e(-dQ1) * pQ2)

        // So SCALE_FACTOR = 1e36 * 1e(-dB1) * 1e(dQ1) * 1e(-fpB1) * 1e(-fpB2) * 1e(fpQ1) * 1e(fpQ2)
        //                 = 1e(36 + dQ1 + fpQ1 + fpQ2 - dB1 - fpB1 - fpB2)
        return 10 ** (decimals() + p.quoteTokenDecimals + p.quoteFeed1.getDecimals() + p.quoteFeed2.getDecimals() - p.baseTokenDecimals - p.baseFeed1.getDecimals() - p.baseFeed2.getDecimals()) * p.quoteVaultConversionSample / p.baseVaultConversionSample;
    }
}
