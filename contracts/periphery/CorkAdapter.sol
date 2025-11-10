// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ICorkAdapter} from "./../interfaces/ICorkAdapter.sol";
import {IPoolManager} from "./../interfaces/IPoolManager.sol";
import {IWhitelistManager} from "./../interfaces/IWhitelistManager.sol";
import {Market, MarketId} from "./../libraries/Market.sol";
import {GeneralAdapter} from "./GeneralAdapter.sol";
import {ErrorsLib} from "./bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract CorkAdapter is GeneralAdapter, ICorkAdapter {
    /// @notice The address of the core Cork contract.
    // slither-disable-next-line naming-convention
    IPoolManager public immutable CORK;

    /// @notice The address of the whitelist manager contract.
    // slither-disable-next-line naming-convention
    IWhitelistManager public immutable WHITELIST_MANAGER;

    /// @param bundler3 The address of the Bundler3 contract.
    /// @param wNative The address of the canonical native token wrapper.
    /// @param cork The address of the Cork's IPool contract.
    /// @param whitelistManager The address of the WhitelistManager contract.
    constructor(address bundler3, address wNative, address cork, address whitelistManager) GeneralAdapter(bundler3, wNative) {
        require(cork != address(0), ErrorsLib.ZeroAddress());
        require(whitelistManager != address(0), ErrorsLib.ZeroAddress());

        CORK = IPoolManager(cork);
        WHITELIST_MANAGER = IWhitelistManager(whitelistManager);
    }

    ///======================================================///
    ///=================== MODIFIERS ========================///
    ///======================================================///

    modifier onlyWhitelisted(MarketId poolId) {
        require(WHITELIST_MANAGER.isWhitelisted(poolId, initiator()), ErrorsLib.UnauthorizedSender());
        _;
    }

    /// @notice Mints shares(CST & CPT) of an Cork Pool.
    /// @dev Underlying tokens must have been previously sent to the adapter.
    /// @param params The parameters for the safe mint operation.
    /// params.poolId The cork pool market id
    /// params.cptAndCstSharesOut The amount of vault shares to mint.
    /// params.receiver The address to which shares(CST & CPT) will be minted.
    /// params.maxCollateralAssetsIn The maximum amount of collateral assets to spend for minting shares.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeMint(SafeMintParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.cptAndCstSharesOut != 0, ErrorsLib.ZeroShares());

        Market memory market = CORK.market(params.poolId);
        IERC20 collateralAsset = IERC20(market.collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 assets = CORK.mint(params.poolId, params.cptAndCstSharesOut, params.receiver);

        // Check slippage protection
        require(assets <= params.maxCollateralAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Deposits collateral token in a Cork Market.
    /// @dev Underlying tokens must have been previously sent to the adapter.
    /// @param params The parameters for the safe deposit operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssetsIn The amount of collateral asset to deposit.
    /// params.receiver The address to which shares(CST & CPT) will be minted.
    /// params.minCptAndCstSharesOut The minimum amount of shares to receive from the deposit.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeDeposit(SafeDepositParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.collateralAssetsIn != 0, ErrorsLib.ZeroAmount());

        Market memory market = CORK.market(params.poolId);
        IERC20 collateralAsset = IERC20(market.collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 shares = CORK.deposit(params.poolId, params.collateralAssetsIn, params.receiver);

        // Check slippage protection
        require(shares >= params.minCptAndCstSharesOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Unwinds a deposit by burning equal amounts of CPT and CST shares.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.

    /// @param params The parameters for the safe unwind deposit operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssetsOut The amount of target collateral to get from the unwind.
    /// params.owner The address that owns the CPT and CST shares being burned
    /// params.receiver The address to which collateral assets and any excess shares will be sent.
    /// params.maxCptAndCstSharesIn The maximum amount of shares to burn for the unwind operation.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeUnwindDeposit(SafeUnwindDepositParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());
        require(params.collateralAssetsOut != 0, ErrorsLib.ZeroAmount());

        IERC20 cpt;
        IERC20 cst;
        {
            (address principalToken, address swapToken) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
            cst = IERC20(swapToken);
        }

        require(params.collateralAssetsOut != 0, ErrorsLib.ZeroAmount());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);

        uint256 sharesIn = CORK.unwindDeposit(params.poolId, params.collateralAssetsOut, params.owner, params.receiver);

        // Check slippage protection
        require(sharesIn <= params.maxCptAndCstSharesIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
        SafeERC20.forceApprove(cst, address(CORK), 0);
    }

    /// @notice Unwinds a mint by burning equal amounts of CPT and CST shares.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe unwind mint operation.
    /// params.poolId The cork pool market id
    /// params.cptAndCstSharesIn The amount of shares to redeem. Pass type(uint).max to redeem the owner's shares.
    /// params.owner The address that owns the CPT and CST shares being burned
    /// params.receiver The address to which collateral assets and any excess shares will be sent.
    /// params.minCollateralAssetsOut The minimum amount of collateral to receive from the unwind operation.
    /// params.deadline The deadline by which the transaction must be completed.
    function safeUnwindMint(SafeUnwindMintParams memory params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 cpt;
        IERC20 cst;
        {
            (address principalToken, address swapToken) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
            cst = IERC20(swapToken);
        }

        if (params.cptAndCstSharesIn == type(uint256).max) {
            // Use the minimum of CPT and CST balances from owner
            uint256 cptBalance = params.owner == address(this) ? cpt.balanceOf(params.owner) : cpt.allowance(params.owner, address(this));
            uint256 cstBalance = params.owner == address(this) ? cst.balanceOf(params.owner) : cst.allowance(params.owner, address(this));
            params.cptAndCstSharesIn = cptBalance < cstBalance ? cptBalance : cstBalance;
        }

        require(params.cptAndCstSharesIn != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);

        uint256 assets = CORK.unwindMint(params.poolId, params.cptAndCstSharesIn, params.owner, params.receiver);

        // Check slippage protection
        require(assets >= params.minCollateralAssetsOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
        SafeERC20.forceApprove(cst, address(CORK), 0);
    }

    /// @notice Withdraws specific amounts of collateral assets from a Cork Pool.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe withdraw operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssetsOut The amount of collateral asset to withdraw
    /// params.owner The address that owns the CPT shares being burned
    /// params.receiver The address to which withdrawn assets will be sent
    /// params.maxCptSharesIn The maximum amount of CPT shares to burn for the withdrawal
    /// params.deadline The deadline by which the transaction must be completed
    function safeWithdraw(SafeWithdrawParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // Ensure collateralAssets is not 0
        require(params.collateralAssetsOut != 0, ErrorsLib.ZeroAmount());

        _safeWithdraw(SafeWithdrawInternalParams({poolId: params.poolId, collateralAssetsOut: params.collateralAssetsOut, referenceAssetsOut: 0, owner: params.owner, receiver: params.receiver, maxCptSharesIn: params.maxCptSharesIn, deadline: params.deadline}));
    }

    /// @notice Withdraws specific amounts of reference assets from a Cork Pool.
    /// @notice if owner != adapter, then CPT tokens must have been approved to the adapter by owner.
    /// @notice if owner == adapter, then CPT tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe withdraw operation.
    /// params.poolId The cork pool market id
    /// params.referenceAssetsOut The amount of reference asset to withdraw
    /// params.owner The address that owns the CPT shares being burned
    /// params.receiver The address to which withdrawn assets will be sent
    /// params.maxCptSharesIn The maximum amount of CPT shares to burn for the withdrawal
    /// params.deadline The deadline by which the transaction must be completed
    function safeWithdrawOther(SafeWithdrawOtherParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // Ensure referenceAssets is not 0
        require(params.referenceAssetsOut != 0, ErrorsLib.ZeroAmount());

        _safeWithdraw(SafeWithdrawInternalParams({poolId: params.poolId, collateralAssetsOut: 0, referenceAssetsOut: params.referenceAssetsOut, owner: params.owner, receiver: params.receiver, maxCptSharesIn: params.maxCptSharesIn, deadline: params.deadline}));
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
    function safeRedeem(SafeRedeemParams memory params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 cpt;
        {
            // slither-disable-next-line unused-return
            (address principalToken,) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
        }

        if (params.cptSharesIn == type(uint256).max) params.cptSharesIn = params.owner == address(this) ? cpt.balanceOf(params.owner) : cpt.allowance(params.owner, address(this));

        require(params.cptSharesIn != 0, ErrorsLib.ZeroShares());

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);

        (uint256 referenceOut, uint256 assets) = CORK.redeem(params.poolId, params.cptSharesIn, params.owner, params.receiver);

        // Check slippage protection
        require(referenceOut >= params.minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(assets >= params.minCollateralAssetsOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
    }

    /// @notice Unwinds a swap by using collateral assets to receive reference assets and swap tokens.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param params The parameters for the safe unwind swap operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssetsIn The amount of collateral assets to use for unwind swap. Pass `type(uint).max` to use the adapter's collateral asset balance.
    /// params.receiver The address to which reference assets and swap tokens will be sent
    /// params.minReferenceAssetsOut The minimum amount of reference assets to receive
    /// params.minCstSharesOut The minimum amount of CST shares to receive
    /// params.deadline The deadline by which the transaction must be completed
    function safeUnwindSwap(SafeUnwindSwapParams memory params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());

        Market memory market = CORK.market(params.poolId);
        IERC20 collateralAsset = IERC20(market.collateralAsset);

        if (params.collateralAssetsIn == type(uint256).max) params.collateralAssetsIn = collateralAsset.balanceOf(address(this));

        require(params.collateralAssetsIn != 0, ErrorsLib.ZeroAmount());

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        // slither-disable-next-line unused-return
        (uint256 cstSharesOut, uint256 referenceAssetsOut,) = CORK.unwindSwap(params.poolId, params.collateralAssetsIn, params.receiver);

        // Check slippage protection
        require(referenceAssetsOut >= params.minReferenceAssetsOut, ErrorsLib.SlippageExceeded());
        require(cstSharesOut >= params.minCstSharesOut, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }

    /// @notice Swaps CST shares and reference token compensation for collateral assets.
    /// @notice CST tokens and reference tokens must have been transferred to the adapter before calling this.
    /// @param params The parameters for the safe swap operation.
    /// params.poolId The cork pool market id
    /// params.collateralAssetsOut The exact amount of collateral assets to receive
    /// params.receiver The address to which collateral assets will be sent
    /// params.maxCstSharesIn The maximum amount of CST shares to spend for the swap
    /// params.maxReferenceAssetsIn The maximum amount of reference token compensation to spend for the swap
    /// params.deadline The deadline by which the transaction must be completed
    function safeSwap(SafeSwapParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.collateralAssetsOut != 0, ErrorsLib.ZeroAmount());

        IERC20 referenceAsset;
        IERC20 cst;
        {
            Market memory market = CORK.market(params.poolId);
            referenceAsset = IERC20(market.referenceAsset);

            // slither-disable-next-line unused-return
            (, address swapToken) = CORK.shares(params.poolId);
            cst = IERC20(swapToken);
        }

        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(referenceAsset, address(CORK), type(uint256).max);

        // slither-disable-next-line unused-return
        (uint256 cstSharesIn, uint256 referenceAssetsIn,) = CORK.swap(params.poolId, params.collateralAssetsOut, params.receiver);

        // Check slippage protection
        require(cstSharesIn <= params.maxCstSharesIn, ErrorsLib.SlippageExceeded());
        require(referenceAssetsIn <= params.maxReferenceAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cst, address(CORK), 0);
        SafeERC20.forceApprove(referenceAsset, address(CORK), 0);
    }

    /// @notice Exercises CST shares or reference token compensation for collateral assets.
    /// @notice cstShares must be non-zero.
    /// @param params The parameters for the safe exercise operation.
    /// params.poolId The cork pool market id
    /// params.cstSharesIn The amount of CST shares to lock
    /// params.receiver The address to which collateral assets will be sent
    /// params.minCollateralAssetsOut The minimum amount of collateral assets to receive
    /// params.maxReferenceAssetsIn The maximum amount of reference asset that can be spent
    /// params.deadline The deadline by which the transaction must be completed
    function safeExercise(SafeExerciseParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // Check cstShares is not 0
        require(params.cstSharesIn != 0, ErrorsLib.ZeroShares());

        _safeExercise(SafeExerciseInternalParams({poolId: params.poolId, cstSharesIn: params.cstSharesIn, referenceAssetsIn: 0, receiver: params.receiver, minCollateralAssetsOut: params.minCollateralAssetsOut, maxOtherTokenIn: params.maxReferenceAssetsIn, deadline: params.deadline}));
    }

    /// @notice Exercises reference token compensation for collateral assets.
    /// @notice referenceAssets must be non-zero.
    /// @param params The parameters for the safe exercise operation.
    /// params.poolId The cork pool market id
    /// params.referenceAssetsIn The amount of reference token compensation to lock
    /// params.receiver The address to which collateral assets will be sent
    /// params.minCollateralAssetsOut The minimum amount of collateral assets to receive
    /// params.maxCstSharesIn The maximum amount of CST shares that can be spent
    /// params.deadline The deadline by which the transaction must be completed
    function safeExerciseOther(SafeExerciseOtherParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        // Check referenceAssets is not 0
        require(params.referenceAssetsIn != 0, ErrorsLib.ZeroShares());

        _safeExercise(SafeExerciseInternalParams({poolId: params.poolId, cstSharesIn: 0, referenceAssetsIn: params.referenceAssetsIn, receiver: params.receiver, minCollateralAssetsOut: params.minCollateralAssetsOut, maxOtherTokenIn: params.maxCstSharesIn, deadline: params.deadline}));
    }

    /// @notice Unwinds an exercise by depositing collateral assets to unlock CST shares and reference token compensation.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param params The parameters for the safe unwind exercise operation.
    /// params.poolId The cork pool market id
    /// params.cstSharesOut The amount of CST shares to unlock.
    /// params.receiver The address to which unlocked CST shares and reference token compensation will be sent
    /// params.minReferenceAssetsOut The minimum amount of reference token compensation to receive
    /// params.maxCollateralAssetsIn The maximum amount of collateral assets to spend for the unwind exercise
    /// params.deadline The deadline by which the transaction must be completed
    function safeUnwindExercise(SafeUnwindExerciseParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        require(params.cstSharesOut != 0, ErrorsLib.ZeroShares());

        _safeUnwindExercise(SafeUnwindExerciseInternalParams({poolId: params.poolId, cstSharesOut: params.cstSharesOut, referenceAssetsOut: 0, receiver: params.receiver, minOtherAssetOut: params.minReferenceAssetsOut, maxCollateralAssetsIn: params.maxCollateralAssetsIn, deadline: params.deadline}));
    }

    /// @notice Unwinds an exercise by depositing collateral assets to unlock CST shares and reference token compensation.
    /// @notice Collateral assets must have been previously sent to the adapter.
    /// @param params The parameters for the safe unwind exercise operation.
    /// params.poolId The cork pool market id
    /// params.referenceAssetsOut The amount of reference token to unlock.
    /// params.receiver The address to which unlocked CST shares and reference token compensation will be sent
    /// params.minCstSharesOut The minimum amount of CST shares to receive
    /// params.maxCollateralAssetsIn The maximum amount of collateral assets to spend for the unwind exercise
    /// params.deadline The deadline by which the transaction must be completed
    function safeUnwindExerciseOther(SafeUnwindExerciseOtherParams calldata params) external onlyBundler3 onlyWhitelisted(params.poolId) {
        require(params.referenceAssetsOut != 0, ErrorsLib.ZeroShares());

        _safeUnwindExercise(SafeUnwindExerciseInternalParams({poolId: params.poolId, cstSharesOut: 0, referenceAssetsOut: params.referenceAssetsOut, receiver: params.receiver, minOtherAssetOut: params.minCstSharesOut, maxCollateralAssetsIn: params.maxCollateralAssetsIn, deadline: params.deadline}));
    }

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

    /// @notice Either collateralAssetsOut or referenceAssetsOut MUST be 0, (not both non-zero).
    function _safeWithdraw(SafeWithdrawInternalParams memory params) internal {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());
        require(params.owner == address(this) || params.owner == initiator(), ErrorsLib.UnexpectedOwner());

        IERC20 cpt;
        {
            // slither-disable-next-line unused-return
            (address principalToken,) = CORK.shares(params.poolId);
            cpt = IERC20(principalToken);
        }

        SafeERC20.forceApprove(cpt, address(CORK), type(uint256).max);

        uint256 cptSharesIn;
        // slither-disable-next-line unused-return
        if (params.collateralAssetsOut != 0) (cptSharesIn,,) = CORK.withdraw(params.poolId, params.collateralAssetsOut, params.owner, params.receiver);
        // slither-disable-next-line unused-return
        else (cptSharesIn,,) = CORK.withdrawOther(params.poolId, params.referenceAssetsOut, params.owner, params.receiver);

        // Check slippage protection
        require(cptSharesIn <= params.maxCptSharesIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cpt, address(CORK), 0);
    }

    /// @notice Either cstShares or referenceAssets MUST be 0, (not both non-zero).
    function _safeExercise(SafeExerciseInternalParams memory params) internal {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());

        IERC20 referenceAsset;
        IERC20 cst;
        {
            Market memory market = CORK.market(params.poolId);
            referenceAsset = IERC20(market.referenceAsset);

            // slither-disable-next-line unused-return
            (, address swapToken) = CORK.shares(params.poolId);
            cst = IERC20(swapToken);
        }

        SafeERC20.forceApprove(cst, address(CORK), type(uint256).max);
        SafeERC20.forceApprove(referenceAsset, address(CORK), type(uint256).max);

        uint256 assets;
        uint256 otherAssetSpent;
        // slither-disable-next-line unused-return
        if (params.cstSharesIn != 0) (assets, otherAssetSpent,) = CORK.exercise(params.poolId, params.cstSharesIn, params.receiver);
        // slither-disable-next-line unused-return
        else (assets, otherAssetSpent,) = CORK.exerciseOther(params.poolId, params.referenceAssetsIn, params.receiver);

        // Check slippage protection
        require(assets >= params.minCollateralAssetsOut, ErrorsLib.SlippageExceeded());
        require(otherAssetSpent <= params.maxOtherTokenIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(cst, address(CORK), 0);
        SafeERC20.forceApprove(referenceAsset, address(CORK), 0);
    }

    /// @notice Either cstSharesOut or referenceAssetsOut MUST be 0, (not both non-zero).
    function _safeUnwindExercise(SafeUnwindExerciseInternalParams memory params) internal {
        // slither-disable-next-line timestamp
        require(block.timestamp <= params.deadline, ErrorsLib.DeadlineExceeded());
        require(params.receiver != address(0), ErrorsLib.ZeroAddress());

        Market memory market = CORK.market(params.poolId);
        IERC20 collateralAsset = IERC20(market.collateralAsset);

        SafeERC20.forceApprove(collateralAsset, address(CORK), type(uint256).max);

        uint256 assetIn;
        uint256 cstSharesOut = params.cstSharesOut;
        uint256 referenceAssetsOut = params.referenceAssetsOut;
        // slither-disable-next-line unused-return
        if (params.cstSharesOut != 0) (assetIn, referenceAssetsOut,) = CORK.unwindExercise(params.poolId, params.cstSharesOut, params.receiver);
        // slither-disable-next-line unused-return
        else (assetIn, cstSharesOut,) = CORK.unwindExerciseOther(params.poolId, params.referenceAssetsOut, params.receiver);

        uint256 otherAssetReceived = params.cstSharesOut != 0 ? referenceAssetsOut : cstSharesOut;

        // Check slippage protection
        require(otherAssetReceived >= params.minOtherAssetOut, ErrorsLib.SlippageExceeded());
        require(assetIn <= params.maxCollateralAssetsIn, ErrorsLib.SlippageExceeded());

        SafeERC20.forceApprove(collateralAsset, address(CORK), 0);
    }
}
