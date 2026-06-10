// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}     from "forge-std/Script.sol";
import {IPoolManager}         from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks}               from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IERC20}              from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookMiner}            from "@uniswap/v4-periphery/test/shared/HookMiner.sol";
import {VRSOracle}            from "../src/VRSOracle.sol";
import {VolatilityVaultHook}  from "../src/VolatilityVaultHook.sol";
import {YieldBuffer}          from "../src/YieldBuffer.sol";
import {LPPositionNFT}        from "../src/LPPositionNFT.sol";
import {IYieldRouter}         from "../src/interfaces/IYieldRouter.sol";

interface IReceiverAdmin { function setBuffer(address) external; }

/// @notice V2 deploy — dual-asset buffer + fee-routing hook.
///         Reuses the existing VRSOracle, MockYieldRouter, and VRSCallbackReceiver;
///         deploys a NEW hook (afterSwapReturnDelta) + NEW dual-asset YieldBuffer,
///         then rewires the receiver to the new buffer.
///
/// Required env: POOL_MANAGER, VRS_ORACLE, MOCK_YIELD_ROUTER, TOKEN0, TOKEN1,
///               CALLBACK_RECEIVER, TOXIC_THRESHOLD
contract DeployV2 is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 constant HOOK_FLAGS = uint160(
        Hooks.AFTER_ADD_LIQUIDITY_FLAG    |
        Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
        Hooks.BEFORE_SWAP_FLAG            |
        Hooks.AFTER_SWAP_FLAG             |
        Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address oracle      = vm.envAddress("VRS_ORACLE");
        address router      = vm.envAddress("MOCK_YIELD_ROUTER");
        address token0      = vm.envAddress("TOKEN0");
        address token1      = vm.envAddress("TOKEN1");
        address receiver    = vm.envAddress("CALLBACK_RECEIVER");
        uint256 toxicThresh = vm.envOr("TOXIC_THRESHOLD", uint256(1_000 ether));

        vm.startBroadcast();

        // 1. Mine + deploy the new hook (address(0) buffer placeholder)
        bytes memory args = abi.encode(IPoolManager(poolManager), VRSOracle(oracle), address(0), toxicThresh);
        (address hookAddr, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, type(VolatilityVaultHook).creationCode, args);

        VolatilityVaultHook hook = new VolatilityVaultHook{salt: salt}(
            IPoolManager(poolManager), VRSOracle(oracle), address(0), toxicThresh
        );
        require(address(hook) == hookAddr, "hook addr mismatch");
        console2.log("NEW Hook:        ", address(hook));

        // 2. Deploy the dual-asset buffer (authorizedTrigger = receiver so RSC can distribute)
        YieldBuffer buffer = new YieldBuffer(
            IERC20(token0), IERC20(token1), hookAddr, receiver, IYieldRouter(router)
        );
        console2.log("NEW YieldBuffer: ", address(buffer));

        // 3. Wire hook -> buffer
        hook.setYieldBuffer(address(buffer));

        // 4. Deploy a fresh position NFT bound to the new hook
        LPPositionNFT nft = new LPPositionNFT(address(hook));
        console2.log("NEW LPPositionNFT:", address(nft));

        // 5. Point the Reactive callback receiver at the new buffer
        IReceiverAdmin(receiver).setBuffer(address(buffer));
        console2.log("Receiver rewired to new buffer.");

        vm.stopBroadcast();

        console2.log("\n=== V2 DEPLOY COMPLETE ===");
        console2.log("Update .env / frontend:");
        console2.log("HOOK_ADDRESS=", address(hook));
        console2.log("YIELD_BUFFER=", address(buffer));
        console2.log("LP_NFT=", address(nft));
        console2.log("\nNext: InitializePool (new hook) + reseed + fund router for yield");
    }
}
