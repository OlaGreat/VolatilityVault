// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VRSOracle} from "../src/VRSOracle.sol";

contract VRSOracleTest is Test {
    VRSOracle oracle;
    address owner   = address(this);
    address updater = makeAddr("updater");
    address rando   = makeAddr("rando");

    function setUp() public {
        oracle = new VRSOracle(updater);
    }

    // ── Initial state ────────────────────────────────────────────────────────

    function test_initialState() public view {
        assertEq(oracle.vrs(), 0);
        assertEq(oracle.owner(), owner);
        assertEq(oracle.authorizedUpdater(), updater);
        assertEq(oracle.getRiskLevel(), "CALM");
    }

    // ── updateVRS ────────────────────────────────────────────────────────────

    function test_updater_canUpdateVRS() public {
        vm.prank(updater);
        oracle.updateVRS(75);
        assertEq(oracle.vrs(), 75);
        assertEq(oracle.getRiskLevel(), "STORM");
    }

    function test_owner_canUpdateVRS() public {
        oracle.updateVRS(90);
        assertEq(oracle.vrs(), 90);
        assertEq(oracle.getRiskLevel(), "HURRICANE");
    }

    function test_rando_cannotUpdateVRS() public {
        vm.prank(rando);
        vm.expectRevert(VRSOracle.Unauthorized.selector);
        oracle.updateVRS(50);
    }

    function test_cannotSetScoreAbove100() public {
        vm.prank(updater);
        vm.expectRevert(VRSOracle.InvalidScore.selector);
        oracle.updateVRS(101);
    }

    function test_updateVRS_emitsEvent() public {
        vm.prank(updater);
        vm.expectEmit(true, false, false, true);
        emit VRSOracle.VRSUpdated(55, block.timestamp);
        oracle.updateVRS(55);
    }

    // ── getFee tiers ─────────────────────────────────────────────────────────

    function test_fee_calm() public {
        oracle.updateVRS(0);
        assertEq(oracle.getFee(), 500);

        oracle.updateVRS(30);
        assertEq(oracle.getFee(), 500);
    }

    function test_fee_cloudy() public {
        oracle.updateVRS(31);
        assertEq(oracle.getFee(), 1_500);

        oracle.updateVRS(60);
        assertEq(oracle.getFee(), 1_500);
    }

    function test_fee_storm() public {
        oracle.updateVRS(61);
        assertEq(oracle.getFee(), 3_000);

        oracle.updateVRS(80);
        assertEq(oracle.getFee(), 3_000);
    }

    function test_fee_hurricane() public {
        oracle.updateVRS(81);
        assertEq(oracle.getFee(), 5_000);

        oracle.updateVRS(100);
        assertEq(oracle.getFee(), 5_000);
    }

    // ── isStorm ──────────────────────────────────────────────────────────────

    function test_isStorm_falseBelow61() public {
        oracle.updateVRS(60);
        assertFalse(oracle.isStorm());
    }

    function test_isStorm_trueAbove60() public {
        oracle.updateVRS(61);
        assertTrue(oracle.isStorm());
    }

    // ── admin ────────────────────────────────────────────────────────────────

    function test_setAuthorizedUpdater() public {
        address newUpdater = makeAddr("newUpdater");
        oracle.setAuthorizedUpdater(newUpdater);
        assertEq(oracle.authorizedUpdater(), newUpdater);

        vm.prank(newUpdater);
        oracle.updateVRS(42);
        assertEq(oracle.vrs(), 42);
    }

    function test_rando_cannotSetUpdater() public {
        vm.prank(rando);
        vm.expectRevert(VRSOracle.Unauthorized.selector);
        oracle.setAuthorizedUpdater(rando);
    }

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        oracle.transferOwnership(newOwner);
        assertEq(oracle.owner(), newOwner);
    }

    // ── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_updateVRS_validScores(uint8 score) public {
        vm.assume(score <= 100);
        vm.prank(updater);
        oracle.updateVRS(score);
        assertEq(oracle.vrs(), score);
    }

    function testFuzz_updateVRS_invalidScores(uint8 score) public {
        vm.assume(score > 100);
        vm.prank(updater);
        vm.expectRevert(VRSOracle.InvalidScore.selector);
        oracle.updateVRS(score);
    }

    // ── getRiskLevel — every tier + boundaries ─────────────────────────────────

    function test_riskLevel_calm_zero()       public { oracle.updateVRS(0);   assertEq(oracle.getRiskLevel(), "CALM"); }
    function test_riskLevel_calm_boundary()   public { oracle.updateVRS(30);  assertEq(oracle.getRiskLevel(), "CALM"); }
    function test_riskLevel_cloudy_lower()    public { oracle.updateVRS(31);  assertEq(oracle.getRiskLevel(), "CLOUDY"); }
    function test_riskLevel_cloudy_boundary() public { oracle.updateVRS(60);  assertEq(oracle.getRiskLevel(), "CLOUDY"); }
    function test_riskLevel_storm_lower()     public { oracle.updateVRS(61);  assertEq(oracle.getRiskLevel(), "STORM"); }
    function test_riskLevel_storm_boundary()  public { oracle.updateVRS(80);  assertEq(oracle.getRiskLevel(), "STORM"); }
    function test_riskLevel_hurricane_lower() public { oracle.updateVRS(81);  assertEq(oracle.getRiskLevel(), "HURRICANE"); }
    function test_riskLevel_hurricane_max()   public { oracle.updateVRS(100); assertEq(oracle.getRiskLevel(), "HURRICANE"); }

    // ── getFee — exact tier boundaries ─────────────────────────────────────────

    function test_fee_boundary_30_31() public {
        oracle.updateVRS(30); assertEq(oracle.getFee(), 500);
        oracle.updateVRS(31); assertEq(oracle.getFee(), 1_500);
    }

    function test_fee_boundary_60_61() public {
        oracle.updateVRS(60); assertEq(oracle.getFee(), 1_500);
        oracle.updateVRS(61); assertEq(oracle.getFee(), 3_000);
    }

    function test_fee_boundary_80_81() public {
        oracle.updateVRS(80); assertEq(oracle.getFee(), 3_000);
        oracle.updateVRS(81); assertEq(oracle.getFee(), 5_000);
    }

    // ── lastUpdated ────────────────────────────────────────────────────────────

    function test_lastUpdated_setOnUpdate() public {
        vm.warp(999_999);
        oracle.updateVRS(50);
        assertEq(oracle.lastUpdated(), 999_999);
    }

    // ── fuzz: fee mapping is correct & bounded for every valid score ───────────

    function testFuzz_getFee_matchesTier(uint8 score) public {
        score = uint8(bound(score, 0, 100));
        oracle.updateVRS(score);
        uint24 fee = oracle.getFee();
        if (score <= 30)      assertEq(fee, 500);
        else if (score <= 60) assertEq(fee, 1_500);
        else if (score <= 80) assertEq(fee, 3_000);
        else                  assertEq(fee, 5_000);
    }

    function testFuzz_isStorm_matchesThreshold(uint8 score) public {
        score = uint8(bound(score, 0, 100));
        oracle.updateVRS(score);
        assertEq(oracle.isStorm(), score > 60);
    }
}
