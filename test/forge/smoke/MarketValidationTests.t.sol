pragma solidity ^0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathHelper} from "contracts/libraries/MathHelper.sol";
import {console2} from "forge-std/console2.sol";
import {SmokeBase} from "test/forge/SmokeBase.sol";

contract MarketParameterValidationTest is SmokeBase {
    function test_smoke_validateExpriy_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    MARKET PARAMETERS VALIDATED");
        console2.log("========================================");

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

        console2.log(unicode"  → Expiry: %s (timestamp)", EXPECTED_EXPIRY_TIMESTAMP);
        console2.log("    Valid range: [%s, %s]", EXPECTED_MIN_EXPIRY_BOUND, EXPECTED_MAX_EXPIRY_BOUND);
        console2.log(
            unicode"  → Rate Range: %s - %s (oracle bounds)",
            _formatRate(EXPECTED_RATE_MIN_BOUND),
            _formatRate(EXPECTED_RATE_MAX_BOUND)
        );
        console2.log(
            unicode"  → Daily Allowance: %s (max rate change per day)",
            _formatPercentage(EXPECTED_RATE_CHANGE_PER_DAY_MAX)
        );
        console2.log(
            unicode"  → Rate Change Capacity: %s (max capacity)", _formatPercentage(EXPECTED_RATE_CHANGE_CAPACITY_MAX)
        );
        console2.log("");
    }

    function test_smoke_pairDecimals_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    PAIR DECIMALS VALIDATED");
        console2.log("========================================");

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

        console2.log(unicode"  → Collateral: %s (decimals: %s)", EXPECTED_COLLATERAL_ADDRESS, collateralDecimals);
        console2.log(unicode"  → Reference: %s (decimals: %s)", EXPECTED_REFERENCE_ADDRESS, referenceDecimals);
        console2.log("    Acceptable range: [%s, %s]", ACCEPTABLE_DECIMALS_MIN, ACCEPTABLE_DECIMALS_MAX);
        console2.log("");
    }

    function test_smoke_oracleValidRate_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    ORACLE INTEGRATION VALIDATED");
        console2.log("========================================");

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

        console2.log(unicode"  → Oracle address: %s responding correctly", ORACLE_ADDRESS);
        console2.log(unicode"  → Rate format matches contract expectations (%s decimals)", EXPECTED_ORACLE_DECIMALS);
        console2.log(
            unicode"  → Initial rate: %s (expected: %s)", _formatRate(oracleRate), _formatRate(EXPECTED_ORACLE_RATE)
        );
        console2.log(
            "    Rate bounds: [%s, %s]", _formatRate(EXPECTED_RATE_MIN_BOUND), _formatRate(EXPECTED_RATE_MAX_BOUND)
        );
        console2.log("");
    }

    function test_smoke_feePercentage() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    FEE APPLICATION VERIFIED");
        console2.log("========================================");

        uint256 swapFeeFromContract = corkPoolManager.swapFee(defaultPoolId);
        uint256 unwindSwapFeeFromContract = corkPoolManager.unwindSwapFee(defaultPoolId);
        uint256 deltaVal = delta(false);

        assertApproxEqAbs(
            swapFeeFromContract,
            EXPECTED_SWAP_FEE_PERCENTAGE,
            deltaVal,
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
            deltaVal,
            string.concat(
                "UnwindSwap : fee amount mismatch: ",
                vm.toString(unwindSwapFeeFromContract),
                " != ",
                vm.toString(EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE)
            )
        );

        console2.log(
            unicode"  → Exercise Swap Fee: %s (expected: %s)",
            _formatPercentage(swapFeeFromContract),
            _formatPercentage(EXPECTED_SWAP_FEE_PERCENTAGE)
        );
        _logDelta(swapFeeFromContract, EXPECTED_SWAP_FEE_PERCENTAGE, deltaVal);

        uint256 exampleSwapAmount = 100 ether;
        uint256 exampleSwapFee = MathHelper.calculatePercentageFee(exampleSwapAmount, swapFeeFromContract);

        console2.log(
            unicode"  → Repurchase Base Fee: %s (expected: %s)",
            _formatPercentage(unwindSwapFeeFromContract),
            _formatPercentage(EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE)
        );
        _logDelta(unwindSwapFeeFromContract, EXPECTED_UNWIND_SWAP_FEE_PERCENTAGE, deltaVal);

        uint256 exampleRepurchaseProfit = 1 ether;
        uint256 exampleRepurchaseFee =
            MathHelper.calculatePercentageFee(exampleRepurchaseProfit, unwindSwapFeeFromContract);
    }

    function test_smoke_swap() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    SWAP OPERATION VALIDATED");
        console2.log("========================================");

        uint256 deltaRef = delta(true);
        uint256 deltaCollateral = delta(false);

        (uint256 cstSharesIn, uint256 referenceAssetsIn, uint256 fee) =
            corkPoolManager.previewSwap(defaultPoolId, EXPECTED_COLLATERAL_SWAP_AMOUNT_OUT);

        assertApproxEqAbs(
            referenceAssetsIn,
            EXPECTED_REFERENCE_SWAP_AMOUNT_IN,
            deltaRef,
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
            deltaCollateral,
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
            deltaCollateral,
            string.concat("Swap : fee amount mismatch: ", vm.toString(fee), " != ", vm.toString(EXPECTED_SWAP_FEE))
        );

        console2.log(unicode"  → Collateral Out: %s", _formatEther(EXPECTED_COLLATERAL_SWAP_AMOUNT_OUT));
        console2.log("");
        console2.log(
            unicode"  → CST Shares In: %s (expected: %s)",
            _formatEther(cstSharesIn),
            _formatEther(EXPECTED_CST_SHARES_SWAP_AMOUNT_IN)
        );
        _logDelta(cstSharesIn, EXPECTED_CST_SHARES_SWAP_AMOUNT_IN, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Reference In: %s (expected: %s)",
            _formatEther(referenceAssetsIn),
            _formatEther(EXPECTED_REFERENCE_SWAP_AMOUNT_IN)
        );
        _logDelta(referenceAssetsIn, EXPECTED_REFERENCE_SWAP_AMOUNT_IN, deltaRef);
        console2.log("");
        console2.log(unicode"  → Fee: %s (expected: %s)", _formatEther(fee), _formatEther(EXPECTED_SWAP_FEE));
        _logDelta(fee, EXPECTED_SWAP_FEE, deltaCollateral);
        console2.log("");
    }

    function test_smoke_exercise_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    EXERCISE OPERATION VALIDATED");
        console2.log("========================================");

        uint256 deltaRef = delta(true);
        uint256 deltaCollateral = delta(false);

        (uint256 collateralAssetsOut, uint256 referenceAssetsIn, uint256 fee) =
            corkPoolManager.previewExercise(defaultPoolId, EXPECTED_CST_SHARES_EXERCISE_AMOUNT_IN);

        assertApproxEqAbs(
            collateralAssetsOut,
            EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT,
            deltaCollateral,
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
            deltaRef,
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
            deltaCollateral,
            string.concat(
                "Exercise : fee amount mismatch: ", vm.toString(fee), " != ", vm.toString(EXPECTED_EXERCISE_FEE)
            )
        );

        console2.log(unicode"  → CST Shares In: %s", _formatEther(EXPECTED_CST_SHARES_EXERCISE_AMOUNT_IN));
        console2.log("");
        console2.log(
            unicode"  → Collateral Out: %s (expected: %s)",
            _formatEther(collateralAssetsOut),
            _formatEther(EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT)
        );
        _logDelta(collateralAssetsOut, EXPECTED_COLLATERAL_EXERCISE_AMOUNT_OUT, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Reference In: %s (expected: %s)",
            _formatEther(referenceAssetsIn),
            _formatEther(EXPECTED_REFERENCE_EXERCISE_AMOUNT_IN)
        );
        _logDelta(referenceAssetsIn, EXPECTED_REFERENCE_EXERCISE_AMOUNT_IN, deltaRef);
        console2.log("");
        console2.log(unicode"  → Fee: %s (expected: %s)", _formatEther(fee), _formatEther(EXPECTED_EXERCISE_FEE));
        _logDelta(fee, EXPECTED_EXERCISE_FEE, deltaCollateral);
        console2.log("");
    }

    function test_smoke_exerciseOther_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    EXERCISE OTHER OPERATION VALIDATED");
        console2.log("========================================");

        uint256 deltaCollateral = delta(false);

        (uint256 collateralAssetsOut, uint256 cstSharesIn, uint256 fee) =
            corkPoolManager.previewExerciseOther(defaultPoolId, EXPECTED_REFERENCE_EXERCISE_OTHER_AMOUNT_IN);

        assertApproxEqAbs(
            collateralAssetsOut,
            EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT,
            deltaCollateral,
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
            deltaCollateral,
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
            deltaCollateral,
            string.concat(
                "ExerciseOther : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_EXERCISE_OTHER_FEE)
            )
        );

        console2.log(unicode"  → Reference In: %s", _formatEther(EXPECTED_REFERENCE_EXERCISE_OTHER_AMOUNT_IN));
        console2.log("");
        console2.log(
            unicode"  → Collateral Out: %s (expected: %s)",
            _formatEther(collateralAssetsOut),
            _formatEther(EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT)
        );
        _logDelta(collateralAssetsOut, EXPECTED_COLLATERAL_EXERCISE_OTHER_AMOUNT_OUT, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → CST Shares In: %s (expected: %s)",
            _formatEther(cstSharesIn),
            _formatEther(EXPECTED_CST_SHARES_EXERCISE_OTHER_AMOUNT_IN)
        );
        _logDelta(cstSharesIn, EXPECTED_CST_SHARES_EXERCISE_OTHER_AMOUNT_IN, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Fee: %s (expected: %s)", _formatEther(fee), _formatEther(EXPECTED_EXERCISE_OTHER_FEE)
        );
        _logDelta(fee, EXPECTED_EXERCISE_OTHER_FEE, deltaCollateral);
        console2.log("");
    }

    function test_smoke_unwindSwap_fees_initial_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    REPURCHASE (UNWIND SWAP) - INITIAL");
        console2.log("========================================");

        uint256 deltaRef = delta(true);
        uint256 deltaCollateral = delta(false);

        (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN);

        assertApproxEqAbs(
            cstSharesOut,
            EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT,
            deltaCollateral,
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
            deltaRef,
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
            deltaCollateral,
            string.concat(
                "UnwindSwap : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_UNWIND_SWAP_FEE_INITIAL)
            )
        );

        console2.log(unicode"  → Collateral In: %s", _formatEther(EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN));
        console2.log("");
        console2.log(
            unicode"  → CST Shares Out: %s (expected: %s)",
            _formatEther(cstSharesOut),
            _formatEther(EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT)
        );
        _logDelta(cstSharesOut, EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Reference Out: %s (expected: %s)",
            _formatEther(referenceAssetsOut),
            _formatEther(EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT)
        );
        _logDelta(referenceAssetsOut, EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT, deltaRef);
        console2.log("");
        console2.log(
            unicode"  → Fee: %s (expected: %s)", _formatEther(fee), _formatEther(EXPECTED_UNWIND_SWAP_FEE_INITIAL)
        );
        _logDelta(fee, EXPECTED_UNWIND_SWAP_FEE_INITIAL, deltaCollateral);
        console2.log("");
    }

    function test_smoke_unwindSwap_fees_beforeExpiry_market() external {
        console2.log("");
        console2.log("========================================");
        console2.log("    REPURCHASE (UNWIND SWAP) - 30%% BEFORE EXPIRY");
        console2.log("========================================");

        uint256 deltaRef = delta(true);
        uint256 deltaCollateral = delta(false);

        uint256 currentTime = block.timestamp;
        uint256 timeToExpiry = EXPECTED_EXPIRY_TIMESTAMP - currentTime;
        uint256 warpTime = currentTime + MathHelper.calculatePercentageFee(timeToExpiry, 70 ether);

        vm.warp(warpTime);

        (uint256 cstSharesOut, uint256 referenceAssetsOut, uint256 fee) =
            corkPoolManager.previewUnwindSwap(defaultPoolId, EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN_BEFORE_EXPIRY);

        assertApproxEqAbs(
            cstSharesOut,
            EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY,
            deltaCollateral,
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
            deltaRef,
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
            deltaCollateral,
            string.concat(
                "UnwindSwap : fee before expiry amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY)
            )
        );

        console2.log(unicode"  → Time warped to 30%% before expiry (timestamp: %s)", warpTime);
        console2.log("");
        console2.log(
            unicode"  → Collateral In: %s", _formatEther(EXPECTED_COLLATERAL_UNWIND_SWAP_AMOUNT_IN_BEFORE_EXPIRY)
        );
        console2.log("");
        console2.log(
            unicode"  → CST Shares Out: %s (expected: %s)",
            _formatEther(cstSharesOut),
            _formatEther(EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY)
        );
        _logDelta(cstSharesOut, EXPECTED_CST_SHARES_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Reference Out: %s (expected: %s)",
            _formatEther(referenceAssetsOut),
            _formatEther(EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY)
        );
        _logDelta(referenceAssetsOut, EXPECTED_REFERENCE_UNWIND_SWAP_AMOUNT_OUT_BEFORE_EXPIRY, deltaRef);
        console2.log("");
        console2.log(
            unicode"  → Fee (30%% before expiry): %s (expected: %s)",
            _formatEther(fee),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY)
        );
        _logDelta(fee, EXPECTED_COLLATERAL_UNWIND_SWAP_FEE_BEFORE_EXPIRY, deltaCollateral);
        console2.log("");
    }

    function test_smoke_unwindExercise_fees_initial_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    REPURCHASE (UNWIND EXERCISE) - INITIAL");
        console2.log("========================================");

        uint256 deltaRef = delta(true);
        uint256 deltaCollateral = delta(false);

        (uint256 collateralAssetsIn, uint256 referenceAssetsOut, uint256 fee) =
            corkPoolManager.previewUnwindExercise(defaultPoolId, EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT);

        assertApproxEqAbs(
            collateralAssetsIn,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN,
            deltaCollateral,
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
            deltaRef,
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
            deltaCollateral,
            string.concat(
                "UnwindExercise : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE)
            )
        );

        console2.log(unicode"  → CST Shares Out: %s", _formatEther(EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT));
        console2.log("");
        console2.log(
            unicode"  → Collateral In: %s (expected: %s)",
            _formatEther(collateralAssetsIn),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN)
        );
        _logDelta(collateralAssetsIn, EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Reference Out: %s (expected: %s)",
            _formatEther(referenceAssetsOut),
            _formatEther(EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT)
        );
        _logDelta(referenceAssetsOut, EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT, deltaRef);
        console2.log("");
        console2.log(
            unicode"  → Fee: %s (expected: %s)",
            _formatEther(fee),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE)
        );
        _logDelta(fee, EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE, deltaCollateral);
        console2.log("");
    }

    function test_smoke_unwindExercise_fees_beforeExpiry_market() external {
        console2.log("");
        console2.log("========================================");
        console2.log("    REPURCHASE (UNWIND EXERCISE) - 30%% BEFORE EXPIRY");
        console2.log("========================================");

        uint256 deltaRef = delta(true);
        uint256 deltaCollateral = delta(false);

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
            deltaCollateral,
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
            deltaRef,
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
            deltaCollateral,
            string.concat(
                "UnwindExercise : fee before expiry amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY)
            )
        );

        console2.log(unicode"  → Time warped to 30%% before expiry (timestamp: %s)", warpTime);
        console2.log("");
        console2.log(
            unicode"  → CST Shares Out: %s",
            _formatEther(EXPECTED_CST_SHARES_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY)
        );
        console2.log("");
        console2.log(
            unicode"  → Collateral In: %s (expected: %s)",
            _formatEther(collateralAssetsIn),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN_BEFORE_EXPIRY)
        );
        _logDelta(collateralAssetsIn, EXPECTED_COLLATERAL_UNWIND_EXERCISE_AMOUNT_IN_BEFORE_EXPIRY, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Reference Out: %s (expected: %s)",
            _formatEther(referenceAssetsOut),
            _formatEther(EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY)
        );
        _logDelta(referenceAssetsOut, EXPECTED_REFERENCE_UNWIND_EXERCISE_AMOUNT_OUT_BEFORE_EXPIRY, deltaRef);
        console2.log("");
        console2.log(
            unicode"  → Fee (30%% before expiry): %s (expected: %s)",
            _formatEther(fee),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY)
        );
        _logDelta(fee, EXPECTED_COLLATERAL_UNWIND_EXERCISE_FEE_BEFORE_EXPIRY, deltaCollateral);
        console2.log("");
    }

    function test_smoke_unwindExerciseOther_fees_initial_market() external view {
        console2.log("");
        console2.log("========================================");
        console2.log("    REPURCHASE (UNWIND EXERCISE OTHER) - INITIAL");
        console2.log("========================================");

        uint256 deltaCollateral = delta(false);

        (uint256 collateralAssetsIn, uint256 cstSharesOut, uint256 fee) = corkPoolManager.previewUnwindExerciseOther(
            defaultPoolId, EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT
        );

        assertApproxEqAbs(
            collateralAssetsIn,
            EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN,
            deltaCollateral,
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
            deltaCollateral,
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
            deltaCollateral,
            string.concat(
                "UnwindExerciseOther : fee amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE)
            )
        );

        console2.log(
            unicode"  → Reference Out: %s", _formatEther(EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT)
        );
        console2.log("");
        console2.log(
            unicode"  → Collateral In: %s (expected: %s)",
            _formatEther(collateralAssetsIn),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN)
        );
        _logDelta(collateralAssetsIn, EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → CST Shares Out: %s (expected: %s)",
            _formatEther(cstSharesOut),
            _formatEther(EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT)
        );
        _logDelta(cstSharesOut, EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Fee: %s (expected: %s)",
            _formatEther(fee),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE)
        );
        _logDelta(fee, EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE, deltaCollateral);
        console2.log("");
    }

    function test_smoke_unwindExerciseOther_fees_beforeExpiry_market() external {
        console2.log("");
        console2.log("========================================");
        console2.log("    REPURCHASE (UNWIND EXERCISE OTHER) - 30%% BEFORE EXPIRY");
        console2.log("========================================");

        uint256 deltaCollateral = delta(false);

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
            deltaCollateral,
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
            deltaCollateral,
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
            deltaCollateral,
            string.concat(
                "UnwindExerciseOther : fee before expiry amount mismatch: ",
                vm.toString(fee),
                " != ",
                vm.toString(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY)
            )
        );

        console2.log(unicode"  → Time warped to 30%% before expiry (timestamp: %s)", warpTime);
        console2.log("");
        console2.log(
            unicode"  → Reference Out: %s",
            _formatEther(EXPECTED_REFERENCE_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY)
        );
        console2.log("");
        console2.log(
            unicode"  → Collateral In: %s (expected: %s)",
            _formatEther(collateralAssetsIn),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN_BEFORE_EXPIRY)
        );
        _logDelta(
            collateralAssetsIn, EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_AMOUNT_IN_BEFORE_EXPIRY, deltaCollateral
        );
        console2.log("");
        console2.log(
            unicode"  → CST Shares Out: %s (expected: %s)",
            _formatEther(cstSharesOut),
            _formatEther(EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY)
        );
        _logDelta(cstSharesOut, EXPECTED_CST_SHARES_UNWIND_EXERCISE_OTHER_AMOUNT_OUT_BEFORE_EXPIRY, deltaCollateral);
        console2.log("");
        console2.log(
            unicode"  → Fee (30%% before expiry): %s (expected: %s)",
            _formatEther(fee),
            _formatEther(EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY)
        );
        _logDelta(fee, EXPECTED_COLLATERAL_UNWIND_EXERCISE_OTHER_FEE_BEFORE_EXPIRY, deltaCollateral);
        console2.log("");
    }

    function test_smoke_whitelistTests_market() external view {
        console2.log("");
        console2.log("========================================");
        if (EXPECTED_WHITELIST_ENABLED) {
            console2.log("    WHITELIST [ENABLED]");
        } else {
            console2.log("    WHITELIST [DISABLED]");
        }
        console2.log("========================================");

        if (EXPECTED_WHITELIST_ENABLED) {
            console2.log(unicode"  → %s addresses configured and tested", EXPECTED_WHITELISTED_ADDRESSES.length);

            for (uint256 i = 0; i < EXPECTED_WHITELISTED_ADDRESSES.length; i++) {
                bool isWhitelisted = whitelistManager.isWhitelisted(defaultPoolId, EXPECTED_WHITELISTED_ADDRESSES[i]);
                assertTrue(
                    isWhitelisted,
                    string.concat("Address ", vm.toString(EXPECTED_WHITELISTED_ADDRESSES[i]), " is not whitelisted")
                );
                console2.log("    [%s] %s", i + 1, EXPECTED_WHITELISTED_ADDRESSES[i]);
            }
        } else {
            console2.log(unicode"  → Whitelist is disabled for this market");
        }

        console2.log("");
    }
}
