// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "./../interfaces/IErrors.sol";
import {IPoolManager, Market, MarketId} from "./../interfaces/IPoolManager.sol";
import {TransferHelper} from "./../libraries/TransferHelper.sol";
import {GeneralAdapter} from "./GeneralAdapter.sol";
import {ErrorsLib} from "./bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract CorkPoolAdapter is GeneralAdapter {
    /// @notice The address of the core Cork contract.
    IPoolManager public immutable CORK;

    /// @param bundler3 The address of the Bundler3 contract.
    /// @param wNative The address of the canonical native token wrapper.
    /// @param cork The address of the Cork's IPool contract.
    constructor(address bundler3, address wNative, address cork) GeneralAdapter(bundler3, wNative) {
        require(cork != address(0), ErrorsLib.ZeroAddress());

        CORK = IPoolManager(cork);
    }

    /// @notice Mints shares(CST & CPT) of an Cork Pool.
    /// @dev Underlying tokens must have been previously sent to the adapter.
    /// @param poolId The cork pool market id
    /// @param shares The amount of vault shares to mint.
    /// @param receiver The address to which shares(CST & CPT) will be minted.
    /// @param maxAssetsIn The maximum amount of collateral assets to spend for minting shares.
    /// @param deadline The deadline by which the transaction must be completed.
    function safeMint(MarketId poolId, uint256 shares, address receiver, uint256 maxAssetsIn, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(shares != 0, ErrorsLib.ZeroShares());

        (address _collateralAsset,) = CORK.underlyingAsset(poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 assets = CORK.mint(poolId, shares, receiver);

        // Check slippage protection
        require(assets <= maxAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Deposits collateral token in a Cork Market.
    /// @dev Underlying tokens must have been previously sent to the adapter.
    /// @param poolId The cork pool market id
    /// @param assets The amount of collateral asset to deposit.
    /// @param receiver The address to which shares(CST & CPT) will be minted.
    /// @param minSharesOut The minimum amount of shares to receive from the deposit.
    /// @param deadline The deadline by which the transaction must be completed.
    function safeDeposit(MarketId poolId, uint256 assets, address receiver, uint256 minSharesOut, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(assets != 0, ErrorsLib.ZeroAmount());

        (address _collateralAsset,) = CORK.underlyingAsset(poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 shares = CORK.deposit(poolId, assets, receiver);

        // Check slippage protection
        require(shares >= minSharesOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Unwinds a deposit by burning equal amounts of CPT and CST shares.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param poolId The cork pool market id
    /// @param assets The amount of target collateral to get from the unwind.
    /// @param owner The address that owns the CPT and CST shares being burned
    /// @param receiver The address to which collateral assets and any excess shares will be sent.
    /// @param maxSharesIn The maximum amount of shares to burn for the unwind operation.
    /// @param deadline The deadline by which the transaction must be completed.
    function safeUnwindDeposit(MarketId poolId, uint256 assets, address owner, address receiver, uint256 maxSharesIn, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(owner == address(this) || owner == initiator(), ErrorsLib.UnexpectedOwner());
        require(assets != 0, ErrorsLib.ZeroAmount());

        IERC20 collateralAsset;
        IERC20 cpt;
        IERC20 cst;
        {
            (address _collateralAsset,) = CORK.underlyingAsset(poolId);
            collateralAsset = IERC20(_collateralAsset);

            (address principalToken, address swapToken) = CORK.shares(poolId);
            cpt = IERC20(principalToken);
            cst = IERC20(swapToken);
        }

        require(assets != 0, ErrorsLib.ZeroAmount());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);

        uint256 sharesIn = CORK.unwindDeposit(poolId, assets, owner, receiver);

        // Check slippage protection
        require(sharesIn <= maxSharesIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
        SafeERC20.forceApprove(cst, address(CORK), 0);
    }

    /// @notice Unwinds a mint by burning equal amounts of CPT and CST shares.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param poolId The cork pool market id
    /// @param shares The amount of shares to redeem. Pass type(uint).max to redeem the owner's shares.
    /// @param owner The address that owns the CPT and CST shares being burned
    /// @param receiver The address to which collateral assets and any excess shares will be sent.
    /// @param minAssetsOut The minimum amount of collateral to receive from the unwind operation.
    /// @param deadline The deadline by which the transaction must be completed.
    function safeUnwindMint(MarketId poolId, uint256 shares, address owner, address receiver, uint256 minAssetsOut, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(owner == address(this) || owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 collateralAsset;
        IERC20 cpt;
        IERC20 cst;
        {
            (address _collateralAsset,) = CORK.underlyingAsset(poolId);
            collateralAsset = IERC20(_collateralAsset);

            (address principalToken, address swapToken) = CORK.shares(poolId);
            cpt = IERC20(principalToken);
            cst = IERC20(swapToken);
        }

        if (shares == type(uint256).max) {
            // Use the minimum of CPT and CST balances from owner
            uint256 cptBalance = owner == address(this) ? cpt.balanceOf(owner) : cpt.allowance(owner, address(this));
            uint256 cstBalance = owner == address(this) ? cst.balanceOf(owner) : cst.allowance(owner, address(this));
            shares = cptBalance < cstBalance ? cptBalance : cstBalance;
        }

        require(shares != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);

        uint256 assets = CORK.unwindMint(poolId, shares, owner, receiver);

        // Check slippage protection
        require(assets >= minAssetsOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
        SafeERC20.forceApprove(cst, address(CORK), 0);
    }

    /// @notice Withdraws specific amounts of collateral and/or reference assets from a Cork Pool.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @notice Either collateralAssets or referenceAssets must be 0.
    /// @param poolId The cork pool market id
    /// @param collateralAssets The amount of collateral asset to withdraw (set to 0 if withdrawing reference asset)
    /// @param referenceAssets The amount of reference asset to withdraw (set to 0 if withdrawing collateral asset)
    /// @param owner The address that owns the CPT shares being burned
    /// @param receiver The address to which withdrawn assets will be sent
    /// @param maxSharesIn The maximum amount of CPT shares to burn for the withdrawal
    /// @param deadline The deadline by which the transaction must be completed
    function safeWithdraw(MarketId poolId, uint256 collateralAssets, uint256 referenceAssets, address owner, address receiver, uint256 maxSharesIn, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(owner == address(this) || owner == initiator(), ErrorsLib.UnexpectedOwner());

        // Ensure either collateralAssets or referenceAssets is 0 (not both non-zero)
        require(collateralAssets == 0 || referenceAssets == 0, ErrorsLib.ZeroAmount());
        require(collateralAssets != 0 || referenceAssets != 0, ErrorsLib.ZeroAmount());

        IERC20 collateralAsset;
        IERC20 referenceAsset;
        IERC20 cpt;
        {
            (address _collateralAsset, address _referenceAsset) = CORK.underlyingAsset(poolId);
            collateralAsset = IERC20(_collateralAsset);
            referenceAsset = IERC20(_referenceAsset);

            (address principalToken,) = CORK.shares(poolId);
            cpt = IERC20(principalToken);
        }

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);

        (uint256 sharesIn,,) = CORK.withdraw(poolId, collateralAssets, referenceAssets, owner, receiver);

        // Check slippage protection
        require(sharesIn <= maxSharesIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
    }

    /// @notice Redeems CPT tokens for collateral and reference assets at expiry.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param poolId The cork pool market id
    /// @param cptShares The amount of CPT tokens to redeem. Pass `type(uint).max` to use the adapter's CPT balance/allowance.
    /// @param owner The address that owns the CPT tokens being redeemed
    /// @param receiver The address to which redeemed assets will be sent
    /// @param minReferenceAssetsOut The minimum amount of reference asset to receive
    /// @param minCollateralAssetsOut The minimum amount of collateral asset to receive
    /// @param deadline The deadline by which the transaction must be completed
    function safeRedeem(MarketId poolId, uint256 cptShares, address owner, address receiver, uint256 minReferenceAssetsOut, uint256 minCollateralAssetsOut, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(owner == address(this) || owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 cpt;
        {
            (address principalToken,) = CORK.shares(poolId);
            cpt = IERC20(principalToken);
        }

        if (cptShares == type(uint256).max) cptShares = owner == address(this) ? cpt.balanceOf(owner) : cpt.allowance(owner, address(this));

        require(cptShares != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);

        (uint256 referenceOut, uint256 assets) = CORK.redeem(poolId, cptShares, owner, receiver);

        // Check slippage protection
        require(referenceOut >= minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(assets >= minCollateralAssetsOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
    }

    /// @notice Unwinds a swap by using collateral assets to receive reference assets and swap tokens.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param poolId The cork pool market id
    /// @param collateralAssets The amount of collateral assets to use for unwind swap. Pass `type(uint).max` to use the adapter's collateral asset balance.
    /// @param receiver The address to which reference assets and swap tokens will be sent
    /// @param minReferenceAssetsOut The minimum amount of reference assets to receive
    /// @param minCstSharesOut The minimum amount of swap tokens to receive
    /// @param deadline The deadline by which the transaction must be completed
    function safeUnwindSwap(MarketId poolId, uint256 collateralAssets, address receiver, uint256 minReferenceAssetsOut, uint256 minCstSharesOut, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());

        (address _collateralAsset,) = CORK.underlyingAsset(poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        if (collateralAssets == type(uint256).max) collateralAssets = collateralAsset.balanceOf(address(this));

        require(collateralAssets != 0, ErrorsLib.ZeroAmount());

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        (uint256 receivedReferenceAsset, uint256 receivedSwapToken,,,) = CORK.unwindSwap(poolId, collateralAssets, receiver);

        // Check slippage protection
        require(receivedReferenceAsset >= minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(receivedSwapToken >= minCstSharesOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Swaps CST shares and reference token compensation for collateral assets.
    /// @notice if owner != adapter, then CST tokens must be approved/transferred to the adapter by owner. And the reference tokens must have been transferred to the adapter by owner.
    /// @notice if owner == adapter, then CST tokens and reference tokens must have been transferred to the adapter before calling this.
    /// @param poolId The cork pool market id
    /// @param collateralAssets The exact amount of collateral assets to receive
    /// @param owner The address that owns the CST shares and reference tokens being swapped
    /// @param receiver The address to which collateral assets will be sent
    /// @param maxCstSharesIn The maximum amount of CST shares to spend for the swap
    /// @param maxReferenceAssetsIn The maximum amount of reference token compensation to spend for the swap
    /// @param deadline The deadline by which the transaction must be completed
    function safeSwap(MarketId poolId, uint256 collateralAssets, address owner, address receiver, uint256 maxCstSharesIn, uint256 maxReferenceAssetsIn, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(owner == address(this) || owner == initiator(), ErrorsLib.UnexpectedOwner());
        require(collateralAssets != 0, ErrorsLib.ZeroAmount());

        IERC20 referenceAsset;
        IERC20 cst;
        {
            (, address _referenceAsset) = CORK.underlyingAsset(poolId);
            referenceAsset = IERC20(_referenceAsset);

            (, address swapToken) = CORK.shares(poolId);
            cst = IERC20(swapToken);
        }

        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(referenceAsset, address(CORK), type(uint256).max);

        (uint256 shares, uint256 compensation) = CORK.swap(poolId, collateralAssets, receiver);

        // Check slippage protection
        require(shares <= maxCstSharesIn, ErrorsLib.SlippageExceeded());
        require(compensation <= maxReferenceAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cst, address(CORK), 0);
        SafeERC20.forceApprove(referenceAsset, address(CORK), 0);
    }

    /// @notice Exercises CST shares or reference token compensation for collateral assets.
    /// @notice if owner != adapter, then CST tokens must be approved/transferred to the adapter by owner. And the reference tokens must have been transferred to the adapter by owner.
    /// @notice if owner == adapter, then CST tokens and reference tokens must have been transferred to the adapter before calling this.
    /// @notice Either cstShares or referenceAssets must be 0 (not both non-zero).
    /// @param poolId The cork pool market id
    /// @param cstShares The amount of CST shares to lock (set to 0 if using referenceAssets)
    /// @param referenceAssets The amount of reference token compensation to lock (set to 0 if using cstShares)
    /// @param owner The address that owns the CST shares and reference tokens being exercised
    /// @param receiver The address to which collateral assets will be sent
    /// @param minCollateralAssetsOut The minimum amount of collateral assets to receive
    /// @param maxOtherTokenIn The maximum amount of other asset that can be spent
    /// @param deadline The deadline by which the transaction must be completed
    function safeExercise(MarketId poolId, uint256 cstShares, uint256 referenceAssets, address owner, address receiver, uint256 minCollateralAssetsOut, uint256 maxOtherTokenIn, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());
        require(owner == address(this) || owner == initiator(), ErrorsLib.UnexpectedOwner());

        // Ensure either cstShares or referenceAssets is 0 (not both non-zero)
        require(cstShares == 0 || referenceAssets == 0, ErrorsLib.ZeroShares());
        require(cstShares != 0 || referenceAssets != 0, ErrorsLib.ZeroShares());

        IERC20 referenceAsset;
        IERC20 cst;
        {
            (, address _referenceAsset) = CORK.underlyingAsset(poolId);
            referenceAsset = IERC20(_referenceAsset);

            (, address swapToken) = CORK.shares(poolId);
            cst = IERC20(swapToken);
        }

        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(referenceAsset, address(CORK), type(uint256).max);

        (uint256 assets, uint256 otherAssetSpent,) = CORK.exercise(poolId, cstShares, referenceAssets, receiver, minCollateralAssetsOut, maxOtherTokenIn);

        // Check slippage protection
        require(assets >= minCollateralAssetsOut, ErrorsLib.SlippageExceeded());
        require(otherAssetSpent <= maxOtherTokenIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cst, address(CORK), 0);
        SafeERC20.forceApprove(referenceAsset, address(CORK), 0);
    }

    /// @notice Unwinds an exercise by depositing collateral assets to unlock CST shares and reference token compensation.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param poolId The cork pool market id
    /// @param shares The amount of CST shares to unlock.
    /// @param receiver The address to which unlocked CST shares and reference token compensation will be sent
    /// @param minReferenceAssetsOut The minimum amount of reference token compensation to receive
    /// @param maxCollateralAssetsIn The maximum amount of collateral assets to spend for the unwind exercise
    /// @param deadline The deadline by which the transaction must be completed
    function safeUnwindExercise(MarketId poolId, uint256 shares, address receiver, uint256 minReferenceAssetsOut, uint256 maxCollateralAssetsIn, uint256 deadline) external onlyBundler3 {
        require(block.timestamp <= deadline, ErrorsLib.DeadlineExceeded());
        require(receiver != address(0), ErrorsLib.ZeroAddress());

        (address _collateralAsset,) = CORK.underlyingAsset(poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        require(shares != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        (uint256 assetIn, uint256 compensationOut) = CORK.unwindExercise(poolId, shares, receiver, minReferenceAssetsOut, maxCollateralAssetsIn);

        // Check slippage protection
        require(compensationOut >= minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(assetIn <= maxCollateralAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }
}
