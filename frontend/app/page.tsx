import { VRSGauge }   from '@/components/VRSGauge'
import { PoolStats }  from '@/components/PoolStats'
import Link           from 'next/link'

export default function Dashboard() {
  return (
    <div className="space-y-6">
      {/* Hero */}
      <div className="text-center py-6">
        <h1 className="text-4xl font-black tracking-tight mb-2">
          <span className="text-purple-400">Volatility</span>Vault
        </h1>
        <p className="text-gray-400 max-w-xl mx-auto text-sm leading-relaxed">
          The first Uniswap V4 hook that taxes arbitrageurs predictively — seeing the storm before
          it lands, charging the people causing the damage, and giving that money back to LPs.
        </p>
        <div className="flex justify-center gap-3 mt-4">
          <Link
            href="/deposit"
            className="px-5 py-2 bg-purple-600 hover:bg-purple-500 rounded-full text-sm font-semibold transition-colors"
          >
            Add Liquidity
          </Link>
          <Link
            href="/buffer"
            className="px-5 py-2 bg-gray-800 hover:bg-gray-700 rounded-full text-sm font-semibold transition-colors"
          >
            View Buffer
          </Link>
        </div>
      </div>

      {/* Main grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2">
          <VRSGauge />
        </div>
        <div>
          <PoolStats />
        </div>
      </div>

      {/* How it works */}
      <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
        <h2 className="text-lg font-semibold text-gray-200 mb-4">How It Works</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {[
            {
              step: '01',
              title: 'Reactive watches 5 chains',
              desc:  'Cross-chain price gaps and volume spikes are detected before they hit Uniswap.',
              color: 'text-purple-400',
            },
            {
              step: '02',
              title: 'AI scores volatility 0–100',
              desc:  'The Volatility Risk Score drives the fee — calm markets pay 0.05%, hurricanes pay 0.50%.',
              color: 'text-blue-400',
            },
            {
              step: '03',
              title: 'Storm fees compound for LPs',
              desc:  'Extra fees sit in a yield buffer earning on Aave/Morpho until the storm passes, then pay out.',
              color: 'text-green-400',
            },
          ].map(s => (
            <div key={s.step} className="bg-gray-800 rounded-xl p-4">
              <span className={`text-xs font-bold ${s.color}`}>{s.step}</span>
              <h3 className="font-semibold text-sm mt-1 mb-1.5">{s.title}</h3>
              <p className="text-xs text-gray-400 leading-relaxed">{s.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
