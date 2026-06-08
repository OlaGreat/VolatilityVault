'use client'

import { useEffect, useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { formatEther } from 'viem'
import Link from 'next/link'
import { CONTRACTS, ERC20_ABI } from '@/lib/contracts'
import { getPositions, type StoredPosition } from '@/lib/positions'
import { Sidebar } from '@/components/Sidebar'

const MS: React.CSSProperties = {
  fontFamily: 'Material Symbols Outlined',
  fontVariationSettings: "'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24",
  lineHeight: 1,
  display: 'inline-block',
  verticalAlign: 'middle',
}

export default function PositionsPage() {
  const { address, isConnected } = useAccount()
  const [positions, setPositions] = useState<StoredPosition[]>([])

  // ── All original data reads preserved exactly ──
  useEffect(() => {
    if (address) {
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

  // ── Shared page wrapper (sidebar + content) ──
  const PageShell = ({ children }: { children: React.ReactNode }) => (
    <>
      <style>{`
        .pos-panel {
          background: rgba(27,31,44,0.7);
          border: 1px solid rgba(255,255,255,0.08);
        }
        .pos-spotlight { position: relative; overflow: hidden; }
        .pos-spotlight::before {
          content: '';
          position: absolute; inset: 0;
          background: radial-gradient(circle at var(--px,50%) var(--py,50%), rgba(255,255,255,0.025) 0%, transparent 65%);
          pointer-events: none; z-index: 1;
        }
        .tr-hover:hover { background: rgba(255,255,255,0.02); }
      `}</style>
      <div className="flex min-h-screen" style={{ paddingTop: '64px' }}>
        <Sidebar />
        <main
          className="flex-1 min-w-0 px-4 sm:px-8 lg:px-10 py-8 pb-20 lg:ml-56 xl:ml-64"
          style={{ color: '#dfe1f4' }}
          onMouseMove={e => {
            document.querySelectorAll<HTMLElement>('.pos-spotlight').forEach(el => {
              const r = el.getBoundingClientRect()
              el.style.setProperty('--px', `${((e.clientX - r.left) / r.width) * 100}%`)
              el.style.setProperty('--py', `${((e.clientY - r.top) / r.height) * 100}%`)
            })
          }}
        >
          {children}
        </main>
      </div>
    </>
  )

  // ── Not connected ──
  if (!isConnected) {
    return (
      <PageShell>
        <div className="flex flex-col items-center justify-center min-h-[60vh] text-center">
          <div className="w-14 h-14 rounded-sm flex items-center justify-center mb-6"
            style={{ background: '#0B1220', border: '1px solid rgba(255,255,255,0.08)' }}>
            <span style={{ ...MS, fontSize: '28px', color: '#38bdf8' }}>query_stats</span>
          </div>
          <h2 className="text-xl font-semibold text-white mb-2">Connect Your Wallet</h2>
          <p className="text-sm mb-1" style={{ color: '#94a3b8' }}>Connect to view positions on Ethereum Sepolia</p>
        </div>
      </PageShell>
    )
  }

  return (
    <PageShell>
      {/* ── Page header ── */}
      <header className="mb-8">
        <h1 className="text-2xl sm:text-3xl font-semibold text-white tracking-tight mb-1">
          Active Positions
        </h1>
        <p className="text-sm sm:text-base" style={{ color: '#94a3b8' }}>
          Real-time oversight of liquidity deployments within Terminal 01.
        </p>
      </header>

      {/* ── Stat boxes: VTKA / VTKB / Total ── */}
      <section className="grid grid-cols-1 sm:grid-cols-3 gap-4 sm:gap-6 mb-8">
        {[
          { label: 'VTKA Balance',    value: vtka,                     icon: 'token',             sub: 'live on-chain' },
          { label: 'VTKB Balance',    value: vtkb,                     icon: 'currency_exchange', sub: 'live on-chain' },
          { label: 'Total Deposited', value: totalDeposited.toFixed(2), icon: 'waves',             sub: 'VTKA liquidity units', accent: true },
        ].map(s => (
          <div
            key={s.label}
            className="pos-panel pos-spotlight rounded-sm p-5 flex flex-col gap-3"
          >
            <div className="flex justify-between items-start">
              <span
                className="text-[10px] font-bold uppercase"
                style={{ letterSpacing: '0.15em', color: '#94a3b8' }}
              >
                {s.label}
              </span>
              <span style={{ ...MS, fontSize: '18px', color: '#94a3b8' }}>{s.icon}</span>
            </div>
            <div>
              <span
                className="text-2xl sm:text-3xl font-semibold tabular-nums"
                style={{ color: s.accent ? '#38bdf8' : '#f1f5f9' }}
              >
                {s.value}
              </span>
              <span
                className="block text-[11px] mt-0.5"
                style={{ color: '#64748b' }}
              >
                {s.sub}
              </span>
            </div>
          </div>
        ))}
      </section>

      {/* ── Deposit history table ── */}
      <section className="pos-panel pos-spotlight rounded-sm mb-8 overflow-hidden">
        {/* Table header bar */}
        <div
          className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 px-5 sm:px-6 py-4"
          style={{ borderBottom: '1px solid rgba(255,255,255,0.05)', background: 'rgba(255,255,255,0.01)' }}
        >
          <h2 className="text-base font-semibold text-white flex items-center gap-2">
            <span style={{ ...MS, fontSize: '18px', color: '#94a3b8' }}>history</span>
            Deposit History
          </h2>
          <div className="flex items-center gap-2">
            <span className="text-[11px]" style={{ color: '#64748b' }}>Most recent first</span>
            <Link
              href="/deposit"
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-sm text-[11px] font-bold uppercase transition-opacity hover:opacity-80"
              style={{ background: '#38bdf8', color: '#050814', letterSpacing: '0.08em' }}
            >
              <span style={{ ...MS, fontSize: '14px', color: '#050814' }}>add</span>
              Add More
            </Link>
          </div>
        </div>

        {positions.length === 0 ? (
          /* Empty state */
          <div className="flex flex-col items-center justify-center py-16 text-center px-4">
            <div
              className="w-14 h-14 rounded-sm flex items-center justify-center mb-5"
              style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)' }}
            >
              <span style={{ ...MS, fontSize: '28px', color: '#475569' }}>folder_off</span>
            </div>
            <h3 className="text-lg font-semibold text-white mb-2">No Active Positions</h3>
            <p className="text-sm mb-6 max-w-sm" style={{ color: '#64748b' }}>
              Initialize your first liquidity deployment to begin earning yield.
            </p>
            <Link
              href="/deposit"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-sm text-sm font-bold uppercase transition-opacity hover:opacity-80"
              style={{ background: '#38bdf8', color: '#050814', letterSpacing: '0.08em' }}
            >
              <span style={{ ...MS, fontSize: '16px', color: '#050814' }}>add</span>
              Open Position
            </Link>
          </div>
        ) : (
          /* Positions table */
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr
                  className="text-[10px] font-semibold uppercase"
                  style={{ letterSpacing: '0.18em', color: '#64748b', background: 'rgba(255,255,255,0.02)', borderBottom: '1px solid rgba(255,255,255,0.05)' }}
                >
                  {['Amount', 'Timestamp', 'Target APY', 'Max IL', 'Payout', 'Transaction'].map(h => (
                    <th key={h} className="px-5 sm:px-6 py-3 font-semibold">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {positions.map((p, i) => (
                  <tr
                    key={i}
                    className="tr-hover transition-colors"
                    style={{ borderBottom: '1px solid rgba(255,255,255,0.04)' }}
                  >
                    <td className="px-5 sm:px-6 py-4 text-sm font-medium text-white whitespace-nowrap">
                      {parseFloat(p.amount).toFixed(2)} VTKA
                    </td>
                    <td className="px-5 sm:px-6 py-4 text-xs whitespace-nowrap" style={{ color: '#94a3b8' }}>
                      {new Date(p.timestamp).toLocaleString()}
                    </td>
                    <td className="px-5 sm:px-6 py-4 text-sm font-mono" style={{ color: '#38bdf8' }}>
                      {p.targetAPY}%
                    </td>
                    <td className="px-5 sm:px-6 py-4 text-sm font-mono" style={{ color: '#ffb4ab' }}>
                      {p.maxIL}%
                    </td>
                    <td className="px-5 sm:px-6 py-4">
                      <span
                        className="text-[11px] font-bold px-2 py-0.5 rounded-sm uppercase"
                        style={{ background: 'rgba(56,189,248,0.08)', border: '1px solid rgba(56,189,248,0.2)', color: '#38bdf8' }}
                      >
                        {p.payout}
                      </span>
                    </td>
                    <td className="px-5 sm:px-6 py-4">
                      <a
                        href={`https://sepolia.etherscan.io/tx/${p.txHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1.5 text-xs transition-colors"
                        style={{ color: '#64748b' }}
                        onMouseEnter={e => (e.currentTarget.style.color = '#38bdf8')}
                        onMouseLeave={e => (e.currentTarget.style.color = '#64748b')}
                      >
                        Etherscan
                        <span style={{ ...MS, fontSize: '13px' }}>open_in_new</span>
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ── Honest note (preserved from original) ── */}
      <div
        className="rounded-sm p-4"
        style={{ background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.05)' }}
      >
        <p className="text-xs leading-relaxed" style={{ color: '#475569' }}>
          <span style={{ color: '#64748b', fontWeight: 600 }}>Note:</span>{' '}
          Deposits route through Uniswap's shared test liquidity router, which owns the underlying
          V4 position — per-wallet position data is tracked here in your browser, while token
          balances above are live on-chain reads. A production deployment would mint an{' '}
          <span className="font-mono">LPPositionNFT</span> per deposit for fully on-chain position ownership.
        </p>
      </div>

    </PageShell>
  )
}
