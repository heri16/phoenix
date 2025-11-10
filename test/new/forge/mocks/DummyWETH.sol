// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20, ERC20Mock} from "./ERC20Mock.sol";

/**
 * @title DummyWETH Contract
 * @author Cork Team
 * @notice Dummy contract which provides WETH with ERC20
 */
contract DummyWETH is ERC20Mock {
    constructor() ERC20("Dummy Wrapped ETH", "DWETH") {}
}
