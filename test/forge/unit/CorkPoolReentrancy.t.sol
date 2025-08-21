// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {IUnwindSwap} from "contracts/interfaces/IUnwindSwap.sol";
import {Initialize} from "contracts/interfaces/Initialize.sol";
import {Market, MarketId, MarketLibrary} from "contracts/libraries/Market.sol";
import {Helper} from "test/forge/Helper.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/**
 * @title Reentrancy Attack Contract
 * @notice Mock malicious contract to test reentrancy protection
 */
contract ReentrancyAttacker {
    CorkPool private target;
    MarketId private marketId;
    uint256 private attackType;
    bool private attacking;

    constructor(address _target) {
        target = CorkPool(_target);
    }

    function setMarketId(MarketId _marketId) external {
        marketId = _marketId;
    }

    function attack(uint256 _attackType) external {
        attackType = _attackType;
        attacking = true;

        if (attackType == 1) {
            // Attack deposit
            target.deposit(marketId, 1 ether, address(this));
        } else if (attackType == 2) {
            // Attack unwindSwap
            target.unwindSwap(marketId, 1 ether, address(this));
        } else if (attackType == 3) {
            // Attack exercise
            target.exercise(marketId, 1 ether, 0, address(this), 0, type(uint256).max);
        } else if (attackType == 4) {
            // Attack redeem
            target.redeem(marketId, 1 ether, address(this), address(this));
        } else if (attackType == 5) {
            // Attack unwindMint
            target.unwindMint(marketId, 1 ether, address(this), address(this));
        } else if (attackType == 6) {
            // Attack swap
            target.swap(marketId, 1 ether, address(this));
        } else if (attackType == 7) {
            // Attack withdraw
            target.withdraw(marketId, 1 ether, 0, address(this), address(this));
        } else if (attackType == 8) {
            // Attack mint
            target.mint(marketId, 1 ether, address(this));
        } else if (attackType == 9) {
            // Attack unwindDeposit
            target.unwindDeposit(marketId, 1 ether, address(this), address(this));
        } else if (attackType == 10) {
            // Attack unwindExercise
            target.unwindExercise(marketId, 1 ether, address(this), 0, type(uint256).max);
        }
    }

    // ERC20 transfer hooks to trigger reentrancy
    function onTransfer() external {
        if (attacking) {
            attacking = false; // Prevent infinite recursion

            if (attackType == 1) target.deposit(marketId, 1 ether, address(this));
            else if (attackType == 2) target.unwindSwap(marketId, 1 ether, address(this));
            else if (attackType == 3) target.exercise(marketId, 1 ether, 1 ether, address(this), 0, type(uint256).max);
            else if (attackType == 4) target.redeem(marketId, 1 ether, address(this), address(this));
            else if (attackType == 5) target.unwindMint(marketId, 1 ether, address(this), address(this));
            else if (attackType == 6) target.swap(marketId, 1 ether, address(this));
            else if (attackType == 7) target.withdraw(marketId, 1 ether, 0, address(this), address(this));
            else if (attackType == 8) target.mint(marketId, 1 ether, address(this));
            else if (attackType == 9) target.unwindDeposit(marketId, 1 ether, address(this), address(this));
            else if (attackType == 10) target.unwindExercise(marketId, 1 ether, address(this), 0, type(uint256).max);
        }
    }

    // Fallback to receive ETH
    receive() external payable {
        if (attacking) {
            attacking = false; // Prevent infinite recursion

            if (attackType == 1) target.deposit(marketId, 1 ether, address(this));
            else if (attackType == 2) target.unwindSwap(marketId, 1 ether, address(this));
            else if (attackType == 3) target.exercise(marketId, 1 ether, 1 ether, address(this), 0, type(uint256).max);
            else if (attackType == 4) target.redeem(marketId, 1 ether, address(this), address(this));
            else if (attackType == 5) target.unwindMint(marketId, 1 ether, address(this), address(this));
            else if (attackType == 6) target.swap(marketId, 1 ether, address(this));
            else if (attackType == 7) target.withdraw(marketId, 1 ether, 0, address(this), address(this));
            else if (attackType == 8) target.mint(marketId, 1 ether, address(this));
            else if (attackType == 9) target.unwindDeposit(marketId, 1 ether, address(this), address(this));
            else if (attackType == 10) target.unwindExercise(marketId, 1 ether, address(this), 0, type(uint256).max);
        }
    }
}

/**
 * @title Malicious ERC20 Token
 * @notice Mock ERC20 that triggers reentrancy on transfer
 */
