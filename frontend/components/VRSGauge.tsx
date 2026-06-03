'use client'

import { useReadContract } from 'wagmi'
import { CONTRACTS, VRS_ORACLE_ABI, FEE_LABELS } from '@/lib/contracts'

export function VRSGauge() {
  const { data: vrs,      refetch: refetchVrs  } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'vrs',          query: { refetchInterval: 6000 } })
  const { data: fee                            } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'getFee',       query: { refetchInterval: 6000 } })
  const { data: level                          } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'getRiskLevel', query: { refetchInterval: 6000 } })
  const { data: lastUpdated                    } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'lastUpdated',  query: { refetchInterval: 6000 } })

  const score    = vrs    !== undefined ? Number(vrs)  : null
  const feeNum   = fee    !== undefined ? Number(fee)  : null
  const feeInfo  = feeNum !== null ? FEE_LABELS[feeNum] : null
  const updatedAt = lastUpdated ? new Date(Number(lastUpdated) * 1000).toLocaleTimeString() : null

  // Gauge colour based on score
  const gaugeColor =
    score === null   ? 'bg-gray-600' :
    score <= 30      ? 'bg-green-500' :
    score <= 60      ? 'bg-yellow-400' :
    score <= 80      ? 'bg-orange-500' :
                       'bg-red-500'

  return (
    <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-gray-200">Volatility Risk Score</h2>
        <span className="text-xs text-gray-500">
          {updatedAt ? `Updated ${updatedAt}` : 'Loading...'}
        </span>
      </div>

      {/* Big score number */}
      <div className="flex items-end gap-3 mb-4">
        <span className={`text-7xl font-black tabular-nums ${feeInfo?.color ?? 'text-gray-400'}`}>
          {score !== null ? score : '--'}
        </span>
        <span className="text-gray-500 text-xl mb-2">/ 100</span>
        {feeInfo && <span className="text-4xl mb-1">{feeInfo.emoji}</span>}
      </div>

      {/* Progress bar */}
      <div className="h-3 bg-gray-800 rounded-full overflow-hidden mb-4">
        <div
          className={`h-full rounded-full transition-all duration-700 ${gaugeColor}`}
          style={{ width: `${score ?? 0}%` }}
        />
      </div>

      {/* Weather legend */}
      <div className="grid grid-cols-4 gap-1 text-center text-xs mb-5">
        {[
          { label: '☀️ CALM',      range: '0-30',  color: 'text-green-400'  },
          { label: '⛅ CLOUDY',   range: '31-60', color: 'text-yellow-400' },
          { label: '⛈️ STORM',    range: '61-80', color: 'text-orange-400' },
          { label: '🌀 HURRICANE', range: '81-100', color: 'text-red-500'   },
        ].map(w => (
          <div key={w.label} className="bg-gray-800 rounded-lg p-1.5">
            <div className={`font-semibold ${w.color}`}>{w.label}</div>
            <div className="text-gray-500">{w.range}</div>
          </div>
        ))}
      </div>

      {/* Current fee */}
      <div className="bg-gray-800 rounded-xl p-4 flex items-center justify-between">
        <div>
          <p className="text-xs text-gray-500 mb-0.5">Current swap fee</p>
          <p className={`text-2xl font-bold ${feeInfo?.color ?? 'text-gray-400'}`}>
            {feeInfo ? feeInfo.bps : '--'}
          </p>
        </div>
        <div className="text-right">
          <p className="text-xs text-gray-500 mb-0.5">Risk level</p>
          <p className={`text-lg font-semibold ${feeInfo?.color ?? 'text-gray-400'}`}>
            {level ?? '--'}
          </p>
        </div>
      </div>

      <p className="mt-3 text-xs text-gray-600 text-center">
        Fee is overridden per-swap based on live VRS — pushed by the Reactive Network RSC
      </p>
    </div>
  )
}
