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
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {VRSOracle} from "./VRSOracle.sol";

/// @notice Minimal interface to the dual-asset YieldBuffer.
interface IYieldBuffer {
    function registerLP(address lp, uint256 liquidity, uint8 payout) external;
    function recordFees(uint256 amount0, uint256 amount1) external;
    function deregisterLP(address lp, uint256 liquidity) external;
}

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
    using SafeCast for uint256;

    /// @notice Buffer fee taken on each swap, scaling with VRS (basis points of the
    ///         unspecified-token swap amount). 10 bps (calm) → 100 bps (hurricane).
    uint256 public constant BUFFER_FEE_MIN_BIPS = 10;
    uint256 public constant BUFFER_FEE_MAX_BONUS = 90;
    uint256 public constant TOTAL_BIPS = 10_000;

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
    //   AFTER_ADD_LIQUIDITY_FLAG       = 1 << 10 = 0x0400
    //   AFTER_REMOVE_LIQUIDITY_FLAG    = 1 << 8  = 0x0100
    //   BEFORE_SWAP_FLAG               = 1 << 7  = 0x0080
    //   AFTER_SWAP_FLAG                = 1 << 6  = 0x0040
    //   AFTER_SWAP_RETURNS_DELTA_FLAG  = 1 << 2  = 0x0004
    //
    //   Required address suffix: 0x05C4
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
            afterSwapReturnDelta:           true,
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

    /// @notice Takes a VRS-scaled buffer fee in the swap's unspecified token and routes
    ///         it into the YieldBuffer. The fee scales with volatility — calm swaps pay
    ///         ~10 bps, hurricane swaps pay ~100 bps — so storm fees accumulate for LPs.
    /// @dev Requires the afterSwapReturnDelta permission. The returned int128 is the
    ///      hook's delta in the unspecified currency (positive = hook took that amount).
    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        uint256 vrs = oracle.vrs();
        uint256 bufferBips = BUFFER_FEE_MIN_BIPS + (vrs * BUFFER_FEE_MAX_BONUS) / 100;

        // The fee is taken in the swap's unspecified token (matches V4 fee-taking pattern).
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            specifiedTokenIs0 ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());
        if (swapAmount < 0) swapAmount = -swapAmount;

        uint256 feeAmount = (uint256(uint128(swapAmount)) * bufferBips) / TOTAL_BIPS;
        if (feeAmount == 0 || yieldBuffer == address(0)) {
            return (IHooks.afterSwap.selector, 0);
        }

        // Pull the fee from the PoolManager directly into the buffer.
        poolManager.take(feeCurrency, yieldBuffer, feeAmount);

        // Record which token the fee landed in.
        if (Currency.unwrap(feeCurrency) == Currency.unwrap(key.currency0)) {
            IYieldBuffer(yieldBuffer).recordFees(feeAmount, 0);
        } else {
            IYieldBuffer(yieldBuffer).recordFees(0, feeAmount);
        }

        return (IHooks.afterSwap.selector, feeAmount.toInt128());
    }

    /// @notice Registers the LP's yield intent and buffer share when they add liquidity.
    /// @dev hookData is abi.encoded (address lp, uint256 targetAPY, uint256 maxILBps, PayoutPreference).
    ///      The LP address is passed explicitly because in V4 the `sender` here is the
    ///      liquidity router, not the end user. (A production PositionManager would mint
    ///      an LPPositionNFT instead of trusting hookData.)
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length > 0) {
            (address lp, uint256 targetAPY, uint256 maxILBps, PayoutPreference pref) =
                abi.decode(hookData, (address, uint256, uint256, PayoutPreference));

            PoolId poolId = key.toId();
            lpIntents[lp][poolId] = LPIntent({
                targetAPY:         targetAPY,
                maxILToleranceBps: maxILBps,
                payout:            pref,
                depositTimestamp:  block.timestamp,
                registered:        true
            });

            emit LPRegistered(poolId, lp, targetAPY, pref);

            // Register the LP's share in the buffer so they can claim storm fees.
            if (yieldBuffer != address(0) && params.liquidityDelta > 0) {
                IYieldBuffer(yieldBuffer).registerLP(lp, uint256(params.liquidityDelta), uint8(pref));
            }
        }

        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    /// @notice Clears the LP's intent and deregisters them from the buffer on exit.
    /// @dev hookData (when present) is abi.encoded (address lp, ...) — same as deposit —
    ///      because the V4 `sender` here is the router, not the end user.
    function afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length > 0) {
            (address lp) = abi.decode(hookData, (address));
            PoolId poolId = key.toId();

            if (lpIntents[lp][poolId].registered) {
                emit LPExited(poolId, lp, block.timestamp);
                delete lpIntents[lp][poolId];
            }

            if (yieldBuffer != address(0) && params.liquidityDelta < 0) {
                IYieldBuffer(yieldBuffer).deregisterLP(lp, uint256(-params.liquidityDelta));
            }
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
