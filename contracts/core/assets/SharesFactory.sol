// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BokkyPooBahsDateTimeLibrary} from "BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";
import {IPoolShare, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title Factory contract for shares (including PoolShare)
 * @author Cork Team
 * @notice Factory contract for deploying shares contracts
 */
contract SharesFactory is ISharesFactory, OwnableUpgradeable, UUPSUpgradeable {
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

    modifier onlyCorkPool() {
        require(data().corkPool == msg.sender, NotCorkPool());
        _;
    }

    ///======================================================///
    ///============== INITIALIZATION FUNCTIONS ==============///
    ///======================================================///

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializes share factory contract and setup owner
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    ///======================================================///
    ///================== CORE FUNCTIONS ====================///
    ///======================================================///

    /**
     * @notice Deploys new swap shares based on the provided parameters.
     * @dev This function deploys two new PoolShare contracts and registers them as a swap pair. Only the CorkPool contract can call this function.
     * @param params The parameters required to deploy the swap shares.
     * @return principalToken The address of the first deployed Principal Token contract.
     * @return swapToken The address of the second deployed Swap token contract.
     */
    function deployPoolShares(DeployParams calldata params) external override onlyCorkPool returns (address principalToken, address swapToken) {
        (string memory name, string memory symbol) = _generateSymbolWithVariant(params.poolParams.collateralAsset, params.poolParams.referenceAsset, params.poolParams.expiryTimestamp, CPT_PREFIX);
        IPoolShare.ConstructorParams memory constructorParams = IPoolShare.ConstructorParams(params.poolId, params.poolParams.expiryTimestamp, name, symbol, params.owner);

        principalToken = address(new PoolShare(constructorParams));

        (name, symbol) = _generateSymbolWithVariant(params.poolParams.collateralAsset, params.poolParams.referenceAsset, params.poolParams.expiryTimestamp, CST_PREFIX);
        constructorParams.pairName = name;
        constructorParams.symbol = symbol;

        swapToken = address(new PoolShare(constructorParams));

        data().swapShares[params.poolId] = SwapPair(principalToken, swapToken);
        data().deployed[principalToken] = true;
        data().deployed[swapToken] = true;

        emit SharesDeployed(params.poolParams.collateralAsset, principalToken, swapToken);
    }

    ///======================================================///
    ///============== ADMINISTRATIVE FUNCTIONS ==============///
    ///======================================================///

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

    ///======================================================///
    ///================== VIEW FUNCTIONS ====================///
    ///======================================================///

    /**
     * @notice Returns the address of the CorkPool contract
     * @return The address of the CorkPool contract
     */
    function corkPool() external view returns (address) {
        return data().corkPool;
    }

    /**
     * @notice for safety checks in pool, also act as kind of like a registry
     * @param share the address of PoolShare contract
     */
    function isDeployed(address share) external view override returns (bool) {
        return data().deployed[share];
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

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function data() internal pure returns (SharesFactoryStorage storage fs) {
        assembly {
            fs.slot := _SHARES_FACTORY_STORAGE_POSITION
        }
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
}
