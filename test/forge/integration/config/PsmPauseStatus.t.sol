pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Helper} from "test/forge/Helper.sol";

contract CorkPoolPauseStatusIntegrationTest is Helper {
    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);

        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        createMarket(1 days);
    }

    function test_pauseDepositStatus_blocksDeposit() public {
        corkConfig.pauseDeposits(defaultCurrencyId);

        vm.expectRevert(IErrors.Paused.selector);
        corkPool.deposit(defaultCurrencyId, 1 ether, currentCaller());
    }

    function test_PauseWithdrawStatus_blocksWithdrawal() public {
        corkConfig.pauseWithdrawals(defaultCurrencyId);
        uint256 expiry = corkPool.expiry(defaultCurrencyId);

        vm.warp(expiry + 1);

        vm.expectRevert(IErrors.Paused.selector);
        corkPool.redeem(defaultCurrencyId, 0, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    function test_pauseUnwindSwapStatus_blocksunwindSwap() public {
        corkConfig.pauseUnwindSwaps(defaultCurrencyId);

        vm.expectRevert(IErrors.Paused.selector);
        corkPool.unwindSwap(defaultCurrencyId, 0.1 ether, address(0));
    }

    function test_PauseRedemptionStatus_blocksRedemption() public {
        corkConfig.pauseSwaps(defaultCurrencyId);

        vm.expectRevert(IErrors.Paused.selector);
        corkPool.exercise(defaultCurrencyId, 0, 0.1 ether, DEFAULT_ADDRESS, 0, type(uint256).max);
    }

    function test_PauseCancelDepositStatus_blocksCancel() public {
        corkConfig.pauseUnwindDepositAndMints(defaultCurrencyId);

        vm.expectRevert(IErrors.Paused.selector);
        // Replace with actual cancelPosition if available
        corkPool.unwindDeposit(defaultCurrencyId, 0.01 ether, address(this), address(this));
    }
}
