// Frontend-side position tracking.
//
// NOTE: Deposits go through Uniswap's shared PoolModifyLiquidityTest router,
// which owns the V4 position — so per-user positions can't be queried from the
// contracts by wallet address. For the demo we record each deposit locally so
// the user can see a summary of what they've added. Token balances shown
// elsewhere are real, live, on-chain reads.

export interface StoredPosition {
  amount:    string   // liquidity amount (human units)
  targetAPY: string   // %
  maxIL:     string   // %
  payout:    string   // Daily | Lump Sum | Reinvest
  txHash:    string
  timestamp: number
}

const KEY = 'vv_positions'

function storageKey(address: string) {
  return `${KEY}_${address.toLowerCase()}`
}

export function savePosition(address: string, pos: StoredPosition) {
  if (typeof window === 'undefined') return
  const existing = getPositions(address)
  existing.unshift(pos)
  localStorage.setItem(storageKey(address), JSON.stringify(existing))
}

export function getPositions(address: string): StoredPosition[] {
  if (typeof window === 'undefined') return []
  try {
    const raw = localStorage.getItem(storageKey(address))
    return raw ? (JSON.parse(raw) as StoredPosition[]) : []
  } catch {
    return []
  }
}

export function clearPositions(address: string) {
  if (typeof window === 'undefined') return
  localStorage.removeItem(storageKey(address))
}

export const PAYOUT_LABELS = ['Daily', 'Lump Sum', 'Reinvest']
