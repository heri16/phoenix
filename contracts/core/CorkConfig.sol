// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {IConfig} from "contracts/interfaces/IConfig.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";

/**
 * @title Config Contract
 * @author Cork Team
 * @notice Config contract for managing pairs and configurations of Cork protocol
 */
contract CorkConfig is AccessControl, Pausable, IConfig {
    bytes32 public constant POOL_CREATOR_ROLE = keccak256("POOL_CREATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    CorkPool public corkPool;
    // Cork Protocol's treasury address. Other Protocol component should fetch this address directly from the config contract
    // instead of storing it themselves, since it'll be hard to update the treasury address in all the components if it changes vs updating it in the config contract once
    address public treasury;

    constructor(address admin, address pauser, address poolCreator) {
        require(admin != address(0) && poolCreator != address(0), InvalidAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(POOL_CREATOR_ROLE, poolCreator);
    }

    function grantRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(role, account), InvalidAddress());
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(role, account), InvalidAddress());
        _revokeRole(role, account);
    }

    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0) && !hasRole(DEFAULT_ADMIN_ROLE, newAdmin), InvalidAddress());
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }

    /// @inheritdoc IConfig
    function setCorkPool(address _corkPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_corkPool != address(0), InvalidAddress());
        corkPool = CorkPool(_corkPool);
        emit CorkPoolSet(_corkPool);
    }

    /// @inheritdoc IConfig
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), InvalidAddress());
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IConfig
    function createNewPool(Market calldata poolParams) external whenNotPaused onlyRole(POOL_CREATOR_ROLE) {
        corkPool.createNewPool(poolParams);
    }

    /// @inheritdoc IConfig
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.updateUnwindSwapFeeRate(id, newUnwindSwapFeePercentage);
    }

    /// @inheritdoc IConfig
    function updateBaseRedemptionFeePercentage(MarketId id, uint256 newBaseRedemptionFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.updateBaseRedemptionFeePercentage(id, newBaseRedemptionFeePercentage);
    }

    /// @inheritdoc IConfig
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IConfig
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IConfig
    function pauseDeposits(MarketId id) external onlyRole(PAUSER_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.DEPOSIT, true);
    }

    /// @inheritdoc IConfig
    function unpauseDeposits(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.DEPOSIT, false);
    }

    /// @inheritdoc IConfig
    function pauseUnwindSwaps(MarketId id) external onlyRole(PAUSER_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.UNWIND_SWAP, true);
    }

    /// @inheritdoc IConfig
    function unpauseUnwindSwaps(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.UNWIND_SWAP, false);
    }

    /// @inheritdoc IConfig
    function pauseSwaps(MarketId id) external onlyRole(PAUSER_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.SWAP, true);
    }

    /// @inheritdoc IConfig
    function unpauseSwaps(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.SWAP, false);
    }

    /// @inheritdoc IConfig
    function pauseWithdrawals(MarketId id) external onlyRole(PAUSER_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.WITHDRAWAL, true);
    }

    /// @inheritdoc IConfig
    function unpauseWithdrawals(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.WITHDRAWAL, false);
    }

    /// @inheritdoc IConfig
    function pauseUnwindDepositAndMints(MarketId id) external onlyRole(PAUSER_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.PREMATURE_WITHDRAWAL, true);
    }

    /// @inheritdoc IConfig
    function unpauseUnwindDepositAndMints(MarketId id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        corkPool.setPausedState(id, IPoolManager.OperationType.PREMATURE_WITHDRAWAL, false);
    }
}
