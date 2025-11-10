// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";
import {MaliciousToken, ReentrancyAttacker} from "test/new/forge/mocks/ReentrancyMock.sol";

/**
 * @title UnwindMint Reentrancy Attacker
 * @notice Specific implementation for unwindMint reentrancy attacks
 */
contract UnwindMintReentrancyAttacker is ReentrancyAttacker {
    constructor(address _target) ReentrancyAttacker(_target) {}

    function _attack() internal override {
        target.unwindMint(marketId, 1 ether, address(this), address(this));
    }
}

contract UnwindMintReentrancyTests is BaseTest {
    MaliciousToken private maliciousCollateral;
    MaliciousToken private maliciousReference;
    MarketId private maliciousMarketId;
    UnwindMintReentrancyAttacker private attacker;

    function setUp() public override {
        super.setUp();

        // Setup malicious tokens for reentrancy tests
        maliciousCollateral = new MaliciousToken(address(alice));
        maliciousReference = new MaliciousToken(address(alice));
        attacker = new UnwindMintReentrancyAttacker(address(corkPoolManager));

        // Create malicious market
        uint256 expiry = block.timestamp + 30 days;
        Market memory maliciousMarket =
            Market({collateralAsset: address(maliciousCollateral), referenceAsset: address(maliciousReference), expiryTimestamp: expiry, rateOracle: address(testOracle), rateMin: 0.9 ether, rateMax: 1.1 ether, rateChangePerDayMax: 0.0001 ether, rateChangeCapacityMax: 0.001 ether});

        maliciousMarketId = corkPoolManager.getId(maliciousMarket);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(maliciousMarket, 0, 0, false));

        // Configure attacker
        attacker.setMarketId(maliciousMarketId);
        maliciousCollateral.setAttacker(payable(address(attacker)));
        maliciousReference.setAttacker(payable(address(attacker)));

        // Transfer tokens to attacker
        overridePrank(alice);
        maliciousCollateral.transfer(address(attacker), 1_000_000 ether);
        maliciousReference.transfer(address(attacker), 1_000_000 ether);
    }

    function test_unwindMint_ShouldPreventReentrancy() external {
        overridePrank(address(attacker));
        maliciousCollateral.approve(address(corkPoolManager), type(uint256).max);
        corkPoolManager.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousCollateral.enableAttack(true);

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack();
    }
}
