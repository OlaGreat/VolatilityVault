// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}  from "forge-std/Script.sol";
import {VolatilityRSC}     from "../reactive/VolatilityRSC.sol";

/// @notice Deploys the VolatilityRSC on Reactive Lasna testnet (chain 5318007).
///         The RSC subscribes to Uniswap V4 Swap events on Sepolia and pushes
///         VRS updates back to the VRSCallbackReceiver on Sepolia.
///
/// Usage:
///   forge script script/DeployRSC.s.sol:DeployRSC \
///     --rpc-url $REACTIVE_RPC_URL --broadcast --private-key $PRIVATE_KEY -vvvv
///
/// Required env:
///   POOL_MANAGER       (Sepolia PoolManager — the Swap event source)
///   CALLBACK_RECEIVER  (VRSCallbackReceiver address on Sepolia)
///   RSC_FUND           (REACT wei to fund subscription + callbacks; default 5 ether)
contract DeployRSC is Script {
    uint256 constant SEPOLIA = 11155111;

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address receiver    = vm.envAddress("CALLBACK_RECEIVER");
        uint256 fund        = vm.envOr("RSC_FUND", uint256(5 ether));

        uint256[] memory chains = new uint256[](1);
        chains[0] = SEPOLIA;

        address[] memory pms = new address[](1);
        pms[0] = poolManager;

        vm.startBroadcast();

        VolatilityRSC rsc = new VolatilityRSC{value: fund}(
            chains,
            pms,
            SEPOLIA,    // destination chain (where the receiver lives)
            receiver
        );

        vm.stopBroadcast();

        console2.log("VolatilityRSC deployed on Lasna:", address(rsc));
        console2.log("Subscribed to Sepolia PoolManager Swap events:", poolManager);
        console2.log("Callbacks target receiver on Sepolia:", receiver);
        console2.log("Funded with REACT (wei):", fund);
    }
}
