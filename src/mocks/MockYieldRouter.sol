// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldRouter} from "../interfaces/IYieldRouter.sol";

/// @title MockYieldRouter
/// @notice Simulates Aave/Morpho for local tests and demo.
///         Returns deposited amount + a fixed APY on withdraw.
contract MockYieldRouter is IYieldRouter {
    using SafeERC20 for IERC20;

    uint256 public constant ANNUAL_YIELD_BPS = 1000; // 10% APY
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Position {
        uint256 amount;
        uint256 depositedAt;
    }

    mapping(address => Position) private _positions;

    function deposit(address asset, uint256 amount) external override returns (uint256) {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        _positions[asset].amount      += amount;
        _positions[asset].depositedAt  = block.timestamp;
        return amount;
    }

    function withdraw(address asset) external override returns (uint256 recalled) {
        Position storage pos = _positions[asset];
        if (pos.amount == 0) return 0;

        uint256 elapsed   = block.timestamp - pos.depositedAt;
        uint256 yield     = (pos.amount * ANNUAL_YIELD_BPS * elapsed) / (10_000 * SECONDS_PER_YEAR);
        recalled          = pos.amount + yield;

        pos.amount      = 0;
        pos.depositedAt = 0;

        // Mint yield by transferring from this contract's balance.
        // In tests, fund this contract with enough tokens to cover yield.
        IERC20(asset).safeTransfer(msg.sender, recalled);
    }

    function balanceOf(address asset) external view override returns (uint256) {
        return _positions[asset].amount;
    }

    /// @notice Preview yield for a deposit without withdrawing.
    function previewYield(address asset) external view returns (uint256 principal, uint256 yield) {
        Position storage pos = _positions[asset];
        principal = pos.amount;
        uint256 elapsed = block.timestamp - pos.depositedAt;
        yield = (pos.amount * ANNUAL_YIELD_BPS * elapsed) / (10_000 * SECONDS_PER_YEAR);
    }
}
