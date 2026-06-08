'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { formatEther } from 'viem'
import { CONTRACTS, YIELD_BUFFER_ABI } from '@/lib/contracts'
import { Sidebar } from '@/components/Sidebar'

const MS: React.CSSProperties = {
  fontFamily: 'Material Symbols Outlined',
  fontVariationSettings: "'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24",
  lineHeight: 1,
  display: 'inline-block',
  verticalAlign: 'middle',
}

const MS_FILL: React.CSSProperties = {
  ...MS,
  fontVariationSettings: "'FILL' 1,'wght' 400,'GRAD' 0,'opsz' 24",
}

export default function BufferPage() {
  const { address, isConnected } = useAccount()

  // ── All original contract reads preserved exactly ──
  const { data: currentEpoch } = useReadContract({
    address: CONTRACTS.YIELD_BUFFER, abi: YIELD_BUFFER_ABI,
    functionName: 'currentEpoch',
    query: { refetchInterval: 8000 },
  })
  const { data: epochData } = useReadContract({
    address: CONTRACTS.YIELD_BUFFER, abi: YIELD_BUFFER_ABI,
    functionName: 'epochs',
    args: currentEpoch !== undefined ? [currentEpoch] : undefined,
    query: { enabled: currentEpoch !== undefined, refetchInterval: 8000 },
  })
  const { data: claimable } = useReadContract({
    address: CONTRACTS.YIELD_BUFFER, abi: YIELD_BUFFER_ABI,
    functionName: 'previewClaim',
    args: address && currentEpoch !== undefined ? [address, currentEpoch > 0n ? currentEpoch - 1n : 0n] : undefined,
    query: { enabled: !!address && currentEpoch !== undefined },
  })
  const { data: lpShare } = useReadContract({
    address: CONTRACTS.YIELD_BUFFER, abi: YIELD_BUFFER_ABI,
    functionName: 'lpLiquidity',
    args: address && currentEpoch !== undefined ? [address, currentEpoch] : undefined,
    query: { enabled: !!address && currentEpoch !== undefined },
  })

  const { writeContract, data: claimHash, isPending } = useWriteContract()
  const { isSuccess } = useWaitForTransactionReceipt({ hash: claimHash })

  // ── All original derived values preserved exactly ──
  const epoch     = currentEpoch !== undefined ? Number(currentEpoch) : null
  const fees      = epochData ? formatEther(epochData[0] as bigint) : '0'
  const yield_    = epochData ? formatEther(epochData[1] as bigint) : '0'
  const totalLiq  = epochData ? formatEther(epochData[2] as bigint) : '0'
  const isActive  = epochData ? Boolean(epochData[4]) : false
  const isDeployed = epochData ? Boolean(epochData[6]) : false
  const myShare   = lpShare   ? formatEther(lpShare as bigint) : '0'
  const myClaim   = claimable ? formatEther(claimable as bigint) : '0'

  // ── Original claim handler preserved exactly ──
  function handleClaim() {
    if (currentEpoch === undefined || currentEpoch === 0n) return
    writeContract({
      address: CONTRACTS.YIELD_BUFFER,
      abi: YIELD_BUFFER_ABI,
      functionName: 'claim',
      args: [currentEpoch - 1n],
    })
  }

  return (
    <>
      <style>{`
        .buf-glass {
          background: rgba(255,255,255,0.02);
          backdrop-filter: blur(20px);
          border: 1px solid rgba(255,255,255,0.08);
        }
        .buf-spotlight { position: relative; overflow: hidden; transition: border-color 0.3s; }
        .buf-spotlight:hover { border-color: rgba(138,235,255,0.2); }
        .buf-spotlight::before {
          content: '';
          position: absolute; inset: 0;
          background: radial-gradient(400px circle at var(--mx,50%) var(--my,50%), rgba(138,235,255,0.04), transparent 40%);
          z-index: 0; pointer-events: none;
        }
        .buf-inner { position: relative; z-index: 1; }
      `}</style>

      <div className="flex min-h-screen" style={{ paddingTop: '64px' }}>
        <Sidebar />

        <main
          className="flex-1 min-w-0 px-4 sm:px-8 lg:px-10 py-8 pb-20 lg:ml-56 xl:ml-64"
          style={{ color: '#dfe1f4' }}
          onMouseMove={e => {
            document.querySelectorAll<HTMLElement>('.buf-spotlight').forEach(el => {
              const r = el.getBoundingClientRect()
              el.style.setProperty('--mx', `${e.clientX - r.left}px`)
              el.style.setProperty('--my', `${e.clientY - r.top}px`)
            })
          }}
        >
          {/* ── Page header ── */}
          <header className="mb-8">
            <div className="flex items-center gap-2 mb-2" style={{ color: '#38bdf8' }}>
              <span style={{ ...MS, fontSize: '18px' }}>shield</span>
              <span className="text-[11px] font-bold uppercase" style={{ letterSpacing: '0.2em' }}>
                Stabilization Protocol
              </span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-semibold text-white tracking-tight mb-1">
              Yield Buffer
            </h1>
            <p className="text-sm sm:text-base max-w-2xl leading-relaxed" style={{ color: '#94a3b8' }}>
              Storm-period fees accumulate here, earn yield on Aave / Morpho, then distribute
              to LPs proportionally when VRS returns to calm.
            </p>
          </header>

          {/* ── Analytics grid ── */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-12 gap-4 sm:gap-6 mb-8">

            {/* Left 8-col: 4 stat cards */}
            <div className="lg:col-span-8 grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6">

              {/* Active Epoch */}
              <div className="buf-glass buf-spotlight rounded-sm p-5 sm:p-6">
                <div className="buf-inner flex justify-between items-start mb-4">
                  <span className="text-[10px] font-bold uppercase" style={{ letterSpacing: '0.18em', color: '#94a3b8' }}>
                    Active Epoch
                  </span>
                  <div className="flex items-center gap-1.5 px-2 py-0.5 rounded-full"
                    style={{ background: isActive ? 'rgba(56,189,248,0.1)' : 'rgba(255,255,255,0.05)' }}>
                    <span className={`w-1.5 h-1.5 rounded-full ${isActive ? 'animate-pulse' : ''}`}
                      style={{ backgroundColor: isActive ? '#38bdf8' : '#475569' }} />
                    <span className="text-[10px] font-bold" style={{ color: isActive ? '#38bdf8' : '#64748b' }}>
                      {isActive ? 'LIVE' : 'DISTRIBUTING'}
                    </span>
                  </div>
                </div>
                <div className="buf-inner">
                  <div className="text-3xl sm:text-4xl font-semibold text-white tabular-nums mb-1">
                    {epoch !== null ? `#${epoch}` : '--'}
                  </div>
                  <div className="flex items-center gap-1.5 text-xs" style={{ color: '#94a3b8' }}>
                    <span style={{ ...MS, fontSize: '14px' }}>schedule</span>
                    <span>Current buffer epoch</span>
                  </div>
                </div>
              </div>

              {/* Fees Held */}
              <div className="buf-glass buf-spotlight rounded-sm p-5 sm:p-6">
                <span className="buf-inner block text-[10px] font-bold uppercase mb-4"
                  style={{ letterSpacing: '0.18em', color: '#94a3b8' }}>
                  Fees Held
                </span>
                <div className="buf-inner">
                  <div className="text-2xl sm:text-3xl font-semibold text-white font-mono tabular-nums mb-1">
                    {parseFloat(fees).toFixed(4)}
                    <span className="text-base font-normal ml-1" style={{ color: '#94a3b8' }}>VTKA</span>
                  </div>
                  <div className="flex items-center gap-1" style={{ color: '#38bdf8' }}>
                    <span style={{ ...MS, fontSize: '14px' }}>trending_up</span>
                    <span className="text-xs">Storm-period accumulation</span>
                  </div>
                </div>
              </div>

              {/* Yield Earned */}
              <div className="buf-glass buf-spotlight rounded-sm p-5 sm:p-6">
                <span className="buf-inner block text-[10px] font-bold uppercase mb-4"
                  style={{ letterSpacing: '0.18em', color: '#94a3b8' }}>
                  Yield Earned
                </span>
                <div className="buf-inner">
                  <div className="text-2xl sm:text-3xl font-semibold font-mono tabular-nums mb-1"
                    style={{ color: '#bdc2ff' }}>
                    {parseFloat(yield_).toFixed(6)}
                    <span className="text-base font-normal ml-1" style={{ color: '#94a3b8' }}>VTKA</span>
                  </div>
                  <div className="text-xs" style={{ color: '#94a3b8' }}>
                    {isDeployed ? 'Deployed to yield router' : 'Holding in vault'}
                  </div>
                </div>
              </div>

              {/* Total Liquidity + utilisation bar */}
              <div className="buf-glass buf-spotlight rounded-sm p-5 sm:p-6">
                <div className="buf-inner flex justify-between items-center mb-4">
                  <span className="text-[10px] font-bold uppercase"
                    style={{ letterSpacing: '0.18em', color: '#94a3b8' }}>
                    Total Liquidity
                  </span>
                  <span className="text-[10px]" style={{ color: '#94a3b8' }}>
                    {isDeployed ? 'Deployed' : 'Vault'}
                  </span>
                </div>
                <div className="buf-inner">
                  <div className="text-2xl sm:text-3xl font-semibold text-white font-mono tabular-nums mb-3">
                    {parseFloat(totalLiq).toFixed(2)}
                  </div>
                  <div className="w-full h-1 rounded-full overflow-hidden" style={{ background: 'rgba(255,255,255,0.05)' }}>
                    <div className="h-full rounded-full" style={{ backgroundColor: '#38bdf8', width: '65%' }} />
                  </div>
                </div>
              </div>
            </div>

            {/* Right 4-col: settlement/claim card */}
            <div className="lg:col-span-4">
              <div
                className="buf-glass rounded-sm p-5 sm:p-6 h-full flex flex-col relative overflow-hidden"
                style={{ border: '1px solid rgba(56,189,248,0.2)' }}
              >
                {/* Decorative icon */}
                <div className="absolute top-0 right-0 p-4 opacity-10">
                  <span style={{ ...MS, fontSize: '64px' }}>stars</span>
                </div>

                <div className="relative z-10 mb-6">
                  <span className="text-[10px] font-bold uppercase block mb-3"
                    style={{ letterSpacing: '0.18em', color: '#38bdf8' }}>
                    Settlement Center
                  </span>
                  <h3 className="text-lg font-semibold text-white mb-2">
                    {epoch !== null ? `Epoch ${epoch > 0 ? epoch - 1 : 0} Ready` : 'Loading...'}
                  </h3>
                  <p className="text-xs leading-relaxed" style={{ color: '#94a3b8' }}>
                    {isConnected
                      ? 'Distribution finalizes after VRS returns to calm. Rewards available for immediate settlement.'
                      : 'Connect your wallet to view claimable rewards.'}
                  </p>
                </div>

                <div className="relative z-10 mt-auto">
                  {/* Claimable amount */}
                  <div className="mb-4">
                    <span className="text-[10px] font-bold uppercase block mb-1"
                      style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                      {isConnected ? 'Claimable Balance' : 'My Liquidity Share'}
                    </span>
                    <span className="text-3xl font-semibold font-mono tabular-nums leading-none"
                      style={{ color: parseFloat(myClaim) > 0 ? '#38bdf8' : '#475569' }}>
                      {isConnected ? parseFloat(myClaim).toFixed(4) : parseFloat(myShare).toFixed(4)}
                      <span className="text-lg font-normal ml-1" style={{ color: '#94a3b8' }}>VTKA</span>
                    </span>
                  </div>

                  {/* Claim button */}
                  <button
                    onClick={handleClaim}
                    disabled={!isConnected || isPending || parseFloat(myClaim) === 0 || !currentEpoch || currentEpoch === 0n}
                    className="w-full py-3.5 rounded-sm font-bold text-[13px] uppercase tracking-wider transition-opacity disabled:cursor-not-allowed disabled:opacity-40"
                    style={{ background: '#38bdf8', color: '#050814', letterSpacing: '0.12em' }}
                    onMouseEnter={e => { if (!e.currentTarget.disabled) e.currentTarget.style.opacity = '0.85' }}
                    onMouseLeave={e => { e.currentTarget.style.opacity = e.currentTarget.disabled ? '0.4' : '1' }}
                  >
                    {isPending ? '⟳ Claiming...' : `Claim ${parseFloat(myClaim).toFixed(4)} VTKA`}
                  </button>

                  {/* TX link */}
                  {claimHash && (
                    <a
                      href={`https://sepolia.etherscan.io/tx/${claimHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex items-center justify-center gap-1.5 text-xs mt-3 transition-colors"
                      style={{ color: '#64748b' }}
                      onMouseEnter={e => (e.currentTarget.style.color = '#38bdf8')}
                      onMouseLeave={e => (e.currentTarget.style.color = '#64748b')}
                    >
                      <span style={{ ...MS, fontSize: '13px' }}>open_in_new</span>
                      View on Etherscan
                    </a>
                  )}

                  {/* Success */}
                  {isSuccess && (
                    <div className="mt-3 p-3 rounded-sm text-center"
                      style={{ background: 'rgba(16,185,129,0.07)', border: '1px solid rgba(16,185,129,0.25)' }}>
                      <span style={{ ...MS_FILL, color: '#10b981' }}>check_circle</span>
                      <span className="text-sm font-semibold ml-2" style={{ color: '#10b981' }}>
                        Claimed successfully!
                      </span>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>

          {/* ── How the buffer works (original content preserved) ── */}
          <div
            className="rounded-sm px-5 sm:px-8 py-8 mb-8"
            style={{ background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.05)' }}
          >
            <div className="max-w-3xl mx-auto text-center mb-8">
              <h2 className="text-xl sm:text-2xl font-semibold text-white mb-2">Operational Framework</h2>
              <p className="text-sm" style={{ color: '#94a3b8' }}>
                The Yield Buffer is an automated insurance layer that absorbs volatility and converts
                storm-period fees into compounded LP yield.
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
              {[
                { n: '01', title: 'Capital Inflow',      body: 'During storms (VRS > 60), extra swap fees accumulate here instead of being distributed immediately — protecting against JIT liquidity attacks.' },
                { n: '02', title: 'Risk Absorption',     body: 'While fees sit in the buffer, the Reactive RSC deploys them to the yield router (Aave / Morpho) to earn additional yield.' },
                { n: '03', title: 'Fee Capture',         body: 'When VRS drops back to calm, Reactive triggers distribution. LPs receive their fees plus all yield earned.' },
                { n: '04', title: 'Yield Distribution',  body: "Each LP's share is proportional to their registered liquidity at deposit time." },
              ].map(step => (
                <div key={step.n} className="flex flex-col items-center text-center">
                  <div
                    className="w-12 h-12 rounded-full flex items-center justify-center mb-4 font-mono text-lg"
                    style={{ border: '1px solid rgba(255,255,255,0.1)', color: '#38bdf8' }}
                  >
                    {step.n}
                  </div>
                  <h4 className="text-base font-semibold text-white mb-2">{step.title}</h4>
                  <p className="text-xs leading-relaxed" style={{ color: '#94a3b8' }}>{step.body}</p>
                </div>
              ))}
            </div>
          </div>

        </main>
      </div>
    </>
  )
}
