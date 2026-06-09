// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldRouter} from "./interfaces/IYieldRouter.sol";

/// @title YieldBuffer (dual-asset)
/// @notice Accumulates storm-period swap fees in BOTH pool tokens, deploys them to
///         a yield protocol, and distributes principal + yield back to LPs when the
///         storm passes.
///
/// @dev Why dual-asset: in Uniswap V4 the hook can only take an afterSwap fee in the
///      swap's *unspecified* token, which alternates between token0 and token1 by
///      direction. So the buffer tracks fees in both tokens per epoch.
///
/// Flow:
///   1. Hook calls registerLP() on afterAddLiquidity            — track LP's share
///   2. Hook takes the fee via PoolManager.take(token, buffer)  — tokens arrive here
///      then calls recordFees(amount0, amount1)                 — record what arrived
///   3. RSC/owner calls deployToYield()                         — fees earn yield
///   4. RSC/owner calls triggerDistribution() when VRS normalizes — epoch closes
///   5. Each LP calls claim(epoch)                              — collect share of both tokens
contract YieldBuffer {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    enum PayoutPreference { DAILY, LUMP_SUM, REINVEST }

    struct EpochData {
        uint256 totalFees0;     // token0 fees recorded this epoch
        uint256 totalFees1;     // token1 fees recorded this epoch
        uint256 totalYield0;    // token0 yield earned (populated on distribution)
        uint256 totalYield1;    // token1 yield earned
        uint256 totalLiquidity; // sum of registered LP liquidity
        uint256 distributedAt;
        bool    isActive;
        bool    isDistributed;
        bool    isDeployed;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    IERC20       public immutable asset0;
    IERC20       public immutable asset1;
    IYieldRouter public yieldRouter;
    address      public hook;
    address      public authorizedTrigger; // RSC callback receiver
    address      public owner;

    uint256 public currentEpoch;

    mapping(uint256 => EpochData)                   public epochs;
    mapping(address => mapping(uint256 => uint256)) public lpLiquidity;  // lp → epoch → liquidity
    mapping(address => mapping(uint256 => bool))    public hasClaimed;   // lp → epoch → claimed
    mapping(address => PayoutPreference)            public lpPreference; // lp → payout pref

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event LPRegistered(uint256 indexed epoch, address indexed lp, uint256 liquidity);
    event LPDeregistered(uint256 indexed epoch, address indexed lp, uint256 liquidity);
    event FeesRecorded(uint256 indexed epoch, uint256 amount0, uint256 amount1);
    event DeployedToYield(uint256 indexed epoch, uint256 amount0, uint256 amount1);
    event EpochDistributed(uint256 indexed epoch, uint256 yield0, uint256 yield1);
    event EpochOpened(uint256 indexed epoch);
    event LPClaimed(uint256 indexed epoch, address indexed lp, uint256 amount0, uint256 amount1);

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
        IERC20       _asset0,
        IERC20       _asset1,
        address      _hook,
        address      _authorizedTrigger,
        IYieldRouter _yieldRouter
    ) {
        asset0            = _asset0;
        asset1            = _asset1;
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

    modifier onlyHook()    { if (msg.sender != hook) revert Unauthorized(); _; }
    modifier onlyTrigger() { if (msg.sender != authorizedTrigger && msg.sender != owner) revert Unauthorized(); _; }
    modifier onlyOwner()   { if (msg.sender != owner) revert Unauthorized(); _; }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook-facing functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Register an LP's share when they add liquidity.
    function registerLP(address lp, uint256 liquidity, PayoutPreference pref) external onlyHook {
        lpLiquidity[lp][currentEpoch] += liquidity;
        epochs[currentEpoch].totalLiquidity += liquidity;
        lpPreference[lp] = pref;
        emit LPRegistered(currentEpoch, lp, liquidity);
    }

    /// @notice Reduce an LP's registered share when they remove liquidity.
    function deregisterLP(address lp, uint256 liquidity) external onlyHook {
        uint256 current = lpLiquidity[lp][currentEpoch];
        uint256 deduct  = liquidity > current ? current : liquidity;
        lpLiquidity[lp][currentEpoch]       -= deduct;
        epochs[currentEpoch].totalLiquidity -= deduct;
        emit LPDeregistered(currentEpoch, lp, deduct);
    }

    /// @notice Record storm fees that the hook already transferred into this contract
    ///         via PoolManager.take(token, address(buffer), amount). No transferFrom —
    ///         the tokens are already here.
    function recordFees(uint256 amount0, uint256 amount1) external onlyHook {
        EpochData storage epoch = epochs[currentEpoch];
        epoch.totalFees0 += amount0;
        epoch.totalFees1 += amount1;
        emit FeesRecorded(currentEpoch, amount0, amount1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RSC / trigger-facing functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy this epoch's accumulated fees (both tokens) to the yield router.
    function deployToYield() external onlyTrigger {
        EpochData storage epoch = epochs[currentEpoch];
        if (!epoch.isActive)  revert EpochNotActive();
        if (epoch.isDeployed) revert AlreadyDeployed();
        if (epoch.totalFees0 == 0 && epoch.totalFees1 == 0) revert NothingToDistribute();

        if (epoch.totalFees0 > 0) {
            asset0.forceApprove(address(yieldRouter), epoch.totalFees0);
            yieldRouter.deposit(address(asset0), epoch.totalFees0);
        }
        if (epoch.totalFees1 > 0) {
            asset1.forceApprove(address(yieldRouter), epoch.totalFees1);
            yieldRouter.deposit(address(asset1), epoch.totalFees1);
        }
        epoch.isDeployed = true;
        emit DeployedToYield(currentEpoch, epoch.totalFees0, epoch.totalFees1);
    }

    /// @notice Close the current epoch and make LPs eligible to claim.
    function triggerDistribution() external onlyTrigger {
        uint256 epochId        = currentEpoch;
        EpochData storage epoch = epochs[epochId];
        if (!epoch.isActive) revert EpochNotActive();

        if (epoch.isDeployed) {
            uint256 recalled0 = epoch.totalFees0 > 0 ? yieldRouter.withdraw(address(asset0)) : 0;
            uint256 recalled1 = epoch.totalFees1 > 0 ? yieldRouter.withdraw(address(asset1)) : 0;
            epoch.totalYield0 = recalled0 > epoch.totalFees0 ? recalled0 - epoch.totalFees0 : 0;
            epoch.totalYield1 = recalled1 > epoch.totalFees1 ? recalled1 - epoch.totalFees1 : 0;
        }
        // If not deployed, fees already sit in the buffer; no yield.

        epoch.isActive      = false;
        epoch.isDistributed = true;
        epoch.distributedAt = block.timestamp;

        currentEpoch++;
        epochs[currentEpoch].isActive = true;

        emit EpochDistributed(epochId, epoch.totalYield0, epoch.totalYield1);
        emit EpochOpened(currentEpoch);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LP claim
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice LP claims their proportional share of both tokens (fees + yield).
    function claim(uint256 epochId) external {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.isDistributed)            revert EpochNotDistributed();
        if (hasClaimed[msg.sender][epochId]) revert AlreadyClaimed();

        uint256 lpLiq = lpLiquidity[msg.sender][epochId];
        if (lpLiq == 0) revert NoShareInEpoch();

        (uint256 share0, uint256 share1) = _shareOf(epoch, lpLiq);

        hasClaimed[msg.sender][epochId] = true;
        if (share0 > 0) asset0.safeTransfer(msg.sender, share0);
        if (share1 > 0) asset1.safeTransfer(msg.sender, share1);

        emit LPClaimed(epochId, msg.sender, share0, share1);
    }

    /// @notice Preview an LP's claimable amounts (token0, token1) for an epoch.
    function previewClaim(address lp, uint256 epochId) external view returns (uint256 share0, uint256 share1) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.isDistributed)    return (0, 0);
        if (hasClaimed[lp][epochId]) return (0, 0);
        uint256 lpLiq = lpLiquidity[lp][epochId];
        if (lpLiq == 0 || epoch.totalLiquidity == 0) return (0, 0);
        return _shareOf(epoch, lpLiq);
    }

    function _shareOf(EpochData storage epoch, uint256 lpLiq) internal view returns (uint256, uint256) {
        uint256 payout0 = epoch.totalFees0 + epoch.totalYield0;
        uint256 payout1 = epoch.totalFees1 + epoch.totalYield1;
        return (
            (payout0 * lpLiq) / epoch.totalLiquidity,
            (payout1 * lpLiq) / epoch.totalLiquidity
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    function setHook(address _hook) external onlyOwner { hook = _hook; }
    function setAuthorizedTrigger(address _trigger) external onlyOwner { authorizedTrigger = _trigger; }
    function setYieldRouter(address _router) external onlyOwner { yieldRouter = IYieldRouter(_router); }
}
