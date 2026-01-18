pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {SmokeBase} from "test/forge/SmokeBase.sol";

contract MarketParameterValidationTest is SmokeBase {
    function test_smoke_validateExpriy_market() external view {
        assertGe(
            EXPECTED_EXPIRY_TIMESTAMP,
            EXPECTED_MIN_EXPIRY_BOUND,
            string.concat(
                "Expiry : timestamp amount mismatch: ",
                vm.toString(EXPECTED_EXPIRY_TIMESTAMP),
                " < ",
                vm.toString(EXPECTED_MIN_EXPIRY_BOUND)
            )
        );
        assertLe(
            EXPECTED_EXPIRY_TIMESTAMP,
            EXPECTED_MAX_EXPIRY_BOUND,
            string.concat(
                "Expiry : timestamp amount mismatch: ",
                vm.toString(EXPECTED_EXPIRY_TIMESTAMP),
                " > ",
                vm.toString(EXPECTED_MAX_EXPIRY_BOUND)
            )
        );
    }

    function test_smoke_pairDecimals_market() external view {
        uint8 collateralDecimals = IERC20Metadata(EXPECTED_COLLATERAL_ADDRESS).decimals();
        uint8 referenceDecimals = IERC20Metadata(EXPECTED_REFERENCE_ADDRESS).decimals();

        assertTrue(
            collateralDecimals <= ACCEPTABLE_DECIMALS_MAX && collateralDecimals >= ACCEPTABLE_DECIMALS_MIN,
            string.concat(
                "Pair : collateral decimals amount mismatch: ",
                vm.toString(collateralDecimals),
                " > ",
                vm.toString(ACCEPTABLE_DECIMALS_MAX),
                " or ",
                vm.toString(collateralDecimals),
                " < ",
                vm.toString(ACCEPTABLE_DECIMALS_MIN)
            )
        );
        assertTrue(
            referenceDecimals <= ACCEPTABLE_DECIMALS_MAX && referenceDecimals >= ACCEPTABLE_DECIMALS_MIN,
            string.concat(
                "Pair : reference decimals amount mismatch: ",
                vm.toString(referenceDecimals),
                " > ",
                vm.toString(ACCEPTABLE_DECIMALS_MAX),
                " or ",
                vm.toString(referenceDecimals),
                " < ",
                vm.toString(ACCEPTABLE_DECIMALS_MIN)
            )
        );
    }

    function test_smoke_oracleValidRate_market() external view {
        uint256 oracleRate = oracle.rate();

        uint256 expectedRateLower =
            EXPECTED_ORACLE_RATE - MathHelper.calculatePercentageFee(1 ether, EXPECTED_ORACLE_RATE);
        uint256 expectedRateUpper =
            EXPECTED_ORACLE_RATE + MathHelper.calculatePercentageFee(1 ether, EXPECTED_ORACLE_RATE);

        assertTrue(
            oracleRate <= expectedRateUpper && oracleRate >= expectedRateLower,
            string.concat(
                "Oracle : rate amount mismatch: ", vm.toString(oracleRate), " != ", vm.toString(EXPECTED_ORACLE_RATE)
            )
        );

        assertEq(oracleRate, EXPECTED_ORACLE_RATE);
    }

    function test_smoke_feePercentage() external view {
        uint256 swapFeeFromContract = corkPoolManager.swapFee(defaultPoolId);
        uint256 unwindSwapFeeFromContract = corkPoolManager.unwindSwapFee(defaultPoolId);

        assertApproxEqAbs(
            swapFeeFromContract,
            EXPECTED_SWAP_FEE_PERCENTAGE,
            delta(false),
            string.concat(
                "Swap : fee amount mismatch: ",
                vm.toString(swapFeeFromContract),
                " != ",
                vm.toString(EXPECTED_SWAP_FEE_PERCENTAGE)
            )
        );
        assertApproxEqAbs(
            unwindSwapFeeFromContract,
            EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE,
            delta(false),
            string.concat(
                "UnwindSwap : fee amount mismatch: ",
                vm.toString(unwindSwapFeeFromContract),
                " != ",
                vm.toString(EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE)
            )
        );
    }

    function test_smoke_swap() external view {
        (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee) =
            corkPoolManager.previewSwap(defaultPoolId, EXPECTED_COLLATERAL_SWAP_AMOUNT_OUT);

        assertApproxEqAbs(
            referenceAssetsIn,
            EXPECTED_REFERENCE_SWAP_AMOUNT_IN,
            delta(true),
            string.concat(
                "Swap : reference input amount mismatch: ",
                vm.toString(referenceAssetsIn),
                " != ",
                vm.toString(EXPECTED_REFERENCE_SWAP_AMOUNT_IN)
            )
        );
        assertApproxEqAbs(
            cstSharesIn,
            EXPECTED_CST_SHARES_SWAP_AMOUNT_IN,
            delta(false),
            string.concat(
                "Swap : CST shares input amount mismatch: ",
                vm.toString(cstSharesIn),
                " != ",
                vm.toString(EXPECTED_CST_SHARES_SWAP_AMOUNT_IN)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_SWAP_FEE,
            delta(false),
            string.concat("Swap : fee amount mismatch: ", vm.toString(fee), " != ", vm.toString(EXPECTED_SWAP_FEE))
        );
    }

    function test_smoke_exercise_market() external view {
        (uint256 collateralAssetsOut, uint256 referenceAssetsIn, uint256 fee) =
            corkPoolManager.previewExercise(defaultPoolId, EXPECTED_CST_SHARES_EXERCISE_AMOUNT_IN);

        assertApproxEqAbs(
            collateralAssetsOut,
            EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT,
            delta(false),
            string.concat(
                "Exercise : collateral output amount mismatch: ",
                vm.toString(collateralAssetsOut),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT)
            )
        );
        assertApproxEqAbs(
            referenceAssetsIn,
            EXPECTED_REFERENCE_EXERCISE_AMOUNT_IN,
            delta(true),
            string.concat(
                "Exercise : reference input amount mismatch: ",
                vm.toString(referenceAssetsIn),
                " != ",
                vm.toString(EXPECTED_REFERENCE_EXERCISE_AMOUNT_IN)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_EXERCISE_FEE,
            delta(false),
            string.concat(
                "Exercise : fee amount mismatch: ", vm.toString(fee), " != ", vm.toString(EXPECTED_EXERCISE_FEE)
            )
        );
    }

    function test_smoke_exerciseOther_market() external view {
        (uint256 collateralAssetsOut, uint256 cstSharesIn, uint256 fee) =
            corkPoolManager.previewExerciseOther(defaultPoolId, EXPECTED_REFERENCE_EXERCISE_OTHER_AMOUNT_IN);

        assertApproxEqAbs(
            collateralAssetsOut,
            EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT,
            delta(false),
            string.concat(
                "ExerciseOther : collateral output amount mismatch: ",
                vm.toString(collateralAssetsOut),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT)
            )
        );
        assertApproxEqAbs(
            cstSharesIn,
            EXPECTED_CST_SHARES_EXERCISE_OTHER_AMOUNT_IN,
            delta(false),
            string.concat(
                "ExerciseOther : CST shares input amount mismatch: ",
                vm.toString(cstSharesIn),
                " != ",
                vm.toString(EXPECTED_CST_SHARES_EXERCISE_OTHER_AMOUNT_IN)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_EXERCISE_OTHER_FEE,
            delta(false),
            string.concat(
                "ExerciseOther : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_EXERCISE_OTHER_FEE)
            )
        );
    }

    function test_smoke_unwindSwap_fees_initial_market() external view {
        (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN);

        assertApproxEqAbs(
            cstSharesOut,
            EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT,
            delta(false),
            string.concat(
                "UnwindSwap : CST shares output amount mismatch: ",
                vm.toString(cstSharesOut),
                " != ",
                vm.toString(EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT)
            )
        );
        assertApproxEqAbs(
            referenceAssetsOut,
            EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT,
            delta(true),
            string.concat(
                "UnwindSwap : reference output amount mismatch: ",
                vm.toString(referenceAssetsOut),
                " != ",
                vm.toString(EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_UNWIND_SWAP_FEE_INITIAL,
            delta(false),
            string.concat(
                "UnwindSwap : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_UNWIND_SWAP_FEE_INITIAL)
            )
        );
    }

    function test_smoke_unwindSwap_fees_beforeExpiry_market() external {
        uint256 currentTime = block.timestamp;
        uint256 timeToExpiry = EXPECTED_EXPIRY_TIMESTAMP - currentTime;
        uint256 warpTime = currentTime + MathHelper.calculatePercentageFee(timeToExpiry, 70 ether);

        vm.warp(warpTime);

        (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN_BEFORE_EXPIRY);

        assertApproxEqAbs(
            cstSharesOut,
            EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindSwap : CST shares output amount mismatch: ",
                vm.toString(cstSharesOut),
                " != ",
                vm.toString(EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY)
            )
        );
        assertApproxEqAbs(
            referenceAssetsOut,
            EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY,
            delta(true),
            string.concat(
                "UnwindSwap : reference output amount mismatch: ",
                vm.toString(referenceAssetsOut),
                " != ",
                vm.toString(EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindSwap : fee before expiry amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY)
            )
        );
    }

    function test_smoke_unwindExercise_fees_initial_market() external view {
        (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) =
            corkPoolManager.previewUnwindExercise(defaultPoolId, EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT);

        assertApproxEqAbs(
            collateralAssetsIn,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN,
            delta(false),
            string.concat(
                "UnwindExercise : collateral input amount mismatch: ",
                vm.toString(collateralAssetsIn),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN)
            )
        );
        assertApproxEqAbs(
            referenceAssetsOut,
            EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT,
            delta(true),
            string.concat(
                "UnwindExercise : reference output amount mismatch: ",
                vm.toString(referenceAssetsOut),
                " != ",
                vm.toString(EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE,
            delta(false),
            string.concat(
                "UnwindExercise : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE)
            )
        );
    }

    function test_smoke_unwindExercise_fees_beforeExpiry_market() external {
        uint256 currentTime = block.timestamp;
        uint256 timeToExpiry = EXPECTED_EXPIRY_TIMESTAMP - currentTime;
        uint256 warpTime = currentTime + MathHelper.calculatePercentageFee(timeToExpiry, 70 ether);

        vm.warp(warpTime);

        (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) = corkPoolManager.previewUnwindExercise(
            defaultPoolId, EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY
        );

        assertApproxEqAbs(
            collateralAssetsIn,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindExercise : collateral input amount mismatch: ",
                vm.toString(collateralAssetsIn),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN_BEFORE_EXPIRY)
            )
        );
        assertApproxEqAbs(
            referenceAssetsOut,
            EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY,
            delta(true),
            string.concat(
                "UnwindExercise : reference output amount mismatch: ",
                vm.toString(referenceAssetsOut),
                " != ",
                vm.toString(EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindExercise : fee before expiry amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY)
            )
        );
    }

    function test_smoke_unwindExerciseOther_fees_initial_market() external view {
        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(
            defaultPoolId, EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT
        );

        assertApproxEqAbs(
            collateralAssetsIn,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN,
            delta(false),
            string.concat(
                "UnwindExerciseOther : collateral input amount mismatch: ",
                vm.toString(collateralAssetsIn),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN)
            )
        );
        assertApproxEqAbs(
            cstSharesOut,
            EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT,
            delta(false),
            string.concat(
                "UnwindExerciseOther : CST shares output amount mismatch: ",
                vm.toString(cstSharesOut),
                " != ",
                vm.toString(EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE,
            delta(false),
            string.concat(
                "UnwindExerciseOther : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE)
            )
        );
    }

    function test_smoke_unwindExerciseOther_fees_beforeExpiry_market() external {
        uint256 currentTime = block.timestamp;
        uint256 timeToExpiry = EXPECTED_EXPIRY_TIMESTAMP - currentTime;
        uint256 warpTime = currentTime + MathHelper.calculatePercentageFee(timeToExpiry, 70 ether);

        vm.warp(warpTime);

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(
            defaultPoolId, EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY
        );

        assertApproxEqAbs(
            collateralAssetsIn,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindExerciseOther : collateral input amount mismatch: ",
                vm.toString(collateralAssetsIn),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN_BEFORE_EXPIRY)
            )
        );
        assertApproxEqAbs(
            cstSharesOut,
            EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindExerciseOther : CST shares output amount mismatch: ",
                vm.toString(cstSharesOut),
                " != ",
                vm.toString(EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY)
            )
        );
        assertApproxEqAbs(
            fee,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY,
            delta(false),
            string.concat(
                "UnwindExerciseOther : fee before expiry amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY)
            )
        );
    }

    function test_smoke_whitelistTests_market() external view {
        for (uint256 i = 0; i < EXPECTED_WHITELISTED_ADDRESSES.length; i++) {
            bool isWhitelisted = whitelistManager.isWhitelisted(defaultPoolId, EXPECTED_WHITELISTED_ADDRESSES[i]);
            assertTrue(
                isWhitelisted,
                string.concat("Address ", vm.toString(EXPECTED_WHITELISTED_ADDRESSES[i]), " is not whitelisted")
            );
        }
    }
}
