// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";

/**
 * @dev SwapToken structure for Swap Token(SwapToken)
 */
struct SwapToken {
    address _address;
    address principalToken;
    uint256 withdrawn;
}

/**
 * @title SwapTokenLibrary Contract
 * @author Cork Team
 * @notice SwapTokenLibrary library which implements SwapToken(Swap Token) related features
 */
library SwapTokenLibrary {
    function isExpired(SwapToken storage self) internal view returns (bool) {
        return PoolShare(self._address).isExpired();
    }

    function isInitialized(SwapToken storage self) internal view returns (bool) {
        return self._address != address(0) && self.principalToken != address(0);
    }

    function issue(SwapToken memory self, address to, uint256 amount) internal {
        PoolShare(self._address).mint(to, amount);
        PoolShare(self.principalToken).mint(to, amount);
    }

    function updateSwapRate(SwapToken storage self, uint256 rate) internal {
        PoolShare(self._address).updateSwapRate(rate);
        PoolShare(self.principalToken).updateSwapRate(rate);
    }
}
