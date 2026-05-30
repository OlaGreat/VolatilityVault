// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldBuffer} from "../src/YieldBuffer.sol";
import {MockYieldRouter} from "../src/mocks/MockYieldRouter.sol";
import {IYieldRouter} from "../src/interfaces/IYieldRouter.sol";

// ── Minimal ERC-20 for testing ────────────────────────────────────────────────
contract MockToken is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract YieldBufferTest is Test {
    MockToken        token;
    MockYieldRouter  router;
    YieldBuffer      buffer;

    address owner   = address(this);
    address hook    = makeAddr("hook");
    address trigger = makeAddr("trigger");
    address lpA     = makeAddr("lpA");
    address lpB     = makeAddr("lpB");

    uint256 constant LP_A_LIQ = 1_000e18;
    uint256 constant LP_B_LIQ = 500e18;
    uint256 constant FEES     = 100e18;

    function setUp() public {
        token  = new MockToken();
        router = new MockYieldRouter();
        buffer = new YieldBuffer(token, hook, trigger, IYieldRouter(address(router)));

        // Fund router so it can pay yield
        token.mint(address(router), 10_000e18);

        // Fund hook so it can send fees
        token.mint(hook, 10_000e18);
        vm.prank(hook);
        token.approve(address(buffer), type(uint256).max);
    }

    // ── Initial state ────────────────────────────────────────────────────────

    function test_initialState() public view {
        assertEq(buffer.currentEpoch(), 0);
        assertEq(address(buffer.asset()), address(token));
        assertEq(buffer.hook(), hook);
        assertEq(buffer.authorizedTrigger(), trigger);
        (,,,, bool isActive, bool isDistributed,) = buffer.epochs(0);
        assertTrue(isActive);
        assertFalse(isDistributed);
    }

    // ── registerLP ───────────────────────────────────────────────────────────

    function test_registerLP_storesLiquidity() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);

        assertEq(buffer.lpLiquidity(lpA, 0), LP_A_LIQ);
        (,, uint256 totalLiq,,,,) = _epochData(0);
        assertEq(totalLiq, LP_A_LIQ);
    }

    function test_registerLP_onlyHook() public {
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
    }

    function test_registerLP_accumulatesMultipleLPs() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.registerLP(lpB, LP_B_LIQ, YieldBuffer.PayoutPreference.LUMP_SUM);
        vm.stopPrank();

        (,, uint256 totalLiq,,,,) = _epochData(0);
        assertEq(totalLiq, LP_A_LIQ + LP_B_LIQ);
    }

    // ── deregisterLP ─────────────────────────────────────────────────────────

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
        buffer.deregisterLP(lpA, LP_A_LIQ * 10); // more than registered
        vm.stopPrank();

        assertEq(buffer.lpLiquidity(lpA, 0), 0);
    }

    // ── accrueFees ───────────────────────────────────────────────────────────

    function test_accrueFees_transfersTokens() public {
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);

        vm.prank(hook);
        buffer.accrueFees(FEES);

        assertEq(token.balanceOf(address(buffer)), FEES);
        (uint256 totalFees,,,,,,) = _epochData(0);
        assertEq(totalFees, FEES);
    }

    function test_accrueFees_onlyHook() public {
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.accrueFees(FEES);
    }

    // ── deployToYield ────────────────────────────────────────────────────────

    function test_deployToYield_movesTokensToRouter() public {
        _setupEpochWithFees();

        vm.prank(trigger);
        buffer.deployToYield();

        assertEq(token.balanceOf(address(buffer)), 0);
        assertEq(router.balanceOf(address(token)), FEES);
        (,,,,, , bool isDeployed) = _epochData(0);
        // Note: isDeployed is the 7th field
    }

    function test_deployToYield_onlyTrigger() public {
        _setupEpochWithFees();

        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.deployToYield();
    }

    function test_deployToYield_cannotDeployTwice() public {
        _setupEpochWithFees();

        vm.prank(trigger);
        buffer.deployToYield();

        vm.prank(trigger);
        vm.expectRevert(YieldBuffer.AlreadyDeployed.selector);
        buffer.deployToYield();
    }

    function test_deployToYield_revertsIfNoFees() public {
        vm.prank(trigger);
        vm.expectRevert(YieldBuffer.NothingToDistribute.selector);
        buffer.deployToYield();
    }

    // ── triggerDistribution ──────────────────────────────────────────────────

    function test_triggerDistribution_closesEpochAndOpensNext() public {
        _setupEpochWithFees();

        vm.prank(trigger);
        buffer.triggerDistribution();

        assertEq(buffer.currentEpoch(), 1);
        (, , , , bool wasActive, bool isDistributed,) = _epochData(0);
        assertFalse(wasActive);
        assertTrue(isDistributed);
        (, , , , bool newActive,,) = _epochData(1);
        assertTrue(newActive);
    }

    function test_triggerDistribution_withYield() public {
        _setupEpochWithFees();

        vm.prank(trigger);
        buffer.deployToYield();

        // Advance time to accumulate yield
        vm.warp(block.timestamp + 365 days);

        vm.prank(trigger);
        buffer.triggerDistribution();

        (, uint256 yieldEarned,,,,,) = _epochData(0);
        assertGt(yieldEarned, 0);
    }

    function test_triggerDistribution_onlyTrigger() public {
        _setupEpochWithFees();
        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.Unauthorized.selector);
        buffer.triggerDistribution();
    }

    // ── claim ────────────────────────────────────────────────────────────────

    function test_claim_singleLP_getsAllFees() public {
        _setupEpochWithFees();
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);

        vm.prank(trigger);
        buffer.triggerDistribution();

        uint256 balBefore = token.balanceOf(lpA);
        vm.prank(lpA);
        buffer.claim(0);
        uint256 received = token.balanceOf(lpA) - balBefore;

        assertEq(received, FEES);
    }

    function test_claim_twoLPs_proportionalSplit() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);  // 1000
        buffer.registerLP(lpB, LP_B_LIQ, YieldBuffer.PayoutPreference.LUMP_SUM); // 500
        buffer.accrueFees(FEES); // 100 tokens total
        vm.stopPrank();

        vm.prank(trigger);
        buffer.triggerDistribution();

        uint256 balA = token.balanceOf(lpA);
        vm.prank(lpA);
        buffer.claim(0);
        uint256 receivedA = token.balanceOf(lpA) - balA;

        uint256 balB = token.balanceOf(lpB);
        vm.prank(lpB);
        buffer.claim(0);
        uint256 receivedB = token.balanceOf(lpB) - balB;

        // lpA has 2/3 of liquidity (1000/1500), lpB has 1/3 (500/1500)
        // Allow 1 wei rounding tolerance from integer division
        assertApproxEqAbs(receivedA, (FEES * LP_A_LIQ) / (LP_A_LIQ + LP_B_LIQ), 1);
        assertApproxEqAbs(receivedB, (FEES * LP_B_LIQ) / (LP_A_LIQ + LP_B_LIQ), 1);
        assertApproxEqAbs(receivedA + receivedB, FEES, 1);
    }

    function test_claim_cannotClaimTwice() public {
        _setupEpochWithFees();
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);

        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.prank(lpA);
        buffer.claim(0);

        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.AlreadyClaimed.selector);
        buffer.claim(0);
    }

    function test_claim_cannotClaimWithoutShare() public {
        _setupEpochWithFees();

        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.NoShareInEpoch.selector);
        buffer.claim(0);
    }

    function test_claim_cannotClaimBeforeDistribution() public {
        _setupEpochWithFees();
        vm.prank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);

        vm.prank(lpA);
        vm.expectRevert(YieldBuffer.EpochNotDistributed.selector);
        buffer.claim(0);
    }

    // ── previewClaim ─────────────────────────────────────────────────────────

    function test_previewClaim_returnsCorrectAmount() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.accrueFees(FEES);
        vm.stopPrank();

        vm.prank(trigger);
        buffer.triggerDistribution();

        uint256 preview = buffer.previewClaim(lpA, 0);
        assertEq(preview, FEES); // lpA is the only LP
    }

    function test_previewClaim_returnsZeroAfterClaim() public {
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.accrueFees(FEES);
        vm.stopPrank();

        vm.prank(trigger);
        buffer.triggerDistribution();

        vm.prank(lpA);
        buffer.claim(0);

        assertEq(buffer.previewClaim(lpA, 0), 0);
    }

    // ── multi-epoch ──────────────────────────────────────────────────────────

    function test_multiEpoch_claimFromBothEpochs() public {
        // Epoch 0
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.accrueFees(FEES);
        vm.stopPrank();

        vm.prank(trigger);
        buffer.triggerDistribution();

        // Epoch 1
        vm.startPrank(hook);
        buffer.registerLP(lpA, LP_A_LIQ, YieldBuffer.PayoutPreference.DAILY);
        buffer.accrueFees(FEES * 2);
        vm.stopPrank();

        vm.prank(trigger);
        buffer.triggerDistribution();

        // Claim from both
        uint256 balBefore = token.balanceOf(lpA);

        vm.startPrank(lpA);
        buffer.claim(0);
        buffer.claim(1);
        vm.stopPrank();

        uint256 totalReceived = token.balanceOf(lpA) - balBefore;
        assertEq(totalReceived, FEES + FEES * 2);
    }

    // ── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_claim_proportionalWithTwoLPs(uint128 liqA, uint128 liqB, uint128 fees) public {
        vm.assume(liqA > 0 && liqB > 0 && fees > 0);
        vm.assume(uint256(liqA) + liqB <= type(uint128).max);
        vm.assume(fees < 1_000_000e18);

        token.mint(hook, fees);
        vm.prank(hook);
        token.approve(address(buffer), type(uint256).max);

        vm.startPrank(hook);
        buffer.registerLP(lpA, liqA, YieldBuffer.PayoutPreference.DAILY);
        buffer.registerLP(lpB, liqB, YieldBuffer.PayoutPreference.DAILY);
        buffer.accrueFees(fees);
        vm.stopPrank();

        vm.prank(trigger);
        buffer.triggerDistribution();

        uint256 expectedA = (uint256(fees) * liqA) / (uint256(liqA) + liqB);
        uint256 expectedB = (uint256(fees) * liqB) / (uint256(liqA) + liqB);

        vm.prank(lpA); buffer.claim(0);
        vm.prank(lpB); buffer.claim(0);

        assertApproxEqAbs(token.balanceOf(lpA), expectedA, 1);
        assertApproxEqAbs(token.balanceOf(lpB), expectedB, 1);
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function _setupEpochWithFees() internal {
        vm.prank(hook);
        buffer.accrueFees(FEES);
    }

    function _epochData(uint256 epochId) internal view returns (
        uint256 totalFees,
        uint256 totalYieldEarned,
        uint256 totalLiquidity,
        uint256 distributedAt,
        bool isActive,
        bool isDistributed,
        bool isDeployed
    ) {
        return buffer.epochs(epochId);
    }
}
