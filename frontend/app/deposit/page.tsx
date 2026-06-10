'use client'

import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseEther, encodeAbiParameters, parseAbiParameters } from 'viem'
import { CONTRACTS, ERC20_ABI } from '@/lib/contracts'
import { savePosition } from '@/lib/positions'
import Link from 'next/link'
import { Sidebar } from '@/components/Sidebar'

// ── All original constants preserved exactly ──
const PAYOUT_OPTIONS = [
  { value: 0, label: 'Daily',    icon: 'calendar_today', desc: 'Small, frequent payouts as fees accumulate' },
  { value: 1, label: 'Lump Sum', icon: 'payments',       desc: 'Wait for storm events, collect bigger payouts' },
  { value: 2, label: 'Reinvest', icon: 'autorenew',      desc: 'Auto-compound fees back into your LP position' },
]

const LIQ_ROUTER_ABI = [
  {
    name: 'modifyLiquidity',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      {
        name: 'key',
        type: 'tuple',
        components: [
          { name: 'currency0',   type: 'address' },
          { name: 'currency1',   type: 'address' },
          { name: 'fee',         type: 'uint24'  },
          { name: 'tickSpacing', type: 'int24'   },
          { name: 'hooks',       type: 'address' },
        ],
      },
      {
        name: 'params',
        type: 'tuple',
        components: [
          { name: 'tickLower',      type: 'int24'   },
          { name: 'tickUpper',      type: 'int24'   },
          { name: 'liquidityDelta', type: 'int256'  },
          { name: 'salt',           type: 'bytes32' },
        ],
      },
      { name: 'hookData', type: 'bytes' },
    ],
    outputs: [{ name: 'delta', type: 'int256' }],
  },
] as const

// Shared inline style for Material Symbol icons
const MS: React.CSSProperties = {
  fontFamily: 'Material Symbols Outlined',
  fontVariationSettings: "'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24",
  fontSize: '18px',
  lineHeight: 1,
  display: 'inline-block',
  verticalAlign: 'middle',
}

const MS_FILLED: React.CSSProperties = {
  ...MS,
  fontVariationSettings: "'FILL' 1,'wght' 400,'GRAD' 0,'opsz' 24",
  fontSize: '14px',
}

