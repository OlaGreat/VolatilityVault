// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {VRSOracle} from "./VRSOracle.sol";

/// @title VolatilityVaultHook
/// @notice Uniswap V4 hook that:
///   1. Reads the Volatility Risk Score (VRS) from VRSOracle and overrides the pool LP fee dynamically.
///   2. Detects toxic (arbitrage) order flow and emits a surcharge event for off-chain settlement.
///   3. Registers each LP's yield intent (target APY, payout preference, IL tolerance) on deposit.
///   4. Emits a withdrawal event so the YieldBuffer can calculate the correct payout on removal.
///
/// @dev This hook must be deployed at an address whose lower bits match getHookPermissions().
///      Use HookMiner to find a valid salt before deploying.
///      The pool must be initialized with LPFeeLibrary.DYNAMIC_FEE_FLAG as its fee.
contract VolatilityVaultHook is IHooks {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    enum PayoutPreference { DAILY, LUMP_SUM, REINVEST }

    struct LPIntent {
        uint256 targetAPY;          // basis points, e.g. 1200 = 12%
        uint256 maxILToleranceBps;  // basis points, e.g. 500 = 5%
        PayoutPreference payout;
        uint256 depositTimestamp;
        bool registered;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    IPoolManager public immutable poolManager;
    VRSOracle    public immutable oracle;

    /// @notice YieldBuffer address — storage (not immutable) so it can be set after
    ///         CREATE2 deployment, breaking the circular dependency with YieldBuffer.
    address public yieldBuffer;
    address public hookOwner;

    /// @notice Minimum swap size (in absolute token units) to be flagged as toxic.
    uint256 public toxicOrderThreshold;

    /// @notice LP address → pool → their stated intent.
    mapping(address => mapping(PoolId => LPIntent)) public lpIntents;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event FeeOverridden(PoolId indexed poolId, uint8 vrs, uint24 fee);
    event ToxicOrderDetected(PoolId indexed poolId, address indexed sender, uint8 vrs, int256 amountSpecified);
    event LPRegistered(PoolId indexed poolId, address indexed lp, uint256 targetAPY, PayoutPreference payout);
    event LPExited(PoolId indexed poolId, address indexed lp, uint256 timestamp);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NotPoolManager();
    error PoolMustUseDynamicFee();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(IPoolManager _poolManager, VRSOracle _oracle, address _yieldBuffer, uint256 _toxicThreshold) {
        poolManager         = _poolManager;
        oracle              = _oracle;
        yieldBuffer         = _yieldBuffer;
        toxicOrderThreshold = _toxicThreshold;
        // tx.origin is the EOA signer — msg.sender would be the CREATE2 proxy during deployment.
        hookOwner = tx.origin;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    modifier onlyHookOwner() {
        require(msg.sender == hookOwner, "Not owner");
        _;
    }

    /// @notice Set YieldBuffer after deployment (breaks circular CREATE2 dependency).
    function setYieldBuffer(address _buffer) external onlyHookOwner {
        yieldBuffer = _buffer;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook permissions — encodes which callbacks this hook uses.
    // The hook address MUST have matching lower bits (use HookMiner).
    //
    //   AFTER_ADD_LIQUIDITY_FLAG      = 1 << 10 = 0x0400
    //   AFTER_REMOVE_LIQUIDITY_FLAG   = 1 << 8  = 0x0100
    //   BEFORE_SWAP_FLAG              = 1 << 7  = 0x0080
    //   AFTER_SWAP_FLAG               = 1 << 6  = 0x0040
    //
    //   Required address suffix: 0x05C0
    // ─────────────────────────────────────────────────────────────────────────

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize:               false,
            afterInitialize:                false,
            beforeAddLiquidity:             false,
            afterAddLiquidity:              true,
            beforeRemoveLiquidity:          false,
            afterRemoveLiquidity:           true,
            beforeSwap:                     true,
            afterSwap:                      true,
            beforeDonate:                   false,
            afterDonate:                    false,
            beforeSwapReturnDelta:          false,
            afterSwapReturnDelta:           false,
            afterAddLiquidityReturnDelta:   false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook callbacks
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Reads VRS from the oracle and overrides the pool fee for this swap.
    ///         Also detects large directional (toxic) swaps during storm conditions.
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        uint8  currentVRS = oracle.vrs();
        uint24 fee        = oracle.getFee();

        PoolId poolId = key.toId();
        emit FeeOverridden(poolId, currentVRS, fee);

        // Toxic order detection: large directional swap during storm conditions.
        if (currentVRS > oracle.THRESHOLD_CLOUDY()) {
            uint256 absAmount = params.amountSpecified < 0
                ? uint256(-params.amountSpecified)
                : uint256(params.amountSpecified);

            if (absAmount >= toxicOrderThreshold) {
                emit ToxicOrderDetected(poolId, sender, currentVRS, params.amountSpecified);
            }
        }

        // Return OVERRIDE_FEE_FLAG | fee to tell V4 to use our dynamic fee for this swap.
        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            LPFeeLibrary.OVERRIDE_FEE_FLAG | fee
        );
    }

    /// @notice After swap: placeholder for storm-fee routing to YieldBuffer.
    ///         Phase 2 will add delta-return logic to take a surcharge here.
    function afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, 0);
    }

    /// @notice Registers the LP's yield intent when they add liquidity.
    ///         hookData must be abi.encoded LPIntent fields: (targetAPY, maxILToleranceBps, PayoutPreference).
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length > 0) {
            (uint256 targetAPY, uint256 maxILBps, PayoutPreference pref) =
                abi.decode(hookData, (uint256, uint256, PayoutPreference));

            PoolId poolId = key.toId();
            lpIntents[sender][poolId] = LPIntent({
                targetAPY:         targetAPY,
                maxILToleranceBps: maxILBps,
                payout:            pref,
                depositTimestamp:  block.timestamp,
                registered:        true
            });

            emit LPRegistered(poolId, sender, targetAPY, pref);
        }

        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    /// @notice Clears the LP's intent and emits an exit event for YieldBuffer payout.
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        if (lpIntents[sender][poolId].registered) {
            emit LPExited(poolId, sender, block.timestamp);
            delete lpIntents[sender][poolId];
        }

        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Unused callbacks — required by IHooks interface
    // ─────────────────────────────────────────────────────────────────────────

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4) { revert(); }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4) { revert(); }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4) { revert(); }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4) { revert(); }
}
