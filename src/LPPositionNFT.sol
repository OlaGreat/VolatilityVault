// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title LPPositionNFT
/// @notice ERC-721 token minted when an LP deposits into a VolatilityVault pool.
///         Each token stores the LP's intent on-chain — target APY, IL tolerance,
///         and payout preference — making positions composable and transferable.
contract LPPositionNFT is ERC721 {

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    enum PayoutPreference { DAILY, LUMP_SUM, REINVEST }

    struct LPIntent {
        uint256 targetAPY;          // basis points, e.g. 1200 = 12%
        uint256 maxILToleranceBps;  // basis points, e.g. 500 = 5%
        PayoutPreference payout;
        uint256 depositTimestamp;
        address pool;               // which pool this position belongs to
        uint256 liquidity;          // liquidity amount at deposit
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    address public hook;
    uint256 private _nextTokenId;

    mapping(uint256 => LPIntent) public intents;

    // Track which tokenId belongs to which LP in which pool.
    // One LP can have one active NFT per pool (simplification for hackathon).
    mapping(address => mapping(address => uint256)) public lpPoolToken; // lp → pool → tokenId
    mapping(uint256 => bool) public tokenActive;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event PositionMinted(uint256 indexed tokenId, address indexed lp, address indexed pool);
    event PositionBurned(uint256 indexed tokenId, address indexed lp);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error Unauthorized();
    error PositionAlreadyExists();
    error TokenNotActive();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address _hook) ERC721("VolatilityVault LP Position", "VV-LP") {
        hook = _hook;
        _nextTokenId = 1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyHook() {
        if (msg.sender != hook) revert Unauthorized();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook-facing functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Mint a position NFT for an LP when they add liquidity.
    ///         If the LP already has a position in this pool, the intent is updated.
    function mint(
        address lp,
        address pool,
        uint256 targetAPY,
        uint256 maxILToleranceBps,
        PayoutPreference payout,
        uint256 liquidity
    ) external onlyHook returns (uint256 tokenId) {
        uint256 existing = lpPoolToken[lp][pool];

        if (existing != 0 && tokenActive[existing]) {
            // Update existing position's liquidity and intent
            LPIntent storage intent = intents[existing];
            intent.liquidity        += liquidity;
            intent.targetAPY        = targetAPY;
            intent.maxILToleranceBps = maxILToleranceBps;
            intent.payout           = payout;
            return existing;
        }

        tokenId = _nextTokenId++;
        _safeMint(lp, tokenId);

        intents[tokenId] = LPIntent({
            targetAPY:         targetAPY,
            maxILToleranceBps: maxILToleranceBps,
            payout:            payout,
            depositTimestamp:  block.timestamp,
            pool:              pool,
            liquidity:         liquidity
        });

        lpPoolToken[lp][pool] = tokenId;
        tokenActive[tokenId]  = true;

        emit PositionMinted(tokenId, lp, pool);
    }

    /// @notice Burn a position NFT when an LP fully removes liquidity.
    function burn(address lp, address pool) external onlyHook {
        uint256 tokenId = lpPoolToken[lp][pool];
        if (tokenId == 0 || !tokenActive[tokenId]) revert TokenNotActive();

        tokenActive[tokenId] = false;
        delete lpPoolToken[lp][pool];
        _burn(tokenId);

        emit PositionBurned(tokenId, lp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function getIntent(uint256 tokenId) external view returns (LPIntent memory) {
        return intents[tokenId];
    }

    function getTokenForLP(address lp, address pool) external view returns (uint256) {
        return lpPoolToken[lp][pool];
    }

    function setHook(address _hook) external {
        if (msg.sender != hook) revert Unauthorized();
        hook = _hook;
    }
}
