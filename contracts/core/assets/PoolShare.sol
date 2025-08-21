// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IExpiry} from "contracts/interfaces/IExpiry.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {IReserve} from "contracts/interfaces/IReserve.sol";
import {ISwapRate} from "contracts/interfaces/ISwapRate.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Contract for Adding Swap Rate functionality
 * @author Cork Team
 * @notice Adds Swap Rate functionality to PoolShare contracts
 */
abstract contract SwapRate is ISwapRate {
    uint256 internal rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    /**
     * @notice returns the current swap rate
     */
    function swapRate() external view override returns (uint256) {
        return rate;
    }
}

/**
 * @title Contract for Adding Expiry functionality to Swap Token
 * @author Cork Team
 * @notice Adds Expiry functionality to PoolShare contracts
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
        require(_expiry > block.timestamp, InvalidExpiry());

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
 * @title PoolShare Contract
 * @author Cork Team
 * @notice Contract for implementing assets like Swap Token/Principal Token etc
 */
contract PoolShare is ERC20Burnable, ERC20Permit, Ownable, Expiry, SwapRate, IPoolShare {
    string public pairName;

    MarketId public poolId;

    IPoolManager public poolManager;

    address public factory;

    modifier onlyFactory() {
        require(_msgSender() == factory, OwnableUnauthorizedAccount(_msgSender()));

        _;
    }

    /**
     * @notice Constructor for the PoolShare contract
     * @param _pairName The name of the asset pair
     * @param _owner The address of the owner of the contract
     * @param _expiry The expiry time of the shares contract
     * @param _rate The swap rate of the shares contract
     */
    constructor(string memory _pairName, string memory _symbol, address _owner, uint256 _expiry, uint256 _rate) SwapRate(_rate) ERC20(_pairName, _symbol) ERC20Permit(_pairName) Ownable(_owner) Expiry(_expiry) {
        pairName = _pairName;

        factory = _msgSender();
    }

    /**
     * @notice Provides Collateral Assets & Reference Assets assets reserves for the shares contract
     * @param collateralAsset The Collateral Assets reserve amount for shares contract.
     * @param referenceAsset The Reference Assets reserve amount for shares contract.
     */
    function getReserves() external view returns (uint256 collateralAsset, uint256 referenceAsset) {
        collateralAsset = poolManager.valueLocked(poolId, true);
        referenceAsset = poolManager.valueLocked(poolId, false);
    }

    /**
     * @notice Sets the pool ID for the shares contract
     * @dev This function can only be called by the factory contract
     * @param _poolId The pool ID for the shares contract
     */
    function setPoolId(MarketId _poolId) external onlyFactory {
        poolId = _poolId;
    }

    /**
     * @notice Sets the cork pool address for the shares contract
     * @dev This function can only be called by the factory contract
     * @param _poolManager The address of the cork pool manager contract
     */
    function setPoolManager(address _poolManager) external onlyFactory {
        poolManager = IPoolManager(_poolManager);
    }

    /**
     * @notice mints `amount` number of tokens to `to` address
     * @param to address of receiver
     * @param amount number of tokens to be minted
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice burns `amount` number of tokens from the caller
     * @param amount number of tokens to be burned
     */
    function burn(uint256 amount) public override onlyOwner {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Updates the rate of the shares contract.
     * @dev This function can only be called by the owner of the contract.
     * @param newRate The new rate to be set for the shares contract.
     */
    function updateSwapRate(uint256 newRate) external override onlyOwner {
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

    /**
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the withdrawal
     * @param receiver The address receiving the reference assets
     * @param owner The address owning the shares
     * @param asset The address of the reference asset
     * @param assets The amount of reference assets withdrawn
     * @param shares The amount of shares burned
     */
    function emitWithdrawOther(address sender, address receiver, address owner, address asset, uint256 assets, uint256 shares) external onlyOwner {
        emit WithdrawOther(sender, receiver, owner, asset, assets, shares);
    }

    /**
     * @dev This function can only be called by the cork pool contract (owner)
     * @param sender The address initiating the deposit
     * @param owner The address receiving the shares
     * @param asset The address of the reference asset
     * @param assets The amount of reference assets deposited
     * @param shares The amount of shares minted
     */
    function emitDepositOther(address sender, address owner, address asset, uint256 assets, uint256 shares) external onlyOwner {
        emit DepositOther(sender, owner, asset, assets, shares);
    }
}
