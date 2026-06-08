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

              {/* ── Deposit section with stepper ── */}
              <section className="mb-10 sm:mb-14">

                {/* Stepper header */}
                <div className="flex items-center gap-3 sm:gap-4 mb-8 sm:mb-10 overflow-x-auto pb-1 no-scrollbar">
                  {/* Step 1 — active */}
                  <div className="flex items-center gap-2 sm:gap-3 shrink-0">
                    <div
                      className="w-6 h-6 sm:w-7 sm:h-7 rounded-full flex items-center justify-center text-[11px] font-bold"
                      style={{ background: '#38bdf8', color: '#050814' }}
                    >
                      1
                    </div>
                    <span
                      className="text-[11px] sm:text-[13px] font-bold uppercase whitespace-nowrap"
                      style={{ letterSpacing: '0.1em', color: '#fff' }}
                    >
                      Select Assets
                    </span>
                  </div>
                  <div className="stepper-line hidden sm:block" />
                  {/* Step 2 */}
                  <div className="flex items-center gap-2 sm:gap-3 shrink-0">
                    <div
                      className="w-6 h-6 sm:w-7 sm:h-7 rounded-full border flex items-center justify-center text-[11px] font-bold"
                      style={{ borderColor: 'rgba(255,255,255,0.12)', color: '#94a3b8' }}
                    >
                      2
                    </div>
                    <span
                      className="text-[11px] sm:text-[13px] font-bold uppercase whitespace-nowrap"
                      style={{ letterSpacing: '0.1em', color: '#94a3b8' }}
                    >
                      Configure Range
                    </span>
                  </div>
                  <div className="stepper-line hidden sm:block" />
                  {/* Step 3 */}
                  <div className="flex items-center gap-2 sm:gap-3 shrink-0">
                    <div
                      className="w-6 h-6 sm:w-7 sm:h-7 rounded-full border flex items-center justify-center text-[11px] font-bold"
                      style={{ borderColor: 'rgba(255,255,255,0.12)', color: '#94a3b8' }}
                    >
                      3
                    </div>
                    <span
                      className="text-[11px] sm:text-[13px] font-bold uppercase whitespace-nowrap"
                      style={{ letterSpacing: '0.1em', color: '#94a3b8' }}
                    >
                      Confirm
                    </span>
                  </div>
                </div>

                {/* Deposit form card */}
                <div className="dash-spotlight rounded-sm p-6 sm:p-8 w-full max-w-2xl">
                  <h3 className="text-lg sm:text-xl font-medium text-white mb-6 sm:mb-8">
                    Deposit Liquidity
                  </h3>
                  <div className="space-y-5 sm:space-y-6">

                    {/* Token A */}
                    <div>
                      <label
                        className="block text-[11px] font-bold uppercase mb-2"
                        style={{ letterSpacing: '0.15em', color: '#94a3b8' }}
                      >
                        Vault Token A
                      </label>
                      <div className="relative">
                        <input
                          readOnly
                          placeholder="0.00"
                          className="w-full px-4 py-3 text-white rounded-sm transition-colors"
                          style={{
                            background: '#050814',
                            border: '1px solid rgba(255,255,255,0.08)',
                            outline: 'none',
                          }}
                          onFocus={e => (e.target.style.borderColor = '#38bdf8')}
                          onBlur={e => (e.target.style.borderColor = 'rgba(255,255,255,0.08)')}
                        />
                        <span
                          className="absolute right-4 top-1/2 -translate-y-1/2 text-xs font-bold"
                          style={{ color: '#94a3b8' }}
                        >
                          VTKA
                        </span>
                      </div>
                    </div>

                    {/* Token B */}
                    <div>
                      <label
                        className="block text-[11px] font-bold uppercase mb-2"
                        style={{ letterSpacing: '0.15em', color: '#94a3b8' }}
                      >
                        Vault Token B
                      </label>
                      <div className="relative">
                        <input
                          readOnly
                          placeholder="0.00"
                          className="w-full px-4 py-3 text-white rounded-sm transition-colors"
                          style={{
                            background: '#050814',
                            border: '1px solid rgba(255,255,255,0.08)',
                            outline: 'none',
                          }}
                          onFocus={e => (e.target.style.borderColor = '#38bdf8')}
                          onBlur={e => (e.target.style.borderColor = 'rgba(255,255,255,0.08)')}
                        />
                        <span
                          className="absolute right-4 top-1/2 -translate-y-1/2 text-xs font-bold"
                          style={{ color: '#94a3b8' }}
                        >
                          VTKB
                        </span>
                      </div>
                    </div>

                    {/* Protection profiles */}
                    <div className="pt-2">
                      <label
                        className="block text-[11px] font-bold uppercase mb-3 sm:mb-4"
                        style={{ letterSpacing: '0.15em', color: '#94a3b8' }}
                      >
                        Protection Profile
                      </label>
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
                        <div
                          className="p-4 rounded-sm cursor-pointer"
                          style={{ border: '2px solid #38bdf8', background: 'rgba(56,189,248,0.05)' }}
                        >
                          <p className="text-sm font-bold text-white mb-1">Dynamic Buffer</p>
                          <p className="text-[11px] leading-normal" style={{ color: '#94a3b8' }}>
                            Optimized for yield capture during volatility storms. Fees accumulate in the buffer.
                          </p>
                        </div>
                        <div
                          className="p-4 rounded-sm cursor-pointer transition-colors"
                          style={{ border: '1px solid rgba(255,255,255,0.08)' }}
                          onMouseEnter={e => (e.currentTarget.style.borderColor = 'rgba(255,255,255,0.2)')}
                          onMouseLeave={e => (e.currentTarget.style.borderColor = 'rgba(255,255,255,0.08)')}
                        >
                          <p className="text-sm font-bold text-white mb-1">Static Stability</p>
                          <p className="text-[11px] leading-normal" style={{ color: '#94a3b8' }}>
                            Fixed range with lower VRS sensitivity for steady, predictable returns.
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* CTA — links to the real deposit page with all its functionality */}
                    <Link
                      href="/deposit"
                      className="w-full block text-center py-3.5 sm:py-4 font-bold text-[13px] uppercase rounded-sm transition-opacity hover:opacity-90 mt-2"
                      style={{
                        background: '#38bdf8',
                        color: '#050814',
                        letterSpacing: '0.15em',
                      }}
                    >
                      Open Full Deposit Terminal →
                    </Link>
                  </div>
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
