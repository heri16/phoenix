// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Call, IBundler3} from "bundler3/interfaces/IBundler3.sol";

contract MockBundler3 is IBundler3 {
    address private _initiator;

    function setInitiator(address initiator_) external {
        _initiator = initiator_;
    }

    function initiator() external view override returns (address) {
        return _initiator;
    }

    function multicall(Call[] calldata calls) external payable override {
        _initiator = msg.sender;

        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata call = calls[i];
            (bool success, bytes memory returnData) = call.to.call{value: call.value}(call.data);

            if (!success && !call.skipRevert) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }
    }

    function reenter(Call[] calldata) external override {
        // Mock implementation - not used in tests
    }

    function reenterHash() external view override returns (bytes32) {
        // Mock implementation - not used in tests
        return bytes32(0);
    }
}
