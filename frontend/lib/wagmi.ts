import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia } from 'wagmi/chains'

export const config = getDefaultConfig({
  appName:     'VolatilityVault',
  projectId:   'volatilityvault-hackathon',
  chains:      [sepolia],
  ssr:         true,
})
