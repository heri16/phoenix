// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BokkyPooBahsDateTimeLibrary} from "BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";

/**
 * @title Factory contract for shares (including PoolShare)
 * @author Cork Team
 * @notice Factory contract for deploying shares contracts
 */
contract SharesFactory is ISharesFactory, OwnableUpgradeable, UUPSUpgradeable {
    using MarketLibrary for Market;

    string private constant CPT_PREFIX = "CPT";
    string private constant CST_PREFIX = "CST";

    struct SwapPair {
        address principalToken;
        address swapToken;
    }

    struct SharesFactoryStorage {
        address corkPool;
        mapping(MarketId => SwapPair) swapShares;
        mapping(address => bool) deployed;
    }

    // ERC-7201 Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cork.storage.SharesFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _SHARES_FACTORY_STORAGE_POSITION = 0xae1bdbe81317319de75cce51dab9288f0dd5d17842126825ac85236faa7ace00;

    function data() internal pure returns (SharesFactoryStorage storage fs) {
        assembly {
            fs.slot := _SHARES_FACTORY_STORAGE_POSITION
        }
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev will generate symbol such as wstETH03CPT.
     * @param collateralAsset The address of the Collateral Asset token.
     * @param referenceAsset The address of the Reference Asset token.
     * @param expiry The expiry date in Unix timestamp format.
     * @param prefix The prefix to be added to the symbol.
     * @return name The generated name with the variant.
     * @return symbol The generated symbol with the variant.
     */
    function _generateSymbolWithVariant(address collateralAsset, address referenceAsset, uint256 expiry, string memory prefix) internal view returns (string memory name, string memory symbol) {
        string memory referenceSymbol = IERC20Metadata(referenceAsset).symbol();
        string memory month = Strings.toString(BokkyPooBahsDateTimeLibrary.getMonth(expiry));

        name = string.concat(IERC20Metadata(collateralAsset).symbol(), "-", referenceSymbol, month, prefix);
        symbol = string.concat(referenceSymbol, month, prefix);
    }

    /**
     * @notice for safety checks in pool, also act as kind of like a registry
     * @param share the address of PoolShare contract
     */
    function isDeployed(address share) external view override returns (bool) {
        return data().deployed[share];
    }

    modifier onlyCorkPool() {
        require(data().corkPool == msg.sender, NotCorkPool());
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
     * @param poolId id of the pool
     * @return principalToken deployed Principal Token shares
     * @return swapToken deployed Swap Token shares
     */
    function poolShares(MarketId poolId) external view override returns (address principalToken, address swapToken) {
        SwapPair memory _shares = data().swapShares[poolId];
        principalToken = _shares.principalToken;
        swapToken = _shares.swapToken;
    }

    /**
     * @notice Deploys new swap shares based on the provided parameters.
     * @dev This function deploys two new PoolShare contracts and registers them as a swap pair. Only the CorkPool contract can call this function.
     * @param params The parameters required to deploy the swap shares.
     * @return principalToken The address of the first deployed Principal Token contract.
     * @return swapToken The address of the second deployed Swap token contract.
     */
    function deployPoolShares(DeployParams calldata params) external override onlyCorkPool returns (address principalToken, address swapToken) {
        require(params.swapRate > 0, InvalidRate());
        MarketId poolId = params.poolParams.toId();

        {
            (string memory name, string memory symbol) = _generateSymbolWithVariant(params.poolParams.collateralAsset, params.poolParams.referenceAsset, params.poolParams.expiryTimestamp, CPT_PREFIX);
            principalToken = address(new PoolShare(name, symbol, params.owner, params.poolParams.expiryTimestamp, params.swapRate));

            PoolShare(principalToken).setPoolManager(data().corkPool);
            PoolShare(principalToken).setPoolId(poolId);

            (name, symbol) = _generateSymbolWithVariant(params.poolParams.collateralAsset, params.poolParams.referenceAsset, params.poolParams.expiryTimestamp, CST_PREFIX);
            swapToken = address(new PoolShare(name, symbol, params.owner, params.poolParams.expiryTimestamp, params.swapRate));

            PoolShare(swapToken).setPoolManager(data().corkPool);
            PoolShare(swapToken).setPoolId(poolId);
        }

        data().swapShares[poolId] = SwapPair(principalToken, swapToken);
        data().deployed[principalToken] = true;
        data().deployed[swapToken] = true;

        emit SharesDeployed(params.poolParams.collateralAsset, principalToken, swapToken);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Sets the CorkPool contract address for the factory contract.
     * @dev Only the owner of the factory contract can call this function.
     * @param _corkPool The address of the CorkPool contract.
     */
    function setCorkPool(address _corkPool) external onlyOwner {
        require(_corkPool != address(0), ZeroAddress());

        address oldCorkPool = data().corkPool;
        data().corkPool = _corkPool;
        emit CorkPoolChanged(oldCorkPool, _corkPool);
    }

    /**
     * @notice Returns the address of the CorkPool contract
     * @return The address of the CorkPool contract
     */
    function corkPool() external view returns (address) {
        return data().corkPool;
    }
}
