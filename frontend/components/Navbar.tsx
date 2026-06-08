'use client'

import { ConnectButton } from '@rainbow-me/rainbowkit'
import Link from 'next/link'
import { usePathname } from 'next/navigation'

const links = [
  { href: '/',          label: 'Dashboard' },
  { href: '/deposit',   label: 'Deposit'   },
  { href: '/positions', label: 'Positions' },
  { href: '/buffer',    label: 'Buffer'    },
]

export function Navbar() {
  const pathname = usePathname()
  const isHome = pathname === '/home'

  return (
    <nav
      className="fixed top-0 w-full z-50 backdrop-blur-md border-b flex justify-between items-center px-4 sm:px-8 h-16"
      style={{ backgroundColor: 'rgba(5,8,20,0.85)', borderColor: 'rgba(255,255,255,0.08)' }}
    >
      {/* Left: logo + nav links (links only on home) */}
      <div className="flex items-center gap-6 lg:gap-8">
        <Link href="/" className="text-lg sm:text-xl font-bold tracking-tight text-white whitespace-nowrap">
          VolatilityVault
        </Link>

        {/* Nav links — only rendered on home page, no active/underline styling */}
        {isHome && (
          <div className="hidden md:flex items-center gap-1">
            {links.map(l => (
              <Link
                key={l.href}
                href={l.href}
                className="px-3 py-1.5 text-[13px] font-medium uppercase tracking-widest transition-colors"
                style={{ color: '#94a3b8' }}
                onMouseEnter={e => ((e.currentTarget as HTMLElement).style.color = '#fff')}
                onMouseLeave={e => ((e.currentTarget as HTMLElement).style.color = '#94a3b8')}
              >
                {l.label}
              </Link>
            ))}
          </div>
        )}
      </div>

      {/* Right: network badge + wallet */}
      <div className="flex items-center gap-3 sm:gap-4">
        {/* Network indicator */}
        <div className="hidden sm:flex flex-col items-end">
          <span className="text-[10px] uppercase tracking-tighter" style={{ color: '#94a3b8' }}>Network</span>
          <span
            className="text-[12px] font-mono font-medium flex items-center gap-1.5"
            style={{ color: '#38bdf8' }}
          >
            <span
              className="w-1.5 h-1.5 rounded-full inline-block"
              style={{ backgroundColor: '#38bdf8' }}
            />
            SEPOLIA
          </span>
        </div>

        {/* RainbowKit wallet button — preserved exactly */}
        <ConnectButton chainStatus="icon" showBalance={false} />
      </div>
    </nav>
  )
}
