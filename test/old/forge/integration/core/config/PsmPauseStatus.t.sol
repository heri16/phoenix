pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager} from "contracts/interfaces/IPoolManager.sol";
import {Market} from "contracts/libraries/Market.sol";
import {Helper} from "test/old/forge/Helper.sol";

contract CorkPoolPauseStatusIntegrationTest is Helper {
    function setUp() public {
        vm.startPrank(DEFAULT_ADDRESS);

        deployContracts(DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
        createMarket(1 days);
    }

    function test_pauseDepositStatus_blocksDeposit() public {
        defaultCorkController.pauseDeposits(defaultCurrencyId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.deposit(defaultCurrencyId, 1 ether, currentCaller());
    }

    function test_PauseWithdrawStatus_blocksWithdrawal() public {
        defaultCorkController.pauseWithdrawals(defaultCurrencyId);
        Market memory market = corkPoolManager.market(defaultCurrencyId);
        uint256 expiry = market.expiryTimestamp;

        vm.warp(expiry + 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.redeem(defaultCurrencyId, 0, DEFAULT_ADDRESS, DEFAULT_ADDRESS);
    }

    function test_pauseUnwindSwapStatus_blocksunwindSwap() public {
        defaultCorkController.pauseUnwindSwaps(defaultCurrencyId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.unwindSwap(defaultCurrencyId, 0.1 ether, address(0));
    }

    function test_PauseRedemptionStatus_blocksRedemption() public {
        defaultCorkController.pauseSwaps(defaultCurrencyId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkPoolManager.exercise(defaultCurrencyId, 0.1 ether, DEFAULT_ADDRESS);
    }

    function test_PauseCancelDepositStatus_blocksCancel() public {
        defaultCorkController.pauseUnwindDepositAndMints(defaultCurrencyId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        // Replace with actual cancelPosition if available
        corkPoolManager.unwindDeposit(defaultCurrencyId, 0.01 ether, address(this), address(this));
    }
}
