// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {IConfig} from "contracts/interfaces/IConfig.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {MarketId} from "contracts/libraries/Market.sol";

/**
 * @title Config Contract
 * @author Cork Team
 * @notice Config contract for managing pairs and configurations of Cork protocol
 */
contract CorkConfig is AccessControl, Pausable, IConfig {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RATE_UPDATERS_ROLE = keccak256("RATE_UPDATERS_ROLE");
    bytes32 public constant MARKET_ADMIN_ROLE = keccak256("MARKET_ADMIN");

    CorkPool public corkPool;
    // Cork Protocol's treasury address. Other Protocol component should fetch this address directly from the config contract
    // instead of storing it themselves, since it'll be hard to update the treasury address in all the components if it changes vs updating it in the config contract once
    address public treasury;

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), CallerNotManager());
        _;
    }

    modifier onlyMarketAdmin() {
        require(hasRole(MARKET_ADMIN_ROLE, msg.sender), CallerNotMarketAdmin());
        _;
    }

    modifier onlyUpdaterOrManager() {
        require(hasRole(RATE_UPDATERS_ROLE, msg.sender) || hasRole(MANAGER_ROLE, msg.sender), CallerNotManager());
        _;
    }

    constructor(address adminAdd, address managerAdd) {
        require(adminAdd != address(0) && managerAdd != address(0), InvalidAddress());

        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(RATE_UPDATERS_ROLE, MANAGER_ROLE);
        _setRoleAdmin(MARKET_ADMIN_ROLE, MANAGER_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, adminAdd);
        _grantRole(MANAGER_ROLE, managerAdd);
        _grantRole(MARKET_ADMIN_ROLE, managerAdd);
    }

    // This will be only used in case of emergency to change the manager role of the different roles if any of the manager is compromised
    // Although DEFAULT_ADMIN_ROLE and MANAGER_ROLE will be multisig so chances of being compromised is very unlikely, but we still keep this function for in case of emergency
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external onlyRole(getRoleAdmin(role)) {
        require(newAdminRole != getRoleAdmin(role), InvalidAdminRole());
        _setRoleAdmin(role, newAdminRole);
    }

    function grantRole(bytes32 role, address account) public override onlyManager {
        require(!hasRole(role, account), InvalidRole());
        _grantRole(role, account);
    }

    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0) && !hasRole(DEFAULT_ADMIN_ROLE, newAdmin), InvalidAddress());
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }

    /// @inheritdoc IConfig
    function setCorkPool(address _corkPool) external onlyManager {
        require(_corkPool != address(0), InvalidAddress());
        corkPool = CorkPool(_corkPool);
        emit CorkPoolSet(_corkPool);
    }

    /// @inheritdoc IConfig
    function setTreasury(address _treasury) external onlyManager {
        require(_treasury != address(0), InvalidAddress());
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IConfig
    function createNewMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address rateOracle, uint256 rateMin, uint256 rateMax, uint256 rateChangePerDayMax, uint256 rateChangeCapacityMax) external whenNotPaused onlyMarketAdmin {
        corkPool.createNewMarket(referenceAsset, collateralAsset, expiryTimestamp, rateOracle, rateMin, rateMax, rateChangePerDayMax, rateChangeCapacityMax);
    }

    /// @inheritdoc IConfig
    function updateUnwindSwapFeeRate(MarketId id, uint256 newUnwindSwapFeePercentage) external onlyManager {
        corkPool.updateUnwindSwapFeeRate(id, newUnwindSwapFeePercentage);
    }

    /// @inheritdoc IConfig
    function updateBaseRedemptionFeePercentage(MarketId id, uint256 newBaseRedemptionFeePercentage) external onlyManager {
        corkPool.updateBaseRedemptionFeePercentage(id, newBaseRedemptionFeePercentage);
    }

    /// @inheritdoc IConfig
    function pause() external onlyManager {
        _pause();
    }

    /// @inheritdoc IConfig
    function unpause() external onlyManager {
        _unpause();
    }

    /// @inheritdoc IConfig
    function pauseDeposits(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.DEPOSIT, true);
    }

    /// @inheritdoc IConfig
    function unpauseDeposits(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.DEPOSIT, false);
    }

    /// @inheritdoc IConfig
    function pauseUnwindSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.UNWIND_SWAP, true);
    }

    /// @inheritdoc IConfig
    function unpauseUnwindSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.UNWIND_SWAP, false);
    }

    /// @inheritdoc IConfig
    function pauseSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.SWAP, true);
    }

    /// @inheritdoc IConfig
    function unpauseSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.SWAP, false);
    }

    /// @inheritdoc IConfig
    function pauseWithdrawals(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.WITHDRAWAL, true);
    }

    /// @inheritdoc IConfig
    function unpauseWithdrawals(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.WITHDRAWAL, false);
    }

    /// @inheritdoc IConfig
    function pauseUnwindDepositAndMints(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.PREMATURE_WITHDRAWAL, true);
    }

    /// @inheritdoc IConfig
    function unpauseUnwindDepositAndMints(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPoolManager.OperationType.PREMATURE_WITHDRAWAL, false);
    }
}
