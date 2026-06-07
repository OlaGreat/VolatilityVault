'use client'

import { useEffect, useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { formatEther } from 'viem'
import Link from 'next/link'
import { CONTRACTS, ERC20_ABI } from '@/lib/contracts'
import { getPositions, type StoredPosition } from '@/lib/positions'

export default function PositionsPage() {
  const { address, isConnected } = useAccount()
  const [positions, setPositions] = useState<StoredPosition[]>([])

  useEffect(() => {
    if (address) {
      // Sort newest-first by timestamp
      const sorted = [...getPositions(address)].sort((a, b) => b.timestamp - a.timestamp)
      setPositions(sorted)
    }
  }, [address])

  const { data: bal0 } = useReadContract({
    address: CONTRACTS.TOKEN0, abi: ERC20_ABI, functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 8000 },
  })
  const { data: bal1 } = useReadContract({
    address: CONTRACTS.TOKEN1, abi: ERC20_ABI, functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 8000 },
  })

  const vtka = bal0 ? parseFloat(formatEther(bal0 as bigint)).toFixed(2) : '--'
  const vtkb = bal1 ? parseFloat(formatEther(bal1 as bigint)).toFixed(2) : '--'

  const totalDeposited = positions.reduce((sum, p) => sum + parseFloat(p.amount || '0'), 0)

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <p className="text-gray-400 text-lg mb-2">Connect your wallet to view positions</p>
        <p className="text-gray-600 text-sm">Make sure you&apos;re on Ethereum Sepolia</p>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">My Positions</h1>
          <p className="text-gray-400 text-sm mt-1">Your VolatilityVault liquidity and wallet balances.</p>
        </div>
        <Link href="/deposit" className="px-4 py-2 bg-purple-600 hover:bg-purple-500 rounded-full text-sm font-semibold transition-colors">
          + Add More
        </Link>
      </div>

      {/* Wallet balances (live on-chain) */}
      <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800">
        <h2 className="font-semibold text-gray-200 mb-4">Wallet Balances <span className="text-xs text-green-400 font-normal">● live on-chain</span></h2>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="VTKA" value={vtka} />
          <Stat label="VTKB" value={vtkb} />
          <Stat label="Total Liquidity Added" value={totalDeposited.toFixed(2)} valueClass="text-purple-400" />
        </div>
      </div>

      {/* Deposit history */}
      <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold text-gray-200">Deposit History</h2>
          <span className="text-xs text-gray-600">Most recent first</span>
        </div>

        {positions.length === 0 ? (
          <div className="text-center py-10">
            <p className="text-gray-500 text-sm mb-3">No positions yet.</p>
            <Link href="/deposit" className="text-purple-400 hover:text-purple-300 text-sm transition-colors">
              Add your first position →
            </Link>
          </div>
        ) : (
          <div className="space-y-3">
            {positions.map((p, i) => (
              <div key={i} className="bg-gray-800 rounded-xl p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="font-semibold text-sm">{parseFloat(p.amount).toFixed(2)} liquidity</span>
                  <span className="text-xs text-gray-500">{new Date(p.timestamp).toLocaleString()}</span>
                </div>
                <div className="grid grid-cols-3 gap-2 text-xs">
                  <div><span className="text-gray-500">Target APY:</span> <span className="text-white">{p.targetAPY}%</span></div>
                  <div><span className="text-gray-500">Max IL:</span> <span className="text-white">{p.maxIL}%</span></div>
                  <div><span className="text-gray-500">Payout:</span> <span className="text-white">{p.payout}</span></div>
                </div>
                <a
                  href={`https://sepolia.etherscan.io/tx/${p.txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-purple-400 hover:text-purple-300 mt-2 inline-block transition-colors"
                >
                  View tx on Etherscan →
                </a>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Honest note */}
      <div className="bg-gray-900/50 border border-gray-800 rounded-xl p-4">
        <p className="text-xs text-gray-500 leading-relaxed">
          <span className="text-gray-400 font-medium">Note:</span> Deposits route through Uniswap&apos;s shared
          test liquidity router, which owns the underlying V4 position — so per-wallet position data is tracked
          here in your browser, while token balances above are live on-chain reads. A production deployment would
          mint an <span className="font-mono">LPPositionNFT</span> per deposit for fully on-chain position ownership.
        </p>
      </div>
    </div>
  )
}

function Stat({ label, value, valueClass = 'text-white' }: { label: string; value: string; valueClass?: string }) {
  return (
    <div className="bg-gray-800 rounded-xl p-3">
      <p className="text-xs text-gray-500 mb-0.5">{label}</p>
      <p className={`font-semibold text-lg tabular-nums ${valueClass}`}>{value}</p>
    </div>
  )
}
