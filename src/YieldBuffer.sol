// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldRouter} from "./interfaces/IYieldRouter.sol";

/// @title YieldBuffer
/// @notice Accumulates storm-period swap fees, deploys them to a yield protocol,
///         and distributes principal + yield back to LPs when the storm passes.
///
/// @dev Flow:
///   1. Hook calls registerLP() on afterAddLiquidity  — track LP's pool share
///   2. Hook calls deregisterLP() on afterRemoveLiquidity
///   3. Hook calls accrueFees() on afterSwap during storm — fees land here
///   4. RSC calls deployToYield() once fees are worth deploying
///   5. RSC calls triggerDistribution() when VRS normalizes — epoch closes
///   6. Each LP calls claim(epoch) to collect their share + yield
///
/// Epoch model: each storm period is one epoch. When distribution triggers,
/// the current epoch closes and a new one opens automatically.
contract YieldBuffer {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    enum PayoutPreference { DAILY, LUMP_SUM, REINVEST }

    struct EpochData {
        uint256 totalFees;        // fees deposited into this epoch
        uint256 totalYieldEarned; // yield earned (populated on distribution)
        uint256 totalLiquidity;   // sum of registered LP liquidity
        uint256 distributedAt;    // timestamp of distribution
        bool    isActive;         // true while storm is ongoing
        bool    isDistributed;    // true after distribution completes
        bool    isDeployed;       // true while funds are in yield protocol
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    IERC20       public immutable asset;
    IYieldRouter public yieldRouter;
    address      public hook;
    address      public authorizedTrigger; // RSC callback address
    address      public owner;

    uint256 public currentEpoch;

    mapping(uint256 => EpochData)                        public epochs;
    mapping(address => mapping(uint256 => uint256))      public lpLiquidity;   // lp → epoch → liquidity
    mapping(address => mapping(uint256 => bool))         public hasClaimed;    // lp → epoch → claimed
    mapping(address => PayoutPreference)                 public lpPreference;  // lp → payout pref

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event LPRegistered(uint256 indexed epoch, address indexed lp, uint256 liquidity);
    event LPDeregistered(uint256 indexed epoch, address indexed lp, uint256 liquidity);
    event FeesAccrued(uint256 indexed epoch, uint256 amount, uint256 epochTotal);
    event DeployedToYield(uint256 indexed epoch, uint256 amount);
    event EpochDistributed(uint256 indexed epoch, uint256 feesRecalled, uint256 yieldEarned);
    event EpochOpened(uint256 indexed epoch);
    event LPClaimed(uint256 indexed epoch, address indexed lp, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error Unauthorized();
    error EpochNotDistributed();
    error AlreadyClaimed();
    error NoShareInEpoch();
    error EpochNotActive();
    error AlreadyDeployed();
    error NothingToDistribute();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        IERC20       _asset,
        address      _hook,
        address      _authorizedTrigger,
        IYieldRouter _yieldRouter
    ) {
        asset             = _asset;
        hook              = _hook;
        authorizedTrigger = _authorizedTrigger;
        yieldRouter       = _yieldRouter;
        owner             = msg.sender;

        epochs[0].isActive = true;
        emit EpochOpened(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyHook() {
        if (msg.sender != hook) revert Unauthorized();
        _;
    }

    modifier onlyTrigger() {
        if (msg.sender != authorizedTrigger && msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook-facing functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Called by hook on afterAddLiquidity to register LP's pool share.
    function registerLP(address lp, uint256 liquidity, PayoutPreference pref) external onlyHook {
        lpLiquidity[lp][currentEpoch] += liquidity;
        epochs[currentEpoch].totalLiquidity += liquidity;
        lpPreference[lp] = pref;
        emit LPRegistered(currentEpoch, lp, liquidity);
    }

    /// @notice Called by hook on afterRemoveLiquidity to reduce LP's registered share.
    function deregisterLP(address lp, uint256 liquidity) external onlyHook {
        uint256 current = lpLiquidity[lp][currentEpoch];
        uint256 deduct  = liquidity > current ? current : liquidity;
        lpLiquidity[lp][currentEpoch]   -= deduct;
        epochs[currentEpoch].totalLiquidity -= deduct;
        emit LPDeregistered(currentEpoch, lp, deduct);
    }

    /// @notice Called by hook on afterSwap during storm — transfers fees into the buffer.
    /// @dev Hook must have approved this contract to pull `amount` of asset beforehand.
    function accrueFees(uint256 amount) external onlyHook {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        epochs[currentEpoch].totalFees += amount;
        emit FeesAccrued(currentEpoch, amount, epochs[currentEpoch].totalFees);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RSC / trigger-facing functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy accumulated fees to the yield router.
    ///         Called by RSC when enough fees have accumulated during the storm.
    function deployToYield() external onlyTrigger {
        EpochData storage epoch = epochs[currentEpoch];
        if (!epoch.isActive) revert EpochNotActive();
        if (epoch.isDeployed) revert AlreadyDeployed();

        uint256 balance = asset.balanceOf(address(this));
        if (balance == 0) revert NothingToDistribute();

        asset.forceApprove(address(yieldRouter), balance);
        yieldRouter.deposit(address(asset), balance);
        epoch.isDeployed = true;

        emit DeployedToYield(currentEpoch, balance);
    }

    /// @notice Close the current epoch and make LPs eligible to claim.
    ///         Called by RSC when VRS drops back to calm.
    function triggerDistribution() external onlyTrigger {
        uint256 epochId       = currentEpoch;
        EpochData storage epoch = epochs[epochId];
        if (!epoch.isActive) revert EpochNotActive();

        uint256 recalled;
        if (epoch.isDeployed) {
            recalled = yieldRouter.withdraw(address(asset));
        } else {
            // Not deployed — no yield earned. Use tracked totalFees (not balanceOf,
            // which would include unclaimed amounts from previous epochs).
            recalled = epoch.totalFees;
        }

        uint256 yield = recalled > epoch.totalFees ? recalled - epoch.totalFees : 0;
        epoch.totalYieldEarned = yield;
        epoch.isActive         = false;
        epoch.isDistributed    = true;
        epoch.distributedAt    = block.timestamp;

        // Open next epoch
        currentEpoch++;
        epochs[currentEpoch].isActive = true;

        emit EpochDistributed(epochId, recalled, yield);
        emit EpochOpened(currentEpoch);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LP claim
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice LP claims their proportional share of fees + yield from a completed epoch.
    function claim(uint256 epochId) external {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.isDistributed)          revert EpochNotDistributed();
        if (hasClaimed[msg.sender][epochId]) revert AlreadyClaimed();

        uint256 lpLiq = lpLiquidity[msg.sender][epochId];
        if (lpLiq == 0)                    revert NoShareInEpoch();

        uint256 totalPayout = epoch.totalFees + epoch.totalYieldEarned;
        uint256 lpShare     = (totalPayout * lpLiq) / epoch.totalLiquidity;

        hasClaimed[msg.sender][epochId] = true;
        asset.safeTransfer(msg.sender, lpShare);

        emit LPClaimed(epochId, msg.sender, lpShare);
    }

    /// @notice Preview how much an LP would receive from a given epoch.
    function previewClaim(address lp, uint256 epochId) external view returns (uint256) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.isDistributed) return 0;
        if (hasClaimed[lp][epochId]) return 0;
        uint256 lpLiq = lpLiquidity[lp][epochId];
        if (lpLiq == 0 || epoch.totalLiquidity == 0) return 0;
        uint256 totalPayout = epoch.totalFees + epoch.totalYieldEarned;
        return (totalPayout * lpLiq) / epoch.totalLiquidity;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    function setHook(address _hook) external onlyOwner {
        hook = _hook;
    }

    function setAuthorizedTrigger(address _trigger) external onlyOwner {
        authorizedTrigger = _trigger;
    }

    function setYieldRouter(address _router) external onlyOwner {
        yieldRouter = IYieldRouter(_router);
    }
}
