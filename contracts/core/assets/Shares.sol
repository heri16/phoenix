// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IExpiry} from "contracts/interfaces/IExpiry.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {IRates} from "contracts/interfaces/IRates.sol";
import {IReserve} from "contracts/interfaces/IReserve.sol";
import {IShares} from "contracts/interfaces/IShares.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Contract for Adding Exchange Rate functionality
 * @author Cork Team
 * @notice Adds Exchange Rate functionality to Shares contracts
 */
abstract contract ExchangeRate is IRates {
    uint256 internal rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    /**
     * @notice returns the current exchange rate
     */
    function exchangeRate() external view override returns (uint256) {
        return rate;
    }
}

/**
 * @title Contract for Adding Expiry functionality to Swap Token
 * @author Cork Team
 * @notice Adds Expiry functionality to Shares contracts
 * @dev Used for adding Expiry functionality to contracts like Swap Token
 */
abstract contract Expiry is IExpiry {
    uint256 internal immutable EXPIRY;
    uint256 internal immutable ISSUED_AT;

    /**
     * @notice Initializes the shares contract with the given expiry timestamp.
     * If the expiry timestamp is in the past, the transaction will revert with an Expired error.
     * If the expiry timestamp is 0, the transaction will revert with an InvalidExpiry error.
     * @param _expiry The expiry timestamp for the shares contract.
     */
    constructor(uint256 _expiry) {
        if (_expiry == 0) revert InvalidExpiry();

        if (_expiry < block.timestamp) revert Expired();

        EXPIRY = _expiry;
        ISSUED_AT = block.timestamp;
    }

    /**
     * @notice returns if contract is expired or not
     */
    function isExpired() public view virtual returns (bool) {
        return block.timestamp >= EXPIRY;
    }

    /**
     * @notice returns expiry timestamp of contract
     */
    function expiry() external view virtual returns (uint256) {
        return EXPIRY;
    }

    /**
     * @notice returns issued timestamp of contract
     */
    function issuedAt() external view virtual returns (uint256) {
        return ISSUED_AT;
    }
}

/**
 * @title Shares Contract
 * @author Cork Team
 * @notice Contract for implementing assets like Swap Token/Principal Token etc
 */
contract Shares is ERC20Burnable, ERC20Permit, Ownable, Expiry, ExchangeRate, IShares {
    string public pairName;

    MarketId public marketId;

    IPool public corkPool;

    address public factory;

    modifier onlyFactory() {
        if (_msgSender() != factory) revert OwnableUnauthorizedAccount(_msgSender());

        _;
    }

    /**
     * @notice Constructor for the Shares contract
     * @param _pairName The name of the asset pair
     * @param _owner The address of the owner of the contract
     * @param _expiry The expiry time of the shares contract
     * @param _rate The exchange rate of the shares contract
     */
    constructor(string memory _pairName, address _owner, uint256 _expiry, uint256 _rate) ExchangeRate(_rate) ERC20(_pairName, _pairName) ERC20Permit(_pairName) Ownable(_owner) Expiry(_expiry) {
        pairName = _pairName;

        factory = _msgSender();
    }

    /**
     * @notice Provides Collateral Assets & Reference Assets assets reserves for the shares contract
     * @param collateralAsset The Collateral Assets reserve amount for shares contract.
     * @param referenceAsset The Reference Assets reserve amount for shares contract.
     */
    function getReserves() external view returns (uint256 collateralAsset, uint256 referenceAsset) {
        collateralAsset = corkPool.valueLocked(marketId, true);
        referenceAsset = corkPool.valueLocked(marketId, false);
    }

    /**
     * @notice Sets the market ID for the shares contract
     * @dev This function can only be called by the factory contract
     * @param _marketId The market ID for the shares contract
     */
    function setMarketId(MarketId _marketId) external onlyFactory {
        marketId = _marketId;
    }

    /**
     * @notice Sets the cork pool address for the shares contract
     * @dev This function can only be called by the factory contract
     * @param _corkPool The address of the cork pool contract
     */
    function setCorkPool(address _corkPool) external onlyFactory {
        corkPool = IPool(_corkPool);
    }

    /**
     * @notice mints `amount` number of tokens to `to` address
     * @param to address of receiver
     * @param amount number of tokens to be minted
     */
    function mint(address to, uint256 amount) public onlyOwner {
        if (isExpired()) revert Expired();
        _mint(to, amount);
    }

    /**
     * @notice Updates the rate of the shares contract.
     * @dev This function can only be called by the owner of the contract.
     * @param newRate The new rate to be set for the shares contract.
     */
    function updateRate(uint256 newRate) external override onlyOwner {
        rate = newRate;
    }

    /**
     * @notice Transfer `amount` of token to address `to` on behalf of `owner` by spending the allowance that `owner` has to `sender`  .
     * - This operation can only be done by cork pool
     * @param sender The address of the sender
     * @param owner The address of the owner
     * @param to The address of the receiver
     * @param amount The amount of tokens to transfer
     */
    function transferFrom(address sender, address owner, address to, uint256 amount) public onlyOwner {
        if (sender != owner) _spendAllowance(owner, sender, amount);

        _transfer(owner, to, amount);
    }

    /**
     * @notice Emits a deposit event for ERC4626 compatibility
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the deposit
     * @param receiver The address receiving the shares
     * @param assets The amount of assets deposited
     * @param shares The amount of shares minted
     */
    function emitDeposit(address sender, address receiver, uint256 assets, uint256 shares) external onlyOwner {
        emit Deposit(sender, receiver, assets, shares);
    }

    /**
     * @notice Emits a withdraw event for ERC4626 compatibility
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the withdrawal
     * @param receiver The address receiving the assets
     * @param owner The address owning the shares
     * @param assets The amount of assets withdrawn
     * @param shares The amount of shares burned
     */
    function emitWithdraw(address sender, address receiver, address owner, uint256 assets, uint256 shares) external onlyOwner {
        emit Withdraw(sender, receiver, owner, assets, shares);
    }
}
