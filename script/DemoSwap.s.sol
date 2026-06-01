// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}    from "forge-std/Script.sol";
import {IPoolManager}        from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks}              from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey}             from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency}            from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta}        from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary}        from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SwapParams}          from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath}            from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20}              from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolSwapTest}        from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {VRSOracle}            from "../src/VRSOracle.sol";

/// @notice End-to-end demo: sets VRS, swaps, and logs the fee applied.
///
/// Demonstrates VolatilityVault's core mechanic:
///   - At VRS=15 (calm) --> 0.05% fee
///   - At VRS=85 (hurricane) --> 0.50% fee
///   - ToxicOrderDetected event fires on large swap during storm
///
/// Usage (against a live testnet pool):
///   forge script script/DemoSwap.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast --private-key $PRIVATE_KEY \
///     -vvvv
///
/// Required env vars:
///   POOL_MANAGER, HOOK_ADDRESS, VRS_ORACLE
///   TOKEN0, TOKEN1
///   SWAP_ROUTER   - deployed PoolSwapTest address
contract DemoSwap is Script {
    uint160 constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    function run() external {
        address hookAddress     = vm.envAddress("HOOK_ADDRESS");
        address oracleAddr      = vm.envAddress("VRS_ORACLE");
        address token0Addr      = vm.envAddress("TOKEN0");
        address token1Addr      = vm.envAddress("TOKEN1");
        address swapRouterAddr  = vm.envAddress("SWAP_ROUTER");

        VRSOracle oracle     = VRSOracle(oracleAddr);
        PoolSwapTest router  = PoolSwapTest(swapRouterAddr);

        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(token0Addr),
            currency1:   Currency.wrap(token1Addr),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks:       IHooks(hookAddress)
        });

        vm.startBroadcast();

        // ── Demo 1: Calm swap (0.05% fee) ────────────────────────────────────
        console2.log("\n--- DEMO 1: CALM (VRS = 15) ---");
        oracle.updateVRS(15);
        console2.log("VRS set to 15 --> expected fee: 0.05% (500 units)");

        IERC20(token0Addr).approve(address(router), 10_000 ether);
        BalanceDelta d1 = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        console2.log("Swap executed. token0 in:", uint256(uint128(-d1.amount0())));
        console2.log("              token1 out:", uint256(uint128(d1.amount1())));

        // ── Demo 2: Hurricane swap (0.50% fee + toxic order) ─────────────────
        console2.log("\n--- DEMO 2: HURRICANE (VRS = 85) ---");
        oracle.updateVRS(85);
        console2.log("VRS set to 85 --> expected fee: 0.50% (5000 units)");
        console2.log("Swap size exceeds toxic threshold --> ToxicOrderDetected event should fire");

        BalanceDelta d2 = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -1_000 ether, sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        console2.log("Swap executed. token0 in:", uint256(uint128(-d2.amount0())));
        console2.log("              token1 out:", uint256(uint128(d2.amount1())));

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("\n=== DEMO COMPLETE ===");
        console2.log("Check logs for FeeOverridden and ToxicOrderDetected events.");
        console2.log("Calm output should be > Hurricane output for same input size.");

        vm.stopBroadcast();
    }
}
