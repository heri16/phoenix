// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

/**
 * @title InvalidERC20 Contract
 * @author Cork Team
 * @notice Mock contract that doesn't implement IERC20Metadata properly
 */
contract InvalidERC20 {
    // This contract doesn't implement symbol() function
    // to test what happens when SharesFactory tries to call symbol()

    function name() external pure returns (string memory) {
        return "Invalid Token";
    }

    // Missing symbol() function intentionally

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}
