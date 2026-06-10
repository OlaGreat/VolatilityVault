// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldBuffer} from "../src/YieldBuffer.sol";
import {MockYieldRouter} from "../src/mocks/MockYieldRouter.sol";
import {IYieldRouter} from "../src/interfaces/IYieldRouter.sol";

contract MockToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract YieldBufferTest is Test {
    MockToken       token0;
    MockToken       token1;
    MockYieldRouter router;
    YieldBuffer     buffer;

    address hook    = makeAddr("hook");
    address trigger = makeAddr("trigger");
    address lpA     = makeAddr("lpA");
    address lpB     = makeAddr("lpB");

    uint256 constant LP_A_LIQ = 1_000e18;
    uint256 constant LP_B_LIQ = 500e18;
    uint256 constant FEES0    = 100e18;
    uint256 constant FEES1    = 60e18;

    function setUp() public {
        token0 = new MockToken("Token0", "TK0");
        token1 = new MockToken("Token1", "TK1");
        router = new MockYieldRouter();
        buffer = new YieldBuffer(token0, token1, hook, trigger, IYieldRouter(address(router)));

        // Fund the router so it can pay yield on withdraw.
        token0.mint(address(router), 1_000_000e18);
        token1.mint(address(router), 1_000_000e18);
    }

    /// @dev Simulate the hook taking a fee: tokens arrive in the buffer (via PoolManager.take
    ///      in production), then the hook records them.
    function _accrue(uint256 amount0, uint256 amount1) internal {
        if (amount0 > 0) token0.mint(address(buffer), amount0);
        if (amount1 > 0) token1.mint(address(buffer), amount1);
        vm.prank(hook);
        buffer.recordFees(amount0, amount1);
    }

    function _epoch(uint256 id) internal view returns (
        uint256 totalFees0, uint256 totalFees1, uint256 totalYield0, uint256 totalYield1,
        uint256 totalLiquidity, uint256 distributedAt, bool isActive, bool isDistributed, bool isDeployed
    ) {
        return buffer.epochs(id);
    }

    // ── Initial state ──────────────────────────────────────────────────────────

    function test_initialState() public view {
        assertEq(buffer.currentEpoch(), 0);
        assertEq(address(buffer.asset0()), address(token0));
        assertEq(address(buffer.asset1()), address(token1));
        assertEq(buffer.hook(), hook);
        (,,,,,, bool isActive, bool isDistributed,) = _epoch(0);
        assertTrue(isActive);
        assertFalse(isDistributed);
    }

    // ── registerLP ───────────────────────────────────────────────────────────

    function test_registerLP_storesLiquidity() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        assertEq(buffer.lpLiquidity(lpA, 0), LP_A_LIQ);
        (,,,, uint256 totalLiq,,,,) = _epoch(0);
        assertEq(totalLiq, LP_A_LIQ);
    }

    function test_registerLP_onlyHook() public {
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
    }

    // ── recordFees ─────────────────────────────────────────────────────────────

    function test_recordFees_bothTokens() public {
        _accrue(FEES0, FEES1);
        (uint256 f0, uint256 f1,,,,,,,) = _epoch(0);
        assertEq(f0, FEES0);
        assertEq(f1, FEES1);
        assertEq(token0.balanceOf(address(buffer)), FEES0);
        assertEq(token1.balanceOf(address(buffer)), FEES1);
    }

    function test_recordFees_onlyHook() public {
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.recordFees(FEES0, FEES1);
    }

    // ── deployToYield ────────────────────────────────────────────────────────

    function test_deployToYield_movesBothTokens() public {
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.deployToYield();
        assertEq(router.balanceOf(address(token0)), FEES0);
        assertEq(router.balanceOf(address(token1)), FEES1);
    }

    function test_deployToYield_onlyTrigger() public {
        _accrue(FEES0, FEES1);
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.deployToYield();
    }

    function test_deployToYield_revertsIfNoFees() public {
        vm.prank(trigger);
        vm.expectRevert(YieldBuffer.NothingToDistribute.selector);
        buffer.deployToYield();
    }

    // ── triggerDistribution ────────────────────────────────────────────────────

    function test_triggerDistribution_opensNextEpoch() public {
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();
        assertEq(buffer.currentEpoch(), 1);
        (,,,,,, bool wasActive, bool isDistributed,) = _epoch(0);
        assertFalse(wasActive);
        assertTrue(isDistributed);
    }

    function test_triggerDistribution_withYield() public {
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.deployToYield();
        vm.warp(block.timestamp + 365 days);
        vm.prank(trigger);
        buffer.triggerDistribution();
        (,, uint256 y0, uint256 y1,,,,,) = _epoch(0);
        assertGt(y0, 0);
        assertGt(y1, 0);
    }

    // ── claim ────────────────────────────────────────────────────────────────

    function test_claim_singleLP_getsAllFees() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.prank(lpA);
        buffer.claim(0);
        assertEq(token0.balanceOf(lpA), FEES0);
        assertEq(token1.balanceOf(lpA), FEES1);
    }

    function test_claim_twoLPs_proportionalBothTokens() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);   // 1000
        buffer.registerLP(lpB, LP_B_LIQ, YieldBuffer.PayoutPreference.LUMP_SUM); // 500
        vm.stopPrank();
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.prank(lpA); buffer.claim(0);
        vm.prank(lpB); buffer.claim(0);

        // lpA: 2/3, lpB: 1/3
        assertApproxEqAbs(token0.balanceOf(lpA), (FEES0 * 2) / 3, 1);
        assertApproxEqAbs(token1.balanceOf(lpA), (FEES1 * 2) / 3, 1);
        assertApproxEqAbs(token0.balanceOf(lpB), FEES0 / 3, 1);
        assertApproxEqAbs(token1.balanceOf(lpB), FEES1 / 3, 1);
    }

    function test_claim_cannotClaimTwice() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.prank(lpA); buffer.claim(0);
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.AlreadyClaimed.selector);
        buffer.claim(0);
    }

    function test_claim_cannotClaimWithoutShare() public {
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.NoShareInEpoch.selector);
        buffer.claim(0);
    }

    function test_claim_cannotClaimBeforeDistribution() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.EpochNotDistributed.selector);
        buffer.claim(0);
    }

    // ── previewClaim ───────────────────────────────────────────────────────────

    function test_previewClaim_returnsBothTokens() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();

        (uint256 s0, uint256 s1) = buffer.previewClaim(lpA, 0);
        assertEq(s0, FEES0);
        assertEq(s1, FEES1);
    }

    function test_previewClaim_zeroAfterClaim() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();
        vm.prank(lpA); buffer.claim(0);

        (uint256 s0, uint256 s1) = buffer.previewClaim(lpA, 0);
        assertEq(s0, 0);
        assertEq(s1, 0);
    }

    // ── multi-epoch ──────────────────────────────────────────────────────────

    function test_multiEpoch_claimBoth() public {
        // Epoch 0
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();

        // Epoch 1
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0 * 2, FEES1 * 2);
        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.startPrank(lpA);
        buffer.claim(0);
        buffer.claim(1);
        vm.stopPrank();

        assertEq(token0.balanceOf(lpA), FEES0 + FEES0 * 2);
        assertEq(token1.balanceOf(lpA), FEES1 + FEES1 * 2);
    }

    // ── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_claim_proportional(uint128 liqA, uint128 liqB, uint128 fees0, uint128 fees1) public {
        vm.assume(liqA > 0 && liqB > 0 && fees0 > 0 && fees1 > 0);
        vm.assume(uint256(liqA) + liqB <= type(uint128).max);

        vm.startPrank(hook);
        buffer.registerLP(lpA, liqA, YieldBuffer.PayoutPreference.DAILY);
        buffer.registerLP(lpB, liqB, YieldBuffer.PayoutPreference.DAILY);
        vm.stopPrank();
        _accrue(fees0, fees1);
        vm.prank(trigger);
        buffer.triggerDistribution();

        uint256 total = uint256(liqA) + liqB;
        vm.prank(lpA); buffer.claim(0);
        vm.prank(lpB); buffer.claim(0);

        assertApproxEqAbs(token0.balanceOf(lpA), (uint256(fees0) * liqA) / total, 1);
        assertApproxEqAbs(token1.balanceOf(lpB), (uint256(fees1) * liqB) / total, 1);
    }

    // ── deregisterLP ───────────────────────────────────────────────────────────

    function test_deregisterLP_reducesLiquidity() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.deregisterLP(lpA, LP_A_LIQ / 2);
        vm.stopPrank();
        assertEq(buffer.lpLiquidity(lpA, 0), LP_A_LIQ / 2);
    }

    function test_deregisterLP_capsAtZero() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.deregisterLP(lpA, LP_A_LIQ * 100); // more than held
        vm.stopPrank();
        assertEq(buffer.lpLiquidity(lpA, 0), 0);
    }

    function test_deregisterLP_onlyHook() public {
        vm.prank(rando());
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.deregisterLP(lpA, 1);
    }

    function rando() internal returns (address) { return makeAddr("rando"); }

    // ── deployToYield: error branches ──────────────────────────────────────────

    function test_deployToYield_cannotDeployTwice() public {
        _accrue(FEES0, FEES1);
        vm.startPrank(trigger);
        buffer.deployToYield();
        vm.expectRevert(YieldBuffer.AlreadyDeployed.selector);
        buffer.deployToYield();
        vm.stopPrank();
    }

    function test_deployToYield_singleToken0Only() public {
        _accrue(FEES0, 0);
        vm.prank(trigger);
        buffer.deployToYield();
        assertEq(router.balanceOf(address(token0)), FEES0);
        assertEq(router.balanceOf(address(token1)), 0);
    }

    function test_deployToYield_ownerCanTrigger() public {
        // owner (this test contract is NOT owner; deployer of buffer is this contract)
        _accrue(FEES0, FEES1);
        // owner bypass: the buffer owner is address(this)
        buffer.deployToYield();
        assertEq(router.balanceOf(address(token0)), FEES0);
    }

    // ── triggerDistribution: error branches ────────────────────────────────────

    function test_triggerDistribution_marksEpochDistributed() public {
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.triggerDistribution();
        (,,,,,, bool isActive, bool isDistributed,) = _epoch(0);
        assertFalse(isActive);
        assertTrue(isDistributed);
    }

    function test_triggerDistribution_onlyTrigger() public {
        _accrue(FEES0, FEES1);
        vm.prank(makeAddr("notTrigger"));
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.triggerDistribution();
    }

    // ── claim with yield ─────────────────────────────────────────────────────────

    function test_claim_includesYield() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        _accrue(FEES0, FEES1);
        vm.prank(trigger);
        buffer.deployToYield();
        vm.warp(block.timestamp + 365 days);
        vm.prank(trigger);
        buffer.triggerDistribution();

        (uint256 s0,) = buffer.previewClaim(lpA, 0);
        assertGt(s0, FEES0); // includes yield on top of fees
    }

    // ── admin setters ────────────────────────────────────────────────────────────

    function test_setHook_updates() public {
        address nh = makeAddr("nh");
        buffer.setHook(nh);
        assertEq(buffer.hook(), nh);
    }

    function test_setHook_onlyOwner() public {
        vm.prank(makeAddr("x"));
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.setHook(makeAddr("x"));
    }

    function test_setAuthorizedTrigger_updates() public {
        address nt = makeAddr("nt");
        buffer.setAuthorizedTrigger(nt);
        assertEq(buffer.authorizedTrigger(), nt);
    }

    function test_setAuthorizedTrigger_onlyOwner() public {
        vm.prank(makeAddr("x"));
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.setAuthorizedTrigger(makeAddr("x"));
    }

    function test_setYieldRouter_updates() public {
        address nr = makeAddr("nr");
        buffer.setYieldRouter(nr);
        assertEq(address(buffer.yieldRouter()), nr);
    }

    function test_setYieldRouter_onlyOwner() public {
        vm.prank(makeAddr("x"));
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.setYieldRouter(makeAddr("x"));
    }
}
