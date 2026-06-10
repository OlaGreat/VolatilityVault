// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LPPositionNFT} from "../src/LPPositionNFT.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract LPPositionNFTTest is Test {
    LPPositionNFT nft;

    address hook  = makeAddr("hook");
    address lpA   = makeAddr("lpA");
    address lpB   = makeAddr("lpB");
    address poolA = makeAddr("poolA");
    address poolB = makeAddr("poolB");
    address rando = makeAddr("rando");

    function setUp() public {
        nft = new LPPositionNFT(hook);
    }

    function _mint(address lp, address pool, uint256 liq) internal returns (uint256) {
        vm.prank(hook);
        return nft.mint(lp, pool, 1200, 500, LPPositionNFT.PayoutPreference.DAILY, liq);
    }

    // ── Constructor ────────────────────────────────────────────────────────────

    function test_constructor_setsHook() public view {
        assertEq(nft.hook(), hook);
    }

    function test_constructor_name() public view {
        assertEq(nft.name(), "VolatilityVault LP Position");
    }

    function test_constructor_symbol() public view {
        assertEq(nft.symbol(), "VV-LP");
    }

    // ── mint: happy path ───────────────────────────────────────────────────────

    function test_mint_firstTokenIdIsOne() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(id, 1);
    }

    function test_mint_secondTokenIdIsTwo() public {
        _mint(lpA, poolA, 100e18);
        uint256 id2 = _mint(lpB, poolA, 50e18);
        assertEq(id2, 2);
    }

    function test_mint_ownerIsLp() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.ownerOf(id), lpA);
    }

    function test_mint_balanceIncrements() public {
        _mint(lpA, poolA, 100e18);
        assertEq(nft.balanceOf(lpA), 1);
    }

    function test_mint_setsTokenActive() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertTrue(nft.tokenActive(id));
    }

    function test_mint_setsLpPoolToken() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.lpPoolToken(lpA, poolA), id);
    }

    function test_mint_storesIntentTargetAPY() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        LPPositionNFT.LPIntent memory intent = nft.getIntent(id);
        assertEq(intent.targetAPY, 1200);
    }

    function test_mint_storesIntentMaxIL() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.getIntent(id).maxILToleranceBps, 500);
    }

    function test_mint_storesIntentPayout() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(uint8(nft.getIntent(id).payout), uint8(LPPositionNFT.PayoutPreference.DAILY));
    }

    function test_mint_storesIntentPool() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.getIntent(id).pool, poolA);
    }

    function test_mint_storesIntentLiquidity() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.getIntent(id).liquidity, 100e18);
    }

    function test_mint_storesDepositTimestamp() public {
        vm.warp(123456);
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.getIntent(id).depositTimestamp, 123456);
    }

    function test_mint_emitsPositionMinted() public {
        vm.expectEmit(true, true, true, false);
        emit LPPositionNFT.PositionMinted(1, lpA, poolA);
        _mint(lpA, poolA, 100e18);
    }

    // ── mint: update existing position ─────────────────────────────────────────

    function test_mint_existingPosition_returnsSameTokenId() public {
        uint256 id1 = _mint(lpA, poolA, 100e18);
        uint256 id2 = _mint(lpA, poolA, 50e18);
        assertEq(id1, id2);
    }

    function test_mint_existingPosition_accumulatesLiquidity() public {
        _mint(lpA, poolA, 100e18);
        uint256 id = _mint(lpA, poolA, 50e18);
        assertEq(nft.getIntent(id).liquidity, 150e18);
    }

    function test_mint_existingPosition_doesNotIncreaseBalance() public {
        _mint(lpA, poolA, 100e18);
        _mint(lpA, poolA, 50e18);
        assertEq(nft.balanceOf(lpA), 1);
    }

    function test_mint_existingPosition_updatesIntent() public {
        _mint(lpA, poolA, 100e18);
        vm.prank(hook);
        uint256 id = nft.mint(lpA, poolA, 9999, 800, LPPositionNFT.PayoutPreference.REINVEST, 10e18);
        assertEq(nft.getIntent(id).targetAPY, 9999);
        assertEq(uint8(nft.getIntent(id).payout), uint8(LPPositionNFT.PayoutPreference.REINVEST));
    }

    function test_mint_sameLpDifferentPool_newToken() public {
        _mint(lpA, poolA, 100e18);
        uint256 id2 = _mint(lpA, poolB, 100e18);
        assertEq(id2, 2);
        assertEq(nft.balanceOf(lpA), 2);
    }

    // ── mint: access control ───────────────────────────────────────────────────

    function test_mint_revertsForNonHook() public {
        vm.prank(rando);
        vm.expectRevert(LPPositionNFT.Unauthorized.selector);
        nft.mint(lpA, poolA, 1200, 500, LPPositionNFT.PayoutPreference.DAILY, 100e18);
    }

    // ── burn: happy path ───────────────────────────────────────────────────────

    function test_burn_setsTokenInactive() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        vm.prank(hook);
        nft.burn(lpA, poolA);
        assertFalse(nft.tokenActive(id));
    }

    function test_burn_clearsLpPoolToken() public {
        _mint(lpA, poolA, 100e18);
        vm.prank(hook);
        nft.burn(lpA, poolA);
        assertEq(nft.lpPoolToken(lpA, poolA), 0);
    }

    function test_burn_destroysToken() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        vm.prank(hook);
        nft.burn(lpA, poolA);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
        nft.ownerOf(id);
    }

    function test_burn_emitsPositionBurned() public {
        _mint(lpA, poolA, 100e18);
        vm.expectEmit(true, true, false, false);
        emit LPPositionNFT.PositionBurned(1, lpA);
        vm.prank(hook);
        nft.burn(lpA, poolA);
    }

    // ── burn: unhappy path ─────────────────────────────────────────────────────

    function test_burn_revertsIfNoPosition() public {
        vm.prank(hook);
        vm.expectRevert(LPPositionNFT.TokenNotActive.selector);
        nft.burn(lpA, poolA);
    }

    function test_burn_revertsIfAlreadyBurned() public {
        _mint(lpA, poolA, 100e18);
        vm.startPrank(hook);
        nft.burn(lpA, poolA);
        vm.expectRevert(LPPositionNFT.TokenNotActive.selector);
        nft.burn(lpA, poolA);
        vm.stopPrank();
    }

    function test_burn_revertsForNonHook() public {
        _mint(lpA, poolA, 100e18);
        vm.prank(rando);
        vm.expectRevert(LPPositionNFT.Unauthorized.selector);
        nft.burn(lpA, poolA);
    }

    // ── re-mint after burn ─────────────────────────────────────────────────────

    function test_mint_afterBurn_createsNewToken() public {
        _mint(lpA, poolA, 100e18);   // id 1
        vm.prank(hook);
        nft.burn(lpA, poolA);
        uint256 id2 = _mint(lpA, poolA, 100e18); // id 2 (1 is dead)
        assertEq(id2, 2);
        assertTrue(nft.tokenActive(id2));
    }

    // ── views ──────────────────────────────────────────────────────────────────

    function test_getTokenForLP_returnsZeroWhenNone() public view {
        assertEq(nft.getTokenForLP(lpA, poolA), 0);
    }

    function test_getTokenForLP_returnsId() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        assertEq(nft.getTokenForLP(lpA, poolA), id);
    }

    // ── setHook ──────────────────────────────────────────────────────────────

    function test_setHook_updatesHook() public {
        address newHook = makeAddr("newHook");
        vm.prank(hook);
        nft.setHook(newHook);
        assertEq(nft.hook(), newHook);
    }

    function test_setHook_revertsForNonHook() public {
        vm.prank(rando);
        vm.expectRevert(LPPositionNFT.Unauthorized.selector);
        nft.setHook(rando);
    }

    function test_setHook_newHookCanMint() public {
        address newHook = makeAddr("newHook");
        vm.prank(hook);
        nft.setHook(newHook);
        vm.prank(newHook);
        uint256 id = nft.mint(lpA, poolA, 1200, 500, LPPositionNFT.PayoutPreference.DAILY, 100e18);
        assertEq(nft.ownerOf(id), lpA);
    }

    // ── ERC721 transferability ──────────────────────────────────────────────────

    function test_position_isTransferable() public {
        uint256 id = _mint(lpA, poolA, 100e18);
        vm.prank(lpA);
        nft.transferFrom(lpA, lpB, id);
        assertEq(nft.ownerOf(id), lpB);
    }

    // ── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_mint_storesAnyIntent(uint256 apy, uint256 il, uint8 payoutRaw, uint256 liq) public {
        payoutRaw = uint8(bound(payoutRaw, 0, 2));
        vm.prank(hook);
        uint256 id = nft.mint(lpA, poolA, apy, il, LPPositionNFT.PayoutPreference(payoutRaw), liq);
        LPPositionNFT.LPIntent memory intent = nft.getIntent(id);
        assertEq(intent.targetAPY, apy);
        assertEq(intent.maxILToleranceBps, il);
        assertEq(uint8(intent.payout), payoutRaw);
        assertEq(intent.liquidity, liq);
    }

    function testFuzz_mint_onlyHook(address caller) public {
        vm.assume(caller != hook);
        vm.prank(caller);
        vm.expectRevert(LPPositionNFT.Unauthorized.selector);
        nft.mint(lpA, poolA, 1200, 500, LPPositionNFT.PayoutPreference.DAILY, 100e18);
    }
}
