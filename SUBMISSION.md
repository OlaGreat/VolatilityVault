# VolatilityVault — Hackathon Submission Description

> Copy the sections below into the Tally submission form.
> Submission link: https://tally.so/r/wLNXMl

---

## Project Name
VolatilityVault

---

## Tagline (One Sentence)
The first Uniswap V4 hook that sees the storm before it lands — taxing arbitrageurs predictively using cross-chain AI, then giving that money back to LPs with compounded yield.

---

## Project Description (Short — for summary fields)

VolatilityVault is a Uniswap V4 hook system that uses Reactive Network to monitor price gaps forming across multiple chains in real time, feeds that data into an AI volatility model, and dynamically raises swap fees before arbitrage bots hit the pool. The excess fees collected during volatile periods flow into a yield-bearing buffer (deployed to Aave/Morpho), then distributed back to LPs based on their personal payout preferences. LPs set their intent once — target APY, IL tolerance, payout style — and the system manages everything autonomously from there.

---

## Full Project Description (Detailed — for main description field)

### The Problem

Impermanent loss is the defining pain of being a liquidity provider. When ETH moves from $2,000 to $2,200, arbitrage bots rush into the pool, buy ETH at the stale price, pocket the profit, and leave the LP holding a rebalanced position worth less than a simple HODL. The LP pays the cost; the bot takes the gain.

Every existing solution to this problem reacts after the damage is done. Reactive hooks fire after the swap. Rebalancers adjust after the price has already moved. Insurance vaults compensate after the IL has been realized.

VolatilityVault takes a different approach: **charge the people causing the damage before they cause it.**

### The Core Insight

Arbitrage opportunities do not appear instantly. A price gap between Uniswap and Coinbase forms over multiple blocks. A large directional order builds up. A known bot wallet begins moving. These are detectable signals — if you are watching the right things, at the right time, across the right chains.

Reactive Network gives us that watchtower. An AI model turns those signals into a Volatility Risk Score. A Uniswap V4 hook reads that score and raises the fee before the swap executes. The arbitrageur still profits — but now they share a meaningful portion of that profit with the LPs they were extracting from.

### How It Works

**Layer 1 — The Watchtower (Reactive Network)**

A Reactive Smart Contract (RSC) monitors price feeds and on-chain activity across Ethereum, Arbitrum, Base, Polygon, and BSC simultaneously, every block. It watches for:
- Price gaps forming between Uniswap and external exchanges
- Volume acceleration (swap rate per block increasing rapidly)
- Large directional wallet movements from known bot addresses
- Cross-pool divergence (e.g. ETH/USDC and ETH/BTC spreading apart)

When signals appear, the RSC aggregates them into a feature vector and calls the AI oracle.

**Layer 2 — The AI Brain (Volatility Risk Score)**

The AI model — trained using Proximal Policy Optimization (PPO) on historical on-chain volatility patterns — outputs a single number every block: the **Volatility Risk Score (VRS)**, ranging from 0 to 100.

```
0–30   →  Calm       (normal trading conditions)
31–60  →  Cloudy     (mild directional pressure)
61–80  →  Storm      (significant arbitrage forming)
81–100 →  Hurricane  (large imminent price move)
```

The RSC pushes the latest VRS on-chain via a callback to the hook's oracle contract, keeping it current for every swap.

**Layer 3 — The Smart Fee Hook (Uniswap V4)**

The core hook reads the live VRS in `beforeSwap` and sets the fee dynamically:

```
VRS 0–30   →  0.05% fee  (competitive for regular traders)
VRS 31–60  →  0.15% fee
VRS 61–80  →  0.30% fee
VRS 81–100 →  0.50% fee  (captures meaningful arbitrage value)
```

Beyond dynamic fees, the hook implements **Toxic Order Flow Detection** — inspired by Angstrom (backed by Paradigm). When a swap is both large and highly directional during a high-VRS period, the hook identifies it as likely arbitrage and applies an additional surcharge, which is routed directly to LP wallets rather than the general fee pool. Ordinary user swaps are never affected — only bot-scale trades trigger this.

**Layer 4 — The Yield Buffer**

Storm-period fees do not get distributed immediately. Instant distribution creates JIT (just-in-time) liquidity attacks where bots deposit just before a large swap and withdraw immediately after, sniping the fees.

Instead, fees accumulated during high-VRS periods flow into a smart yield buffer (ERC-4626 vault). An AI agent autonomously deploys the buffer to the highest-yielding lending protocol available — currently Aave or Morpho — and rebalances when rates change. When the VRS drops back to calm, Reactive Network triggers a distribution event. LPs receive their proportional share of the storm fees plus all the yield earned while the buffer was deployed.

**Layer 5 — LP Intent & Personalization**

When depositing, each LP registers their intent on-chain via the hook:

- **Target APY** — what annual return they are aiming for
- **Max IL Tolerance** — at what point they want the system to alert or act
- **Payout Preference** — DAILY (frequent small payouts), LUMP_SUM (wait for big storm distributions), or REINVEST (auto-compound back into position)
- **Time Horizon** — how long they plan to stay in the pool

