import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia } from 'wagmi/chains'
import { http } from 'wagmi'

// getDefaultConfig enables EIP-6963 multi-injected provider discovery by default,
// so every installed wallet (MetaMask, Brave, Coinbase, Rabby, etc.) is detected
// and the user picks whichever they want — no wallet is hardcoded or forced.
export const config = getDefaultConfig({
  appName:   'VolatilityVault',
  projectId: 'volatilityvault-hackathon',
  chains:    [sepolia],
  transports: { [sepolia.id]: http() },
  ssr:       true,
})
