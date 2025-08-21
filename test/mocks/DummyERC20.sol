// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20, ERC20Mock} from "./ERC20Mock.sol";

/**
 * @title DummyERC20 Contract
 * @author Cork Team
 * @notice Dummy contract which provides ERC20
 */
contract DummyERC20 is ERC20Mock {
    uint8 internal __decimals;

    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        __decimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }
}
