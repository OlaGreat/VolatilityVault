'use client'

import { CONTRACTS } from '@/lib/contracts'

export function PoolStats() {
  const stats = [
    { label: 'Liquidity Pair',  value: 'VTKA / VTKB' },
    { label: 'Fee Model',       value: 'Dynamic (AI-controlled)' },
    { label: 'Tick Spacing',    value: '60' },
    { label: 'V4 Hook',         value: shortAddr(CONTRACTS.HOOK),         href: `https://sepolia.etherscan.io/address/${CONTRACTS.HOOK}` },
    { label: 'Pool Manager',    value: shortAddr(CONTRACTS.POOL_MANAGER), href: `https://sepolia.etherscan.io/address/${CONTRACTS.POOL_MANAGER}` },
  ]

  return (
    <div
      className="spotlight-card rounded-sm p-6 sm:p-8 flex flex-col h-full"
      style={{ background: '#0B1220', border: '1px solid rgba(255,255,255,0.08)' }}
    >
      {/* Header */}
      <h2
        className="text-xs font-bold uppercase mb-6 sm:mb-8"
        style={{ letterSpacing: '0.2em', color: '#94a3b8' }}
      >
        Asset Parameters
      </h2>

      {/* Stat rows */}
      <div className="space-y-4 sm:space-y-5 flex-1">
        {stats.map(s => (
          <div
            key={s.label}
            className="flex justify-between items-end pb-3 sm:pb-4 border-b"
            style={{ borderColor: 'rgba(255,255,255,0.06)' }}
          >
            <span className="text-xs sm:text-[13px]" style={{ color: '#94a3b8' }}>{s.label}</span>
            {s.href ? (
              <a
                href={s.href}
                target="_blank"
                rel="noopener noreferrer"
                className="font-mono text-xs sm:text-[13px] flex items-center gap-1.5 hover:underline"
                style={{ color: '#38bdf8' }}
              >
                {s.value}
                <span
                  style={{
                    fontFamily: 'Material Symbols Outlined',
                    fontVariationSettings: "'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24",
                    fontSize: '14px',
                  }}
                >
                  open_in_new
                </span>
              </a>
            ) : (
              <span className="font-medium text-white text-xs sm:text-[15px]">{s.value}</span>
            )}
          </div>
        ))}

        {/* Market depth mockup */}
        <div className="pt-2">
          <span
            className="text-[10px] font-bold uppercase block mb-3 sm:mb-4"
            style={{ letterSpacing: '0.15em', color: '#94a3b8' }}
          >
            Market Depth Profile
          </span>
          <div
            className="h-24 sm:h-32 rounded-sm border flex items-end p-2 gap-1 overflow-hidden"
            style={{ backgroundColor: '#111827', borderColor: 'rgba(255,255,255,0.06)' }}
          >
            {[60, 75, 90, 85, 70, 55, 40, 30].map((h, i) => (
              <div
                key={i}
                className="flex-1 rounded-none border-t transition-all duration-700"
                style={{
                  height: `${h}%`,
                  backgroundColor: i >= 2 && i <= 4 ? 'rgba(56,189,248,0.5)' : 'rgba(56,189,248,0.15)',
                  borderColor: i >= 2 && i <= 4 ? 'rgba(56,189,248,0.8)' : 'transparent',
                }}
              />
            ))}
          </div>
        </div>
      </div>

      {/* Pool ID */}
      <div
        className="mt-4 pt-4 border-t"
        style={{ borderColor: 'rgba(255,255,255,0.06)' }}
      >
        <p
          className="text-[10px] uppercase font-bold mb-1.5"
          style={{ color: '#475569', letterSpacing: '0.1em' }}
        >
          Pool ID
        </p>
        <p className="text-[10px] font-mono break-all" style={{ color: '#475569' }}>
          0x0e32107f870f47cac70d5501dc91328470a9e53b583bc9c677bab6aaedb5436b
        </p>
      </div>

      {/* CTA */}
      <button
        onClick={() => window.open(`https://sepolia.etherscan.io/address/${CONTRACTS.HOOK}`, '_blank')}
        className="w-full mt-4 py-2.5 sm:py-3 text-xs font-bold uppercase transition-colors"
        style={{
          backgroundColor: '#111827',
          border: '1px solid rgba(255,255,255,0.08)',
          color: '#f1f5f9',
          letterSpacing: '0.1em',
        }}
        onMouseEnter={e => (e.currentTarget.style.backgroundColor = '#1e293b')}
        onMouseLeave={e => (e.currentTarget.style.backgroundColor = '#111827')}
      >
        View Hook on Etherscan
      </button>
    </div>
  )
}

function shortAddr(addr: string) {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`
}
