// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SafeSwapTests is BaseTest {
    // ================================ STATE VARIABLES ================================ //

    uint256 internal swapAmount = 1000 ether;

    function setUp() public override {
        super.setUp();

        overridePrank(bravo);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);

        _deposit(defaultPoolId, 2000 ether, bravo);

        swapToken.transfer(address(corkAdapter), swapAmount);

        _giveAssets(address(corkAdapter));
    }

    // ================================ SAFE_SWAP TESTS ================================ //

    function test_safeSwap_ShouldSwapTokensCorrectly() external __as(BUNDLER3_ADDRESS) {
        // Take state snapshot before swap
        StateSnapshot memory stateBefore = _getStateSnapshot(alice, defaultPoolId);

        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );

        // Take state snapshot after swap
        StateSnapshot memory stateAfter = _getStateSnapshot(alice, defaultPoolId);

        // Verify contract state changes
        assertEq(
            stateAfter.contractCollateral,
            stateBefore.contractCollateral - swapAmount,
            "Contract should sent correct amount of collateral assets"
        );
        assertEq(
            stateAfter.contractRef,
            stateBefore.contractRef + swapAmount,
            "Contract should take correct amount of reference assets"
        );
    }

    // ================================ NEGATIVE TESTS ================================ //

    function test_safeSwap_ShouldRevert_WhenCalledByNonBundler3() external __as(alice) {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: address(0),
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenDeadlinePassed() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.DeadlineExceeded.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp - 1
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenZeroAddressAsReciever() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: address(0),
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenZeroAmount() external __as(BUNDLER3_ADDRESS) {
        vm.expectRevert(IErrors.ZeroAmount.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: 0,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenSlippageExeceed()
        external
        __giveAssets(address(corkAdapter))
        __as(BUNDLER3_ADDRESS)
    {
        // When maxCstSharesIn is too low
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount - 1,
                maxReferenceAssetsIn: type(uint256).max,
                deadline: block.timestamp
            })
        );

        // When maxReferenceAssetsIn is too low
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: type(uint256).max,
                maxReferenceAssetsIn: swapAmount - 1,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenExpired() external __as(BUNDLER3_ADDRESS) {
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(IErrors.Expired.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setPausedBitMap(defaultPoolId, (1 << 1)); // logical OR to enable the 2nd bit

        overridePrank(BUNDLER3_ADDRESS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenSwapsPaused() public __as(pauser) {
        defaultCorkController.pauseSwaps(defaultPoolId);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }

    function test_safeSwap_ShouldRevert_WhenContractGloballyPaused() external {
        overridePrank(address(defaultCorkController));
        corkPoolManager.setAllPaused(true);

        overridePrank(BUNDLER3_ADDRESS);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        corkAdapter.safeSwap(
            ICorkAdapter.SafeSwapParams({
                poolId: defaultPoolId,
                collateralAssetsOut: swapAmount,
                receiver: alice,
                maxCstSharesIn: swapAmount,
                maxReferenceAssetsIn: swapAmount,
                deadline: block.timestamp
            })
        );
    }
}
