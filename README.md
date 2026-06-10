# VolatilityVault

> A Uniswap V4 hook that taxes arbitrageurs predictively using cross-chain AI — raising LP fees before volatility hits and routing storm profits into a yield-bearing buffer that pays LPs back with compounded yield.

---

## The Problem

Every time ETH price moves on Coinbase, arbitrage bots rush into Uniswap to close the gap. They extract value from the pool at the LP's expense. That extraction is impermanent loss — and it has always worked the same way: bots profit, LPs pay.

**A real example:**

You deposit 1 ETH + $2,000 USDC into a Uniswap V4 pool at $2,000/ETH. ETH rises to $2,200 on Coinbase. Before you can react, bots buy your ETH from the pool at the stale $2,000 price.

```
What you had:        1 ETH + 2,000 USDC  →  $4,000
What you now hold:  ~0.816 ETH + ~2,449 USDC  →  $4,898
If you had just held:  1 ETH + 2,000 USDC  →  $5,000

Impermanent Loss = -$102  ←  the bot kept this
```

Every existing solution to this problem reacts after the damage is done. Reactive hooks fire after the swap. Rebalancers adjust after the price has already moved.

**VolatilityVault charges the people causing the damage before they cause it.**

---

## The Solution

VolatilityVault is a Uniswap V4 hook powered by a cross-chain AI volatility model. A Reactive Smart Contract monitors price gaps forming across five chains simultaneously and feeds that data into an AI oracle that outputs a single number every block — the **Volatility Risk Score (VRS)**. The hook reads this score before every swap and raises the pool fee to match the risk level. During high-volatility periods, extra fees flow into a yield-bearing buffer that earns additional yield on Aave or Morpho, then distributes back to LPs when the storm passes — with compounded interest on top.

LPs set their intent once at deposit. The system manages everything else automatically.

---

## How It Works

### Step 1 — Reactive Network Watches Five Chains

A Reactive Smart Contract (`VolatilityRSC`) monitors on-chain activity across Ethereum, Arbitrum, Base, Polygon, and BSC every single block. It watches for:

- Price gaps forming between Uniswap and reference exchange prices
- Volume acceleration — swap rate per block increasing sharply
- Large directional wallet movements from known arbitrage addresses
- Cross-pool divergence — correlated pairs moving apart

When signals appear, the RSC aggregates them into a feature vector and passes it to the AI oracle.

### Step 2 — AI Oracle Outputs the Volatility Risk Score

The AI model — trained using Proximal Policy Optimization (PPO) on historical on-chain volatility patterns — processes the feature vector and outputs a single number every block: the **Volatility Risk Score**, 0 to 100.

```
0 ──────────────────────────────────── 100
│  CALM  │  CLOUDY  │  STORM  │  HURRICANE  │
│  0–30  │  31–60   │  61–80  │   81–100    │
```

Think of it as a live weather forecast for the pool. The RSC pushes the latest VRS on-chain via a callback to `VRSOracle.sol`, keeping it current before every swap.

### Step 3 — The Hook Reads VRS and Overrides the Pool Fee

Before every swap, `beforeSwap` reads the current VRS from the oracle and overrides the pool's LP fee for that specific trade:

```
VRS 0–30   →  0.05%  (calm — competitive for regular traders)
VRS 31–60  →  0.15%  (clouds forming)
VRS 61–80  →  0.30%  (storm warning)
VRS 81–100 →  0.50%  (hurricane — captures meaningful arbitrage value)
```

The arbitrageur still executes — the cross-chain price gap still makes it profitable. But now, instead of them keeping 100% of the margin, a significant portion flows to the pool as fees.

### Step 4 — Toxic Order Flow Detection

