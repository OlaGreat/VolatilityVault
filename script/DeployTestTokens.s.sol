// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20}            from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

/// @notice Deploys two test ERC-20 tokens for the demo pool.
///         Mints 1,000,000 of each to the deployer.
///         After running, add TOKEN0 and TOKEN1 to your .env (sorted by address).
contract DeployTestTokens is Script {
    function run() external {
        vm.startBroadcast();

        MockERC20 tokenA = new MockERC20("Volatile Token A", "VTKA", 1_000_000 ether);
        MockERC20 tokenB = new MockERC20("Volatile Token B", "VTKB", 1_000_000 ether);

        vm.stopBroadcast();

        // Sort so TOKEN0 < TOKEN1 (V4 requirement)
        address t0 = address(tokenA) < address(tokenB)
            ? address(tokenA) : address(tokenB);
        address t1 = address(tokenA) < address(tokenB)
            ? address(tokenB) : address(tokenA);

        console2.log("=== TEST TOKENS DEPLOYED ===");
        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        console2.log("\nAdd to .env (already sorted):");
        console2.log("TOKEN0=", t0);
        console2.log("TOKEN1=", t1);
        console2.log("FEE_TOKEN=", t0);
    }
}
