// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import {
    AggregatorV3Interface,
    IERC4626,
    IMorphoChainlinkOracleV2
} from "@morpho-oracle/interfaces/IMorphoChainlinkOracleV2.sol";

/// @title MorphoOracleMock
/// @notice Mock implementation of IMorphoChainlinkOracleV2 for testing WrapperRateConsumer
contract MorphoOracleMock is IMorphoChainlinkOracleV2 {
    uint256 private _price;
    IERC4626 private _baseVault;
    IERC4626 private _quoteVault;
    uint256 private _baseVaultConversionSample;
    uint256 private _quoteVaultConversionSample;
    AggregatorV3Interface private _baseFeed1;
    AggregatorV3Interface private _baseFeed2;
    AggregatorV3Interface private _quoteFeed1;
    AggregatorV3Interface private _quoteFeed2;
    uint256 private _scaleFactor;

    /// @notice Set the price returned by price()
    function setPrice(uint256 price_) external {
        _price = price_;
    }

    /// @notice Set the base vault and its conversion sample
    function setBaseVault(address vault, uint256 conversionSample) external {
        _baseVault = IERC4626(vault);
        _baseVaultConversionSample = conversionSample;
    }

    /// @notice Set the quote vault and its conversion sample
    function setQuoteVault(address vault, uint256 conversionSample) external {
        _quoteVault = IERC4626(vault);
        _quoteVaultConversionSample = conversionSample;
    }

    /// @notice Set the scale factor
    function setScaleFactor(uint256 scaleFactor_) external {
        _scaleFactor = scaleFactor_;
    }

    /// @notice Returns the price
    function price() external view returns (uint256) {
        return _price;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function BASE_VAULT() external view returns (IERC4626) {
        return _baseVault;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function BASE_VAULT_CONVERSION_SAMPLE() external view returns (uint256) {
        return _baseVaultConversionSample;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function QUOTE_VAULT() external view returns (IERC4626) {
        return _quoteVault;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function QUOTE_VAULT_CONVERSION_SAMPLE() external view returns (uint256) {
        return _quoteVaultConversionSample;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function BASE_FEED_1() external view returns (AggregatorV3Interface) {
        return _baseFeed1;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function BASE_FEED_2() external view returns (AggregatorV3Interface) {
        return _baseFeed2;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function QUOTE_FEED_1() external view returns (AggregatorV3Interface) {
        return _quoteFeed1;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function QUOTE_FEED_2() external view returns (AggregatorV3Interface) {
        return _quoteFeed2;
    }

    /// @inheritdoc IMorphoChainlinkOracleV2
    function SCALE_FACTOR() external view returns (uint256) {
        return _scaleFactor;
    }
}
