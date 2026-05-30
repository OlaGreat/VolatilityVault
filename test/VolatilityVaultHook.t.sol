// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test}  from "forge-std/Test.sol";
import {Vm}    from "forge-std/Vm.sol";

// V4 core
import {PoolManager}            from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager}           from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks}                 from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey}                from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary}  from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency}               from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta}           from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Hooks}                  from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary}           from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary}           from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// V4 test routers (no solmate dependency)
import {PoolSwapTest}           from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

// OpenZeppelin
import {ERC20}   from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Our contracts
import {VolatilityVaultHook}    from "../src/VolatilityVaultHook.sol";
import {VRSOracle}              from "../src/VRSOracle.sol";
import {YieldBuffer}            from "../src/YieldBuffer.sol";
import {MockYieldRouter}        from "../src/mocks/MockYieldRouter.sol";
import {IYieldRouter}           from "../src/interfaces/IYieldRouter.sol";

// ── Minimal test token ────────────────────────────────────────────────────────
contract TestToken is ERC20 {
    constructor(string memory name) ERC20(name, name) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract VolatilityVaultHookTest is Test {
    using PoolIdLibrary  for PoolKey;
    using StateLibrary   for IPoolManager;
    using LPFeeLibrary   for uint24;

    // ── Hook address bits ────────────────────────────────────────────────────
    // AFTER_ADD_LIQUIDITY_FLAG  = 1 << 10 = 0x0400
    // AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 8  = 0x0100
    // BEFORE_SWAP_FLAG          = 1 << 7  = 0x0080
    // AFTER_SWAP_FLAG           = 1 << 6  = 0x0040
    // Combined                           = 0x05C0
    uint160 constant HOOK_FLAGS       = 0x05C0;
    uint160 constant CLEAR_ALL_MASK   = ~uint160(0) << 14;

    // Canonical sqrtPrice for a 1:1 pool
    uint160 constant SQRT_PRICE_1_1   = 79228162514264337593543950336;
    uint160 constant MIN_PRICE_LIMIT  = 4295128740;
    uint160 constant MAX_PRICE_LIMIT  = 1461446703485210103287273052203988822378723970341;

    int24  constant TICK_SPACING      = 60;
    uint256 constant TOXIC_THRESHOLD  = 1_000e18;

    // ── Infrastructure ───────────────────────────────────────────────────────
    IPoolManager            manager;
    PoolSwapTest            swapRouter;
    PoolModifyLiquidityTest liquidityRouter;

    // ── Our contracts ────────────────────────────────────────────────────────
    VRSOracle               oracle;
    MockYieldRouter         yieldRouter;
    YieldBuffer             buffer;
    VolatilityVaultHook     hook;

    // ── Tokens & pool ────────────────────────────────────────────────────────
    TestToken  token0;
    TestToken  token1;
    Currency   currency0;
    Currency   currency1;
    PoolKey    poolKey;

    // ── Actors ───────────────────────────────────────────────────────────────
    address lp      = makeAddr("lp");
    address swapper = makeAddr("swapper");

    // ─────────────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        // 1. Deploy PoolManager
        manager = IPoolManager(address(new PoolManager(address(this))));

        // 2. Deploy test routers
        swapRouter      = new PoolSwapTest(manager);
        liquidityRouter = new PoolModifyLiquidityTest(manager);

        // 3. Deploy and sort two ERC-20 tokens (V4 requires currency0 < currency1)
        TestToken tA = new TestToken("TokenA");
        TestToken tB = new TestToken("TokenB");
        if (address(tA) < address(tB)) {
            token0 = tA; token1 = tB;
        } else {
            token0 = tB; token1 = tA;
        }
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // 4. Compute the hook's target address (bits must match HOOK_FLAGS)
        address hookAddr = address(uint160(uint256(type(uint160).max) & CLEAR_ALL_MASK) | HOOK_FLAGS);

        // 5. Deploy support contracts
        oracle      = new VRSOracle(address(this));
        yieldRouter = new MockYieldRouter();

        // YieldBuffer receives token0 as the fee token (simplification for tests)
        buffer = new YieldBuffer(
            IERC20(address(token0)),
            hookAddr,
            address(this),
            IYieldRouter(address(yieldRouter))
        );

        // 6. Deploy hook impl with real constructor args, then etch to hookAddr.
        //    Immutables (poolManager, oracle, yieldBuffer, threshold) are baked
        //    into the runtime bytecode and are carried over by vm.etch.
        VolatilityVaultHook impl = new VolatilityVaultHook(
            manager,
            oracle,
            address(buffer),
            TOXIC_THRESHOLD
        );
        vm.etch(hookAddr, address(impl).code);
        hook = VolatilityVaultHook(hookAddr);

        // toxicOrderThreshold is a storage variable — vm.etch copies bytecode only.
        // Use vm.store to write it to slot 0 at the etched address.
        vm.store(hookAddr, bytes32(uint256(0)), bytes32(TOXIC_THRESHOLD));

        // 7. Mint tokens and approve routers for this test contract
        token0.mint(address(this), 10_000_000e18);
        token1.mint(address(this), 10_000_000e18);
        token0.approve(address(swapRouter),      type(uint256).max);
        token0.approve(address(liquidityRouter), type(uint256).max);
        token1.approve(address(swapRouter),      type(uint256).max);
        token1.approve(address(liquidityRouter), type(uint256).max);

        // 8. Initialize pool with DYNAMIC_FEE_FLAG (required for fee override)
        poolKey = PoolKey({
            currency0:   currency0,
            currency1:   currency1,
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks:       IHooks(hookAddr)
        });
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // 9. Seed the pool with deep initial liquidity so test swaps cause minimal price impact
        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1_000_000e18, salt: 0}),
            ""
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook address sanity
    // ─────────────────────────────────────────────────────────────────────────

    function test_hookAddress_hasCorrectBits() public view {
        uint160 addr = uint160(address(hook));
        assertTrue(addr & Hooks.BEFORE_SWAP_FLAG           != 0, "BEFORE_SWAP_FLAG missing");
        assertTrue(addr & Hooks.AFTER_SWAP_FLAG            != 0, "AFTER_SWAP_FLAG missing");
        assertTrue(addr & Hooks.AFTER_ADD_LIQUIDITY_FLAG   != 0, "AFTER_ADD_LIQUIDITY_FLAG missing");
        assertTrue(addr & Hooks.AFTER_REMOVE_LIQUIDITY_FLAG != 0, "AFTER_REMOVE_LIQUIDITY_FLAG missing");
    }

    function test_hookImmutables() public view {
        assertEq(address(hook.poolManager()), address(manager));
        assertEq(address(hook.oracle()),      address(oracle));
        assertEq(address(hook.yieldBuffer()), address(buffer));
        assertEq(hook.toxicOrderThreshold(),  TOXIC_THRESHOLD);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dynamic fee — beforeSwap overrides LP fee per VRS level
    // ─────────────────────────────────────────────────────────────────────────

    function test_fee_calm() public {
        oracle.updateVRS(15); // CALM → 0.05%
        (,,,uint256 fee) = manager.getSlot0(poolKey.toId());
        // Fee is 0 in storage (dynamic pool stores 0 until overridden per-swap)
        assertEq(fee, 0);

        // Execute a swap and verify the event carries the correct fee
        vm.expectEmit(false, false, false, false); // just verify it emits without reverting
        emit IPoolManager.Swap(poolKey.toId(), address(swapRouter), 0, 0, 0, 0, 0, 500);
        _swap(-1_000e18, true);
    }

    function test_fee_calm_reducedOutput() public {
        oracle.updateVRS(15); // 0.05%
        BalanceDelta calm = _swap(-1_000e18, true);

        oracle.updateVRS(90); // 0.50%
        BalanceDelta hurricane = _swap(-1_000e18, true);

        // Higher fee → less output (amount1 is positive = tokens received)
        assertGt(calm.amount1(), hurricane.amount1(), "calm should yield more output than hurricane");
    }

    function test_fee_hurricane_lessOutput() public {
        oracle.updateVRS(90); // HURRICANE → 0.50%
        BalanceDelta delta = _swap(-100_000e18, true);
        // Swap produces some output — not zero
        assertGt(delta.amount1(), 0);
    }

    function test_fee_allLevels_increasingFee() public {
        uint8[4] memory scores = [15, 45, 70, 90];
        int256 prevOutput = type(int256).max;

        for (uint256 i = 0; i < 4; i++) {
            oracle.updateVRS(scores[i]);
            BalanceDelta d = _swap(-1_000e18, true);
            int256 output = int256(d.amount1());
            assertLt(output, prevOutput, "higher VRS should yield less output");
            prevOutput = output;

        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LP intent registration — afterAddLiquidity
    // ─────────────────────────────────────────────────────────────────────────

    function test_afterAddLiquidity_registersIntent() public {
        bytes memory hookData = abi.encode(
            uint256(1200),                             // targetAPY = 12%
            uint256(500),                              // maxILToleranceBps = 5%
            VolatilityVaultHook.PayoutPreference.DAILY
        );

        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}),
            hookData
        );

        // In V4, afterAddLiquidity's `sender` = the address that called manager.modifyLiquidity()
        // which is address(liquidityRouter) (PoolModifyLiquidityTest's unlockCallback).
        (
            uint256 targetAPY,
            uint256 maxIL,
            VolatilityVaultHook.PayoutPreference pref,
            uint256 depositTs,
            bool registered
        ) = hook.lpIntents(address(liquidityRouter), poolKey.toId());

        assertTrue(registered);
        assertEq(targetAPY, 1200);
        assertEq(maxIL, 500);
        assertEq(uint8(pref), uint8(VolatilityVaultHook.PayoutPreference.DAILY));
        assertGt(depositTs, 0);
    }

    function test_afterAddLiquidity_noHookData_noIntent() public {
        // Add liquidity with no hookData — intent should NOT be registered
        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}),
            ""
        );

        (,,,, bool registered) = hook.lpIntents(address(this), poolKey.toId());
        assertFalse(registered);
    }

    function test_afterAddLiquidity_emitsLPRegistered() public {
        bytes memory hookData = abi.encode(uint256(1000), uint256(300), VolatilityVaultHook.PayoutPreference.REINVEST);

        vm.expectEmit(true, true, false, false);
        emit VolatilityVaultHook.LPRegistered(poolKey.toId(), address(liquidityRouter), 1000, VolatilityVaultHook.PayoutPreference.REINVEST);

        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}),
            hookData
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LP intent cleared — afterRemoveLiquidity
    // ─────────────────────────────────────────────────────────────────────────

    function test_afterRemoveLiquidity_clearsIntent() public {
        bytes memory hookData = abi.encode(uint256(1200), uint256(500), VolatilityVaultHook.PayoutPreference.DAILY);

        // Add liquidity with intent
        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}),
            hookData
        );

        (,,,, bool registeredBefore) = hook.lpIntents(address(liquidityRouter), poolKey.toId());
        assertTrue(registeredBefore);

        // Remove liquidity
        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -10e18, salt: 0}),
            ""
        );

        (,,,, bool registeredAfter) = hook.lpIntents(address(liquidityRouter), poolKey.toId());
        assertFalse(registeredAfter);
    }

    function test_afterRemoveLiquidity_emitsLPExited() public {
        bytes memory hookData = abi.encode(uint256(1200), uint256(500), VolatilityVaultHook.PayoutPreference.LUMP_SUM);

        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}),
            hookData
        );

        vm.expectEmit(true, true, false, false);
        emit VolatilityVaultHook.LPExited(poolKey.toId(), address(liquidityRouter), block.timestamp);

        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -10e18, salt: 0}),
            ""
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Toxic order detection
    // ─────────────────────────────────────────────────────────────────────────

    function test_toxicOrder_emitsEvent_whenLargeSwapDuringStorm() public {
        oracle.updateVRS(85); // HURRICANE

        // Swap larger than TOXIC_THRESHOLD
        vm.expectEmit(true, true, false, false);
        emit VolatilityVaultHook.ToxicOrderDetected(
            poolKey.toId(), address(swapRouter), 85, -int256(TOXIC_THRESHOLD)
        );

        _swap(-int256(TOXIC_THRESHOLD), true);
    }

    function test_toxicOrder_noEvent_whenSmallSwap() public {
        oracle.updateVRS(85); // HURRICANE

        // Small swap — below threshold, should NOT emit ToxicOrderDetected
        vm.recordLogs();
        _swap(-1_000e18 + 1, true); // just below threshold (threshold = 1_000e18 exactly)

        // Check no ToxicOrderDetected event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ToxicOrderDetected(bytes32,address,uint8,int256)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == sig, "ToxicOrderDetected should not be emitted");
        }
    }

    function test_toxicOrder_noEvent_duringCalmPeriod() public {
        oracle.updateVRS(15); // CALM — even large swaps not flagged

        vm.recordLogs();
        _swap(-int256(TOXIC_THRESHOLD * 10), true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ToxicOrderDetected(bytes32,address,uint8,int256)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == sig, "ToxicOrderDetected should not be emitted during calm");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Access control — only PoolManager can call hook
    // ─────────────────────────────────────────────────────────────────────────

    function test_onlyPoolManager_beforeSwap_reverts() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(VolatilityVaultHook.NotPoolManager.selector);
        hook.beforeSwap(
            address(this),
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            ""
        );
    }

    function test_onlyPoolManager_afterSwap_reverts() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(VolatilityVaultHook.NotPoolManager.selector);
        hook.afterSwap(
            address(this),
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            BalanceDelta.wrap(0),
            ""
        );
    }

    function test_onlyPoolManager_afterAddLiquidity_reverts() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(VolatilityVaultHook.NotPoolManager.selector);
        hook.afterAddLiquidity(
            address(this),
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: 0}),
            BalanceDelta.wrap(0),
            BalanceDelta.wrap(0),
            ""
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FeeOverridden event
    // ─────────────────────────────────────────────────────────────────────────

    function test_feeOverridden_eventEmitted() public {
        oracle.updateVRS(75); // STORM → 0.30%

        vm.expectEmit(true, false, false, true);
        emit VolatilityVaultHook.FeeOverridden(poolKey.toId(), 75, 3000);

        _swap(-1_000e18, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────────────

    function _swap(int256 amountSpecified, bool zeroForOne) internal returns (BalanceDelta delta) {
        delta = swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne:        zeroForOne,
                amountSpecified:   amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }
}