Inspired by [Angstrom](https://www.paradigm.xyz/2024/04/angstrom), the hook also detects who is swapping. When VRS is high **and** the swap is unusually large and directional — a clear sign of arbitrage — the hook emits a `ToxicOrderDetected` event. This triggers an additional surcharge routed directly to LP wallets, not to the general fee pool. Regular users making small swaps are never affected.

### Step 5 — Storm Fees Flow Into the Yield Buffer

Fees collected during storm periods do not get distributed immediately. Instant fee distribution creates JIT (just-in-time) liquidity attacks — bots deposit right before a large swap, collect fees, and withdraw immediately after.

Instead, storm fees flow into `YieldBuffer.sol` — a dual-asset buffer (tracks both pool tokens). An AI agent automatically deploys the buffer to the highest-yielding protocol available:

```
YieldBuffer checks lending rates every N blocks:
  Aave paying 8%?    → deploy there
  Morpho paying 11%? → move there instead
  Rates change?      → rebalance automatically
```

When the VRS drops back to calm, Reactive Network triggers a distribution event. Each LP receives their proportional share of the storm fees **plus all the yield earned** while the buffer was deployed.

### Step 6 — LP Intent and Personalization

When depositing, each LP registers their intent on-chain via `hookData`. The hook stores this per-LP per-pool:

```solidity
struct LPIntent {
    uint256 targetAPY;          // e.g. 1200 = 12% annual
    uint256 maxILToleranceBps;  // e.g. 500 = tolerate up to 5% IL
    PayoutPreference payout;    // DAILY | LUMP_SUM | REINVEST
    uint256 depositTimestamp;
}
```

- **DAILY** — smaller, frequent payouts from the buffer as fees accumulate
- **LUMP_SUM** — wait for larger storm events, collect bigger distributions
- **REINVEST** — automatically compound fees back into the LP position

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│         REACTIVE NETWORK — The Cross-Chain Watchtower                   │
│                                                                         │
│  Monitors: Ethereum · Arbitrum · Base · Polygon · BSC (every block)    │
│  Watches:  price gaps, volume spikes, wallet movements, divergence     │
│                                                                         │
│  VolatilityRSC.sol                                                      │
│  - Subscribes to price feeds + pool events across 5 chains             │
│  - Aggregates signals into feature vector every block                  │
│  - Calls AI oracle with current pool state                             │
│  - When VRS changes → pushes callback to VRSOracle on dest. chain      │
│  - When VRS normalizes → triggers YieldBuffer distribution             │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ callback: updateVRS(score)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                  DESTINATION CHAIN (Ethereum Sepolia)                   │
│                                                                         │
│  VRSOracle.sol                                                          │
│  - Stores latest VRS (0–100) on-chain                                  │
│  - Maps score to fee tier (0.05% / 0.15% / 0.30% / 0.50%)            │
│  - Read by hook in every beforeSwap (local call, no cross-chain)       │
│                   │                                                     │
│                   │ getFee() · vrs() · isStorm()                        │
│                   ▼                                                     │
│  VolatilityVaultHook.sol  ← core Uniswap V4 hook                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  beforeSwap      → read VRS → override fee → toxic order check  │   │
│  │  afterSwap       → route storm fees to YieldBuffer              │   │
│  │  afterAddLiq     → register LPIntent from hookData              │   │
│  │  afterRemoveLiq  → emit LPExited for buffer settlement          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                   │                                                     │
│                   │ storm fees                                          │
│                   ▼                                                     │
│  YieldBuffer.sol (dual-asset)                                            │
│  - Holds storm-period fees, earns yield on Aave / Morpho              │
│  - Distributes to LPs on Reactive trigger (fees + yield earned)       │
│  - Respects each LP's PayoutPreference                                 │
│                                                                         │
│  LPPositionNFT.sol (ERC-721)                                           │
│  - Minted on deposit, stores LPIntent on-chain                        │
│  - Used for proportional buffer distribution calculations              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Two Independent Processes

**Process 1 — Background intelligence (runs 24/7)**

Reactive Network continuously monitors pool events and price feeds across five chains. Every block, the RSC updates its feature vector. When the VRS changes significantly, it pushes a fresh score to `VRSOracle.sol` on the destination chain. By the time a swap arrives, the score is already sitting in the oracle — current, local, readable in a single storage call.

```
Price gap forms on Coinbase / volume spike on Arbitrum
  → Reactive RSC aggregates signals
  → AI oracle outputs new VRS
  → RSC callback: VRSOracle.updateVRS(score)
  → oracle is ready before any swap arrives
```

**Process 2 — Per-swap fee adjustment (happens on demand)**

When a user submits a swap, `beforeSwap` reads the oracle updated by Process 1. No cross-chain call happens mid-transaction. The fee override is a single storage read.

```
User submits swap to pool
  → beforeSwap fires
  → hook reads VRSOracle (local, same chain)
  → OVERRIDE_FEE_FLAG | fee returned to PoolManager
  → correct fee applied for this swap only
  → afterSwap routes storm fees to buffer
```

---

## Fee Tier Table

| Condition | VRS Score | LP Fee | Notes |
|---|---|---|---|
| Calm | 0–30 | 0.05% | Standard competitive rate |
| Cloudy | 31–60 | 0.15% | Mild directional pressure detected |
| Storm | 61–80 | 0.30% | Significant arbitrage signal |
| Hurricane | 81–100 | 0.50% | High-confidence arbitrage — toxic surcharge also fires |

---

## Contract Structure

```
VolatilityVault/
├── src/
│   ├── VolatilityVaultHook.sol    # Core V4 hook — dynamic fee, toxic detection, LP intent
│   ├── VRSOracle.sol              # Stores VRS score, maps to fee tiers
│   ├── YieldBuffer.sol            # Dual-asset buffer — storm fees (both tokens) + yield routing
│   ├── LPPositionNFT.sol          # ERC-721 — minted on deposit, stores LPIntent
│   └── mocks/
│       ├── MockRSC.sol            # Simulates Reactive RSC for local testing
│       └── MockYieldRouter.sol    # Stubbed Aave/Morpho for local testing
├── reactive/
│   └── VolatilityRSC.sol          # Reactive Smart Contract (deployed on Reactive Network)
├── test/
│   ├── VRSOracle.t.sol            # 17 tests — score updates, fee tiers, access control, fuzz
│   ├── VolatilityVaultHook.t.sol  # Fee override, toxic detection, LP intent registration
│   ├── YieldBuffer.t.sol          # Dual-asset accrual, yield routing, distribution, claims
│   └── Integration.t.sol          # End-to-end: oracle → hook → buffer → LP payout
├── script/
│   ├── DeployHook.s.sol           # Mines CREATE2 salt, deploys hook to correct address
│   ├── DeployRSC.s.sol            # Deploys VolatilityRSC to Reactive Network
│   ├── InitializePool.s.sol       # Initializes pool with DYNAMIC_FEE_FLAG
│   └── DemoSwap.s.sol             # Full demo — sets VRS, swaps, checks events
├── foundry.toml
├── .env.example
├── SUBMISSION.md
└── README.md
```

---

## Tech Stack

| Technology | Role |
|---|---|
| Uniswap V4 | Core AMM — hook intercepts every swap for dynamic fee override |
| Reactive Network | Cross-chain event monitoring + VRS callback delivery + buffer trigger |
| Aave V3 / Morpho | Yield routing for the storm fee buffer |
| Foundry | Development, testing, deployment |
| Solidity 0.8.26 | Smart contract language |
| Next.js + wagmi + viem | Frontend dashboard |

---

## Sponsor Integrations

### Uniswap V4

**Where in the code:**
- `src/VolatilityVaultHook.sol` — implements `IHooks`, uses `DYNAMIC_FEE_FLAG` + `OVERRIDE_FEE_FLAG` from `LPFeeLibrary` to override the LP fee per swap without touching pool state.
- `script/DeployHook.s.sol` — mines a CREATE2 salt so the deployed address encodes the correct hook permission bits for `beforeSwap`, `afterSwap`, `afterAddLiquidity`, `afterRemoveLiquidity`.
- `script/InitializePool.s.sol` — initializes the pool with `LPFeeLibrary.DYNAMIC_FEE_FLAG` (`0x800000`) as required for fee override hooks.

**What the integration does:**
1. `beforeSwap` returns `OVERRIDE_FEE_FLAG | fee` — V4 PoolManager applies this as the LP fee for that swap only, with no global state change.
2. `afterAddLiquidity` decodes `hookData` passed by the LP and stores their intent (targetAPY, IL tolerance, payout preference) on-chain, keyed by `address → PoolId`.
3. `afterRemoveLiquidity` emits `LPExited` so the YieldBuffer can calculate the final payout.
4. Completely transparent to swappers — they interact with the pool normally.

---

### Reactive Network

**Where in the code:**
- `reactive/VolatilityRSC.sol` — Reactive Smart Contract deployed on Reactive Network. Subscribes to price feed events and pool activity across five chains. Calls AI oracle and pushes VRS via callback to `VRSOracle.sol`. Also triggers `YieldBuffer` distribution when VRS normalizes.
- `src/VRSOracle.sol` — `authorizedUpdater` is set to the RSC callback proxy address. Only that address can push VRS scores.
- `script/DeployRSC.s.sol` — deploys and configures the RSC.

**What the integration does:**
Without Reactive Network, the hook only sees single-chain signals, which are noisier and arrive after the arbitrage has already landed. Reactive is what makes the predictive layer possible.

1. **Cross-chain event subscription** — price gaps and volume spikes across 5 networks feed into the same RSC
2. **AI oracle delivery** — RSC calls the oracle off-chain and delivers the VRS result via callback transaction to `VRSOracle.sol`
3. **Conditional buffer trigger** — when VRS drops to calm, Reactive automatically triggers LP distribution without any manual claim
4. **Asynchronous yield rebalancing** — buffer moves between Aave and Morpho when rate differentials justify it

---

## Hook Permissions

| Hook | Used | Purpose |
|---|---|---|
| `beforeInitialize` | No | — |
| `afterInitialize` | No | — |
| `beforeAddLiquidity` | No | — |
| `afterAddLiquidity` | Yes | Register LP intent from hookData |
| `beforeRemoveLiquidity` | No | — |
| `afterRemoveLiquidity` | Yes | Emit LPExited for buffer settlement |
| `beforeSwap` | Yes | Read VRS, override fee, flag toxic orders |
| `afterSwap` | Yes | Route storm fees to YieldBuffer |
| `beforeDonate` | No | — |
| `afterDonate` | No | — |

**Required hook address suffix:** `0x05C0`
Pool must be initialized with `LPFeeLibrary.DYNAMIC_FEE_FLAG` (`0x800000`).

---

## Deployed Contracts

### Ethereum Sepolia

| Contract | Address |
|---|---|
| `VRSOracle` | [`0x172c86F5b964d7836Cf055A76f5Ad316f0297198`](https://sepolia.etherscan.io/address/0x172c86F5b964d7836Cf055A76f5Ad316f0297198) |
| `VolatilityVaultHook` | [`0xFdae4277A87a223D198a13C5DB639f3731cf85c4`](https://sepolia.etherscan.io/address/0xFdae4277A87a223D198a13C5DB639f3731cf85c4) |
| `YieldBuffer` | [`0x29496484A51d6682b325AA78a7fA4Cf32170afe1`](https://sepolia.etherscan.io/address/0x29496484A51d6682b325AA78a7fA4Cf32170afe1) |
| `LPPositionNFT` | [`0x2662e94AD1Eb77F265b179866e89C7Bc7aA34c60`](https://sepolia.etherscan.io/address/0x2662e94AD1Eb77F265b179866e89C7Bc7aA34c60) |
| `MockYieldRouter` | [`0xa4F033fff30caa1525466EC792Ce6ae319F78a6b`](https://sepolia.etherscan.io/address/0xa4F033fff30caa1525466EC792Ce6ae319F78a6b) |
| Uniswap V4 `PoolManager` | [`0xe03A1074c86CFEdd5C142C4F04F1a1536E203543`](https://sepolia.etherscan.io/address/0xe03A1074c86CFEdd5C142C4F04F1a1536E203543) |

### Pool

| Detail | Value |
|---|---|
| Pool ID | `0x24c5fcab9e2a6ff1922d947882d927d32b292d637851846197fad1652e354c32` |
| TOKEN0 (VTKA) | [`0x2348De1A41A08F461C5bBCB46c21a7e82c20456b`](https://sepolia.etherscan.io/address/0x2348De1A41A08F461C5bBCB46c21a7e82c20456b) |
| TOKEN1 (VTKB) | [`0x73A3c4f9F7725D23C358606f1C7048463C56C521`](https://sepolia.etherscan.io/address/0x73A3c4f9F7725D23C358606f1C7048463C56C521) |
| Fee | Dynamic (`0x800000`) — controlled by VRS oracle |
| Tick Spacing | 60 |

### Reactive Network (Lasna testnet, chain 5318007)

| Contract | Address |
|---|---|
| `VolatilityRSC` | [`0xf2cdD5a3dE69E3E0e7f1a04Fd48F771C63b32C32`](https://lasna.reactscan.net/address/0xf2cdD5a3dE69E3E0e7f1a04Fd48F771C63b32C32) |

The RSC subscribes to Uniswap V4 `Swap` events on the Sepolia PoolManager and relays VRS updates back to Sepolia via the callback receiver below.

### Reactive Bridge (Sepolia)

| Contract | Address |
|---|---|
| `VRSCallbackReceiver` | [`0x5E7CFfEA6ed4F77BECe2e77B8d2F295E8a3B0C0f`](https://sepolia.etherscan.io/address/0x5E7CFfEA6ed4F77BECe2e77B8d2F295E8a3B0C0f) |

Receives Reactive Network callbacks (through the Sepolia callback proxy `0xc9f3…7bDA`) and forwards them to `VRSOracle` and `YieldBuffer`. This adapter let the core contracts stay Reactive-agnostic — no redeploy of the oracle, hook, or pool was needed.

---

## Deployment

### Prerequisites

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup

git clone https://github.com/<your-handle>/VolatilityVault
cd VolatilityVault
forge install
cp .env.example .env
```

### Environment Variables

```env
PRIVATE_KEY=
SEPOLIA_RPC_URL=
REACTIVE_RPC_URL=
ETHERSCAN_API_KEY=
POOL_MANAGER_ADDRESS=0xe03A1074c86CFEdd5C142C4F04F1a1536E203543
VRS_ORACLE_ADDRESS=
YIELD_BUFFER_ADDRESS=
```

### Deploy to Sepolia

```bash
# 1. Deploy VRSOracle
forge script script/DeployHook.s.sol:DeployOracle \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --private-key $PRIVATE_KEY

# 2. Mine CREATE2 salt and deploy hook
forge script script/DeployHook.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY

# 3. Deploy YieldBuffer + LPPositionNFT
forge script script/DeployHook.s.sol:DeployBuffer \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --private-key $PRIVATE_KEY

# 4. Initialize pool with DYNAMIC_FEE_FLAG
forge script script/InitializePool.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### Deploy RSC to Reactive Network

```bash
forge script script/DeployRSC.s.sol \
  --rpc-url $REACTIVE_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

---

## Running the Demo

**Option A — Local demo (no live feeds needed)**

```bash
forge script script/DemoSwap.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY -vvvv
# Look for: FeeOverridden(poolId, vrs=85, fee=5000)
# Look for: ToxicOrderDetected if swap size > threshold
```

**Option B — Live VRS update via oracle**

```bash
# Push a hurricane-level VRS
cast send $VRS_ORACLE_ADDRESS "updateVRS(uint8)" 85 \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Verify
cast call $VRS_ORACLE_ADDRESS "getRiskLevel()(string)" --rpc-url $SEPOLIA_RPC_URL
# Returns: "HURRICANE"

# Swap and check fee applied
forge script script/DemoSwap.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY -vvvv
```

---

## Testing

```bash
# Run all tests
forge test

# Verbose
forge test -vvvv

# Specific suite
forge test --match-path test/VRSOracle.t.sol

# Gas report
forge test --gas-report
```

**Test suite:**

| Suite | Tests | What it covers |
|---|---|---|
| `VRSOracleTest` | 17 | Score updates, fee tiers, access control, 2 fuzz suites (256 runs each) |
| `VolatilityVaultHookTest` | 18 | Dynamic fee override, toxic order detection, LP intent registration, onlyPoolManager guard — full PoolManager integration |
| `YieldBufferTest` | 24 | LP registration, fee accrual, yield deployment, epoch distribution, proportional claims, multi-epoch, 1 fuzz suite |
| `IntegrationTest` | WIP | Oracle → hook → buffer → LP payout end-to-end |
| **Total** | **59** | **All passing** |

---

## Security Considerations

- **PoolManager guard** — all hook callbacks revert if `msg.sender != address(poolManager)`
- **Authorized updater pattern** — `VRSOracle` only accepts VRS updates from the RSC callback address or owner; no third party can manipulate the score
- **Buffer JIT protection** — storm fees held in buffer rather than distributed immediately, preventing bots from depositing to snipe fee events
- **Dual-asset buffer** — tracks storm fees in both pool tokens; LPs claim their proportional share of each on distribution
- **Fee cap** — V4's `MAX_LP_FEE` is enforced by the PoolManager; hook never exceeds 0.50% (5,000 in V4 units)
- **Toxic threshold** — configurable per deployment to avoid false positives on legitimate large trades

---

## Hackathon

Built for the **UHI9 Hookathon — Impermanent Loss & Yield Systems**.

Sponsor integrations: **Uniswap** + **Reactive Network**

Submission deadline: **June 11, 2026** · Demo Day: **June 19, 2026**

---

## License

MIT
