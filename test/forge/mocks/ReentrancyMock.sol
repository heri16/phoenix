// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {MarketId} from "contracts/interfaces/IPoolManager.sol";

/**
 * @title Generic Reentrancy Attack Contract
 * @notice Mock malicious contract to test reentrancy protection for any function
 */
abstract contract ReentrancyAttacker {
    CorkPoolManager internal target;
    MarketId internal marketId;
    bool internal attacking;

    constructor(address _target) {
        target = CorkPoolManager(_target);
    }

    function setMarketId(MarketId _marketId) external {
        marketId = _marketId;
    }

    function attack() external {
        attacking = true;
        _attack();
    }

    function _attack() internal virtual {}

    receive() external payable {
        if (attacking) {
            attacking = false;
            _attack();
        }
    }
}

/**
 * @title Generic Malicious ERC20 Token
 * @notice Mock ERC20 that triggers reentrancy on transfer
 */
contract MaliciousToken is ERC20 {
    ReentrancyAttacker private attacker;
    bool private shouldAttack;

    constructor(address _user) ERC20("Malicious Token", "MAL") {
        _mint(_user, 1_000_000 ether);
    }

    function setAttacker(address payable _attacker) external {
        attacker = ReentrancyAttacker(_attacker);
    }

    function enableAttack(bool _enable) external {
        shouldAttack = _enable;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        if (shouldAttack && address(attacker) != address(0)) attacker.attack();
        return success;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        if (shouldAttack && address(attacker) != address(0)) attacker.attack();
        return success;
    }
}
