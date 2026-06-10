// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VolatilityRSC, IReactive} from "../reactive/VolatilityRSC.sol";

/// @dev In a Foundry test there is no system contract at 0x...fffFfF, so the RSC
///      constructor sets isVm = true (skips subscribe) and react() is callable.
contract VolatilityRSCTest is Test {
    VolatilityRSC rsc;

    address poolManager = makeAddr("poolManager");
    address receiver    = makeAddr("receiver");
    address rando       = makeAddr("rando");
    uint256 constant SEPOLIA = 11155111;
    uint160 constant SQRT_1_1 = 79228162514264337593543950336;

    function setUp() public {
        uint256[] memory chains = new uint256[](1);
        chains[0] = SEPOLIA;
        address[] memory pms = new address[](1);
        pms[0] = poolManager;
        rsc = new VolatilityRSC(chains, pms, SEPOLIA, receiver);
    }

    // Build a Reactive LogRecord carrying a V4-Swap-shaped data blob.
    function _log(uint160 sqrtPrice, uint256 blockNum) internal view returns (IReactive.LogRecord memory l) {
        l.chain_id     = SEPOLIA;
        l._contract    = poolManager;
        l.topic_0      = rsc.SWAP_TOPIC_0();
        l.data         = abi.encode(int128(0), int128(0), sqrtPrice, uint128(0), int24(0), uint24(0));
        l.block_number = blockNum;
    }

    // ── Constructor ────────────────────────────────────────────────────────────

    function test_constructor_owner() public view {
        assertEq(rsc.owner(), address(this));
    }

    function test_constructor_destinationChain() public view {
        assertEq(rsc.destinationChainId(), SEPOLIA);
    }

    function test_constructor_callbackReceiver() public view {
        assertEq(rsc.callbackReceiver(), receiver);
    }

    function test_constructor_lengthMismatchReverts() public {
        uint256[] memory chains = new uint256[](2);
        address[] memory pms = new address[](1);
        vm.expectRevert("length mismatch");
        new VolatilityRSC(chains, pms, SEPOLIA, receiver);
    }

    // ── react: VRS computation ───────────────────────────────────────────────────

    function test_react_firstSwap_setsVRS() public {
        rsc.react(_log(SQRT_1_1, 1000));
        // first swap: priceChange 0, freq 1 → VRS = 5
        assertEq(rsc.currentVRS(), 5);
    }

    function test_react_updatesLastSqrtPrice() public {
        rsc.react(_log(SQRT_1_1, 1000));
        assertEq(rsc.lastSqrtPrice(), SQRT_1_1);
    }

    function test_react_updatesLastBlock() public {
        rsc.react(_log(SQRT_1_1, 1000));
        assertEq(rsc.lastBlockNumber(), 1000);
    }

    function test_react_emitsVRSComputed() public {
        vm.expectEmit(false, false, false, true);
        emit VolatilityRSC.VRSComputed(5, 0, 1);
        rsc.react(_log(SQRT_1_1, 1000));
    }

    function test_react_emitsCallbackToReceiver() public {
        bytes memory payload = abi.encodeWithSignature("updateVRS(address,uint8)", address(0), uint8(5));
        vm.expectEmit(true, true, true, true);
        emit IReactive.Callback(SEPOLIA, receiver, 500_000, payload);
        rsc.react(_log(SQRT_1_1, 1000));
    }

    function test_react_priceJump_raisesVRS() public {
        rsc.react(_log(SQRT_1_1, 1000));
        // Big upward price move on a later block → larger priceChangeBps
        rsc.react(_log(SQRT_1_1 * 2, 1100));
        assertGt(rsc.currentVRS(), 5);
    }

    function test_react_frequencySpike_raisesVRS() public {
        // Many swaps within the same 10-block window → frequency drives VRS up
        for (uint256 i = 0; i < 8; i++) {
            rsc.react(_log(SQRT_1_1, 1000 + i)); // same window
        }
        assertGt(rsc.currentVRS(), 30); // storm territory from frequency
    }

    function test_react_smallDelta_noStateChange() public {
        rsc.react(_log(SQRT_1_1, 1000)); // VRS 5
        uint8 v1 = rsc.currentVRS();
        // a swap that yields the same VRS (delta < MIN_VRS_DELTA) shouldn't change currentVRS
        // window resets (block +100) → freq 1, price same → VRS 5 again, delta 0
        rsc.react(_log(SQRT_1_1, 1200));
        assertEq(rsc.currentVRS(), v1);
    }

    function test_react_stormThenCalm_triggersDistribution() public {
        // 1. Drive a storm via frequency
        for (uint256 i = 0; i < 8; i++) {
            rsc.react(_log(SQRT_1_1, 1000 + i));
        }
        assertTrue(rsc.wasStorm());

        // 2. Calm swap far in the future (window resets) → expect distribution callback
        bytes memory distPayload = abi.encodeWithSignature("triggerDistribution(address)", address(0));
        vm.expectEmit(true, true, true, true);
        emit IReactive.Callback(SEPOLIA, receiver, 500_000, distPayload);
        rsc.react(_log(SQRT_1_1, 5000));
    }

    // ── pay ────────────────────────────────────────────────────────────────────

    function test_pay_revertsForNonService() public {
        vm.prank(rando);
        vm.expectRevert("SERVICE only");
        rsc.pay(1 ether);
    }

    // ── admin ──────────────────────────────────────────────────────────────────

    function test_setCallbackReceiver_updates() public {
        address nr = makeAddr("nr");
        rsc.setCallbackReceiver(nr);
        assertEq(rsc.callbackReceiver(), nr);
    }

    function test_setCallbackReceiver_onlyOwner() public {
        vm.prank(rando);
        vm.expectRevert(VolatilityRSC.Unauthorized.selector);
        rsc.setCallbackReceiver(rando);
    }

    function test_setDestinationChain_updates() public {
        rsc.setDestinationChain(8453);
        assertEq(rsc.destinationChainId(), 8453);
    }

    function test_setDestinationChain_onlyOwner() public {
        vm.prank(rando);
        vm.expectRevert(VolatilityRSC.Unauthorized.selector);
        rsc.setDestinationChain(8453);
    }

    function test_transferOwnership_updates() public {
        rsc.transferOwnership(rando);
        assertEq(rsc.owner(), rando);
    }

    function test_transferOwnership_onlyOwner() public {
        vm.prank(rando);
        vm.expectRevert(VolatilityRSC.Unauthorized.selector);
        rsc.transferOwnership(rando);
    }

    function test_subscribe_onlyOwner() public {
        vm.prank(rando);
        vm.expectRevert(VolatilityRSC.Unauthorized.selector);
        rsc.subscribe(SEPOLIA, poolManager);
    }

    function test_unsubscribe_onlyOwner() public {
        vm.prank(rando);
        vm.expectRevert(VolatilityRSC.Unauthorized.selector);
        rsc.unsubscribe(SEPOLIA, poolManager);
    }

    // ── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_react_vrsNeverExceeds100(uint160 sqrtPrice, uint256 blockNum) public {
        vm.assume(sqrtPrice > 0);
        blockNum = bound(blockNum, 1, 1_000_000);
        rsc.react(_log(sqrtPrice, blockNum));
        assertLe(rsc.currentVRS(), 100);
    }

    function testFuzz_setCallbackReceiver_onlyOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.prank(caller);
        vm.expectRevert(VolatilityRSC.Unauthorized.selector);
        rsc.setCallbackReceiver(caller);
    }
}
