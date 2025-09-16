// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IExpiry} from "contracts/interfaces/IExpiry.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {ISwapRate} from "contracts/interfaces/ISwapRate.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

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

    /// @inheritdoc IExpiry
    function isExpired() public view virtual returns (bool) {
        return block.timestamp >= EXPIRY;
    }

    /// @inheritdoc IExpiry
    function expiry() external view virtual returns (uint256) {
        return EXPIRY;
    }

    /// @inheritdoc IExpiry
    function issuedAt() external view virtual returns (uint256) {
        return ISSUED_AT;
    }
}

/**
 * @title PoolShare Contract
 * @author Cork Team
 * @notice Contract for implementing assets like Swap Token/Principal Token etc
 */
contract PoolShare is ERC20Burnable, ERC20Permit, Ownable, Expiry, ISwapRate, IPoolShare {
    string public pairName;

    MarketId public poolId;

    IPoolManager public poolManager;

    address public factory;

    modifier onlyFactory() {
        require(_msgSender() == factory, OwnableUnauthorizedAccount(_msgSender()));

        _;
    }

    constructor(IPoolShare.ConstructorParams memory params) ERC20(params.pairName, params.symbol) ERC20Permit(params.pairName) Ownable(params.poolManager) Expiry(params.expiry) {
        pairName = params.pairName;
        poolManager = IPoolManager(params.poolManager);
        poolId = params.poolId;

        factory = _msgSender();
    }

    /// @inheritdoc ISwapRate
    function swapRate() external view returns (uint256 rate) {
        return poolManager.swapRate(poolId);
    }

    /**
     * @notice Provides Collateral Assets & Reference Assets assets reserves for the shares contract
     * @param collateralAsset The Collateral Assets reserve amount for shares contract.
     * @param referenceAsset The Reference Assets reserve amount for shares contract.
     */
    function getReserves() external view returns (uint256 collateralAsset, uint256 referenceAsset) {
        (collateralAsset, referenceAsset) = poolManager.valueLocked(poolId);
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

    /// @inheritdoc ERC20Burnable
    function burn(uint256 amount) public override onlyOwner {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice burns `amount` number of tokens from `owner`
     * @param owner address of the owner to be burned from
     * @param amount number of tokens to be burned
     */
    function burnFrom(address owner, uint256 amount) public override onlyOwner {
        _spendAllowance(owner, _msgSender(), amount);
        _burn(owner, amount);
    }

    /**
     * @notice burns `amount` number of tokens from `owner` by spending the allowance that `owner` has to `sender`  .
     * - This operation can only be done by cork pool
     * - if sender == owner, it will treat it as a regular `burn`
     * @param sender The address of the sender
     * @param owner address of the owner to be burned from
     * @param amount number of tokens to be burned
     */
    function burnFrom(address sender, address owner, uint256 amount) public onlyOwner {
        // we branch here because in case sender == owner, who would in the right mind give allowance
        // to themselves. so it will treat it as a regular `burn`
        if (sender != owner) _spendAllowance(owner, sender, amount);

        _burn(owner, amount);
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

    /// @inheritdoc IPoolShare
    function emitDeposit(address sender, address receiver, uint256 assets, uint256 shares) external onlyOwner {
        emit Deposit(sender, receiver, assets, shares);
    }

    /// @inheritdoc IPoolShare
    function emitWithdraw(address sender, address receiver, address owner, uint256 assets, uint256 shares) external onlyOwner {
        emit Withdraw(sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc IPoolShare
    function emitWithdrawOther(address sender, address receiver, address owner, address asset, uint256 assets, uint256 shares) external onlyOwner {
        emit WithdrawOther(sender, receiver, owner, asset, assets, shares);
    }

    /// @inheritdoc IPoolShare
    function emitDepositOther(address sender, address owner, address asset, uint256 assets, uint256 shares) external onlyOwner {
        emit DepositOther(sender, owner, asset, assets, shares);
    }

    /// @inheritdoc IPoolShare
    function maxMint(address owner) public view returns (uint256 maxAmount) {
        return poolManager.maxMint(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxDeposit(address owner) public view returns (uint256 maxCollateralAssets) {
        return poolManager.maxDeposit(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindDeposit(address owner) public view returns (uint256 maxCollateralAssetAmountOut) {
        return poolManager.maxUnwindDeposit(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindMint(address owner) public view returns (uint256 maxCptAndCstSharesIn) {
        return poolManager.maxUnwindMint(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxWithdraw(address owner) public view returns (uint256 maxCollateralAssets) {
        return poolManager.maxWithdraw(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxWithdrawOther(address owner) public view returns (uint256 maxReferenceAssets) {
        return poolManager.maxWithdrawOther(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxExercise(address owner) public view returns (uint256 maxCstShares) {
        return poolManager.maxExercise(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxExerciseOther(address owner) public view returns (uint256 maxReferenceAssets) {
        return poolManager.maxExerciseOther(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return poolManager.maxRedeem(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxSwap(address owner) public view returns (uint256 maxAssets) {
        return poolManager.maxSwap(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindExercise(address receiver) public view returns (uint256 maxShares) {
        return poolManager.maxUnwindExercise(poolId, receiver);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindExerciseOther(address receiver) public view returns (uint256 maxReferenceAssets) {
        return poolManager.maxUnwindExerciseOther(poolId, receiver);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindSwap(address receiver) public view returns (uint256 maxAmount) {
        return poolManager.maxUnwindSwap(poolId, receiver);
    }

    /// @inheritdoc IPoolShare
    function previewExercise(uint256 shares, uint256 compensation) public view returns (uint256 assets, uint256 otherAssetSpent, uint256 fee) {
        return poolManager.previewExercise(poolId, shares, compensation);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindExercise(uint256 shares) public view returns (uint256 assetIn, uint256 compensationOut) {
        return poolManager.previewUnwindExercise(poolId, shares);
    }

    /// @inheritdoc IPoolShare
    function previewDeposit(uint256 collateralAssets) public view returns (uint256 outShares) {
        return poolManager.previewDeposit(poolId, collateralAssets);
    }

    /// @inheritdoc IPoolShare
    function previewSwap(uint256 collateralAssets) public view returns (uint256 suppliedCstShares, uint256 suppliedReferenceAssets) {
        return poolManager.previewSwap(poolId, collateralAssets);
    }

    /// @inheritdoc IPoolShare
    function previewRedeem(uint256 cptShares) public view returns (uint256 outReferenceAssets, uint256 outCollateralAssets) {
        return poolManager.previewRedeem(poolId, cptShares);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindDeposit(uint256 collateralAssets) public view returns (uint256 suppliedShares) {
        return poolManager.previewUnwindDeposit(poolId, collateralAssets);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindSwap(uint256 collateralAssets) public view returns (uint256 outReferenceAssets, uint256 outCstShares) {
        IUnwindSwap.UnwindSwapReturnParams memory returnParams = poolManager.previewUnwindSwap(poolId, collateralAssets);
        outReferenceAssets = returnParams.receivedReferenceAsset;
        outCstShares = returnParams.receivedSwapToken;
    }

    /// @inheritdoc IPoolShare
    function previewMint(uint256 shares) public view returns (uint256 suppliedCollateralAssets) {
        return poolManager.previewMint(poolId, shares);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindMint(uint256 shares) public view returns (uint256 outCollateralAssets) {
        return poolManager.previewUnwindMint(poolId, shares);
    }

    /// @inheritdoc IPoolShare
    function previewWithdraw(uint256 collateralAssetOut, uint256 referenceAssetOut) public view returns (uint256 sharesIn, uint256 actualReferenceAssetOut) {
        return poolManager.previewWithdraw(poolId, collateralAssetOut, referenceAssetOut);
    }
}
