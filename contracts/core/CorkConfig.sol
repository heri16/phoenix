// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {ExchangeRateProvider} from "contracts/core/ExchangeRateProvider.sol";
import {IConfig} from "contracts/interfaces/IConfig.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
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
    ExchangeRateProvider public defaultExchangeRateProvider;
    // Cork Protocol's treasury address. Other Protocol component should fetch this address directly from the config contract
    // instead of storing it themselves, since it'll be hard to update the treasury address in all the components if it changes vs updating it in the config contract once
    address public treasury;

    modifier onlyManager() {
        if (!hasRole(MANAGER_ROLE, msg.sender)) revert CallerNotManager();
        _;
    }

    modifier onlyMarketAdmin() {
        if (!hasRole(MARKET_ADMIN_ROLE, msg.sender)) revert CallerNotMarketAdmin();
        _;
    }

    modifier onlyUpdaterOrManager() {
        if (!hasRole(RATE_UPDATERS_ROLE, msg.sender) && !hasRole(MANAGER_ROLE, msg.sender)) revert CallerNotManager();
        _;
    }

    constructor(address adminAdd, address managerAdd) {
        if (adminAdd == address(0) || managerAdd == address(0)) revert InvalidAddress();

        defaultExchangeRateProvider = new ExchangeRateProvider(address(this));

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
        if (newAdminRole == getRoleAdmin(role)) revert InvalidAdminRole();
        _setRoleAdmin(role, newAdminRole);
    }

    function grantRole(bytes32 role, address account) public override onlyManager {
        if (hasRole(role, account)) revert InvalidRole();
        _grantRole(role, account);
    }

    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0) || hasRole(DEFAULT_ADMIN_ROLE, newAdmin)) revert InvalidAddress();
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }

    /// @inheritdoc IConfig
    function setCorkPool(address _corkPool) external onlyManager {
        if (_corkPool == address(0)) revert InvalidAddress();
        corkPool = CorkPool(_corkPool);
        emit CorkPoolSet(_corkPool);
    }

    /// @inheritdoc IConfig
    function setTreasury(address _treasury) external onlyManager {
        if (_treasury == address(0)) revert InvalidAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IConfig
    function createNewMarket(address referenceAsset, address collateralAsset, uint256 expiryTimestamp, address exchangeRateProvider) external whenNotPaused onlyMarketAdmin {
        corkPool.createNewMarket(referenceAsset, collateralAsset, expiryTimestamp, exchangeRateProvider);
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
    function updateCorkPoolRate(MarketId id, uint256 newRate) external onlyUpdaterOrManager {
        // we update the rate in our provider regardless it's up or down. won't affect other market's rates that doesn't use this provider
        defaultExchangeRateProvider.setRate(id, newRate);
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
        corkPool.setPausedState(id, IPool.OperationType.DEPOSIT, true);
    }

    /// @inheritdoc IConfig
    function unpauseDeposits(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.DEPOSIT, false);
    }

    /// @inheritdoc IConfig
    function pauseUnwindSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.UNWIND_SWAP, true);
    }

    /// @inheritdoc IConfig
    function unpauseUnwindSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.UNWIND_SWAP, false);
    }

    /// @inheritdoc IConfig
    function pauseSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.SWAP, true);
    }

    /// @inheritdoc IConfig
    function unpauseSwaps(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.SWAP, false);
    }

    /// @inheritdoc IConfig
    function pauseWithdrawals(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.WITHDRAWAL, true);
    }

    /// @inheritdoc IConfig
    function unpauseWithdrawals(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.WITHDRAWAL, false);
    }

    /// @inheritdoc IConfig
    function pauseUnwindDepositAndMints(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.PREMATURE_WITHDRAWAL, true);
    }

    /// @inheritdoc IConfig
    function unpauseUnwindDepositAndMints(MarketId id) external onlyManager {
        corkPool.setPausedState(id, IPool.OperationType.PREMATURE_WITHDRAWAL, false);
    }
}
