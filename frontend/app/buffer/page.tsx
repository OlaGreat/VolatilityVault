'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { formatEther } from 'viem'
import { CONTRACTS, YIELD_BUFFER_ABI } from '@/lib/contracts'

export default function BufferPage() {
  const { address, isConnected } = useAccount()

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

  const epoch = currentEpoch !== undefined ? Number(currentEpoch) : null
  const fees   = epochData ? formatEther(epochData[0] as bigint) : '0'
  const yield_ = epochData ? formatEther(epochData[1] as bigint) : '0'
  const totalLiq = epochData ? formatEther(epochData[2] as bigint) : '0'
  const isActive = epochData ? Boolean(epochData[4]) : false
  const isDeployed = epochData ? Boolean(epochData[6]) : false

  const myShare = lpShare ? formatEther(lpShare as bigint) : '0'
  const myClaim = claimable ? formatEther(claimable as bigint) : '0'

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
    <div className="max-w-2xl mx-auto space-y-4">
      <div>
        <h1 className="text-2xl font-bold">Yield Buffer</h1>
        <p className="text-gray-400 text-sm mt-1">
          Storm-period fees accumulate here, earn yield, then distribute to LPs when calm returns.
        </p>
      </div>

      {/* Epoch status */}
      <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold text-gray-200">Current Epoch</h2>
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${isActive ? 'bg-green-400 animate-pulse' : 'bg-gray-600'}`} />
            <span className={`text-xs font-medium ${isActive ? 'text-green-400' : 'text-gray-500'}`}>
              {isActive ? 'ACTIVE' : 'DISTRIBUTING'}
            </span>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-3">
          <Stat label="Epoch #"    value={epoch !== null ? `#${epoch}` : '--'} />
          <Stat label="Fees Held"  value={`${parseFloat(fees).toFixed(4)} VTKA`} />
          <Stat label="Yield Earned" value={`${parseFloat(yield_).toFixed(6)} VTKA`} />
        </div>

        <div className="mt-3 pt-3 border-t border-gray-800 grid grid-cols-2 gap-3">
          <Stat label="Total Liquidity" value={`${parseFloat(totalLiq).toFixed(2)}`} />
          <Stat
            label="Yield Status"
            value={isDeployed ? 'Deployed to router' : 'Holding in vault'}
            valueClass={isDeployed ? 'text-green-400' : 'text-yellow-400'}
          />
        </div>
      </div>

      {/* My position */}
      {isConnected ? (
        <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800">
          <h2 className="font-semibold text-gray-200 mb-4">My Buffer Position</h2>

          <div className="grid grid-cols-2 gap-3 mb-4">
            <Stat label="My Liquidity Share" value={`${parseFloat(myShare).toFixed(4)}`} />
            <Stat label="Claimable (prev epoch)" value={`${parseFloat(myClaim).toFixed(6)} VTKA`}
              valueClass={parseFloat(myClaim) > 0 ? 'text-green-400' : 'text-gray-400'} />
          </div>

          <button
            onClick={handleClaim}
            disabled={isPending || parseFloat(myClaim) === 0 || !currentEpoch || currentEpoch === 0n}
            className="w-full py-3 rounded-xl font-semibold text-sm bg-green-600 hover:bg-green-500 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          >
            {isPending ? 'Claiming...' : `Claim ${parseFloat(myClaim).toFixed(4)} VTKA`}
          </button>

          {claimHash && (
            <a
              href={`https://sepolia.etherscan.io/tx/${claimHash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="block text-center text-xs text-purple-400 hover:text-purple-300 mt-2 transition-colors"
            >
              View transaction on Etherscan →
            </a>
          )}

          {isSuccess && (
            <div className="mt-2 bg-green-900/30 border border-green-700 rounded-xl p-3 text-center">
              <p className="text-green-400 text-sm font-semibold">Claimed successfully!</p>
            </div>
          )}
        </div>
      ) : (
        <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800 text-center py-10">
          <p className="text-gray-400">Connect wallet to view your buffer position and claim</p>
        </div>
      )}

      {/* How buffer works */}
      <div className="bg-gray-900 rounded-2xl p-5 border border-gray-800">
        <h2 className="font-semibold text-gray-200 mb-3">How the Buffer Works</h2>
        <ol className="space-y-2 text-sm text-gray-400">
          {[
            'During storms (VRS > 60), extra swap fees accumulate here instead of being distributed immediately — protecting against JIT liquidity attacks.',
            'While fees sit in the buffer, the Reactive RSC deploys them to the yield router to earn additional yield.',
            'When VRS drops back to calm, Reactive triggers distribution. LPs receive their fees plus all yield earned.',
            'Each LP\'s share is proportional to their registered liquidity at deposit time.',
          ].map((text, i) => (
            <li key={i} className="flex gap-3">
              <span className="text-purple-400 font-bold shrink-0">{i + 1}.</span>
              <span>{text}</span>
            </li>
          ))}
        </ol>
      </div>
    </div>
  )
}

function Stat({ label, value, valueClass = 'text-white' }: { label: string; value: string; valueClass?: string }) {
  return (
    <div className="bg-gray-800 rounded-xl p-3">
      <p className="text-xs text-gray-500 mb-0.5">{label}</p>
      <p className={`font-semibold text-sm ${valueClass}`}>{value}</p>
    </div>
  )
}
