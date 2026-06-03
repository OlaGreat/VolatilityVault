'use client'

import { CONTRACTS, POOL_KEY } from '@/lib/contracts'

export function PoolStats() {
  const stats = [
    { label: 'Network',       value: 'Ethereum Sepolia' },
    { label: 'Pool Pair',     value: 'VTKA / VTKB' },
    { label: 'Fee Model',     value: 'Dynamic (AI-controlled)' },
    { label: 'Tick Spacing',  value: '60' },
    { label: 'Hook',          value: shortAddr(CONTRACTS.HOOK) },
    { label: 'Pool Manager',  value: shortAddr(CONTRACTS.POOL_MANAGER) },
  ]

  return (
    <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
      <h2 className="text-lg font-semibold text-gray-200 mb-4">Pool Info</h2>
      <div className="space-y-3">
        {stats.map(s => (
          <div key={s.label} className="flex justify-between text-sm">
            <span className="text-gray-500">{s.label}</span>
            <span className="text-gray-200 font-mono">{s.value}</span>
          </div>
        ))}
      </div>

      <div className="mt-4 pt-4 border-t border-gray-800">
        <p className="text-xs text-gray-600 mb-2">Pool ID</p>
        <p className="text-xs font-mono text-gray-500 break-all">
          0x0e32107f870f47cac70d5501dc91328470a9e53b583bc9c677bab6aaedb5436b
        </p>
      </div>

      <a
        href={`https://sepolia.etherscan.io/address/${CONTRACTS.HOOK}`}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-4 block text-center text-xs text-purple-400 hover:text-purple-300 transition-colors"
      >
        View hook on Etherscan →
      </a>
    </div>
  )
}

function shortAddr(addr: string) {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`
}
