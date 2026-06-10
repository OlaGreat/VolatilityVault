// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}        from "forge-std/Script.sol";
import {IHooks}                  from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey}                 from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency}               from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary}           from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SwapParams}             from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20}                 from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolSwapTest}           from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

/// @notice A single oneForZero storm swap to accrue buffer fees (token0 side),
///         pushing price up so it won't hit the lower limit.
contract StormSwap is Script {
    uint160 constant MAX_PRICE_LIMIT = 1461446703485210103287273052203988822378723970340;

    function run() external {
        address hook   = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address swapR  = vm.envAddress("SWAP_ROUTER");

        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(token0),
            currency1:   Currency.wrap(token1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks:       IHooks(hook)
        });

        vm.startBroadcast();
        IERC20(token1).approve(swapR, type(uint256).max);
        PoolSwapTest(swapR).swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -1 ether, sqrtPriceLimitX96: MAX_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        console2.log("Storm swap (oneForZero) done - buffer fee accrued in token0.");
        vm.stopBroadcast();
    }
}
