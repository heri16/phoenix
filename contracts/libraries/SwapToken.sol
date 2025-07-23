// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Shares} from "contracts/core/assets/Shares.sol";

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
        return Shares(self._address).isExpired();
    }

    function isInitialized(SwapToken storage self) internal view returns (bool) {
        return self._address != address(0) && self.principalToken != address(0);
    }

    function issue(SwapToken memory self, address to, uint256 amount) internal {
        Shares(self._address).mint(to, amount);
        Shares(self.principalToken).mint(to, amount);
    }

    function updateExchangeRate(SwapToken storage self, uint256 rate) internal {
        Shares(self._address).updateRate(rate);
        Shares(self.principalToken).updateRate(rate);
    }
}
