// SPDX-License-Identifier: GPL-2.0-or-later
// Source: Morpho Bundler3
// URL: https://github.com/morpho-org/bundler3/tree/4887f33299ba6e60b54a51237b16e7392dceeb97
pragma solidity ^0.8.0;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @custom:security-contact security@morpho.org
/// @notice Utils library.
library UtilsLib {
    /// @dev Bubbles up the revert reason / custom error encoded in `returnData`.
    /// @dev Assumes `returnData` is the return data of any kind of failing CALL to a contract.
    function lowLevelRevert(bytes memory returnData) internal pure {
        assembly ("memory-safe") {
            revert(add(32, returnData), mload(returnData))
        }
    }
}
