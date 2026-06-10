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
import {VRSOracle}              from "../src/VRSOracle.sol";
import {YieldBuffer}            from "../src/YieldBuffer.sol";

/// @notice End-to-end claim demo on the live V2 contracts (run as the deployer/LP).
///         deposit (registers LP) → storm swap (accrues fees) → distribute → claim.
contract DemoClaim is Script {
    uint160 constant MIN_PRICE_LIMIT = 4295128740;

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hook        = vm.envAddress("HOOK_ADDRESS");
        address oracleAddr  = vm.envAddress("VRS_ORACLE");
        address bufferAddr  = vm.envAddress("YIELD_BUFFER");
        address token0      = vm.envAddress("TOKEN0");
        address token1      = vm.envAddress("TOKEN1");
        address liqR        = vm.envAddress("LIQ_ROUTER");
        address swapR       = vm.envAddress("SWAP_ROUTER");

        VRSOracle   oracle = VRSOracle(oracleAddr);
        YieldBuffer buffer = YieldBuffer(bufferAddr);

        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(token0),
            currency1:   Currency.wrap(token1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks:       IHooks(hook)
        });

        vm.startBroadcast();
        address lp = msg.sender;

        // Approvals
        IERC20(token0).approve(liqR,  type(uint256).max);
        IERC20(token1).approve(liqR,  type(uint256).max);
        IERC20(token0).approve(swapR, type(uint256).max);
        IERC20(token1).approve(swapR, type(uint256).max);

        // 1. Deposit WITH hookData encoding the LP address -> registers LP in buffer
        bytes memory hookData = abi.encode(lp, uint256(1200), uint256(500), uint8(0));
        PoolModifyLiquidityTest(liqR).modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 50 ether, salt: 0}),
            hookData
        );
        console2.log("Deposited + registered LP. buffer liquidity:", buffer.lpLiquidity(lp, buffer.currentEpoch()));

        // 2. Storm -> swap accrues a buffer fee (taken in token1, the unspecified side)
        oracle.updateVRS(85);
        PoolSwapTest(swapR).swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -5 ether, sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        uint256 epochId = buffer.currentEpoch();
        (uint256 f0, uint256 f1,,,,,,,) = buffer.epochs(epochId);
        console2.log("After swap - buffer fees token0:", f0);
        console2.log("After swap - buffer fees token1:", f1);

        // 3. Distribution (deployer is owner -> can trigger)
        buffer.triggerDistribution();
        console2.log("Distribution triggered. Epoch closed:", epochId);

        // 4. Claim
        (uint256 p0, uint256 p1) = buffer.previewClaim(lp, epochId);
        console2.log("Claimable token0:", p0);
        console2.log("Claimable token1:", p1);

        uint256 bal1Before = IERC20(token1).balanceOf(lp);
        buffer.claim(epochId);
        uint256 received1 = IERC20(token1).balanceOf(lp) - bal1Before;
        console2.log("CLAIMED token1:", received1);
        require(received1 == p1, "claim mismatch");
        console2.log("\n=== CLAIM FLOW VERIFIED ON-CHAIN ===");

        vm.stopBroadcast();
    }
}
