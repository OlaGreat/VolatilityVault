'use client'

import { ConnectButton } from '@rainbow-me/rainbowkit'
import Link from 'next/link'
import { usePathname } from 'next/navigation'

const links = [
  { href: '/',        label: 'Dashboard' },
  { href: '/deposit', label: 'Deposit'   },
  { href: '/buffer',  label: 'Buffer'    },
]

export function Navbar() {
  const pathname = usePathname()

  return (
    <nav className="border-b border-gray-800 bg-gray-950/80 backdrop-blur sticky top-0 z-10">
      <div className="max-w-5xl mx-auto px-4 h-16 flex items-center justify-between">
        <div className="flex items-center gap-8">
          <Link href="/" className="font-bold text-lg tracking-tight">
            <span className="text-purple-400">Volatility</span>Vault
          </Link>
          <div className="flex gap-1">
            {links.map(l => (
              <Link
                key={l.href}
                href={l.href}
                className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  pathname === l.href
                    ? 'bg-purple-600 text-white'
                    : 'text-gray-400 hover:text-white hover:bg-gray-800'
                }`}
              >
                {l.label}
              </Link>
            ))}
          </div>
        </div>
        <ConnectButton chainStatus="icon" showBalance={false} />
      </div>
    </nav>
  )
}
