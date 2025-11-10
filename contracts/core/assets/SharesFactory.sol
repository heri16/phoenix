// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BokkyPooBahsDateTimeLibrary} from "BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";
import {IPoolShare, PoolShare} from "contracts/core/assets/PoolShare.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title Factory contract for shares (including PoolShare)
 * @author Cork Team
 * @notice Factory contract for deploying shares contracts
 */
contract SharesFactory is ISharesFactory {
    string private constant CPT_PREFIX = "CPT";
    string private constant CST_PREFIX = "CST";

    // slither-disable-next-line naming-convention
    address public immutable CORK_POOL_MANAGER;

    modifier onlyCorkPoolManager() {
        require(CORK_POOL_MANAGER == msg.sender, NotCorkPoolManager());
        _;
    }

    ///======================================================///
    ///============== INITIALIZATION FUNCTIONS ==============///
    ///======================================================///

    constructor(address corkPoolManager) {
        require(corkPoolManager != address(0), ZeroAddress());
        CORK_POOL_MANAGER = corkPoolManager;
    }

    ///======================================================///
    ///================== CORE FUNCTIONS ====================///
    ///======================================================///

    /**
     * @notice Deploys new swap shares based on the provided parameters.
     * @dev This function deploys two new PoolShare contracts and registers them as a swap pair. Only the CorkPoolManager contract can call this function.
     * @param params The parameters required to deploy the swap shares.
     * @return principalToken The address of the first deployed Principal Token contract.
     * @return swapToken The address of the second deployed Swap token contract.
     */
    function deployPoolShares(DeployParams calldata params) external override onlyCorkPoolManager returns (address principalToken, address swapToken) {
        // slither-disable-next-line write-after-write
        (string memory name, string memory symbol) = _generateSymbolWithVariant(params.poolParams.collateralAsset, params.poolParams.referenceAsset, params.poolParams.expiryTimestamp, CPT_PREFIX);
        IPoolShare.ConstructorParams memory constructorParams = IPoolShare.ConstructorParams(params.poolId, name, symbol, params.owner);

        principalToken = address(new PoolShare(constructorParams));

        // slither-disable-next-line write-after-write
        (name, symbol) = _generateSymbolWithVariant(params.poolParams.collateralAsset, params.poolParams.referenceAsset, params.poolParams.expiryTimestamp, CST_PREFIX);
        constructorParams.pairName = name;
        constructorParams.symbol = symbol;

        swapToken = address(new PoolShare(constructorParams));

        emit SharesDeployed(params.poolParams.collateralAsset, principalToken, swapToken);
    }

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

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
