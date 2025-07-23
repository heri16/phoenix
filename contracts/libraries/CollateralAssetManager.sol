// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";

/**
 * @dev CollateralAssetManager structure for Redemption Manager
 */
struct CollateralAssetManager {
    address _address;
    uint256 locked;
    uint256 free;
}

/**
 * @title CollateralAssetManagerLibrary Contract
 * @author Cork Team
 * @notice CollateralAssetManager Library implements functions for Collateral Asset(Redemption Assets) contract
 */
library CollateralAssetManagerLibrary {
    using SafeERC20 for IERC20;

    function initialize(address collateralAsset) internal pure returns (CollateralAssetManager memory) {
        if (collateralAsset == address(0)) revert IErrors.ZeroAddress();
        return CollateralAssetManager(collateralAsset, 0, 0);
    }

    function reset(CollateralAssetManager storage self) internal {
        self.locked = 0;
        self.free = 0;
    }

    function increaseLocked(CollateralAssetManager storage self, uint256 amount) internal {
        self.locked = self.locked + amount;
    }

    function convertAllToFree(CollateralAssetManager storage self) internal returns (uint256) {
        if (self.locked == 0) return self.free;

        self.free = self.free + self.locked;
        self.locked = 0;

        return self.free;
    }

    function decreaseLocked(CollateralAssetManager storage self, uint256 amount) internal {
        if (amount > self.locked) revert IErrors.InvalidAmount();
        self.locked = self.locked - amount;
    }

    function lockFrom(CollateralAssetManager storage self, uint256 amount, address from) internal {
        lockUnchecked(self, amount, from);
        increaseLocked(self, amount);
    }

    function lockUnchecked(CollateralAssetManager storage self, uint256 amount, address from) internal {
        IERC20(self._address).safeTransferFrom(from, address(this), amount);
    }

    function unlockTo(CollateralAssetManager storage self, address to, uint256 amount) internal {
        decreaseLocked(self, amount);
        unlockToUnchecked(self, amount, to);
    }

    function unlockToUnchecked(CollateralAssetManager storage self, uint256 amount, address to) internal {
        IERC20(self._address).safeTransfer(to, amount);
    }
}
