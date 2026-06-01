// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}    from "forge-std/Script.sol";
import {IPoolManager}        from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks}              from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey}             from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency}            from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary}        from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath}            from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

/// @notice Initializes a VolatilityVault pool and seeds it with initial liquidity.
///
/// Usage:
///   forge script script/InitializePool.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast --private-key $PRIVATE_KEY \
///     -vvvv
///
/// Required env vars:
///   POOL_MANAGER   - PoolManager address
///   HOOK_ADDRESS   - deployed VolatilityVaultHook address
///   TOKEN0         - lower-address token (sorted)
///   TOKEN1         - higher-address token (sorted)
///   TICK_SPACING   - pool tick spacing (default 60 for dynamic fee pools)
///   SQRT_PRICE     - initial sqrtPriceX96 (default = 1:1 ratio)
contract InitializePool is Script {
    // 1:1 price - sqrt(1) * 2^96
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address token0Addr  = vm.envAddress("TOKEN0");
        address token1Addr  = vm.envAddress("TOKEN1");
        int24 tickSpacing   = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        uint160 sqrtPrice   = uint160(vm.envOr("SQRT_PRICE", uint256(SQRT_PRICE_1_1)));

        // Ensure tokens are sorted (V4 requires currency0 < currency1)
        require(token0Addr < token1Addr, "TOKEN0 must be < TOKEN1 by address - swap them");

        vm.startBroadcast();

        IPoolManager manager = IPoolManager(poolManager);

        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(token0Addr),
            currency1:   Currency.wrap(token1Addr),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks:       IHooks(hookAddress)
        });

        manager.initialize(key, sqrtPrice);

        console2.log("Pool initialized");
        console2.log("currency0:", token0Addr);
        console2.log("currency1:", token1Addr);
        console2.log("fee:       DYNAMIC (0x800000)");
        console2.log("hook:     ", hookAddress);

        vm.stopBroadcast();

        // Print the pool key hash for reference
        bytes32 poolId = keccak256(abi.encode(key));
        console2.log("Pool ID (keccak):", uint256(poolId));
        console2.log("\nNext: add liquidity via cast or a frontend");
    }
}
