'use client'

import { useReadContract } from 'wagmi'
import { CONTRACTS, VRS_ORACLE_ABI, FEE_LABELS } from '@/lib/contracts'

export function VRSGauge() {
  // ── All original contract reads preserved exactly ──
  const { data: vrs       } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'vrs',          query: { refetchInterval: 6000 } })
  const { data: fee       } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'getFee',       query: { refetchInterval: 6000 } })
  const { data: level     } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'getRiskLevel', query: { refetchInterval: 6000 } })
  const { data: lastUpdated } = useReadContract({ address: CONTRACTS.VRS_ORACLE, abi: VRS_ORACLE_ABI, functionName: 'lastUpdated',  query: { refetchInterval: 6000 } })

  const score     = vrs         !== undefined ? Number(vrs)  : null
  const feeNum    = fee         !== undefined ? Number(fee)  : null
  const feeInfo   = feeNum      !== null      ? FEE_LABELS[feeNum] : null
  const updatedAt = lastUpdated ? new Date(Number(lastUpdated) * 1000).toLocaleTimeString() : null

  // SVG circular gauge
  const RADIUS      = 130
  const CIRCUMFERENCE = 2 * Math.PI * RADIUS  // ≈ 816.8
  const dashOffset  = score !== null
    ? CIRCUMFERENCE - (CIRCUMFERENCE * score) / 100
    : CIRCUMFERENCE

  // Stroke colour by score
  const strokeColor =
    score === null  ? '#64748b' :
    score <= 30     ? '#10b981' :   // emerald — CALM
    score <= 60     ? '#eab308' :   // yellow  — CLOUDY
    score <= 80     ? '#f97316' :   // orange  — STORM
                      '#ef4444'     // red     — HURRICANE

  // Risk environment label
  const envLabel =
    score === null  ? 'LOADING'       :
    score <= 30     ? 'CALM'          :
    score <= 60     ? 'ELEVATED RISK' :
    score <= 80     ? 'HIGH RISK'     :
                      'CRITICAL RISK'

  const envBg =
    score === null  ? 'rgba(100,116,139,0.1)' :
    score <= 30     ? 'rgba(16,185,129,0.1)'  :
    score <= 60     ? 'rgba(234,179,8,0.1)'   :
    score <= 80     ? 'rgba(249,115,22,0.1)'  :
                      'rgba(239,68,68,0.1)'

  const envBorder =
    score === null  ? 'rgba(100,116,139,0.3)' :
    score <= 30     ? 'rgba(16,185,129,0.3)'  :
    score <= 60     ? 'rgba(234,179,8,0.3)'   :
    score <= 80     ? 'rgba(249,115,22,0.3)'  :
                      'rgba(239,68,68,0.3)'

  return (
    <div
      className="spotlight-card rounded-sm p-6 sm:p-8 flex flex-col min-h-[420px] sm:min-h-[450px]"
      style={{ position: 'relative', overflow: 'hidden', background: '#0B1220', border: '1px solid rgba(255,255,255,0.08)', transition: 'border-color 0.3s' }}
    >
      {/* Header */}
      <div className="flex flex-wrap justify-between items-start gap-3 mb-8 sm:mb-12">
        <div>
          <h2
            className="text-xs font-bold uppercase mb-1"
            style={{ letterSpacing: '0.2em', color: '#94a3b8' }}
          >
            Risk Metric
          </h2>
          <p className="text-lg sm:text-xl font-medium text-white">Volatility Risk Score (VRS)</p>
          <p className="text-xs mt-1" style={{ color: '#64748b' }}>
            {updatedAt ? `Updated ${updatedAt}` : 'Awaiting oracle...'}
          </p>
        </div>
        <div
          className="px-3 sm:px-4 py-1.5 rounded-sm text-[10px] font-bold uppercase"
          style={{ letterSpacing: '0.15em', backgroundColor: envBg, border: `1px solid ${envBorder}`, color: strokeColor }}
        >
          {envLabel}
        </div>
      </div>

      {/* Circular gauge */}
      <div className="flex-1 flex flex-col items-center justify-center py-4 sm:py-6">
        <div className="relative w-52 h-52 sm:w-72 sm:h-72">
          <svg className="w-full h-full" style={{ transform: 'rotate(-90deg)' }} viewBox="0 0 288 288">
            {/* Track */}
            <circle
              cx="144" cy="144" r={RADIUS}
              fill="transparent"
              stroke="rgba(255,255,255,0.05)"
              strokeWidth="4"
            />
            {/* Progress arc */}
            <circle
              cx="144" cy="144" r={RADIUS}
              fill="transparent"
              stroke={strokeColor}
              strokeWidth="6"
              strokeLinecap="square"
              strokeDasharray={CIRCUMFERENCE}
              strokeDashoffset={dashOffset}
              style={{ transition: 'stroke-dashoffset 1s ease, stroke 0.5s ease' }}
            />
          </svg>

          {/* Centre text */}
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <span
              className="font-light tabular-nums leading-none"
              style={{ fontSize: 'clamp(2.5rem, 8vw, 4.5rem)', color: score !== null ? strokeColor : '#64748b' }}
            >
              {score !== null ? score : '--'}
            </span>
            <span
              className="text-xs font-bold uppercase mt-2"
              style={{ letterSpacing: '0.3em', color: strokeColor }}
            >
              {feeInfo?.label ?? (score !== null ? envLabel : 'VRS')}
            </span>
            {feeInfo && (
              <span className="text-sm mt-1" style={{ color: '#94a3b8' }}>
                {feeInfo.emoji}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Current fee row */}
      <div
        className="rounded-sm p-3 sm:p-4 flex items-center justify-between mb-4 sm:mb-6"
        style={{ backgroundColor: '#111827', border: '1px solid rgba(255,255,255,0.06)' }}
      >
        <div>
          <p className="text-[10px] uppercase mb-0.5" style={{ color: '#64748b', letterSpacing: '0.1em' }}>Current Swap Fee</p>
          <p className="text-xl sm:text-2xl font-bold" style={{ color: feeInfo?.color ? undefined : '#94a3b8', ...(feeInfo && { color: strokeColor }) }}>
            {feeInfo ? feeInfo.bps : '--'}
          </p>
        </div>
        <div className="text-right">
          <p className="text-[10px] uppercase mb-0.5" style={{ color: '#64748b', letterSpacing: '0.1em' }}>Risk Level</p>
          <p className="text-base sm:text-lg font-semibold" style={{ color: strokeColor }}>
            {(level as string) ?? '--'}
          </p>
        </div>
      </div>

      {/* 4-level legend */}
      <div className="grid grid-cols-4 gap-2 sm:gap-4 pt-4 sm:pt-6 border-t" style={{ borderColor: 'rgba(255,255,255,0.08)' }}>
        {[
          { label: '01 / Calm',     bar: 'rgba(16,185,129,0.4)',  active: score !== null && score <= 30  },
          { label: '02 / Cloudy',   bar: 'rgba(234,179,8,0.4)',   active: score !== null && score > 30 && score <= 60 },
          { label: '03 / Storm',     bar: 'rgba(249,115,22,0.8)', active: score !== null && score > 60 && score <= 80 },
          { label: '04 / Hurricane', bar: 'rgba(239,68,68,0.6)',  active: score !== null && score > 80  },
        ].map(tier => (
          <div key={tier.label} className="space-y-1.5 sm:space-y-2">
            <div className="h-1 rounded-full overflow-hidden" style={{ backgroundColor: 'rgba(255,255,255,0.05)' }}>
              <div
                className="h-full rounded-full transition-all duration-500"
                style={{ backgroundColor: tier.bar, width: tier.active ? '100%' : '0%' }}
              />
            </div>
            <span
              className="text-[9px] sm:text-[10px] font-bold uppercase block"
              style={{ letterSpacing: '0.1em', color: tier.active ? '#f1f5f9' : '#475569' }}
            >
              {tier.label}
            </span>
          </div>
        ))}
      </div>

      <p className="mt-3 text-[10px] text-center" style={{ color: '#334155' }}>
        Fee overridden per-swap based on live VRS — pushed by the Reactive Network RSC
      </p>
    </div>
  )
}
