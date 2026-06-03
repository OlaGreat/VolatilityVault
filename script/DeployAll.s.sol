// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager}     from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks}           from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks}            from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary}     from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IERC20}           from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookMiner}            from "@uniswap/v4-periphery/test/shared/HookMiner.sol";
import {VRSOracle}            from "../src/VRSOracle.sol";
import {VolatilityVaultHook}  from "../src/VolatilityVaultHook.sol";
import {YieldBuffer}          from "../src/YieldBuffer.sol";
import {LPPositionNFT}        from "../src/LPPositionNFT.sol";
import {MockYieldRouter}      from "../src/mocks/MockYieldRouter.sol";
import {IYieldRouter}         from "../src/interfaces/IYieldRouter.sol";

/// @notice Deploys the full VolatilityVault system to any EVM chain.
///
/// Usage:
///   forge script script/DeployAll.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast --verify \
///     --private-key $PRIVATE_KEY \
///     -vvvv
///
/// Required env vars:
///   PRIVATE_KEY          - deployer private key
///   POOL_MANAGER         - Uniswap V4 PoolManager address for this chain
///   FEE_TOKEN            - ERC-20 to use as the yield buffer asset (e.g. USDC)
///   TOXIC_THRESHOLD      - minimum swap size (18-dec units) to flag as toxic
///                          defaults to 1_000 ether if not set
///
/// After running, set these env vars for InitializePool.s.sol:
///   VRS_ORACLE, HOOK_ADDRESS, YIELD_BUFFER, LP_NFT
contract DeployAll is Script {
    // CREATE2 Deployer Proxy - standard across all EVM chains
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Hook permission bits
    uint160 constant HOOK_FLAGS = uint160(
        Hooks.AFTER_ADD_LIQUIDITY_FLAG    |
        Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
        Hooks.BEFORE_SWAP_FLAG            |
        Hooks.AFTER_SWAP_FLAG
    );

    function run() external {
        address poolManager  = vm.envAddress("POOL_MANAGER");
        address feeToken     = vm.envOr("FEE_TOKEN", address(0));
        uint256 toxicThresh  = vm.envOr("TOXIC_THRESHOLD", uint256(1_000 ether));

        vm.startBroadcast();

        // ── 1. Deploy VRSOracle ───────────────────────────────────────────────
        // Deployer is the initial authorized updater - rotate to RSC after it is deployed.
        VRSOracle oracle = new VRSOracle(msg.sender);
        console2.log("VRSOracle:          ", address(oracle));

        // ── 2. Deploy MockYieldRouter (for testnet / demo) ────────────────────
        MockYieldRouter yieldRouter = new MockYieldRouter();
        console2.log("MockYieldRouter:    ", address(yieldRouter));

        // ── 3. Mine a CREATE2 salt so the hook lands at an address with the
        //       correct permission bits in its lower 14 bits. ─────────────────
        //
        // We mine using address(0) as the yieldBuffer placeholder. The hook is
        // deployed with address(0) first, then we call setYieldBuffer() after
        // the buffer is deployed. This breaks the circular dependency.
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager),
            oracle,
            address(0),   // yieldBuffer placeholder - set via setYieldBuffer() after deploy
            toxicThresh
        );

        (address hookAddr, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            HOOK_FLAGS,
            type(VolatilityVaultHook).creationCode,
            constructorArgs
        );
        console2.log("Hook address (mined):", hookAddr);
        console2.log("Salt:                ", uint256(salt));

        // ── 4. Deploy hook at mined address with address(0) as buffer ─────────
        VolatilityVaultHook hook = new VolatilityVaultHook{salt: salt}(
            IPoolManager(poolManager),
            oracle,
            address(0),   // placeholder - updated below
            toxicThresh
        );
        require(address(hook) == hookAddr, "Hook address mismatch - salt invalid");
        console2.log("VolatilityVaultHook:", address(hook));

        // ── 5. Deploy YieldBuffer with the now-known hook address ─────────────
        address assetAddress = feeToken == address(0) ? address(yieldRouter) : feeToken;

        YieldBuffer buffer = new YieldBuffer(
            IERC20(assetAddress),
            hookAddr,      // hook address is now known
            msg.sender,    // authorized trigger - rotate to RSC after deployment
            IYieldRouter(address(yieldRouter))
        );
        console2.log("YieldBuffer:        ", address(buffer));

        // ── 6. Wire hook to buffer ────────────────────────────────────────────
        hook.setYieldBuffer(address(buffer));
        console2.log("Hook wired to buffer.");

        // ── 7. Deploy LPPositionNFT ───────────────────────────────────────────
        LPPositionNFT nft = new LPPositionNFT(address(hook));
        console2.log("LPPositionNFT:      ", address(nft));

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("Chain ID:           ", block.chainid);
        console2.log("PoolManager:        ", poolManager);
        console2.log("VRSOracle:          ", address(oracle));
        console2.log("VolatilityVaultHook:", address(hook));
        console2.log("YieldBuffer:        ", address(buffer));
        console2.log("LPPositionNFT:      ", address(nft));
        console2.log("MockYieldRouter:    ", address(yieldRouter));
        console2.log("\nNext steps:");
        console2.log("1. Deploy VolatilityRSC on Reactive Network");
        console2.log("2. Call oracle.setAuthorizedUpdater(rscCallbackAddr)");
        console2.log("3. Call buffer.setAuthorizedTrigger(rscCallbackAddr)");
        console2.log("4. Run InitializePool.s.sol to create the pool");
    }
}
