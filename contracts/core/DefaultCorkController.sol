// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IWhitelistManager} from "contracts/interfaces/IWhitelistManager.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title DefaultCorkController Contract
 * @author Cork Team
 * @notice DefaultCorkController contract for managing pairs and controlling Cork protocol
 */
contract DefaultCorkController is AccessControl, Pausable, IDefaultCorkController {
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 public constant POOL_CREATOR_ROLE = keccak256("POOL_CREATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    CorkPoolManager public immutable corkPoolManager;
    IWhitelistManager public immutable whitelistManager;

    ///======================================================///
    ///===================== CONSTRUCTOR ====================///
    ///======================================================///

    constructor(address admin, address configurator, address pauser, address poolCreator, address corkPoolAddress, address whitelistManagerAddress, address whitelistManagerAdminAddress) {
        require(admin != address(0) && configurator != address(0) && pauser != address(0) && poolCreator != address(0) && corkPoolAddress != address(0) && whitelistManagerAddress != address(0) && whitelistManagerAdminAddress != address(0), InvalidAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIGURATOR_ROLE, configurator);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(POOL_CREATOR_ROLE, poolCreator);
        _grantRole(WHITELIST_MANAGER_ROLE, whitelistManagerAdminAddress);

        corkPoolManager = CorkPoolManager(corkPoolAddress);
        whitelistManager = IWhitelistManager(whitelistManagerAddress);
    }

    ///======================================================///
    ///=================== SETUP FUNCTIONS ==================///
    ///======================================================///

    /// @inheritdoc IDefaultCorkController
    function setTreasury(address treasuryAddress) external onlyRole(CONFIGURATOR_ROLE) {
        require(treasuryAddress != address(0), InvalidAddress());

        // updated event are emitted in this call
        corkPoolManager.setTreasuryAddress(treasuryAddress);
    }

    /// @inheritdoc IDefaultCorkController
    function setSharesFactory(address sharesFactory) external onlyRole(CONFIGURATOR_ROLE) {
        require(sharesFactory != address(0), InvalidAddress());

        // Events for `setSharesFactory` are emitted in this call
        corkPoolManager.setSharesFactory(sharesFactory);
    }

    ///======================================================///
    ///================ POOL DEPLOYMENT FUNCTIONS ===========///
    ///======================================================///

    /// @inheritdoc IDefaultCorkController
    function createNewPool(PoolCreationParams calldata params) external whenNotPaused onlyRole(POOL_CREATOR_ROLE) {
        // compute the id here to save gas
        MarketId id = MarketId.wrap(keccak256(abi.encode(params.pool)));

        if (params.isWhitelistEnabled) whitelistManager.activateMarketWhitelist(id);
        else whitelistManager.disableMarketWhitelist(id);

        corkPoolManager.createNewPool(params.pool);

        // update fees
        corkPoolManager.updateUnwindSwapFeeRate(id, params.unwindSwapFeePercentage);
        corkPoolManager.updateSwapFeePercentage(id, params.swapFeePercentage);
    }

    ///======================================================///
    ///================= FEE RELATED FUNCTIONS ==============///
    ///======================================================///

    /// @inheritdoc IDefaultCorkController
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external onlyRole(CONFIGURATOR_ROLE) {
        corkPoolManager.updateUnwindSwapFeeRate(id, newUnwindSwapFeePercentage);
    }

    /// @inheritdoc IDefaultCorkController
    function updateSwapFeePercentage(MarketId id, uint256 newSwapFeePercentage) external onlyRole(CONFIGURATOR_ROLE) {
        corkPoolManager.updateSwapFeePercentage(id, newSwapFeePercentage);
    }

    ///======================================================///
    ///================ ADMINISTRATIVE FUNCTIONS ============///
    ///======================================================///
    /// @inheritdoc IDefaultCorkController
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IDefaultCorkController
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IDefaultCorkController
    function pauseDeposits(MarketId id) external onlyRole(PAUSER_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap | (1 << 0); // logical OR to enable the 1st bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    /// @inheritdoc IDefaultCorkController
    function unpauseDeposits(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap & ~(uint16(1) << 0); // logical AND NOT to disable the 1st bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    function isDepositPaused(MarketId id) external view returns (bool isPaused) {
        isPaused = corkPoolManager.getPausedBitMap(id) & (1 << 0) != 0;
    }

    /// @inheritdoc IDefaultCorkController
    function pauseSwaps(MarketId id) external onlyRole(PAUSER_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap | (1 << 1); // logical OR to enable the 2nd bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    /// @inheritdoc IDefaultCorkController
    function unpauseSwaps(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap & ~(uint16(1) << 1); // logical AND NOT to disable the 2nd bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    function isSwapPaused(MarketId id) external view returns (bool isPaused) {
        isPaused = corkPoolManager.getPausedBitMap(id) & (1 << 1) != 0;
    }

    /// @inheritdoc IDefaultCorkController
    function pauseWithdrawals(MarketId id) external onlyRole(PAUSER_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap | (1 << 2); // logical OR to enable the 3rd bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    /// @inheritdoc IDefaultCorkController
    function unpauseWithdrawals(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap & ~(uint16(1) << 2); // logical AND NOT to disable the 3rd bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    function isWithdrawalPaused(MarketId id) external view returns (bool isPaused) {
        isPaused = corkPoolManager.getPausedBitMap(id) & (1 << 2) != 0;
    }

    /// @inheritdoc IDefaultCorkController
    function pauseUnwindDepositAndMints(MarketId id) external onlyRole(PAUSER_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap | (1 << 3); // logical OR to enable the 4th bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    /// @inheritdoc IDefaultCorkController
    function unpauseUnwindDepositAndMints(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap & ~(uint16(1) << 3); // logical AND NOT to disable the 4th bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    function isUnwindDepositAndMintPaused(MarketId id) external view returns (bool isPaused) {
        isPaused = corkPoolManager.getPausedBitMap(id) & (1 << 3) != 0;
    }

    /// @inheritdoc IDefaultCorkController
    function pauseUnwindSwaps(MarketId id) external onlyRole(PAUSER_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap | (1 << 4); // logical OR to enable the 5th bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    /// @inheritdoc IDefaultCorkController
    function unpauseUnwindSwaps(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 currentPauseBitMap = corkPoolManager.getPausedBitMap(id);
        uint16 newPauseBitMap = currentPauseBitMap & ~(uint16(1) << 4); // logical AND NOT to disable the 5th bit
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    function isUnwindSwapPaused(MarketId id) external view returns (bool isPaused) {
        isPaused = corkPoolManager.getPausedBitMap(id) & (1 << 4) != 0;
    }

    /// @inheritdoc IDefaultCorkController
    function pauseMarket(MarketId id) external onlyRole(PAUSER_ROLE) {
        uint16 newPauseBitMap = 0x1F; // 0x1F = 0001_1111 (bits 0–4 set)
        corkPoolManager.setPausedBitMap(id, newPauseBitMap);
    }

    /// @inheritdoc IDefaultCorkController
    function pauseAll() external onlyRole(PAUSER_ROLE) {
        corkPoolManager.setAllPaused(true);
    }

    /// @inheritdoc IDefaultCorkController
    function unpauseAll() external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPoolManager.setAllPaused(false);
    }

    ///======================================================///
    ///================= WHITELIST FUNCTIONS ===============///
    ///======================================================///

    /// @inheritdoc IDefaultCorkController
    function disableMarketWhitelist(MarketId marketId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistManager.disableMarketWhitelist(marketId);
    }

    /// @inheritdoc IDefaultCorkController
    function addToGlobalWhitelist(address[] calldata accounts) external onlyRole(WHITELIST_MANAGER_ROLE) {
        whitelistManager.addToGlobalWhitelist(accounts);
    }

    /// @inheritdoc IDefaultCorkController
    function removeFromGlobalWhitelist(address[] calldata accounts) external onlyRole(WHITELIST_MANAGER_ROLE) {
        whitelistManager.removeFromGlobalWhitelist(accounts);
    }

    /// @inheritdoc IDefaultCorkController
    function addToMarketWhitelist(MarketId marketId, address[] calldata accounts) external onlyRole(WHITELIST_MANAGER_ROLE) {
        whitelistManager.addToMarketWhitelist(marketId, accounts);
    }

    /// @inheritdoc IDefaultCorkController
    function removeFromMarketWhitelist(MarketId marketId, address[] calldata accounts) external onlyRole(WHITELIST_MANAGER_ROLE) {
        whitelistManager.removeFromMarketWhitelist(marketId, accounts);
    }

    /// @inheritdoc IDefaultCorkController
    function isWhitelisted(MarketId marketId, address account) external view returns (bool) {
        return whitelistManager.isWhitelisted(marketId, account);
    }
}
