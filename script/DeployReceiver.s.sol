// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2}      from "forge-std/Script.sol";
import {VRSCallbackReceiver}   from "../src/VRSCallbackReceiver.sol";

interface IOracleAdmin { function setAuthorizedUpdater(address) external; }
interface IBufferAdmin { function setAuthorizedTrigger(address) external; }

/// @notice Deploys the VRSCallbackReceiver on Sepolia, wires it as the authorized
///         updater/trigger on the oracle and buffer, and funds it for callback debt.
///
/// Usage:
///   forge script script/DeployReceiver.s.sol:DeployReceiver \
///     --rpc-url $SEPOLIA_RPC_URL --broadcast --verify \
///     --etherscan-api-key $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY -vvvv
///
/// Required env:
///   VRS_ORACLE, YIELD_BUFFER
///   CALLBACK_PROXY   (Sepolia callback proxy; default 0xc9f3...7bDA)
///   RECEIVER_FUND    (wei to fund the receiver for callback gas; default 0.01 ether)
contract DeployReceiver is Script {
    address constant DEFAULT_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    function run() external {
        address oracle  = vm.envAddress("VRS_ORACLE");
        address buffer  = vm.envAddress("YIELD_BUFFER");
        address proxy   = vm.envOr("CALLBACK_PROXY", DEFAULT_PROXY);
        uint256 fundAmt = vm.envOr("RECEIVER_FUND", uint256(0.01 ether));

        vm.startBroadcast();

        VRSCallbackReceiver receiver = new VRSCallbackReceiver(proxy, oracle, buffer);
        console2.log("VRSCallbackReceiver:", address(receiver));

        // Authorize the receiver to push VRS and trigger distribution.
        IOracleAdmin(oracle).setAuthorizedUpdater(address(receiver));
        IBufferAdmin(buffer).setAuthorizedTrigger(address(receiver));
        console2.log("Wired oracle.authorizedUpdater + buffer.authorizedTrigger -> receiver");

        // Fund the receiver so it can settle callback debt to the proxy.
        receiver.fund{value: fundAmt}();
        console2.log("Funded receiver with (wei):", fundAmt);

        vm.stopBroadcast();

        console2.log("\nNext: set CALLBACK_RECEIVER in .env and run DeployRSC on Lasna");
    }
}
