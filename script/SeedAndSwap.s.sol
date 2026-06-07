// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}        from "forge-std/Script.sol";
import {IHooks}                  from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey}                 from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency}               from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary}           from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20}                 from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolSwapTest}           from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

/// @notice Seeds liquidity then performs a swap on the VolatilityVault pool.
///         The swap emits a PoolManager Swap event, which the VolatilityRSC on
///         Reactive Lasna is subscribed to — triggering the automatic VRS update.
///
/// Usage:
///   forge script script/SeedAndSwap.s.sol:SeedAndSwap \
///     --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY -vvvv
contract SeedAndSwap is Script {
    uint160 constant MIN_PRICE_LIMIT = 4295128740; // TickMath.MIN_SQRT_PRICE + 1

    function run() external {
        address hook    = vm.envAddress("HOOK_ADDRESS");
        address token0  = vm.envAddress("TOKEN0");
        address token1  = vm.envAddress("TOKEN1");
        address swapR   = vm.envAddress("SWAP_ROUTER");
        address liqR    = vm.envAddress("LIQ_ROUTER");

        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(token0),
            currency1:   Currency.wrap(token1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks:       IHooks(hook)
        });

        vm.startBroadcast();

        // Approve both routers for both tokens
        IERC20(token0).approve(liqR,  type(uint256).max);
        IERC20(token1).approve(liqR,  type(uint256).max);
        IERC20(token0).approve(swapR, type(uint256).max);
        IERC20(token1).approve(swapR, type(uint256).max);

        // Seed a healthy chunk of liquidity
        PoolModifyLiquidityTest(liqR).modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 ether, salt: 0}),
            ""
        );
        console2.log("Liquidity seeded.");

        // Swap 1 token0 -> token1 (exact input). Emits the Swap event.
        PoolSwapTest(swapR).swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        console2.log("Swap executed -> Swap event emitted -> Reactive RSC should fire.");

        vm.stopBroadcast();
    }
}
