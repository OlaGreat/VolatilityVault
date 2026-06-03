// Live Sepolia contract addresses
export const CONTRACTS = {
  VRS_ORACLE:   '0x172c86F5b964d7836Cf055A76f5Ad316f0297198' as `0x${string}`,
  HOOK:         '0x63Ce6162Af038c903fc21ECBE090A690eD5b85C0' as `0x${string}`,
  YIELD_BUFFER: '0x2704187fbE9a0617312B5Eb7399508E760821BBc' as `0x${string}`,
  LP_NFT:       '0xb7d9Cf1BC3Aed3FAc9BbcF8d8Eb0BE94fb7462Cb' as `0x${string}`,
  POOL_MANAGER: '0xe03A1074c86CFEdd5C142C4F04F1a1536E203543' as `0x${string}`,
  // Uniswap V4 test routers (deployed by Uniswap on Sepolia)
  SWAP_ROUTER:  '0x9b6b46e2c869aa39918db7f52f5557fe577b6eee' as `0x${string}`,
  LIQ_ROUTER:   '0x0c478023803a644c94c4ce1c1e7b9a087e411b0a' as `0x${string}`,
  // Pool tokens
  TOKEN0:       '0x2348De1A41A08F461C5bBCB46c21a7e82c20456b' as `0x${string}`,
  TOKEN1:       '0x73A3c4f9F7725D23C358606f1C7048463C56C521' as `0x${string}`,
} as const

// Pool key parameters
export const POOL_KEY = {
  currency0:   CONTRACTS.TOKEN0,
  currency1:   CONTRACTS.TOKEN1,
  fee:         0x800000, // DYNAMIC_FEE_FLAG
  tickSpacing: 60,
  hooks:       CONTRACTS.HOOK,
} as const

// VRSOracle ABI (read functions only)
export const VRS_ORACLE_ABI = [
  { name: 'vrs',          type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint8' }] },
  { name: 'getFee',       type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint24' }] },
  { name: 'getRiskLevel', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'string' }] },
  { name: 'isStorm',      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'bool' }] },
  { name: 'lastUpdated',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'updateVRS',    type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'score', type: 'uint8' }], outputs: [] },
] as const

// YieldBuffer ABI
export const YIELD_BUFFER_ABI = [
  { name: 'currentEpoch',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'epochs',        type: 'function', stateMutability: 'view',
    inputs: [{ name: '', type: 'uint256' }],
    outputs: [
      { name: 'totalFees',        type: 'uint256' },
      { name: 'totalYieldEarned', type: 'uint256' },
      { name: 'totalLiquidity',   type: 'uint256' },
      { name: 'distributedAt',    type: 'uint256' },
      { name: 'isActive',         type: 'bool' },
      { name: 'isDistributed',    type: 'bool' },
      { name: 'isDeployed',       type: 'bool' },
    ]
  },
  { name: 'lpLiquidity',   type: 'function', stateMutability: 'view',
    inputs: [{ name: '', type: 'address' }, { name: '', type: 'uint256' }],
    outputs: [{ type: 'uint256' }]
  },
  { name: 'previewClaim',  type: 'function', stateMutability: 'view',
    inputs: [{ name: 'lp', type: 'address' }, { name: 'epochId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }]
  },
  { name: 'claim',         type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'epochId', type: 'uint256' }], outputs: []
  },
  { name: 'triggerDistribution', type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
] as const

// ERC20 ABI (minimal)
export const ERC20_ABI = [
  { name: 'approve',  type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ type: 'bool' }]
  },
  { name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }]
  },
] as const

// Fee tier labels
export const FEE_LABELS: Record<number, { label: string; bps: string; emoji: string; color: string }> = {
  500:  { label: 'CALM',      bps: '0.05%', emoji: '☀️',  color: 'text-green-400' },
  1500: { label: 'CLOUDY',    bps: '0.15%', emoji: '⛅',  color: 'text-yellow-400' },
  3000: { label: 'STORM',     bps: '0.30%', emoji: '⛈️',  color: 'text-orange-400' },
  5000: { label: 'HURRICANE', bps: '0.50%', emoji: '🌀',  color: 'text-red-500' },
}