export default function DepositPage() {
  // ── All original state preserved exactly ──
  const { address, isConnected } = useAccount()
  const [amount,    setAmount]    = useState('100')
  const [targetAPY, setTargetAPY] = useState('12')
  const [maxIL,     setMaxIL]     = useState('5')
  const [payout,    setPayout]    = useState(0)
  const [step,      setStep]      = useState<'idle'|'approving'|'approved'|'depositing'|'done'>('idle')
  const [error,     setError]     = useState<string | null>(null)

  const { writeContractAsync, data: txHash, isPending } = useWriteContract()
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  // hookData carries the LP address explicitly — in V4 the hook's `sender` is the
  // liquidity router, so the hook reads the real LP from here to register them in the buffer.
  function buildHookData() {
    return encodeAbiParameters(
      parseAbiParameters('address lp, uint256 targetAPY, uint256 maxILBps, uint8 payout'),
      [address as `0x${string}`, BigInt(Number(targetAPY) * 100), BigInt(Number(maxIL) * 100), payout]
    )
  }

  async function handleApprove() {
    setError(null)
    setStep('approving')
    try {
      const allowance = parseEther('1000000')
      await writeContractAsync({ address: CONTRACTS.TOKEN0, abi: ERC20_ABI, functionName: 'approve', args: [CONTRACTS.LIQ_ROUTER, allowance] })
      await writeContractAsync({ address: CONTRACTS.TOKEN1, abi: ERC20_ABI, functionName: 'approve', args: [CONTRACTS.LIQ_ROUTER, allowance] })
      setStep('approved')
    } catch (e: any) {
      setError(e?.shortMessage ?? e?.message ?? 'Approval failed')
      setStep('idle')
    }
  }

  async function handleDeposit() {
    setError(null)
    setStep('depositing')
    try {
      const hash = await writeContractAsync({
        address: CONTRACTS.LIQ_ROUTER,
        abi: LIQ_ROUTER_ABI,
        functionName: 'modifyLiquidity',
        args: [
          { currency0: CONTRACTS.TOKEN0, currency1: CONTRACTS.TOKEN1, fee: 0x800000, tickSpacing: 60, hooks: CONTRACTS.HOOK },
          { tickLower: -120, tickUpper: 120, liquidityDelta: parseEther(amount), salt: '0x0000000000000000000000000000000000000000000000000000000000000000' },
          buildHookData(),
        ],
      })
      if (address) {
        savePosition(address, { amount, targetAPY, maxIL, payout: PAYOUT_OPTIONS[payout].label, txHash: hash, timestamp: Date.now() })
      }
      setStep('done')
    } catch (e: any) {
      setError(e?.shortMessage ?? e?.message ?? 'Deposit failed')
      setStep('approved')
    }
  }

  // ── Stepper derived state ──
  const stepNum = step === 'idle' ? 1 : step === 'approving' ? 1 : step === 'approved' ? 2 : step === 'depositing' ? 2 : 3

  // ── Not connected state ──
  if (!isConnected) {
    return (
      <div className="flex min-h-screen" style={{ paddingTop: '64px' }}>
        <Sidebar />
        <div className="flex-1 flex flex-col items-center justify-center text-center px-4 lg:ml-56 xl:ml-64">
          <div
            className="w-14 h-14 rounded-sm flex items-center justify-center mb-6"
            style={{ background: '#0B1220', border: '1px solid rgba(255,255,255,0.08)' }}
          >
            <span style={{ ...MS, fontSize: '28px', color: '#38bdf8' }}>account_balance_wallet</span>
          </div>
          <h2 className="text-xl font-semibold text-white mb-2">Connect Your Wallet</h2>
          <p className="text-sm mb-1" style={{ color: '#94a3b8' }}>Connect to add liquidity to the VTKA / VTKB pool</p>
          <p className="text-xs" style={{ color: '#475569' }}>Make sure you're on Ethereum Sepolia</p>
        </div>
      </div>
    )
  }

  return (
    <>
      <style>{`
        .dp-input {
          background: #050814;
          border: 1px solid rgba(255,255,255,0.10);
          color: #f1f5f9;
          transition: border-color 0.2s ease;
          outline: none;
          width: 100%;
        }
        .dp-input:focus { border-color: #22D3EE; }
        .dp-input::-webkit-outer-spin-button,
        .dp-input::-webkit-inner-spin-button { -webkit-appearance: none; margin: 0; }
        .dp-input[type=number] { -moz-appearance: textfield; }
        .dp-card { background: #0B1220; border: 1px solid rgba(255,255,255,0.08); }
        .dp-step-active   { background: #22D3EE; color: #050814; }
        .dp-step-done     { background: rgba(34,211,238,0.15); border: 1px solid rgba(34,211,238,0.4); color: #22D3EE; }
        .dp-step-inactive { border: 1px solid rgba(255,255,255,0.15); color: #475569; }
        .dp-line          { height: 1px; flex: 1; background: rgba(255,255,255,0.10); }
        .dp-line-active   { background: #22D3EE; }
      `}</style>

      {/* Sidebar + content layout */}
      <div className="flex min-h-screen" style={{ paddingTop: '64px' }}>
        <Sidebar />

        {/* Main content offset by sidebar */}
        <div
          className="flex-1 min-w-0 px-4 sm:px-8 lg:px-10 py-8 pb-16 lg:ml-56 xl:ml-64"
          style={{ color: '#f1f5f9' }}
        >
        <div className="max-w-4xl mx-auto">

          {/* ── Page header ── */}
          <header className="mb-8">
            <h1 className="text-2xl sm:text-3xl font-semibold text-white tracking-tight mb-1">
              Liquid Provision
            </h1>
            <p className="text-sm sm:text-base" style={{ color: '#94a3b8' }}>
              Deploy liquidity into the VTKA / VTKB Uniswap V4 pool with on-chain yield intent.
            </p>
          </header>

          {/* ── Stepper ── */}
          <div className="flex items-center gap-3 mb-8 sm:mb-10 max-w-md overflow-x-auto pb-1">
            {/* Step 1 */}
            <div className="flex items-center gap-2 shrink-0">
              <div className={`w-7 h-7 rounded flex items-center justify-center text-[11px] font-bold ${stepNum > 1 ? 'dp-step-done' : stepNum === 1 ? 'dp-step-active' : 'dp-step-inactive'}`}>
                {stepNum > 1
                  ? <span style={MS_FILLED}>check</span>
                  : '1'}
              </div>
              <span className="text-[11px] font-bold uppercase whitespace-nowrap"
                style={{ letterSpacing: '0.08em', color: stepNum === 1 ? '#22D3EE' : stepNum > 1 ? '#64748b' : '#475569' }}>
                Approve
              </span>
            </div>
            <div className={`dp-line ${stepNum > 1 ? 'dp-line-active' : ''}`} />

            {/* Step 2 */}
            <div className="flex items-center gap-2 shrink-0">
              <div className={`w-7 h-7 rounded flex items-center justify-center text-[11px] font-bold ${stepNum > 2 ? 'dp-step-done' : stepNum === 2 ? 'dp-step-active' : 'dp-step-inactive'}`}>
                {stepNum > 2
                  ? <span style={MS_FILLED}>check</span>
                  : '2'}
              </div>
              <span className="text-[11px] font-bold uppercase whitespace-nowrap"
                style={{ letterSpacing: '0.08em', color: stepNum === 2 ? '#22D3EE' : stepNum > 2 ? '#64748b' : '#475569' }}>
                Deposit
              </span>
            </div>
            <div className={`dp-line ${stepNum > 2 ? 'dp-line-active' : ''}`} />

            {/* Step 3 */}
            <div className="flex items-center gap-2 shrink-0">
              <div className={`w-7 h-7 rounded flex items-center justify-center text-[11px] font-bold ${stepNum === 3 ? 'dp-step-active' : 'dp-step-inactive'}`}>
                {stepNum === 3
                  ? <span style={MS_FILLED}>check</span>
                  : '3'}
              </div>
              <span className="text-[11px] font-bold uppercase whitespace-nowrap"
                style={{ letterSpacing: '0.08em', color: stepNum === 3 ? '#22D3EE' : '#475569' }}>
                Finalize
              </span>
            </div>
          </div>

          {/* ── Main grid: form (3) + summary (2) ── */}
          <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">

            {/* ── LEFT: deposit form ── */}
            <div className="lg:col-span-3 dp-card rounded-sm p-5 sm:p-6 flex flex-col gap-5 sm:gap-6">

              {/* Amount */}
              <div>
                <label className="block text-[11px] font-bold uppercase mb-2"
                  style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                  Amount (VTKA)
                </label>
                <div className="relative">
                  <input
                    type="number"
                    value={amount}
                    onChange={e => setAmount(e.target.value)}
                    placeholder="0.00"
                    min="0"
                    className="dp-input rounded-sm px-4 py-3 text-lg font-mono pr-24"
                  />
                  <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-2">
                    <button
                      className="px-2 py-0.5 text-[10px] transition-colors"
                      style={{ border: '1px solid rgba(255,255,255,0.15)', color: '#94a3b8' }}
                      onMouseEnter={e => { e.currentTarget.style.borderColor = '#22D3EE'; e.currentTarget.style.color = '#22D3EE' }}
                      onMouseLeave={e => { e.currentTarget.style.borderColor = 'rgba(255,255,255,0.15)'; e.currentTarget.style.color = '#94a3b8' }}
                      onClick={() => setAmount('1000000')}
                      type="button"
                    >
                      MAX
                    </button>
                    <span className="text-xs font-bold" style={{ color: '#94a3b8' }}>VTKA</span>
                  </div>
                </div>
                <p className="text-[11px] mt-1.5" style={{ color: '#475569' }}>
                  Pool range: tick −120 to +120 (±1.2% from current price)
                </p>
              </div>

              {/* APY + Max IL */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[11px] font-bold uppercase mb-2"
                    style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                    Target APY
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      value={targetAPY}
                      onChange={e => setTargetAPY(e.target.value)}
                      placeholder="12"
                      className="dp-input rounded-sm px-3 py-3 font-mono pr-8"
                    />
                    <span className="absolute right-3 top-1/2 -translate-y-1/2 text-sm font-mono"
                      style={{ color: '#94a3b8' }}>%</span>
                  </div>
                </div>
                <div>
                  <label className="block text-[11px] font-bold uppercase mb-2"
                    style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                    Max IL Tolerance
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      value={maxIL}
                      onChange={e => setMaxIL(e.target.value)}
                      placeholder="5"
                      className="dp-input rounded-sm px-3 py-3 font-mono pr-8"
                    />
                    <span className="absolute right-3 top-1/2 -translate-y-1/2 text-sm font-mono"
                      style={{ color: '#94a3b8' }}>%</span>
                  </div>
                </div>
              </div>

              {/* Payout preference */}
              <div>
                <label className="block text-[11px] font-bold uppercase mb-3"
                  style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                  Payout Preference
                </label>
                <div className="flex gap-2">
                  {PAYOUT_OPTIONS.map(opt => (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => setPayout(opt.value)}
                      className="flex-1 flex flex-col sm:flex-row items-center justify-center gap-1.5 p-2.5 sm:p-3 rounded-sm transition-all text-left"
                      style={
                        payout === opt.value
                          ? { background: 'rgba(34,211,238,0.06)', border: '1px solid #22D3EE', color: '#22D3EE' }
                          : { background: 'rgba(5,8,20,0.6)', border: '1px solid rgba(255,255,255,0.08)', color: '#94a3b8' }
                      }
                      onMouseEnter={e => { if (payout !== opt.value) e.currentTarget.style.borderColor = 'rgba(255,255,255,0.2)' }}
                      onMouseLeave={e => { if (payout !== opt.value) e.currentTarget.style.borderColor = 'rgba(255,255,255,0.08)' }}
                    >
                      <span style={{ ...MS, fontSize: '16px' }}>{opt.icon}</span>
                      <span className="text-[11px] font-medium whitespace-nowrap">{opt.label}</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* Action buttons */}
              <div className="flex flex-col gap-2 pt-1">
                {/* Step 1: Approve */}
                <button
                  type="button"
                  onClick={handleApprove}
                  disabled={isPending || step === 'approved' || step === 'done'}
                  className="w-full py-3.5 rounded-sm font-bold text-[13px] uppercase tracking-wider transition-all disabled:cursor-not-allowed"
                  style={
                    step === 'approved' || step === 'done'
                      ? { background: 'rgba(34,211,238,0.08)', border: '1px solid rgba(34,211,238,0.3)', color: '#22D3EE', opacity: 1 }
                      : { background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.12)', color: '#f1f5f9', opacity: (isPending ? 0.5 : 1) }
                  }
                >
                  {step === 'approving'
                    ? '⟳ Approving both tokens...'
                    : step === 'approved' || step === 'done'
                    ? '✓ Tokens Approved'
                    : '1. Approve VTKA + VTKB'}
                </button>

                {/* Step 2: Deposit */}
                <button
                  type="button"
                  onClick={handleDeposit}
                  disabled={isPending || step === 'idle' || step === 'approving' || step === 'done'}
                  className="w-full py-3.5 rounded-sm font-bold text-[13px] uppercase tracking-wider transition-all disabled:cursor-not-allowed disabled:opacity-40"
                  style={{ background: '#22D3EE', color: '#050814' }}
                  onMouseEnter={e => { if (!e.currentTarget.disabled) e.currentTarget.style.opacity = '0.88' }}
                  onMouseLeave={e => { e.currentTarget.style.opacity = e.currentTarget.disabled ? '0.4' : '1' }}
                >
                  {step === 'depositing' ? '⟳ Adding liquidity...' : '2. Deposit Liquidity'}
                </button>
              </div>

              {/* Error */}
              {error && (
                <div className="rounded-sm p-3 flex items-start gap-3"
                  style={{ background: 'rgba(255,180,171,0.05)', border: '1px solid rgba(255,180,171,0.2)' }}>
                  <span style={{ ...MS, color: '#ffb4ab' }}>error</span>
                  <p className="text-xs break-words" style={{ color: '#ffb4ab' }}>{error}</p>
                </div>
              )}

              {/* TX link */}
              {txHash && (
                <a
                  href={`https://sepolia.etherscan.io/tx/${txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1.5 text-xs transition-colors"
                  style={{ color: '#22D3EE' }}
                >
                  <span style={{ ...MS, fontSize: '14px' }}>open_in_new</span>
                  View transaction on Etherscan
                </a>
              )}

              {/* Success */}
              {step === 'done' && isSuccess && (
                <div className="rounded-sm p-4"
                  style={{ background: 'rgba(16,185,129,0.05)', border: '1px solid rgba(16,185,129,0.25)' }}>
                  <div className="flex items-center gap-2 mb-2">
                    <span style={{ ...MS, color: '#10b981', fontVariationSettings: "'FILL' 1,'wght' 400,'GRAD' 0,'opsz' 24" }}>
                      check_circle
                    </span>
                    <p className="font-semibold text-sm" style={{ color: '#10b981' }}>Position opened!</p>
                  </div>
                  <p className="text-xs mb-3" style={{ color: '#94a3b8' }}>
                    Your LP intent is stored on-chain. VolatilityVault manages your position automatically.
                  </p>
                  <Link
                    href="/positions"
                    className="inline-flex items-center gap-1.5 px-4 py-2 rounded-sm text-xs font-bold uppercase transition-opacity hover:opacity-80"
                    style={{ background: '#10b981', color: '#050814', letterSpacing: '0.08em' }}
                  >
                    <span style={{ ...MS, fontSize: '14px', color: '#050814' }}>analytics</span>
                    View My Positions
                  </Link>
                </div>
              )}
            </div>

            {/* ── RIGHT: intent summary + network activity ── */}
            <div className="lg:col-span-2 flex flex-col gap-4 sm:gap-5">

              {/* Intent summary card */}
              <div className="dp-card rounded-sm p-5">
                <div className="flex justify-between items-center mb-5">
                  <h3 className="text-[11px] font-bold uppercase"
                    style={{ letterSpacing: '0.15em', color: '#94a3b8' }}>
                    Intent Summary
                  </h3>
                  <span style={{ ...MS, fontSize: '16px', color: '#94a3b8' }}>bar_chart</span>
                </div>

                <div className="flex flex-col gap-3">
                  <div className="flex justify-between items-end pb-3"
                    style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                    <span className="text-xs" style={{ color: '#94a3b8' }}>Allocated Principal</span>
                    <span className="font-mono text-sm text-white">{amount || '0.00'} VTKA</span>
                  </div>
                  <div className="flex justify-between items-end pb-3"
                    style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                    <span className="text-xs" style={{ color: '#94a3b8' }}>Target APY</span>
                    <span className="font-mono text-sm" style={{ color: '#22D3EE' }}>{targetAPY}%</span>
                  </div>
                  <div className="flex justify-between items-end pb-3"
                    style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                    <span className="text-xs" style={{ color: '#94a3b8' }}>Max IL Tolerance</span>
                    <span className="font-mono text-sm text-white">{maxIL}%</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-xs" style={{ color: '#94a3b8' }}>Payout Mode</span>
                    <span className="text-[11px] font-bold px-2 py-0.5 rounded-sm uppercase"
                      style={{ background: 'rgba(34,211,238,0.08)', border: '1px solid rgba(34,211,238,0.2)', color: '#22D3EE' }}>
                      {PAYOUT_OPTIONS[payout].label}
                    </span>
                  </div>
                </div>

                {/* Market insight */}
                <div className="mt-5 p-3 rounded-sm"
                  style={{ background: 'rgba(5,8,20,0.6)', border: '1px solid rgba(255,255,255,0.05)' }}>
                  <div className="flex items-center gap-2 mb-1.5">
                    <span style={{ ...MS, fontSize: '13px', color: '#22D3EE' }}>info</span>
                    <span className="text-[10px] font-bold uppercase" style={{ letterSpacing: '0.1em', color: '#22D3EE' }}>
                      Market Insight
                    </span>
                  </div>
                  <p className="text-[11px] italic leading-relaxed" style={{ color: '#64748b' }}>
                    Storm-period fees accumulate in the yield buffer (Aave / Morpho) and distribute
                    to LPs automatically when VRS returns to calm.
                  </p>
                </div>
              </div>

              {/* Network activity card */}
              <div className="dp-card rounded-sm p-4 flex flex-col gap-3">
                <div className="flex items-center justify-between">
                  <span className="text-[10px] font-bold uppercase"
                    style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                    Network Activity
                  </span>
                  <div className="flex items-center gap-1.5">
                    <span className="w-1.5 h-1.5 rounded-full inline-block animate-pulse"
                      style={{ backgroundColor: '#22D3EE' }}></span>
                    <span className="text-[10px] font-mono" style={{ color: '#22D3EE' }}>LIVE</span>
                  </div>
                </div>

                {/* Mini bar chart */}
                <div className="flex gap-1 items-end" style={{ height: '32px' }}>
                  {[3, 5, 8, 4, 6, 2, 5, 7].map((h, i) => (
                    <div
                      key={i}
                      className="flex-1 rounded-sm"
                      style={{
                        height: `${h * 12.5}%`,
                        backgroundColor: i === 2 ? '#22D3EE' : 'rgba(255,255,255,0.06)',
                      }}
                    />
                  ))}
                </div>

                <span className="text-[10px] font-mono" style={{ color: '#475569', letterSpacing: '-0.02em' }}>
                  SEPOLIA // HOOK: {CONTRACTS.HOOK.slice(0, 8)}...
                </span>
              </div>

              {/* Pool range info */}
              <div className="dp-card rounded-sm p-4">
                <h4 className="text-[10px] font-bold uppercase mb-3"
                  style={{ letterSpacing: '0.12em', color: '#94a3b8' }}>
                  Pool Parameters
                </h4>
                {[
                  { label: 'Pair',         value: 'VTKA / VTKB' },
                  { label: 'Tick Range',   value: '−120 to +120' },
                  { label: 'Tick Spacing', value: '60' },
                  { label: 'Fee Flag',     value: '0x800000 (dynamic)' },
                ].map(row => (
                  <div key={row.label}
                    className="flex justify-between text-xs py-2"
                    style={{ borderBottom: '1px solid rgba(255,255,255,0.04)' }}>
                    <span style={{ color: '#64748b' }}>{row.label}</span>
                    <span className="font-mono" style={{ color: '#f1f5f9' }}>{row.value}</span>
                  </div>
                ))}
              </div>

            </div>
          </div>
          </div>{/* max-w-4xl */}
        </div>{/* main content */}
      </div>{/* flex wrapper */}
    </>
  )
}
