# VolatilityVault

> A Uniswap V4 hook that prices volatility directly into the swap fee. A Reactive Network smart contract scores on-chain volatility in real time, raises LP fees as risk rises, and routes the surplus fees into a yield buffer that distributes back to LPs when markets calm down.

> **Scope note:** This is a working hackathon prototype deployed on Ethereum Sepolia. The volatility score is a transparent on-chain heuristic, deliberately designed so it can be replaced by a trained ML model without touching the hook or any other contract. The yield router is a mock on testnet, with Aave/Morpho integration as the next step. "Roadmap" notes throughout mark what is live versus what is planned.

---

## The Problem

Every time ETH price moves on Coinbase, arbitrage bots rush into Uniswap to close the gap. They extract value from the pool at the LP's expense. That extraction is impermanent loss, and it has always worked the same way: bots profit, LPs pay.

**A concrete example:**

You deposit 1 ETH and $2,000 USDC into a Uniswap V4 pool at $2,000/ETH. ETH rises to $2,200 on Coinbase. Before you can react, bots buy your ETH from the pool at the stale $2,000 price.

```
What you had:       1 ETH + 2,000 USDC   →  $4,000
What you now hold:  ~0.816 ETH + ~2,449 USDC  →  $4,898
If you had just held:  1 ETH + 2,000 USDC  →  $5,000

Impermanent Loss = -$102  ←  the bot kept this
```

Every existing mitigation reacts after the damage is done. Reactive hooks fire after the swap. Rebalancers adjust after the price has already moved.

**VolatilityVault charges the people causing the damage before they cause it.**

---

## The Solution

VolatilityVault is a Uniswap V4 hook driven by a Reactive Smart Contract. The RSC subscribes to Uniswap V4 `Swap` events on Ethereum Sepolia, computes a **Volatility Risk Score (VRS)** from on-chain signals, and relays it cross-chain via a callback to an on-chain oracle. The hook reads that score before every swap and overrides the pool fee to match the current risk level. During high-volatility periods, the hook skims an extra fee into a yield buffer, which earns additional yield through a router and then distributes everything back to LPs when the storm passes.

LPs set their intent once at deposit. The protection loop then runs on-chain autonomously.

---

## How It Works

### Step 1: A Reactive Smart Contract Watches Swaps

A Reactive Smart Contract (`VolatilityRSC`) deployed on Reactive Lasna subscribes to Uniswap V4 `Swap` events on Ethereum Sepolia. Every time a swap fires, the RSC reacts inside the ReactVM and reads two on-chain signals from the event:

- **Price velocity:** how far the pool price moved since the last swap
- **Swap frequency:** how many swaps occurred in a recent block window

> **Roadmap:** the subscription model extends to multiple chains (Reactive supports many event origins), and the signal set can grow to include reference-price gaps and wallet-pattern detection. Today it runs on Sepolia with the two signals above.

The RSC combines these into the Volatility Risk Score.

### Step 2: The RSC Computes the Volatility Risk Score

The scoring function combines price velocity and swap frequency into a single number from 0 to 100: the **Volatility Risk Score**. It is a transparent on-chain heuristic (readable in `reactive/VolatilityRSC.sol`), deliberately kept simple and auditable. The architecture is designed so this scorer can be replaced by a trained ML model without changing the hook or any other contract. The hook only ever reads a number from the oracle.

```
0 ──────────────────────────────────── 100
│  CALM  │  CLOUDY  │  STORM  │  HURRICANE  │
│  0–30  │  31–60   │  61–80  │   81–100    │
```

Think of it as a live weather forecast for the pool. The RSC pushes the latest VRS on-chain via a callback to `VRSOracle.sol`, keeping it current before every swap.

### Step 3: The Hook Reads VRS and Overrides the Pool Fee

Before every swap, `beforeSwap` reads the current VRS from the oracle and overrides the pool's LP fee for that specific trade only:

```
VRS 0–30   →  0.05%  (calm — competitive for regular traders)
VRS 31–60  →  0.15%  (clouds forming)
VRS 61–80  →  0.30%  (storm warning)
VRS 81–100 →  0.50%  (hurricane — captures meaningful arbitrage value)
```

The arbitrageur still executes. The cross-chain price gap still makes it profitable. But now, instead of them keeping 100% of the margin, a significant portion flows to the pool as fees.

### Step 4: Toxic Order Flow Detection

