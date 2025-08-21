// SPDX-License-Identifier: GPL-2.0-or-later
// Source: Morpho Bundler3
// URL: https://github.com/morpho-org/bundler3/tree/4887f33299ba6e60b54a51237b16e7392dceeb97
pragma solidity >=0.5.0;

interface IWNative {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    function transfer(address dst, uint256 wad) external returns (bool);
    function balanceOf(address guy) external returns (uint256);
}
