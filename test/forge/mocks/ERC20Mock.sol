// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title ERC20Mock Contract
 * @author Cork Team
 * @notice Mock contract which provides ERC20
 */
abstract contract ERC20Mock is ERC20Burnable {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    fallback() external payable {
        deposit();
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 wad) public {
        _burn(msg.sender, wad);
        emit Withdrawal(msg.sender, wad);

        payable(msg.sender).transfer(wad);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