Inspired by [Angstrom](https://www.paradigm.xyz/2024/04/angstrom), the hook also looks at how the pool is being swapped. When VRS is high and the swap is unusually large and directional (a signal of likely arbitrage), the hook emits a `ToxicOrderDetected` event. Regular users making small swaps never trigger it.

> **Roadmap:** today this emits an on-chain event flagging the toxic order. A follow-up will route an additional surcharge from flagged orders directly to LP wallets.

### Step 5: Storm Fees Flow Into the Yield Buffer

Fees collected during storm periods are not distributed immediately. Instant fee distribution creates JIT (just-in-time) liquidity attacks where bots deposit right before a large swap, collect the fees, and withdraw immediately after.

Instead, storm fees flow into `YieldBuffer.sol`, a dual-asset buffer that tracks both pool tokens. While they sit there, the buffer deploys them to a yield router to earn extra return, then distributes everything back when the storm passes.

> **Built today:** the buffer is wired to a `MockYieldRouter` on testnet that returns a fixed yield, so the full deploy, earn, distribute, and claim cycle works end-to-end.
> **Roadmap:** swap the mock for an `AaveYieldRouter` or `MorphoYieldRouter` that routes to whichever lending market pays best. The buffer takes a router address, so this is a drop-in change.

When the VRS drops back to calm, a distribution is triggered (by the Reactive RSC automatically, or by the owner in the demo). Each LP receives their proportional share of the storm fees plus the yield earned while the buffer was deployed.

### Step 6: LP Intent and Personalization

When depositing, each LP registers their intent on-chain via `hookData`. The hook stores this per-LP per-pool:

```solidity
struct LPIntent {
    uint256 targetAPY;          // e.g. 1200 = 12% annual
    uint256 maxILToleranceBps;  // e.g. 500 = tolerate up to 5% IL
    PayoutPreference payout;    // DAILY | LUMP_SUM | REINVEST
    uint256 depositTimestamp;
}
```

- **DAILY:** smaller, frequent payouts from the buffer as fees accumulate
- **LUMP_SUM:** wait for larger storm events and collect bigger distributions
- **REINVEST:** automatically compound fees back into the LP position

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│         REACTIVE LASNA — The Cross-Chain Watcher                        │
│                                                                         │
│  Subscribes to: Uniswap V4 Swap events on Ethereum Sepolia             │
│  Signals:       price velocity + swap frequency  (extensible)          │
│                                                                         │
│  VolatilityRSC.sol                                                      │
│  - Reacts in the ReactVM on every subscribed Swap event                │
│  - Computes the Volatility Risk Score (0–100)                          │
│  - When VRS changes: callback to VRSOracle on the destination chain    │
│  - When VRS normalizes: triggers YieldBuffer distribution              │
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
│  │  beforeSwap      → read VRS, override fee, toxic order check    │   │
│  │  afterSwap       → route storm fees to YieldBuffer              │   │
│  │  afterAddLiq     → register LPIntent from hookData              │   │
│  │  afterRemoveLiq  → emit LPExited for buffer settlement          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                   │                                                     │
│                   │ storm fees                                          │
│                   ▼                                                     │
│  YieldBuffer.sol (dual-asset)                                           │
│  - Holds storm-period fees and earns yield via a yield router          │
│  - Distributes to LPs on Reactive trigger (fees plus yield earned)     │
│  - Respects each LP's PayoutPreference                                 │
│                                                                         │
│  LPPositionNFT.sol (ERC-721)                                           │
│  - Minted on deposit, stores LPIntent on-chain                        │
│  - Used for proportional buffer distribution calculations              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Two Independent Processes

**Process 1: Background Intelligence (runs continuously)**

The Reactive RSC reacts to Uniswap V4 swaps on Sepolia. On each reaction it recomputes the VRS, and when the score changes meaningfully it pushes a fresh value to `VRSOracle.sol` on the destination chain. By the time the next swap arrives, the score is already sitting in the oracle: current, local, readable in a single storage call.

```
A swap happens on the Sepolia V4 pool
  → Reactive RSC reacts in the ReactVM
  → recomputes the Volatility Risk Score
  → RSC callback: VRSOracle.updateVRS(score)
  → oracle is ready before the next swap arrives
```

**Process 2: Per-swap Fee Adjustment (happens on demand)**

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
│   ├── VolatilityVaultHook.sol    # Core V4 hook: dynamic fee, fee skim, toxic detection, LP intent
│   ├── VRSOracle.sol              # Stores VRS score and maps it to fee tiers
│   ├── YieldBuffer.sol            # Dual-asset buffer: storm fees (both tokens) plus yield routing
│   ├── LPPositionNFT.sol          # ERC-721: minted on deposit, stores LPIntent on-chain
│   ├── VRSCallbackReceiver.sol    # Reactive callback adapter, forwards to oracle and buffer
│   └── mocks/
│       ├── MockRSC.sol            # Simulates Reactive RSC for local testing
│       └── MockYieldRouter.sol    # Mock yield router (Aave/Morpho planned)
├── reactive/
│   └── VolatilityRSC.sol          # Reactive Smart Contract deployed on Reactive Network
├── test/                          # 194 tests, 94.8% coverage
│   ├── VRSOracle.t.sol            # 31 tests: score updates, fee tiers, access control, fuzz
│   ├── VolatilityVaultHook.t.sol  # 36 tests: fee tiers, toxic detection, LP intent, end-to-end claim
│   ├── YieldBuffer.t.sol          # 34 tests: dual-asset accrual, distribution, claims, errors, fuzz
│   ├── LPPositionNFT.t.sol        # 38 tests: mint/update/burn, intent, access control, fuzz
│   ├── VRSCallbackReceiver.t.sol  # 31 tests: callback forwarding, access, pay/withdraw, fuzz
│   └── VolatilityRSC.t.sol        # 24 tests: react() scoring, callbacks, storm-to-calm distribution, fuzz
├── script/
│   ├── DeployHook.s.sol           # Mines CREATE2 salt and deploys hook to correct address
│   ├── DeployRSC.s.sol            # Deploys VolatilityRSC to Reactive Network
│   ├── InitializePool.s.sol       # Initializes pool with DYNAMIC_FEE_FLAG
│   └── DemoSwap.s.sol             # Full demo: sets VRS, swaps, checks events
├── foundry.toml
├── .env.example
├── SUBMISSION.md
└── README.md
```

---

## Tech Stack

| Technology | Role |
|---|---|
| Uniswap V4 | Core AMM: hook intercepts every swap for dynamic fee override and fee skim |
| Reactive Network | Cross-chain Swap-event subscription, VRS callback delivery, and buffer trigger |
| Yield Router | `MockYieldRouter` on testnet; Aave V3 / Morpho planned as a drop-in replacement |
| Foundry | Development, testing (194 tests), and deployment |
| Solidity 0.8.26 | Smart contract language |
| Next.js + wagmi v2 + viem + RainbowKit | Frontend dashboard |

---

## Sponsor Integrations

### Uniswap V4

**Where in the code:**
- `src/VolatilityVaultHook.sol` implements `IHooks`, uses `DYNAMIC_FEE_FLAG` and `OVERRIDE_FEE_FLAG` from `LPFeeLibrary` to override the LP fee per swap without touching pool state.
- `script/DeployHook.s.sol` mines a CREATE2 salt so the deployed address encodes the correct hook permission bits for `beforeSwap`, `afterSwap`, `afterAddLiquidity`, and `afterRemoveLiquidity`.
- `script/InitializePool.s.sol` initializes the pool with `LPFeeLibrary.DYNAMIC_FEE_FLAG` (`0x800000`) as required for fee override hooks.

**What the integration does:**

1. `beforeSwap` returns `OVERRIDE_FEE_FLAG | fee`. The V4 PoolManager applies this as the LP fee for that swap only, with no global state change.
2. `afterAddLiquidity` decodes `hookData` passed by the LP and stores their intent (targetAPY, IL tolerance, payout preference) on-chain, keyed by `address → PoolId`.
3. `afterRemoveLiquidity` emits `LPExited` so the YieldBuffer can calculate the final payout.
4. Completely transparent to swappers: they interact with the pool normally through any router.

---

### Reactive Network

**Where in the code:**
- `reactive/VolatilityRSC.sol` is the Reactive Smart Contract deployed on Reactive Lasna. It subscribes to Uniswap V4 `Swap` events on Sepolia, computes the VRS in the ReactVM, and pushes it via callback to `VRSCallbackReceiver.sol`. It also triggers `YieldBuffer` distribution when VRS normalizes.
- `src/VRSCallbackReceiver.sol` is the destination-chain adapter that authorizes only the Reactive callback proxy and forwards calls to `VRSOracle` and `YieldBuffer`.
- `src/VRSOracle.sol` sets `authorizedUpdater` to the callback receiver. Only it (or the owner) can push VRS scores.
- `script/DeployRSC.s.sol` deploys and configures the RSC.

**What the integration does:**

The cross-chain reaction is what makes the hook autonomous: the fee updates from real swap activity with no off-chain keeper required.

1. **Cross-chain event subscription:** the RSC subscribes to Sepolia V4 swaps from Reactive Lasna (the model extends to more chains and events).
2. **Callback delivery:** the RSC emits a callback that the Reactive signer posts to Sepolia, updating the on-chain oracle.
3. **Conditional buffer trigger:** when VRS returns to calm, the RSC triggers LP distribution automatically.
4. **Verified live:** a real Sepolia swap moved the on-chain VRS with no manual input. Reactions are visible on reactscan.

---

## Hook Permissions

| Hook | Used | Purpose |
|---|---|---|
| `beforeInitialize` | No | N/A |
| `afterInitialize` | No | N/A |
| `beforeAddLiquidity` | No | N/A |
| `afterAddLiquidity` | Yes | Register LP intent from hookData |
| `beforeRemoveLiquidity` | No | N/A |
| `afterRemoveLiquidity` | Yes | Emit LPExited for buffer settlement |
| `beforeSwap` | Yes | Read VRS, override fee, flag toxic orders |
| `afterSwap` | Yes | Route storm fees to YieldBuffer |
| `beforeDonate` | No | N/A |
| `afterDonate` | No | N/A |

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
| Fee | Dynamic (`0x800000`), controlled by VRS oracle |
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

Receives Reactive Network callbacks through the Sepolia callback proxy and forwards them to `VRSOracle` and `YieldBuffer`. This adapter keeps the core contracts Reactive-agnostic: no redeploy of the oracle, hook, or pool is needed if the RSC is redeployed.

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

# 3. Deploy YieldBuffer and LPPositionNFT
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

**Option A: Local demo (no live feeds needed)**

```bash
forge script script/DemoSwap.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY -vvvv
# Look for: FeeOverridden(poolId, vrs=85, fee=5000)
# Look for: ToxicOrderDetected if swap size exceeds threshold
```

**Option B: Live VRS update via oracle**

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

# Verbose output
forge test -vvvv

# Specific suite
forge test --match-path test/VRSOracle.t.sol

# Gas report
forge test --gas-report
```

**194 tests, 94.8% line coverage** across all six suites: happy paths, unhappy paths, every error case as its own test case, and fuzz tests on every contract.

| Suite | Tests | What it covers |
|---|---|---|
| `LPPositionNFTTest` | 38 | mint / update / burn, intent storage, access control, transferability, fuzz |
| `VolatilityVaultHookTest` | 36 | dynamic fee tiers, toxic-order detection, LP intent, buffer fee accrual, end-to-end deposit to swap to claim, permissions, all unused-callback reverts, fuzz |
| `YieldBufferTest` | 34 | dual-asset accrual, deploy / distribute / claim, yield, deregister, every error case, admin, fuzz |
| `VRSOracleTest` | 31 | every fee tier and boundary, all risk levels, access control, fuzz |
| `VRSCallbackReceiverTest` | 31 | callback forwarding, proxy and owner access, pay/withdraw, admin rotation, fuzz |
| `VolatilityRSCTest` | 24 | `react()` VRS computation, callback emission, storm-to-calm distribution trigger, admin, fuzz |
| **Total** | **194** | **All passing** |

Run `forge coverage` to reproduce the numbers. The uncovered lines are defensive infrastructure paths (Reactive system-contract glue and `require` failure branches) that cannot be unit-tested without mocking the Reactive network layer.

---

## Security Considerations

- **PoolManager guard:** all hook callbacks revert if `msg.sender != address(poolManager)`
- **Authorized updater pattern:** `VRSOracle` only accepts VRS updates from the RSC callback address or the owner; no third party can manipulate the score
- **Buffer JIT protection:** storm fees are held in the buffer rather than distributed immediately, preventing bots from depositing to snipe fee events
- **Dual-asset buffer:** tracks storm fees in both pool tokens; LPs claim their proportional share of each on distribution
- **Fee cap:** V4's `MAX_LP_FEE` is enforced by the PoolManager; the hook never exceeds 0.50% (5,000 in V4 units)
- **Toxic threshold:** configurable per deployment to avoid false positives on legitimate large trades

---

## Hackathon

Built for the **UHI9 Hookathon: Impermanent Loss and Yield Systems**.

Sponsor integrations: **Uniswap** and **Reactive Network**

Submission deadline: **June 11, 2026** · Demo Day: **June 19, 2026**

---

## License

MIT
