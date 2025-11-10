// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {IConstraintRateAdapter} from "contracts/interfaces/IConstraintRateAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IComposableRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {Market, MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";

/**
 * @title RateOracle Contract
 * @author Cork Team
 * @notice Contract for managing oracle rate
 */
contract ConstraintRateAdapter is IErrors, IConstraintRateAdapter, UUPSUpgradeable, OwnableUpgradeable {
    struct ConstraintRateAdapterStorage {
        address corkPoolManager;
        mapping(MarketId => ConstraintState) constraints;
    }

    // ERC-7201 Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cork.storage.ConstraintRateAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant _CONSTRAINT_ADAPTER_STORAGE_POSITION = 0xf88cefad790528de4ec7608c6ea34edd21e78fe1868b343ccaa1ae3a22fa9c00;

    ///======================================================///
    ///=================== MODIFIERS ========================///
    ///======================================================///

    modifier onlyCorkPoolManager() {
        require(_msgSender() == data().corkPoolManager, IErrors.NotCorkPoolManager());
        _;
    }

    ///======================================================///
    ///============== INITIALIZATION FUNCTIONS ==============///
    ///======================================================///

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address corkPoolManager) external initializer {
        require(initialOwner != address(0) && corkPoolManager != address(0), InvalidAddress());
        __UUPSUpgradeable_init();
        __Ownable_init(initialOwner);
        data().corkPoolManager = corkPoolManager;
    }

    ///======================================================///
    ///================== CORE FUNCTIONS ====================///
    ///======================================================///

    function bootstrap(MarketId poolId) external onlyCorkPoolManager {
        Market memory pool = CorkPoolManager(data().corkPoolManager).market(poolId);
        ConstraintState storage constraint = data().constraints[poolId];

        uint256 rate = _fetchRate(pool);

        constraint._lastAdjustedRate = rate;
        constraint._lastAdjustmentTimestamp = block.timestamp;
        constraint._remainingCredits = pool.rateChangeCapacityMax;
    }

    function adjustedRate(MarketId poolId) external onlyCorkPoolManager returns (uint256 rate) {
        Market memory pool = CorkPoolManager(data().corkPoolManager).market(poolId);
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

    function previewAdjustedRate(MarketId poolId) external view onlyCorkPoolManager returns (uint256 rate) {
        Market memory pool = CorkPoolManager(data().corkPoolManager).market(poolId);
        ConstraintState storage constraint = data().constraints[poolId];

        uint256 newRate = _fetchRate(pool);

        (rate,) = _calculateRate(RateCalculationParams(newRate, constraint._lastAdjustedRate, constraint._remainingCredits, constraint._lastAdjustmentTimestamp, block.timestamp, pool.rateChangePerDayMax, pool.rateChangeCapacityMax, pool.rateMin, pool.rateMax));
    }

    /**
     * @notice Returns the address of the CorkPoolManager contract
     * @return The address of the CorkPoolManager contract
     */
    function constraints(MarketId poolId) external view returns (uint256, uint256, uint256) {
        ConstraintState memory constraint = data().constraints[poolId];
        return (constraint._lastAdjustedRate, constraint._lastAdjustmentTimestamp, constraint._remainingCredits);
    }

    ///======================================================///
    ///================= INTERNAL FUNCTIONS =================///
    ///======================================================///

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function data() internal pure returns (ConstraintRateAdapterStorage storage cs) {
        // slither-disable-next-line assembly
        assembly {
            cs.slot := _CONSTRAINT_ADAPTER_STORAGE_POSITION
        }
    }

    function _fetchRate(Market memory pool) internal view returns (uint256 rate) {
        try IComposableRateOracle(pool.rateOracle).rate() returns (uint256 _rate) {
            rate = _rate;
        } catch {
            // slither-disable-next-line unused-return
            (, int256 answer,,,) = IComposableRateOracle(pool.rateOracle).latestRoundData();

            require(answer > 0, IErrors.InvalidRate());

            rate = uint256(answer);
            rate = TransferHelper.normalizeDecimals(rate, IComposableRateOracle(pool.rateOracle).decimals(), TransferHelper.TARGET_DECIMALS);
        }
    }

    // for some reason, slither complains that we use a block.timestamp comparison here which we don't.
    // slither-disable-start timestamp
    function _calculateRate(RateCalculationParams memory params) internal pure returns (uint256 rate, uint256 remainingCreditsResult) {
        int256 rateChangeIncoming = int256(params.newRate) - int256(params.lastAdjustedRate);

        // to prevent unnecessary math being done if there's no change in the rates
        // slither-disable-next-line incorrect-equality
        if (rateChangeIncoming == 0) return (params.lastAdjustedRate, params.remainingCredits);

        // keep full precision by multiplying with 1e18
        uint256 refillRatePerSeconds = Math.mulDiv(params.rateChangePerDayMax, 1e18, 1 days);

        // refillRatePerSeconds is scaled by 1e18, we need to div down this operation by 1e18
        // because we won't need the extra precision since it's just sub and add after this
        uint256 creditsRefilled = Math.mulDiv(params.currentTimestamp - params.lastAdjustmentTimestamp, refillRatePerSeconds, 1e18);

        uint256 creditsCapped = params.rateChangeCapacityMax < params.remainingCredits + creditsRefilled ? params.rateChangeCapacityMax : params.remainingCredits + creditsRefilled;

        uint256 rateChangeIncomingAbs = rateChangeIncoming > 0 ? uint256(rateChangeIncoming) : uint256(-rateChangeIncoming);
        uint256 creditsConsumed = rateChangeIncomingAbs < creditsCapped ? rateChangeIncomingAbs : creditsCapped;

        // we're gonna double calculate the rate, if the first calculation go below/above min/max rate, we're gonna clamp it down/up
        // and recalculate what the actual rate change and credits consumed.

        // before, we let the math handle the decision of sub/add with operator matching (-+ = -)
        // now, we explicitly check what do we need to do since it's not possible to do the above because the params is now a regular uint256
        //
        // first calculation, may go below/above the min/max rate
        rate = rateChangeIncoming > 0 ? params.lastAdjustedRate + creditsConsumed : params.lastAdjustedRate - creditsConsumed;

        // Clamp rate to min/max bounds
        if (rate < params.rateMin) rate = params.rateMin;
        else if (rate > params.rateMax) rate = params.rateMax;

        // Calculate actual credits consumed based on the actual rate change
        uint256 actualRateChange = rate > params.lastAdjustedRate ? rate - params.lastAdjustedRate : params.lastAdjustedRate - rate;
        uint256 actualCreditsConsumed = actualRateChange;

        remainingCreditsResult = creditsCapped - actualCreditsConsumed;
    }
    // slither-disable-end timestamp
}
