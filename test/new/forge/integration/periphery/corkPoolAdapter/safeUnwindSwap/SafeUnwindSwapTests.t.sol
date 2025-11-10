// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {ErrorsLib} from "contracts/periphery/bundler3/libraries/ErrorsLib.sol";
import {BaseTest} from "test/new/forge/BaseTest.sol";

contract SafeUnwindSwapTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal unwindSwapAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(DEFAULT_ADDRESS);
        defaultCorkController.updateUnwindSwapFeeRate(defaultPoolId, 0);

        _deposit(defaultPoolId, 2000 ether, DEFAULT_ADDRESS);

        _swap(defaultPoolId, 1000 ether, DEFAULT_ADDRESS);

        _giveAssets(address(corkAdapter));
    }

    // ================================ SAFE_UNWIND_SWAP TESTS ================================ //

    function test_safeUnwindSwap_ShouldWorkCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before swap
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));

        // Take state snapshot after swap
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(stateAfter.contractCollateral, stateBefore.contractCollateral + unwindSwapAmount, "Contract should sent correct amount of collateral assets");
        assertEq(stateAfter.contractRef, stateBefore.contractRef - unwindSwapAmount, "Contract should take correct amount of reference assets");
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeUnwindSwap_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: address(0), minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp - 1}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: address(0), minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAmount.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: 0, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenSlippageExeceed() external __giveAssets(address(corkAdapter)) __as(BUNDLER3_ADDRESS) {
        // When minCstSharesOut is too high
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount + 1, minReferenceAssetsOut: 0, deadline: block.timestamp}));

        // When minReferenceAssetsOut is too high
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: 0, minReferenceAssetsOut: unwindSwapAmount + 1, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, 1 << 4); // logical OR to enable the 5th bit

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenUnwindSwapsPaused() public __as(pauser) {
        defaultCorkController.pauseUnwindSwaps(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }

    function test_safeUnwindSwap_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeUnwindSwap(ICorkAdapter.SafeUnwindSwapParams({poolId: defaultPoolId, collateralAssetsIn: unwindSwapAmount, receiver: alice, minCstSharesOut: unwindSwapAmount, minReferenceAssetsOut: unwindSwapAmount, deadline: block.timestamp}));
    }
}
