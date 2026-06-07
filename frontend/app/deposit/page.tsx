'use client'

import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi'
import { parseEther, encodeFunctionData, encodeAbiParameters, parseAbiParameters } from 'viem'
import { CONTRACTS, ERC20_ABI } from '@/lib/contracts'
import { savePosition } from '@/lib/positions'
import Link from 'next/link'

const PAYOUT_OPTIONS = [
  { value: 0, label: 'Daily',    desc: 'Small, frequent payouts as fees accumulate' },
  { value: 1, label: 'Lump Sum', desc: 'Wait for storm events, collect bigger payouts' },
  { value: 2, label: 'Reinvest', desc: 'Auto-compound fees back into your LP position' },
]

// PoolModifyLiquidityTest ABI (Uniswap V4 Sepolia test router)
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

export default function DepositPage() {
  const { address, isConnected } = useAccount()

  const [amount,    setAmount]    = useState('100')
  const [targetAPY, setTargetAPY] = useState('12')
  const [maxIL,     setMaxIL]     = useState('5')
  const [payout,    setPayout]    = useState(0)
  const [step,      setStep]      = useState<'idle'|'approving'|'approved'|'depositing'|'done'>('idle')

  const { writeContract, writeContractAsync, data: txHash, isPending } = useWriteContract()
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash })
  const [error, setError] = useState<string | null>(null)

  // Encode LP intent as hookData
  function buildHookData() {
    return encodeAbiParameters(
      parseAbiParameters('uint256 targetAPY, uint256 maxILBps, uint8 payout'),
      [BigInt(Number(targetAPY) * 100), BigInt(Number(maxIL) * 100), payout]
    )
  }

  // Adding liquidity around the current 1:1 price requires BOTH tokens,
  // so we approve both token0 and token1 to the liquidity router.
  async function handleApprove() {
    setError(null)
    setStep('approving')
    try {
      const allowance = parseEther('1000000') // generous allowance for repeated testing
      await writeContractAsync({
        address: CONTRACTS.TOKEN0,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [CONTRACTS.LIQ_ROUTER, allowance],
      })
      await writeContractAsync({
        address: CONTRACTS.TOKEN1,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [CONTRACTS.LIQ_ROUTER, allowance],
      })
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
          {
            currency0:   CONTRACTS.TOKEN0,
            currency1:   CONTRACTS.TOKEN1,
            fee:         0x800000,
            tickSpacing: 60,
            hooks:       CONTRACTS.HOOK,
          },
          {
            tickLower:      -120,
            tickUpper:       120,
            liquidityDelta:  parseEther(amount),
            salt:            '0x0000000000000000000000000000000000000000000000000000000000000000',
          },
          buildHookData(),
        ],
      })
      // Record the deposit locally so the user sees it on the Positions page.
      if (address) {
        savePosition(address, {
          amount,
          targetAPY,
          maxIL,
          payout:    PAYOUT_OPTIONS[payout].label,
          txHash:    hash,
          timestamp: Date.now(),
        })
      }
      setStep('done')
    } catch (e: any) {
      setError(e?.shortMessage ?? e?.message ?? 'Deposit failed')
      setStep('approved')
    }
  }

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <p className="text-gray-400 text-lg mb-2">Connect your wallet to add liquidity</p>
        <p className="text-gray-600 text-sm">Make sure you're on Ethereum Sepolia</p>
      </div>
    )
  }

  return (
    <div className="max-w-xl mx-auto space-y-4">
      <div>
        <h1 className="text-2xl font-bold">Add Liquidity</h1>
        <p className="text-gray-400 text-sm mt-1">
          Set your yield intent — the vault manages your position automatically.
        </p>
      </div>

      {/* Amount */}
      <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800 space-y-4">
        <h2 className="font-semibold text-gray-200">Liquidity Amount</h2>
        <div>
          <label className="text-xs text-gray-500 block mb-1.5">Amount (VTKA)</label>
          <input
            type="number"
            value={amount}
            onChange={e => setAmount(e.target.value)}
            className="w-full bg-gray-800 rounded-xl px-4 py-3 text-white text-lg font-mono outline-none border border-gray-700 focus:border-purple-500 transition-colors"
            placeholder="100"
            min="0"
          />
        </div>
        <p className="text-xs text-gray-600">Pool range: tick -120 to +120 (±1.2% from current price)</p>
      </div>

      {/* LP Intent */}
      <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800 space-y-4">
        <h2 className="font-semibold text-gray-200">Yield Intent</h2>
        <p className="text-xs text-gray-500">
          Your preferences are stored on-chain and respected automatically — no manual management needed.
        </p>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-gray-500 block mb-1.5">Target APY (%)</label>
            <input
              type="number"
              value={targetAPY}
              onChange={e => setTargetAPY(e.target.value)}
              className="w-full bg-gray-800 rounded-xl px-3 py-2.5 text-white outline-none border border-gray-700 focus:border-purple-500 transition-colors"
              placeholder="12"
            />
          </div>
          <div>
            <label className="text-xs text-gray-500 block mb-1.5">Max IL Tolerance (%)</label>
            <input
              type="number"
              value={maxIL}
              onChange={e => setMaxIL(e.target.value)}
              className="w-full bg-gray-800 rounded-xl px-3 py-2.5 text-white outline-none border border-gray-700 focus:border-purple-500 transition-colors"
              placeholder="5"
            />
          </div>
        </div>

        <div>
          <label className="text-xs text-gray-500 block mb-2">Payout Preference</label>
          <div className="space-y-2">
            {PAYOUT_OPTIONS.map(opt => (
              <button
                key={opt.value}
                onClick={() => setPayout(opt.value)}
                className={`w-full text-left p-3 rounded-xl border transition-colors ${
                  payout === opt.value
                    ? 'border-purple-500 bg-purple-500/10'
                    : 'border-gray-700 bg-gray-800 hover:border-gray-600'
                }`}
              >
                <span className="font-medium text-sm">{opt.label}</span>
                <span className="text-gray-500 text-xs block mt-0.5">{opt.desc}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Intent summary */}
      <div className="bg-purple-900/20 border border-purple-800/40 rounded-xl p-4 text-sm">
        <p className="font-medium text-purple-300 mb-1">Your intent will be stored on-chain:</p>
        <ul className="text-gray-400 space-y-0.5 text-xs">
          <li>Target APY: <span className="text-white">{targetAPY}%</span></li>
          <li>Max IL tolerance: <span className="text-white">{maxIL}%</span></li>
          <li>Payout: <span className="text-white">{PAYOUT_OPTIONS[payout].label}</span></li>
        </ul>
      </div>

      {/* Actions */}
      <div className="space-y-2">
        <button
          onClick={handleApprove}
          disabled={isPending || step === 'approved' || step === 'done'}
          className="w-full py-3.5 rounded-xl font-semibold text-sm bg-gray-700 hover:bg-gray-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {step === 'approving' ? 'Approving both tokens...' : step === 'approved' || step === 'done' ? '✓ Tokens Approved' : '1. Approve VTKA + VTKB'}
        </button>
        <button
          onClick={handleDeposit}
          disabled={isPending || step === 'idle' || step === 'approving' || step === 'done'}
          className="w-full py-3.5 rounded-xl font-semibold text-sm bg-purple-600 hover:bg-purple-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {step === 'depositing' ? 'Adding liquidity...' : '2. Add Liquidity'}
        </button>
      </div>

      {error && (
        <div className="bg-red-900/30 border border-red-700 rounded-xl p-3 text-center">
          <p className="text-red-400 text-xs break-words">{error}</p>
        </div>
      )}

      {txHash && (
        <a
          href={`https://sepolia.etherscan.io/tx/${txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="block text-center text-xs text-purple-400 hover:text-purple-300 transition-colors"
        >
          View transaction on Etherscan →
        </a>
      )}

      {step === 'done' && isSuccess && (
        <div className="bg-green-900/30 border border-green-700 rounded-xl p-4 text-center">
          <p className="text-green-400 font-semibold">Position opened!</p>
          <p className="text-gray-400 text-xs mt-1 mb-3">
            Your LP intent is stored on-chain. VolatilityVault will manage your position automatically.
          </p>
          <Link
            href="/positions"
            className="inline-block px-4 py-2 bg-green-600 hover:bg-green-500 rounded-lg text-sm font-semibold transition-colors"
          >
            View My Positions →
          </Link>
        </div>
      )}
    </div>
  )
}
