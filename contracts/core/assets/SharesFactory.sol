// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BokkyPooBahsDateTimeLibrary} from "BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";
import {Shares} from "contracts/core/assets/Shares.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";

/**
 * @title Factory contract for Shares
 * @author Cork Team
 * @notice Factory contract for deploying shares contracts
 */
contract SharesFactory is ISharesFactory, OwnableUpgradeable, UUPSUpgradeable {
    using MarketLibrary for Market;

    string private constant CPT_PREFIX = "CPT";
    string private constant CST_PREFIX = "CST";

    address public corkPool;

    struct SwapPair {
        address principalToken;
        address swapToken;
    }

    mapping(MarketId => SwapPair) internal swapShares;
    mapping(address => bool) internal deployed;

    /// @notice __gap variable to prevent storage collisions
    // slither-disable-next-line unused-state
    uint256[49] private __gap;

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev will generate symbol such as wstETH03CPT.
     * @param referenceAsset The address of the Reference Asset token.
     * @param expiry The expiry date in Unix timestamp format.
     * @param prefix The prefix to be added to the symbol.
     * @return symbol The generated symbol with the variant.
     */
    function _generateSymbolWithVariant(address referenceAsset, uint256 expiry, string memory prefix) internal view returns (string memory symbol) {
        string memory baseSymbol = IERC20Metadata(referenceAsset).symbol();
        string memory month = Strings.toString(BokkyPooBahsDateTimeLibrary.getMonth(expiry));

        symbol = string.concat(baseSymbol, month, prefix);
    }

    /**
     * @notice for safety checks in pool, also act as kind of like a registry
     * @param share the address of Shares contract
     */
    function isDeployed(address share) external view override returns (bool) {
        return deployed[share];
    }

    modifier onlyCorkPool() {
        if (corkPool != msg.sender) revert NotCorkPool();
        _;
    }

    /**
     * @notice initializes share factory contract and setup owner
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice for getting deployed SwapShare for given parameters with this factory
     * @param _collateralAsset Address of Collateral Asset
     * @param _referenceAsset Address of Reference Asset
     * @param _expiryTimestamp expiry timestamp
     * @param _exchangeRateProvider address of exchange rate provider
     * @return principalToken deployed Principal Token shares
     * @return swapToken deployed Swap Token shares
     */
    function getDeployedSwapShares(address _collateralAsset, address _referenceAsset, uint256 _expiryTimestamp, address _exchangeRateProvider) external view override returns (address principalToken, address swapToken) {
        SwapPair memory _shares = swapShares[Market(_referenceAsset, _collateralAsset, _expiryTimestamp, _exchangeRateProvider).toId()];
        principalToken = _shares.principalToken;
        swapToken = _shares.swapToken;
    }

    /**
     * @notice Deploys new swap shares based on the provided parameters.
     * @dev This function deploys two new Shares contracts and registers them as a swap pair. Only the CorkPool contract can call this function.
     * @param params The parameters required to deploy the swap shares.
     * @return principalToken The address of the first deployed Principal Token contract.
     * @return swapToken The address of the second deployed Swap token contract.
     */
    function deploySwapShares(DeployParams calldata params) external override onlyCorkPool returns (address principalToken, address swapToken) {
        if (params.exchangeRate == 0) revert InvalidRate();
        Market memory market = Market(params._referenceAsset, params._collateralAsset, params.expiryTimestamp, params.exchangeRateProvider);
        MarketId id = market.toId();

        {
            principalToken = address(new Shares(_generateSymbolWithVariant(market.referenceAsset, params.expiryTimestamp, CPT_PREFIX), params._owner, params.expiryTimestamp, params.exchangeRate));

            Shares(principalToken).setMarketId(id);
            Shares(principalToken).setCorkPool(corkPool);

            swapToken = address(new Shares(_generateSymbolWithVariant(market.referenceAsset, params.expiryTimestamp, CST_PREFIX), params._owner, params.expiryTimestamp, params.exchangeRate));

            Shares(swapToken).setMarketId(id);
            Shares(swapToken).setCorkPool(corkPool);
        }

        swapShares[id] = SwapPair(principalToken, swapToken);

        deployed[principalToken] = true;
        deployed[swapToken] = true;

        emit SharesDeployed(params._collateralAsset, principalToken, swapToken);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Sets the CorkPool contract address for the factory contract.
     * @dev Only the owner of the factory contract can call this function.
     * @param _corkPool The address of the CorkPool contract.
     */
    function setCorkPool(address _corkPool) external onlyOwner {
        if (_corkPool == address(0)) revert ZeroAddress();

        address oldCorkPool = corkPool;
        corkPool = _corkPool;
        emit CorkPoolChanged(oldCorkPool, _corkPool);
    }
}
