// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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

    // ERC-7201 Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cork.storage.ConstraintAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _CONSTRAINT_ADAPTER_STORAGE_POSITION = 0x850a01c36e696ae1195ad02907192131a1808c20fd305f275554f8ccd5afa800;

    ///======================================================///
    ///=================== MODIFIERS ========================///
    ///======================================================///

    modifier onlyCorkPool() {
        require(_msgSender() == data().corkPool, IErrors.NotCorkPool());
        _;
    }

    ///======================================================///
    ///============== INITIALIZATION FUNCTIONS ==============///
    ///======================================================///

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _corkPool) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner);
        data().corkPool = _corkPool;
    }

    ///======================================================///
    ///================== CORE FUNCTIONS ====================///
    ///======================================================///

    function bootstrap(MarketId poolId) external onlyCorkPool {
        Market memory pool = CorkPool(data().corkPool).market(poolId);
        ConstraintState storage constraint = data().constraints[poolId];

        uint256 rate = _fetchRate(pool);

        constraint._lastAdjustedRate = rate;
        constraint._lastAdjustmentTimestamp = block.timestamp;
        constraint._remainingCredits = pool.rateChangeCapacityMax;
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

    ///======================================================///
    ///================== VIEW FUNCTIONS ====================///
    ///======================================================///

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

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    function _calculateRate(RateCalculationParams memory params) internal pure returns (uint256 rate, uint256 remainingCreditsResult) {
        int256 rateChangeIncoming = int256(params.newRate) - int256(params.lastAdjustedRate);

        if (rateChangeIncoming == 0) return (params.lastAdjustedRate, params.remainingCredits);

        // keep full precision by multiplying with 1e18
        uint256 refillRatePerSeconds = Math.mulDiv(params.rateChangePerDayMax, 1e18, 1 days);

        // refillRatePerSeconds is scaled by 1e18, we need to div down this operation by 1e18
        // because we won't need the extra precision since it's just sub and add after this
        uint256 creditsRefilled = Math.mulDiv(params.currentTimestamp - params.lastAdjustmentTimestamp, refillRatePerSeconds, 1e18);

        uint256 creditsCapped = params.rateChangeCapacityMax < params.remainingCredits + creditsRefilled ? params.rateChangeCapacityMax : params.remainingCredits + creditsRefilled;

        uint256 rateChangeIncomingAbs = rateChangeIncoming > 0 ? uint256(rateChangeIncoming) : uint256(-rateChangeIncoming);
        uint256 creditsConsumed = rateChangeIncomingAbs < creditsCapped ? rateChangeIncomingAbs : creditsCapped;

        uint256 creditsRemaining = creditsCapped - creditsConsumed;

        {
            // before, we let the math handle the decision of sub/add with operator matching (-+ = -)
            // now, we explicitly check what do we need to do since it's not possible to do the above becauuse the params is now a regular uint256
            rate = rateChangeIncoming > 0 ? params.lastAdjustedRate + creditsConsumed : params.lastAdjustedRate - creditsConsumed;

            remainingCreditsResult = creditsRemaining;
        }

        if (rate < params.rateMin) return (params.rateMin, remainingCreditsResult);
        if (rate > params.rateMax) return (params.rateMax, remainingCreditsResult);
    }
}
