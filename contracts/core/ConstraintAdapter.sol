// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SD59x18, abs, convert, div, mul, sd, sub, unwrap} from "@prb/math/src/SD59x18.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {IConstraintAdapter} from "contracts/interfaces/IConstraintAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IComposableRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title RateOracle Contract
 * @author Cork Team
 * @notice Contract for managing oracle rate
 */
contract ConstraintAdapter is IErrors, IConstraintAdapter, UUPSUpgradeable, OwnableUpgradeable {
    struct ConstraintAdapterStorage {
        address corkPool;
        mapping(MarketId => ConstraintState) constraints;
    }

    modifier onlyCorkPool() {
        require(_msgSender() == data().corkPool, IErrors.NotCorkPool());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _corkPool) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner);
        data().corkPool = _corkPool;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ERC-7201 Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cork.storage.ConstraintAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _CONSTRAINT_ADAPTER_STORAGE_POSITION = 0x850a01c36e696ae1195ad02907192131a1808c20fd305f275554f8ccd5afa800;

    function data() internal pure returns (ConstraintAdapterStorage storage cs) {
        assembly {
            cs.slot := _CONSTRAINT_ADAPTER_STORAGE_POSITION
        }
    }

    function _fetchRate(Market memory pool) internal view returns (uint256 rate) {
        try IComposableRateOracle(pool.rateOracle).rate() returns (uint256 _rate) {
            rate = _rate;
        } catch {
            (, int256 answer,,,) = IComposableRateOracle(pool.rateOracle).latestRoundData();

            require(answer > 0, IErrors.InvalidRate());

            rate = uint256(answer);
            rate = TransferHelper.normalizeDecimals(rate, IComposableRateOracle(pool.rateOracle).decimals(), TransferHelper.TARGET_DECIMALS);
        }
    }

    function bootstrap(MarketId poolId) external onlyCorkPool {
        Market memory pool = CorkPool(data().corkPool).market(poolId);
        ConstraintState storage constraint = data().constraints[poolId];

        uint256 rate = _fetchRate(pool);

        constraint._lastAdjustedRate = rate;
        constraint._lastAdjustmentTimestamp = block.timestamp;
        constraint._remainingCredits = pool.rateChangeCapacityMax;
    }

    struct RateCalculationParams {
        uint256 newRate;
        uint256 lastAdjustedRate;
        uint256 remainingCredits;
        uint256 lastAdjustmentTimestamp;
        uint256 currentTimestamp;
        uint256 rateChangePerDayMax;
        uint256 rateChangeCapacityMax;
        uint256 rateMin;
        uint256 rateMax;
    }

    function _calculateRate(RateCalculationParams memory params) internal pure returns (uint256 rate, uint256 remainingCreditsResult) {
        SD59x18 newRateSD = sd(int256(params.newRate));
        SD59x18 lastAdjustedRateSD = sd(int256(params.lastAdjustedRate));
        SD59x18 remainingCreditsSD = sd(int256(params.remainingCredits));
        SD59x18 lastAdjustmentTimestampSD = sd(int256(params.lastAdjustmentTimestamp));
        SD59x18 currentTimestampSD = sd(int256(params.currentTimestamp));
        SD59x18 rateChangePerDayMaxSD = sd(int256(params.rateChangePerDayMax));
        SD59x18 rateChangeCapacityMaxSD = sd(int256(params.rateChangeCapacityMax));

        SD59x18 rateChangeIncoming = newRateSD - lastAdjustedRateSD;

        if (rateChangeIncoming == sd(0)) return (params.lastAdjustedRate, params.remainingCredits);

        SD59x18 refillRatePerSeconds = rateChangePerDayMaxSD / sd(1 days);
        SD59x18 creditsRefilled = (currentTimestampSD - lastAdjustmentTimestampSD) * refillRatePerSeconds;
        SD59x18 creditsCapped = rateChangeCapacityMaxSD < remainingCreditsSD + creditsRefilled ? rateChangeCapacityMaxSD : remainingCreditsSD + creditsRefilled;

        SD59x18 creditsConsumed = abs(rateChangeIncoming) < creditsCapped ? abs(rateChangeIncoming) : creditsCapped;
        SD59x18 creditsRemaining = creditsCapped - creditsConsumed;

        {
            // if this is not bootstraped, it won't produce the correct rates
            SD59x18 changeCapped = rateChangeIncoming > sd(0) ? creditsConsumed : -creditsConsumed;
            rate = uint256(unwrap(lastAdjustedRateSD + changeCapped));
            remainingCreditsResult = uint256(unwrap(creditsRemaining));
        }

        if (rate < params.rateMin) return (params.rateMin, remainingCreditsResult);
        if (rate > params.rateMax) return (params.rateMax, remainingCreditsResult);
    }

    function adjustedRate(MarketId poolId) external onlyCorkPool returns (uint256 rate) {
        Market memory pool = CorkPool(data().corkPool).market(poolId);
        ConstraintState storage constraint = data().constraints[poolId];

        uint256 newRate = _fetchRate(pool);

        uint256 remainingCreditsResult;
        (rate, remainingCreditsResult) = _calculateRate(RateCalculationParams(newRate, constraint._lastAdjustedRate, constraint._remainingCredits, constraint._lastAdjustmentTimestamp, block.timestamp, pool.rateChangePerDayMax, pool.rateChangeCapacityMax, pool.rateMin, pool.rateMax));

        // update stuff
        constraint._lastAdjustedRate = rate;
        constraint._lastAdjustmentTimestamp = block.timestamp;
        constraint._remainingCredits = remainingCreditsResult;
    }

    function previewAdjustedRate(MarketId poolId) external view onlyCorkPool returns (uint256 rate) {
        Market memory pool = CorkPool(data().corkPool).market(poolId);
        ConstraintState storage constraint = data().constraints[poolId];

        uint256 newRate = _fetchRate(pool);

        (rate,) = _calculateRate(RateCalculationParams(newRate, constraint._lastAdjustedRate, constraint._remainingCredits, constraint._lastAdjustmentTimestamp, block.timestamp, pool.rateChangePerDayMax, pool.rateChangeCapacityMax, pool.rateMin, pool.rateMax));
    }

    /**
     * @notice Returns the address of the CorkPool contract
     * @return The address of the CorkPool contract
     */
    function constraints(MarketId poolId) external view returns (uint256, uint256, uint256) {
        ConstraintState memory constraint = data().constraints[poolId];
        return (constraint._lastAdjustedRate, constraint._lastAdjustmentTimestamp, constraint._remainingCredits);
    }
}
