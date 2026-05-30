// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IYieldRouter {
    function deposit(address asset, uint256 amount) external returns (uint256 deposited);
    function withdraw(address asset) external returns (uint256 recalled);
    function balanceOf(address asset) external view returns (uint256);
}