The system respects each LP's preferences individually with no ongoing manual action required.

### Why Reactive Network Is Central

Reactive Network is not a peripheral component in this system — it is the reason the predictive layer works. Without the ability to monitor multiple chains simultaneously and react to cross-chain events with on-chain callbacks, the VRS would be limited to single-chain signals, which are far noisier and arrive too late. The RSC is what makes the watchtower possible.

Specifically, Reactive Network enables:
1. Cross-chain event subscription (price gaps across 5 networks)
2. Off-chain AI computation with on-chain callback delivery (VRS pushed to hook)
3. Conditional automation (distribution triggered when VRS normalizes)
4. Asynchronous yield routing (buffer rebalanced between protocols)

### What Makes VolatilityVault Novel

Existing solutions and why they fall short:

| Solution | Approach | Limitation |
|---|---|---|
| Angstrom | Detects toxic flow, charges more | Reacts per-swap, no predictive cross-chain layer |
| Gamma Strategies | Auto-rebalancing LP ranges | Reacts after IL has occurred |
| Standard dynamic fee hooks | Volatility-based fees | Single-chain signals, no AI, no yield buffer |
| **VolatilityVault** | **Cross-chain AI prediction + predictive fees + toxic detection + yield-bearing buffer + LP intent** | **First to combine all layers** |

The specific combination of:
- Cross-chain signal aggregation via Reactive Network
- AI volatility prediction (not just reactive formula)
- Fee charging *before* the damaging trade executes
- Yield buffer that compounds storm fees while the storm lasts
- Per-LP personalized payout preferences

...has not been built before.

### Technical Architecture

```
[Reactive RSC]
  Monitors: ETH, ARB, BASE, POLYGON, BSC price feeds + volume
  Calls: AI Oracle with aggregated feature vector
  Pushes: VRS score to VRSOracle.sol via callback
  Triggers: YieldBuffer distribution when VRS normalizes

[VRSOracle.sol]
  Stores latest VRS score on-chain
  Callable by VolatilityVaultHook in beforeSwap

[VolatilityVaultHook.sol]  ← core V4 hook
  beforeSwap:      reads VRS → sets dynamic fee → checks for toxic order
  afterSwap:       routes storm fees to YieldBuffer
  afterAddLiq:     registers LP + stores LPIntent
  afterRemoveLiq:  calculates final payout respecting LP preference

[YieldBuffer.sol]  ← ERC-4626 vault
  Holds accumulated storm fees
  AI agent routes to Aave / Morpho for yield
  Distributes on Reactive trigger with yield earned

[LPPositionNFT.sol]  ← ERC-721
  Minted on deposit
  Stores LPIntent struct on-chain
  Used to calculate proportional distributions
```

### Tech Stack

| Layer | Technology |
|---|---|
| V4 Hook | Solidity, Uniswap V4 Hook interface, BaseHook |
| Reactive Smart Contract | Reactive Network RSC (ReactVM) |
| AI Oracle | PPO volatility model via Chainlink Functions |
| Toxic Order Detection | On-chain heuristics (size threshold + wallet pattern) |
| Yield Buffer | ERC-4626 vault |
| Yield Routing | Aave V3 + Morpho integration |
| LP Positions | ERC-721 NFT with on-chain LPIntent |
| Testing | Foundry (forge) |
| Frontend | Next.js + wagmi + viem |

### Demo Scenario

**Setup:** ETH/USDC pool on Uniswap V4 with VolatilityVault hook. Two LPs have deposited. LP A chose DAILY payouts. LP B chose REINVEST.

**T=0:** VRS = 18. Normal conditions. Swaps charged 0.05%. LPs earning standard fees.

**T=10 blocks:** Reactive RSC detects a $50 price gap forming between Coinbase and Uniswap. Volume acceleration detected on Arbitrum. AI oracle outputs VRS = 84.

**T=11 blocks:** RSC pushes VRS = 84 to hook via callback. Hook is now charging 0.50% on all swaps.

**T=12 blocks:** Large bot swap arrives. Toxic order detection fires. Bot pays 0.50% base + surcharge. $180 of the bot's arbitrage profit flows to the buffer instead of their wallet.

**T=20 blocks:** Buffer deploys $180 to Morpho at 11% APY.

**T=100 blocks:** Storm passes. VRS drops to 22. RSC triggers distribution. LP A receives daily payout (storm fees + Morpho yield). LP B's share gets auto-compounded.

**Result:** Regular LPs absorbed IL. VolatilityVault LPs earned from the same event.

---

## Sponsor Track

- [x] Uniswap — IL & Yield Systems
- [x] Reactive Network — Innovative RSC Integration

---

## Team

- Team Member 1: [Add name + role]
- Team Member 2: [Add name + role]

---

## Links

- GitHub: [Add repo link]
- Demo: [Add demo link if available]
- Slides: [Add if available]
