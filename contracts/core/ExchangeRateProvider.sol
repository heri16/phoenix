// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IExchangeRateProvider} from "contracts/interfaces/IExchangeRateProvider.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title ExchangeRateProvider Contract
 * @author Cork Team
 * @notice Contract for managing exchange rate
 */
contract ExchangeRateProvider is IErrors, IExchangeRateProvider {
    address public immutable CONFIG;

    mapping(MarketId => uint256) internal exchangeRate;

    constructor(address _config) {
        if (_config == address(0)) revert IErrors.ZeroAddress();
        CONFIG = _config;
    }

    /// @inheritdoc IExchangeRateProvider
    function rate() external view returns (uint256 _rate) {
        // For future use
    }

    /// @inheritdoc IExchangeRateProvider
    function rate(MarketId id) external view returns (uint256 _rate) {
        _rate = exchangeRate[id];
    }

    /**
     * @dev checks if caller is config contract or not
     */
    function onlyConfig() internal view {
        if (msg.sender != CONFIG) revert IErrors.OnlyConfigAllowed();
    }

    /// @inheritdoc IExchangeRateProvider
    function setRate(MarketId id, uint256 newRate) external {
        onlyConfig();

        exchangeRate[id] = newRate;
        emit RateUpdated(id, newRate);
    }
}