contract MaliciousToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    string public name = "Malicious Token";
    string public symbol = "MAL";
    uint8 public decimals = 18;

    ReentrancyAttacker private attacker;
    bool private shouldAttack;

    constructor(address _user) {
        totalSupply = 1_000_000 ether;
        balanceOf[_user] = totalSupply;
    }

    function setAttacker(address payable _attacker) external {
        attacker = ReentrancyAttacker(_attacker);
    }

    function enableAttack(bool _enable) external {
        shouldAttack = _enable;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        if (shouldAttack && address(attacker) != address(0)) attacker.onTransfer();

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        if (shouldAttack && address(attacker) != address(0)) attacker.onTransfer();

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract CorkPoolReentrancyTest is Helper {
    ERC20Mock private collateralAsset;
    ERC20Mock private referenceAsset;
    MaliciousToken private maliciousCollateral;
    MaliciousToken private maliciousReference;
    MarketId private marketId;
    MarketId private maliciousMarketId;
    ReentrancyAttacker private attacker;
    address private user;

    function setUp() public {
        user = address(0x1234);

        vm.startPrank(DEFAULT_ADDRESS);
        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        (collateralAsset, referenceAsset, marketId) = createMarket(1 days);

        // Deploy malicious tokens and attacker
        maliciousCollateral = new MaliciousToken(user);
        maliciousReference = new MaliciousToken(user);
        attacker = new ReentrancyAttacker(address(corkPool));

        // Setup malicious market
        uint256 expiry = block.timestamp + 30 days;
        uint256 rateMin = 0.9 ether;
        uint256 rateMax = 1.1 ether;
        uint256 rateChangePerDayMax = 0.0001 ether;
        uint256 rateChangeCapacityMax = 0.001 ether;
        maliciousMarketId = corkPool.getId(address(maliciousReference), address(maliciousCollateral), expiry, address(testOracle), rateMin, rateMax, rateChangePerDayMax, rateChangeCapacityMax);

        corkConfig.createNewMarket(address(maliciousReference), address(maliciousCollateral), expiry, address(testOracle), rateMin, rateMax, rateChangePerDayMax, rateChangeCapacityMax);

        // Setup attacker
        attacker.setMarketId(maliciousMarketId);
        maliciousCollateral.setAttacker(payable(address(attacker)));
        maliciousReference.setAttacker(payable(address(attacker)));

        // Fund accounts
        vm.deal(user, type(uint256).max);
        vm.deal(address(attacker), type(uint256).max);

        vm.startPrank(user);
        collateralAsset.deposit{value: type(uint128).max}();
        referenceAsset.deposit{value: type(uint128).max}();

        // Transfer malicious tokens to attacker
        maliciousCollateral.transfer(address(attacker), 1_000_000 ether);
        maliciousReference.transfer(address(attacker), 1_000_000 ether);

        vm.stopPrank();
    }

    // ================================ Reentrancy Tests ================================ //

    function test_deposit_ShouldPreventReentrancy() external {
        vm.startPrank(address(attacker));

        // Setup attacker with tokens and approvals
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(1); // Attack type 1 = deposit

        vm.stopPrank();
    }

    function test_unwindDeposit_ShouldPreventReentrancy() external {
        // Setup with tokens
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(9); // Attack type 9 = unwindDeposit

        vm.stopPrank();
    }

    function test_mint_ShouldPreventReentrancy() external {
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(8); // Attack type 8 = mint

        vm.stopPrank();
    }

    function test_unwindMint_ShouldPreventReentrancy() external {
        // Setup with tokens
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(5); // Attack type 5 = unwindMint

        vm.stopPrank();
    }

    function test_exercise_ShouldPreventReentrancy() external {
        // Setup market with some deposits and swap tokens
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        maliciousReference.approve(address(corkPool), type(uint256).max);

        // Deposit to get shares
        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(3); // Attack type 3 = exercise

        vm.stopPrank();
    }

    function test_unwindExercise_ShouldPreventReentrancy() external {
        // Setup market with deposits
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        maliciousReference.approve(address(corkPool), type(uint256).max);

        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousReference.approve(address(corkPool), type(uint256).max);
        corkPool.exercise(maliciousMarketId, 100 ether, 0, address(attacker), 0, type(uint256).max);

        maliciousReference.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(10); // Attack type 10 = unwindExercise

        vm.stopPrank();
    }

    function test_swap_ShouldPreventReentrancy() external {
        // Setup market with deposits
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        maliciousReference.approve(address(corkPool), type(uint256).max);

        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousReference.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(6); // Attack type 6 = swap

        vm.stopPrank();
    }

    function test_unwindSwap_ShouldPreventReentrancy() external {
        // First setup some liquidity in the malicious market
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        maliciousReference.approve(address(corkPool), type(uint256).max);
        corkPool.exercise(maliciousMarketId, 100 ether, 0, address(attacker), 0, type(uint256).max);

        maliciousReference.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(2); // Attack type 2 = unwindSwap

        vm.stopPrank();
    }

    function test_redeem_ShouldPreventReentrancy() external {
        // Setup expired market with shares
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        // Fast forward past expiry
        vm.warp(block.timestamp + 31 days);

        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(4); // Attack type 4 = redeem

        vm.stopPrank();
    }

    function test_withdraw_ShouldPreventReentrancy() external {
        // Setup expired market with shares
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);
        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        // Fast forward past expiry
        vm.warp(block.timestamp + 31 days);

        maliciousCollateral.enableAttack(true);

        // Attempt reentrancy attack - should revert
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(7); // Attack type 7 = withdraw

        vm.stopPrank();
    }

    function test_deposit_to_unwindDeposit_ShouldPreventCrossReentrancy() external {
        // Test that calling one nonReentrant function from another also fails
        vm.startPrank(address(attacker));
        maliciousCollateral.approve(address(corkPool), type(uint256).max);

        // Setup a different attack pattern - deposit trying to call unwindSwap
        maliciousCollateral.enableAttack(true);

        corkPool.deposit(maliciousMarketId, 1000 ether, address(attacker));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        attacker.attack(9);

        vm.stopPrank();
    }
}
