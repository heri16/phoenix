// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ICorkPoolAdapter} from "./../interfaces/ICorkPoolAdapter.sol";
import {IErrors} from "./../interfaces/IErrors.sol";
import {IPoolManager, Market, MarketId} from "./../interfaces/IPoolManager.sol";
import {TransferHelper} from "./../libraries/TransferHelper.sol";
import {GeneralAdapter} from "./GeneralAdapter.sol";
import {ErrorsLib} from "./bundler3/libraries/ErrorsLib.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract CorkPoolAdapter is GeneralAdapter, ICorkPoolAdapter {
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
    /// @param params The parameters for the safe mint operation.
    /// params.poolId The cork pool market id
    /// params.shares The amount of vault shares to mint.
    /// params.receiver The address to which shares(CST & CPT) will be minted.
    /// params.maxAssetsIn The maximum amount of collateral assets to spend for minting shares.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeMint(SafeMintParams calldata params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.shares != 0, ErrorsLib.ZeroShares());

        (address _collateralAsset,) = CORK.underlyingAsset(params.poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 assets = CORK.mint(params.poolId, params.shares, params.receiver);

        // Check slippage protection
        require(assets <= params.maxAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Deposits collateral token in a Cork Market.
    /// @dev Underlying tokens must have been previously sent to the adapter.
    /// @param params The parameters for the safe deposit operation.
    /// params.poolId The cork pool market id
    /// params.assets The amount of collateral asset to deposit.
    /// params.receiver The address to which shares(CST & CPT) will be minted.
    /// params.minSharesOut The minimum amount of shares to receive from the deposit.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeDeposit(SafeDepositParams calldata params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.assets != 0, ErrorsLib.ZeroAmount());

        (address _collateralAsset,) = CORK.underlyingAsset(params.poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 shares = CORK.deposit(params.poolId, params.assets, params.receiver);

        // Check slippage protection
        require(shares >= params.minSharesOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Unwinds a deposit by burning equal amounts of CPT and CST shares.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.

    /// @param params The parameters for the safe unwind deposit operation.
    /// params.poolId The cork pool market id
    /// params.assets The amount of target collateral to get from the unwind.
    /// params.owner The address that owns the CPT and CST shares being burned
    /// params.receiver The address to which collateral assets and any excess shares will be sent.
    /// params.maxSharesIn The maximum amount of shares to burn for the unwind operation.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeUnwindDeposit(SafeUnwindDepositParams calldata params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());
        require(params.assets != 0, ErrorsLib.ZeroAmount());

        IERC20 collateralAsset;
        IERC20 cpt;
        IERC20 cst;
        {
            (address _collateralAsset,) = CORK.underlyingAsset(params.poolId);
            collateralAsset = IERC20(_collateralAsset);

            (address principalToken, address swapToken) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
            cst = IERC20(swapToken);
        }

        require(params.assets != 0, ErrorsLib.ZeroAmount());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);

        uint256 sharesIn = CORK.unwindDeposit(params.poolId, params.assets, params.owner, params.receiver);

        // Check slippage protection
        require(sharesIn <= params.maxSharesIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
        SafeERC20.forceApprove(cst, address(CORK), 0);
    }

    /// @notice Unwinds a mint by burning equal amounts of CPT and CST shares.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe unwind mint operation.
    /// params.poolId The cork pool market id
    /// params.shares The amount of shares to redeem. Pass type(uint).max to redeem the owner's shares.
    /// params.owner The address that owns the CPT and CST shares being burned
    /// params.receiver The address to which collateral assets and any excess shares will be sent.
    /// params.minAssetsOut The minimum amount of collateral to receive from the unwind operation.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeUnwindMint(SafeUnwindMintParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 collateralAsset;
        IERC20 cpt;
        IERC20 cst;
        {
            (address _collateralAsset,) = CORK.underlyingAsset(params.poolId);
            collateralAsset = IERC20(_collateralAsset);

            (address principalToken, address swapToken) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
            cst = IERC20(swapToken);
        }

        if (params.shares == type(uint256).max) {
            // Use the minimum of CPT and CST balances from owner
            uint256 cptBalance = params.owner == address(this) ? cpt.balanceOf(params.owner) : cpt.allowance(params.owner, address(this));
            uint256 cstBalance = params.owner == address(this) ? cst.balanceOf(params.owner) : cst.allowance(params.owner, address(this));
            params.shares = cptBalance < cstBalance ? cptBalance : cstBalance;
        }

        require(params.shares != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);

        uint256 assets = CORK.unwindMint(params.poolId, params.shares, params.owner, params.receiver);

        // Check slippage protection
        require(assets >= params.minAssetsOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
        SafeERC20.forceApprove(cst, address(CORK), 0);
    }

    /// @notice Withdraws specific amounts of collateral and/or reference assets from a Cork Pool.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @notice Either collateralAssets or referenceAssets must be 0.
    /// @param params The parameters for the safe withdraw operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssets The amount of collateral asset to withdraw (set to 0 if withdrawing reference asset)
    /// params.referenceAssets The amount of reference asset to withdraw (set to 0 if withdrawing collateral asset)
    /// params.owner The address that owns the CPT shares being burned
    /// params.receiver The address to which withdrawn assets will be sent
    /// params.maxSharesIn The maximum amount of CPT shares to burn for the withdrawal
    /// params.deadline The deadline by which the transaction must be completed
    function safeWithdraw(SafeWithdrawParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        // Ensure either collateralAssets or referenceAssets is 0 (not both non-zero)
        require(params.collateralAssets == 0 || params.referenceAssets == 0, ErrorsLib.ZeroAmount());
        require(params.collateralAssets != 0 || params.referenceAssets != 0, ErrorsLib.ZeroAmount());

        IERC20 collateralAsset;
        IERC20 referenceAsset;
        IERC20 cpt;
        {
            (address _collateralAsset, address _referenceAsset) = CORK.underlyingAsset(params.poolId);
            collateralAsset = IERC20(_collateralAsset);
            referenceAsset = IERC20(_referenceAsset);

            (address principalToken,) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
        }

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);

        (uint256 sharesIn,,) = CORK.withdraw(IPoolManager.WithdrawParams({poolId: params.poolId, collateralAssetOut: params.collateralAssets, referenceAssetOut: params.referenceAssets, owner: params.owner, receiver: params.receiver}));

        // Check slippage protection
        require(sharesIn <= params.maxSharesIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
    }

    /// @notice Redeems CPT tokens for collateral and reference assets at expiry.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe redeem operation.
    /// params.poolId The cork pool market id
    /// params.cptShares The amount of CPT tokens to redeem. Pass `type(uint).max` to use the adapter's CPT balance/allowance.
    /// params.owner The address that owns the CPT tokens being redeemed
    /// params.receiver The address to which redeemed assets will be sent
    /// params.minReferenceAssetsOut The minimum amount of reference asset to receive
    /// params.minCollateralAssetsOut The minimum amount of collateral asset to receive
    /// params.deadline The deadline by which the transaction must be completed
    function safeRedeem(SafeRedeemParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 cpt;
        {
            (address principalToken,) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
        }

        if (params.cptShares == type(uint256).max) params.cptShares = params.owner == address(this) ? cpt.balanceOf(params.owner) : cpt.allowance(params.owner, address(this));

        require(params.cptShares != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);

        (uint256 referenceOut, uint256 assets) = CORK.redeem(params.poolId, params.cptShares, params.owner, params.receiver);

        // Check slippage protection
        require(referenceOut >= params.minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(assets >= params.minCollateralAssetsOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
    }

    /// @notice Unwinds a swap by using collateral assets to receive reference assets and swap tokens.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param params The parameters for the safe unwind swap operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssets The amount of collateral assets to use for unwind swap. Pass `type(uint).max` to use the adapter's collateral asset balance.
    /// params.receiver The address to which reference assets and swap tokens will be sent
    /// params.minReferenceAssetsOut The minimum amount of reference assets to receive
    /// params.minCstSharesOut The minimum amount of swap tokens to receive
    /// params.deadline The deadline by which the transaction must be completed
    function safeUnwindSwap(SafeUnwindSwapParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());

        (address _collateralAsset,) = CORK.underlyingAsset(params.poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        if (params.collateralAssets == type(uint256).max) params.collateralAssets = collateralAsset.balanceOf(address(this));

        require(params.collateralAssets != 0, ErrorsLib.ZeroAmount());

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        IUnwindSwap.UnwindSwapReturnParams memory returnParams = CORK.unwindSwap(params.poolId, params.collateralAssets, params.receiver);

        // Check slippage protection
        require(returnParams.receivedReferenceAsset >= params.minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(returnParams.receivedSwapToken >= params.minCstSharesOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Swaps CST shares and reference token compensation for collateral assets.
    /// @notice if owner != adapter, then CST tokens must be approved/transferred to the adapter by owner. And the reference tokens must have been transferred to the adapter by owner.
    /// @notice if owner == adapter, then CST tokens and reference tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe swap operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssets The exact amount of collateral assets to receive
    /// params.owner The address that owns the CST shares and reference tokens being swapped
    /// params.receiver The address to which collateral assets will be sent
    /// params.maxCstSharesIn The maximum amount of CST shares to spend for the swap
    /// params.maxReferenceAssetsIn The maximum amount of reference token compensation to spend for the swap
    /// params.deadline The deadline by which the transaction must be completed
    function safeSwap(SafeSwapParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());
        require(params.collateralAssets != 0, ErrorsLib.ZeroAmount());

        IERC20 referenceAsset;
        IERC20 cst;
        {
            (, address _referenceAsset) = CORK.underlyingAsset(params.poolId);
            referenceAsset = IERC20(_referenceAsset);

            (, address swapToken) = CORK.shares(params.poolId);
            cst = IERC20(swapToken);
        }

        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(referenceAsset, address(CORK), type(uint256).max);

        (uint256 shares, uint256 compensation, uint256 fee) = CORK.swap(params.poolId, params.collateralAssets, params.receiver);

        // Check slippage protection
        require(shares <= params.maxCstSharesIn, ErrorsLib.SlippageExceeded());
        require(compensation <= params.maxReferenceAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cst, address(CORK), 0);
        SafeERC20.forceApprove(referenceAsset, address(CORK), 0);
    }

    /// @notice Exercises CST shares or reference token compensation for collateral assets.
    /// @notice if owner != adapter, then CST tokens must be approved/transferred to the adapter by owner. And the reference tokens must have been transferred to the adapter by owner.
    /// @notice if owner == adapter, then CST tokens and reference tokens must have been transferred to the adapter before calling this.
    /// @notice Either cstShares or referenceAssets must be 0 (not both non-zero).
    /// @param params The parameters for the safe exercise operation.
    /// params.poolId The cork pool market id
    /// params.cstShares The amount of CST shares to lock (set to 0 if using referenceAssets)
    /// params.referenceAssets The amount of reference token compensation to lock (set to 0 if using cstShares)
    /// params.owner The address that owns the CST shares and reference tokens being exercised
    /// params.receiver The address to which collateral assets will be sent
    /// params.minCollateralAssetsOut The minimum amount of collateral assets to receive
    /// params.maxOtherTokenIn The maximum amount of other asset that can be spent
    /// params.deadline The deadline by which the transaction must be completed
    function safeExercise(SafeExerciseParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        // Ensure either cstShares or referenceAssets is 0 (not both non-zero)
        require(params.cstShares == 0 || params.referenceAssets == 0, ErrorsLib.ZeroShares());
        require(params.cstShares != 0 || params.referenceAssets != 0, ErrorsLib.ZeroShares());

        IERC20 referenceAsset;
        IERC20 cst;
        {
            (, address _referenceAsset) = CORK.underlyingAsset(params.poolId);
            referenceAsset = IERC20(_referenceAsset);

            (, address swapToken) = CORK.shares(params.poolId);
            cst = IERC20(swapToken);
        }

        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(referenceAsset, address(CORK), type(uint256).max);

        (uint256 assets, uint256 otherAssetSpent,) = CORK.exercise(IPoolManager.ExerciseParams({poolId: params.poolId, shares: params.cstShares, compensation: params.referenceAssets, receiver: params.receiver, minAssetsOut: params.minCollateralAssetsOut, maxOtherAssetSpent: params.maxOtherTokenIn}));

        // Check slippage protection
        require(assets >= params.minCollateralAssetsOut, ErrorsLib.SlippageExceeded());
        require(otherAssetSpent <= params.maxOtherTokenIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cst, address(CORK), 0);
        SafeERC20.forceApprove(referenceAsset, address(CORK), 0);
    }

    /// @notice Unwinds an exercise by depositing collateral assets to unlock CST shares and reference token compensation.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param params The parameters for the safe unwind exercise operation.
    /// params.poolId The cork pool market id
    /// params.shares The amount of CST shares to unlock.
    /// params.receiver The address to which unlocked CST shares and reference token compensation will be sent
    /// params.minReferenceAssetsOut The minimum amount of reference token compensation to receive
    /// params.maxCollateralAssetsIn The maximum amount of collateral assets to spend for the unwind exercise
    /// params.deadline The deadline by which the transaction must be completed
    function safeUnwindExercise(SafeUnwindExerciseParams memory params) external onlyBundler3 {
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());

        (address _collateralAsset,) = CORK.underlyingAsset(params.poolId);
        IERC20 collateralAsset = IERC20(_collateralAsset);

        require(params.shares != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        (uint256 assetIn, uint256 compensationOut, uint256 fee) = CORK.unwindExercise(IPoolManager.UnwindExerciseParams({poolId: params.poolId, shares: params.shares, receiver: params.receiver, minCompensationOut: params.minReferenceAssetsOut, maxAssetsIn: params.maxCollateralAssetsIn}));

        // Check slippage protection
        require(compensationOut >= params.minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(assetIn <= params.maxCollateralAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }
}
