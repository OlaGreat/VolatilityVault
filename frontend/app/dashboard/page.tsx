'use client'

import { VRSGauge }  from '@/components/VRSGauge'
import { PoolStats } from '@/components/PoolStats'
import { Sidebar }   from '@/components/Sidebar'
import Link          from 'next/link'

export default function Dashboard() {
  return (
    <>
      <style>{`
        .dash-spotlight {
          position: relative;
          overflow: hidden;
          background: #0B1220;
          border: 1px solid rgba(255,255,255,0.08);
          transition: border-color 0.3s ease;
        }
        .dash-spotlight:hover { border-color: rgba(255,255,255,0.14); }
        .dash-spotlight::before {
          content: '';
          position: absolute;
          inset: 0;
          background: radial-gradient(circle at var(--x,50%) var(--y,50%), rgba(255,255,255,0.04) 0%, transparent 55%);
          opacity: 0;
          transition: opacity 0.3s;
          pointer-events: none;
        }
        .dash-spotlight:hover::before { opacity: 1; }

        .stepper-line {
          height: 1px;
          background: rgba(255,255,255,0.08);
          flex: 1;
        }

        /* remove default main padding on this page */
        .dash-root { width: 100%; }
      `}</style>

      <div
        className="dash-root"
        onMouseMove={e => {
          /* spotlight tracking for all cards */
          document.querySelectorAll<HTMLElement>('.dash-spotlight').forEach(card => {
            const r = card.getBoundingClientRect()
            card.style.setProperty('--x', `${((e.clientX - r.left) / card.clientWidth) * 100}%`)
            card.style.setProperty('--y', `${((e.clientY - r.top) / card.clientHeight) * 100}%`)
          })
        }}
      >
        {/* ── Sidebar + main layout ── */}
        <div className="flex min-h-screen" style={{ paddingTop: '64px' /* navbar height */ }}>

          {/* ── Sidebar — uses shared component with live active state ── */}
          <Sidebar />

          {/* ── Main content — offset by sidebar width on large screens ── */}
          <main
            className="flex-1 min-w-0 px-4 sm:px-8 lg:px-12 py-8 sm:py-10 lg:ml-56 xl:ml-64"
          >
            {/* inner container — fills width on small screens, caps on xl */}
            <div className="w-full max-w-none xl:max-w-[1400px]" style={{ marginLeft: 0 }}>

              {/* ── Hero header ── */}
              <header className="mb-10 sm:mb-14">
                <h1 className="text-2xl sm:text-3xl lg:text-4xl font-semibold text-white tracking-tight mb-3">
                  VolatilityVault Terminal
                </h1>
                <p className="text-base sm:text-lg font-light leading-relaxed max-w-2xl" style={{ color: '#94a3b8' }}>
                  AI-driven LP protection on Uniswap V4. Real-time volatility scoring, dynamic fee
                  adjustments, and storm-fee yield buffering — all on Ethereum Sepolia.
                </p>
              </header>

              {/* ── Dashboard grid: VRSGauge (8 cols) + PoolStats (4 cols) ── */}
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 xl:gap-8 mb-10 sm:mb-14">
                <div className="lg:col-span-8">
                  <VRSGauge />
                </div>
                <div className="lg:col-span-4">
                  <PoolStats />
                </div>
              </div>


              {/* ── Quick actions ── */}
              <section className="mb-10 sm:mb-14">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 sm:gap-6">
                  {[
                    { href: '/deposit',   icon: 'account_balance_wallet', title: 'Add Liquidity', body: 'Deposit VTKA/VTKB and set your yield intent — the vault manages it automatically.' },
                    { href: '/positions', icon: 'query_stats',            title: 'My Positions',  body: 'Review your deposits, live balances, and on-chain LP intent.' },
                    { href: '/buffer',    icon: 'shield',                 title: 'Yield Buffer',  body: 'Track storm-fee accumulation and claim your share when the storm passes.' },
                  ].map(c => (
                    <Link
                      key={c.href}
                      href={c.href}
                      className="dash-spotlight rounded-sm p-6 sm:p-7 flex flex-col gap-3 transition-opacity hover:opacity-95"
                    >
                      <span style={{ fontFamily: 'Material Symbols Outlined', fontSize: '24px', color: '#38bdf8' }}>{c.icon}</span>
                      <span className="text-base font-medium text-white">{c.title}</span>
                      <span className="text-xs sm:text-sm leading-relaxed" style={{ color: '#94a3b8' }}>{c.body}</span>
                      <span className="text-[11px] font-bold uppercase mt-1" style={{ letterSpacing: '0.1em', color: '#38bdf8' }}>Open →</span>
                    </Link>
                  ))}
                </div>
              </section>

              {/* ── Operational architecture (How it works) ── */}
              <section>
                <h2
                  className="text-[10px] sm:text-[11px] font-bold uppercase text-center mb-8 sm:mb-10"
                  style={{ letterSpacing: '0.4em', color: 'rgba(148,163,184,0.5)' }}
                >
                  Operational Architecture
                </h2>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6 xl:gap-8">
                  {[
                    {
                      proc:  'PROC_01',
                      title: 'Reactive Monitoring',
                      body:  'Continuous ingestion of Uniswap V4 hook signals across 5 chains. Systems detect cross-chain price gaps and toxic order flow before settlement.',
                    },
                    {
                      proc:  'PROC_02',
                      title: 'VRS Calibration',
                      body:  'The Volatility Risk Score is updated every epoch — calm markets score 0–30 (0.05% fee), hurricanes 81–100 (0.50% fee). Score is pushed on-chain by the Reactive RSC.',
                    },
                    {
                      proc:  'PROC_03',
                      title: 'Dynamic Fee Peg',
                      body:  'Storm fees accumulate in the yield buffer, earning on Aave / Morpho. When VRS drops to calm, Reactive triggers automatic distribution back to LPs.',
                    },
                  ].map(card => (
                    <div
                      key={card.proc}
                      className="p-6 sm:p-8 rounded-sm"
                      style={{ border: '1px solid rgba(255,255,255,0.08)' }}
                    >
                      <span
                        className="font-mono text-xs block mb-3 sm:mb-4"
                        style={{ color: '#38bdf8' }}
                      >
                        {card.proc}
                      </span>
                      <h4 className="text-base sm:text-lg font-medium text-white mb-2 sm:mb-3">
                        {card.title}
                      </h4>
                      <p className="text-xs sm:text-sm leading-relaxed" style={{ color: '#94a3b8' }}>
                        {card.body}
                      </p>
                    </div>
                  ))}
                </div>
              </section>

            </div>
          </main>
        </div>
      </div>
    </>
  )
}
