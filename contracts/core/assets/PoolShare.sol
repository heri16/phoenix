// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IPoolShare} from "contracts/interfaces/IPoolShare.sol";
import {ISwapRate} from "contracts/interfaces/ISwapRate.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title PoolShare Contract
 * @author Cork Team
 * @notice Contract for implementing assets like Swap Token/Principal Token etc
 */
contract PoolShare is ERC20Burnable, ERC20Permit, Ownable, ISwapRate, IPoolShare {
    string public pairName;

    // poolId, poolManager, factory needs to adhere to IPoolShare interface without extra boilerplate
    // so we keep the variable camel case rather than SCREAMING_CASE
    MarketId public immutable poolId;

    IPoolManager public immutable poolManager;

    address public immutable factory;

    uint256 public immutable issuedAt;

    ///======================================================///
    ///=================== MODIFIERS ========================///
    ///======================================================///

    modifier onlyFactory() {
        require(_msgSender() == factory, OwnableUnauthorizedAccount(_msgSender()));

        _;
    }

    ///======================================================///
    ///================== CONSTRUCTOR =======================///
    ///======================================================///

    constructor(IPoolShare.ConstructorParams memory params) ERC20(params.pairName, params.symbol) ERC20Permit(params.pairName) Ownable(params.poolManager) {
        pairName = params.pairName;
        poolManager = IPoolManager(params.poolManager);
        poolId = params.poolId;

        factory = _msgSender();
        issuedAt = block.timestamp;
    }

    ///======================================================///
    ///================== VIEW FUNCTIONS ====================///
    ///======================================================///

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
        (collateralAsset, referenceAsset) = poolManager.assets(poolId);
    }

    /// @inheritdoc IPoolShare
    function isExpired() public view returns (bool) {
        Market memory market = poolManager.market(poolId);
        // slither-disable-next-line timestamp
        return block.timestamp >= market.expiryTimestamp;
    }

    /// @inheritdoc IPoolShare
    function expiry() external view returns (uint256) {
        Market memory market = poolManager.market(poolId);
        return market.expiryTimestamp;
    }

    ///======================================================///
    ///================== CORE FUNCTIONS ====================///
    ///======================================================///

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
     * - This operation can only be done by CorkPoolManager
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
     * - This operation can only be done by CorkPoolManager
     * @param sender The address of the sender
     * @param owner The address of the owner
     * @param to The address of the receiver
     * @param amount The amount of tokens to transfer
     */
    function transferFrom(address sender, address owner, address to, uint256 amount) public onlyOwner {
        if (sender != owner) _spendAllowance(owner, sender, amount);

        _transfer(owner, to, amount);
    }

    ///======================================================///
    ///================= EVENT EMITTER FUNCTIONS ============///
    ///======================================================///

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

    ///======================================================///
    ///=================== MAX FUNCTIONS ====================///
    ///======================================================///

    /// @inheritdoc IPoolShare
    function maxMint(address owner) public view returns (uint256 maxCptAndCstSharesOut) {
        maxCptAndCstSharesOut = poolManager.maxMint(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxDeposit(address owner) public view returns (uint256 maxCollateralAssetsIn) {
        maxCollateralAssetsIn = poolManager.maxDeposit(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindDeposit(address owner) public view returns (uint256 maxCollateralAssetsOut) {
        maxCollateralAssetsOut = poolManager.maxUnwindDeposit(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindMint(address owner) public view returns (uint256 maxCptAndCstSharesIn) {
        maxCptAndCstSharesIn = poolManager.maxUnwindMint(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxWithdraw(address owner) public view returns (uint256 maxCollateralAssetsOut) {
        maxCollateralAssetsOut = poolManager.maxWithdraw(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxWithdrawOther(address owner) public view returns (uint256 maxReferenceAssetsOut) {
        maxReferenceAssetsOut = poolManager.maxWithdrawOther(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxExercise(address owner) public view returns (uint256 maxCstSharesIn) {
        maxCstSharesIn = poolManager.maxExercise(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxExerciseOther(address owner) public view returns (uint256 maxReferenceAssetsIn) {
        maxReferenceAssetsIn = poolManager.maxExerciseOther(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxRedeem(address owner) public view returns (uint256 maxCptSharesIn) {
        maxCptSharesIn = poolManager.maxRedeem(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxSwap(address owner) public view returns (uint256 maxCollateralAssetsOut) {
        maxCollateralAssetsOut = poolManager.maxSwap(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindExercise(address owner) public view returns (uint256 maxCstSharesOut) {
        maxCstSharesOut = poolManager.maxUnwindExercise(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindExerciseOther(address owner) public view returns (uint256 maxReferenceAssetsOut) {
        maxReferenceAssetsOut = poolManager.maxUnwindExerciseOther(poolId, owner);
    }

    /// @inheritdoc IPoolShare
    function maxUnwindSwap(address owner) public view returns (uint256 maxCollateralAssetsIn) {
        maxCollateralAssetsIn = poolManager.maxUnwindSwap(poolId, owner);
    }

    ///======================================================///
    ///================= PREVIEW FUNCTIONS ==================///
    ///======================================================///

    /// @inheritdoc IPoolShare
    function previewExercise(uint256 cstSharesIn) public view returns (uint256 collateralAssetsOut, uint256 referenceAssetsIn, uint256 fee) {
        (collateralAssetsOut, referenceAssetsIn, fee) = poolManager.previewExercise(poolId, cstSharesIn);
    }

    /// @inheritdoc IPoolShare
    function previewExerciseOther(uint256 referenceAssetsIn) public view returns (uint256 collateralAssetsOut, uint256 cstSharesIn, uint256 fee) {
        (collateralAssetsOut, cstSharesIn, fee) = poolManager.previewExerciseOther(poolId, referenceAssetsIn);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindExercise(uint256 cstSharesOut) public view returns (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) {
        (collateralAssetsIn, referenceAssetsOut, fee) = poolManager.previewUnwindExercise(poolId, cstSharesOut);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindExerciseOther(uint256 referenceAssetsOut) public view returns (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) {
        (collateralAssetsIn, cstSharesOut, fee) = poolManager.previewUnwindExerciseOther(poolId, referenceAssetsOut);
    }

    /// @inheritdoc IPoolShare
    function previewDeposit(uint256 collateralAssetsIn) public view returns (uint256 cptAndCstSharesOut) {
        (cptAndCstSharesOut) = poolManager.previewDeposit(poolId, collateralAssetsIn);
    }

    /// @inheritdoc IPoolShare
    function previewSwap(uint256 collateralAssetsOut) public view returns (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee) {
        (cstSharesIn, referenceAssetsIn, fee) = poolManager.previewSwap(poolId, collateralAssetsOut);
    }

    /// @inheritdoc IPoolShare
    function previewRedeem(uint256 cptSharesIn) public view returns (uint256 referenceAssetsOut, uint256 collateralAssetsOut) {
        (referenceAssetsOut, collateralAssetsOut) = poolManager.previewRedeem(poolId, cptSharesIn);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindDeposit(uint256 collateralAssetsOut) public view returns (uint256 cptAndCstSharesIn) {
        (cptAndCstSharesIn) = poolManager.previewUnwindDeposit(poolId, collateralAssetsOut);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindSwap(uint256 collateralAssetsIn) public view returns (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee) {
        (cstSharesOut, referenceAssetsOut, fee) = poolManager.previewUnwindSwap(poolId, collateralAssetsIn);
    }

    /// @inheritdoc IPoolShare
    function previewMint(uint256 cptAndCstSharesOut) public view returns (uint256 collateralAssetsIn) {
        (collateralAssetsIn) = poolManager.previewMint(poolId, cptAndCstSharesOut);
    }

    /// @inheritdoc IPoolShare
    function previewUnwindMint(uint256 cptAndCstSharesIn) public view returns (uint256 collateralAssetsOut) {
        (collateralAssetsOut) = poolManager.previewUnwindMint(poolId, cptAndCstSharesIn);
    }

    /// @inheritdoc IPoolShare
    function previewWithdraw(uint256 collateralAssetsOut) external view returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut) {
        (cptSharesIn, actualCollateralAssetsOut, actualReferenceAssetsOut) = poolManager.previewWithdraw(poolId, collateralAssetsOut);
    }

    /// @inheritdoc IPoolShare
    function previewWithdrawOther(uint256 referenceAssetsOut) external view returns (uint256 cptSharesIn, uint256 actualCollateralAssetsOut, uint256 actualReferenceAssetsOut) {
        (cptSharesIn, actualCollateralAssetsOut, actualReferenceAssetsOut) = poolManager.previewWithdrawOther(poolId, referenceAssetsOut);
    }
}
