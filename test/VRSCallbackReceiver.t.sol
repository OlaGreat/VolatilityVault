// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VRSCallbackReceiver} from "../src/VRSCallbackReceiver.sol";

// ── Mocks for the forwarded calls ──────────────────────────────────────────────
contract MockOracle {
    uint8 public lastScore;
    bool  public called;
    function updateVRS(uint8 score) external { lastScore = score; called = true; }
}

contract MockBuffer {
    bool public distributed;
    function triggerDistribution() external { distributed = true; }
}

contract VRSCallbackReceiverTest is Test {
    VRSCallbackReceiver receiver;
    MockOracle oracle;
    MockBuffer buffer;

    address owner = address(this);
    address proxy = makeAddr("proxy");
    address rando = makeAddr("rando");

    function setUp() public {
        oracle   = new MockOracle();
        buffer   = new MockBuffer();
        receiver = new VRSCallbackReceiver(proxy, address(oracle), address(buffer));
    }

    // ── Constructor ────────────────────────────────────────────────────────────

    function test_constructor_setsOwner() public view {
        assertEq(receiver.owner(), owner);
    }

    function test_constructor_setsCallbackProxy() public view {
        assertEq(receiver.callbackProxy(), proxy);
    }

    function test_constructor_setsOracle() public view {
        assertEq(address(receiver.oracle()), address(oracle));
    }

    function test_constructor_setsBuffer() public view {
        assertEq(address(receiver.buffer()), address(buffer));
    }

    // ── updateVRS ──────────────────────────────────────────────────────────────

    function test_updateVRS_forwardsToOracle() public {
        vm.prank(proxy);
        receiver.updateVRS(address(0), 77);
        assertEq(oracle.lastScore(), 77);
    }

    function test_updateVRS_emitsVRSForwarded() public {
        vm.expectEmit(false, false, false, true);
        emit VRSCallbackReceiver.VRSForwarded(77);
        vm.prank(proxy);
        receiver.updateVRS(address(0), 77);
    }

    function test_updateVRS_revertsForNonProxy() public {
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.updateVRS(address(0), 77);
    }

    function test_updateVRS_ownerCannotCall() public {
        // owner is not the proxy — only the proxy may push callbacks
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.updateVRS(address(0), 77);
    }

    // ── triggerDistribution ────────────────────────────────────────────────────

    function test_triggerDistribution_forwardsToBuffer() public {
        vm.prank(proxy);
        receiver.triggerDistribution(address(0));
        assertTrue(buffer.distributed());
    }

    function test_triggerDistribution_emitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit VRSCallbackReceiver.DistributionForwarded();
        vm.prank(proxy);
        receiver.triggerDistribution(address(0));
    }

    function test_triggerDistribution_revertsForNonProxy() public {
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.triggerDistribution(address(0));
    }

    // ── pay ────────────────────────────────────────────────────────────────────

    function test_pay_sendsEthToProxy() public {
        vm.deal(address(receiver), 1 ether);
        uint256 before = proxy.balance;
        vm.prank(proxy);
        receiver.pay(0.3 ether);
        assertEq(proxy.balance - before, 0.3 ether);
    }

    function test_pay_revertsForNonProxy() public {
        vm.deal(address(receiver), 1 ether);
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.pay(0.1 ether);
    }

    // ── funding ──────────────────────────────────────────────────────────────

    function test_receive_acceptsEth() public {
        (bool ok, ) = address(receiver).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(receiver).balance, 0.5 ether);
    }

    function test_fund_increasesBalance() public {
        receiver.fund{value: 0.5 ether}();
        assertEq(address(receiver).balance, 0.5 ether);
    }

    // ── admin: setCallbackProxy ──────────────────────────────────────────────────

    function test_setCallbackProxy_updates() public {
        address np = makeAddr("np");
        receiver.setCallbackProxy(np);
        assertEq(receiver.callbackProxy(), np);
    }

    function test_setCallbackProxy_emits() public {
        address np = makeAddr("np");
        vm.expectEmit(true, false, false, false);
        emit VRSCallbackReceiver.CallbackProxyUpdated(np);
        receiver.setCallbackProxy(np);
    }

    function test_setCallbackProxy_revertsForNonOwner() public {
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.setCallbackProxy(rando);
    }

    function test_setCallbackProxy_newProxyCanCall() public {
        address np = makeAddr("np");
        receiver.setCallbackProxy(np);
        vm.prank(np);
        receiver.updateVRS(address(0), 42);
        assertEq(oracle.lastScore(), 42);
    }

    function test_setCallbackProxy_oldProxyCannotCall() public {
        address np = makeAddr("np");
        receiver.setCallbackProxy(np);
        vm.prank(proxy);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.updateVRS(address(0), 42);
    }

    // ── admin: setOracle / setBuffer ───────────────────────────────────────────

    function test_setOracle_updates() public {
        address no = makeAddr("no");
        receiver.setOracle(no);
        assertEq(address(receiver.oracle()), no);
    }

    function test_setOracle_revertsForNonOwner() public {
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.setOracle(rando);
    }

    function test_setBuffer_updates() public {
        address nb = makeAddr("nb");
        receiver.setBuffer(nb);
        assertEq(address(receiver.buffer()), nb);
    }

    function test_setBuffer_revertsForNonOwner() public {
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.setBuffer(rando);
    }

    // ── admin: transferOwnership ─────────────────────────────────────────────────

    function test_transferOwnership_updates() public {
        receiver.transferOwnership(rando);
        assertEq(receiver.owner(), rando);
    }

    function test_transferOwnership_revertsForNonOwner() public {
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.transferOwnership(rando);
    }

    function test_transferOwnership_newOwnerHasControl() public {
        receiver.transferOwnership(rando);
        vm.prank(rando);
        receiver.setOracle(makeAddr("x")); // should not revert
    }

    // ── admin: withdraw ──────────────────────────────────────────────────────────

    function test_withdraw_sendsToOwner() public {
        vm.deal(address(receiver), 1 ether);
        uint256 before = owner.balance;
        receiver.withdraw(0.4 ether);
        assertEq(owner.balance - before, 0.4 ether);
    }

    function test_withdraw_revertsForNonOwner() public {
        vm.deal(address(receiver), 1 ether);
        vm.prank(rando);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.withdraw(0.1 ether);
    }

    // ── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_updateVRS_forwardsAnyScore(uint8 score) public {
        vm.prank(proxy);
        receiver.updateVRS(address(0), score);
        assertEq(oracle.lastScore(), score);
    }

    function testFuzz_updateVRS_onlyProxy(address caller) public {
        vm.assume(caller != proxy);
        vm.prank(caller);
        vm.expectRevert(VRSCallbackReceiver.Unauthorized.selector);
        receiver.updateVRS(address(0), 50);
    }

    // allow this test contract to receive ETH from withdraw
    receive() external payable {}
}
