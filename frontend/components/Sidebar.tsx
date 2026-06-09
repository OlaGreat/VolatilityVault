'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const MS: React.CSSProperties = {
  fontFamily: 'Material Symbols Outlined',
  fontVariationSettings: "'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24",
  lineHeight: 1,
  display: 'inline-block',
  verticalAlign: 'middle',
}

const nav = [
  { href: '/dashboard', icon: 'grid_view',              label: 'Dashboard'  },
  { href: '/deposit',   icon: 'account_balance_wallet', label: 'Deposit'    },
  { href: '/positions', icon: 'query_stats',            label: 'Positions'  },
  { href: '/buffer',    icon: 'shield',                 label: 'Buffer'     },
]

export function Sidebar() {
  const pathname = usePathname()

  return (
    <aside
      className="hidden lg:flex flex-col py-8 px-4 gap-2 w-56 xl:w-64 shrink-0 fixed left-0 h-full z-30"
      style={{
        top: '64px',
        background: '#0B1220',
        borderRight: '1px solid rgba(255,255,255,0.08)',
      }}
    >
      {/* Identity block */}
      <div className="mb-8 px-2">
        <div className="flex items-center gap-3">
          <div
            className="w-8 h-8 rounded-sm flex items-center justify-center shrink-0"
            style={{ background: '#111827', border: '1px solid rgba(255,255,255,0.08)' }}
          >
            <span style={{ ...MS, fontSize: '16px', color: '#94a3b8' }}>terminal</span>
          </div>
          <div>
            <p className="text-sm font-semibold text-white">TERMINAL_01</p>
            <p
              className="text-[11px] font-medium uppercase tracking-tight flex items-center gap-1"
              style={{ color: '#94a3b8' }}
            >
              <span
                className="w-1.5 h-1.5 rounded-full inline-block"
                style={{ backgroundColor: '#38bdf8' }}
              />
              Sepolia
            </p>
          </div>
        </div>
      </div>

      {/* Nav items */}
      <div className="space-y-1">
        {nav.map(item => {
          const active = pathname === item.href
          return (
            <Link
              key={item.href}
              href={item.href}
              className="flex items-center gap-3 px-3 py-2.5 rounded-sm transition-all"
              style={
                active
                  ? { background: '#111827', color: '#38bdf8', borderLeft: '2px solid #38bdf8' }
                  : { color: '#94a3b8' }
              }
              onMouseEnter={e => {
                if (!active) {
                  e.currentTarget.style.background = '#111827'
                  e.currentTarget.style.color = '#fff'
                }
              }}
              onMouseLeave={e => {
                if (!active) {
                  e.currentTarget.style.background = 'transparent'
                  e.currentTarget.style.color = '#94a3b8'
                }
              }}
            >
              <span style={{ ...MS, fontSize: '20px' }}>{item.icon}</span>
              <span className="text-[13px] font-medium">{item.label}</span>
            </Link>
          )
        })}
      </div>

      {/* Bottom settings */}
      <div
        className="mt-auto space-y-1 pt-6"
        style={{ borderTop: '1px solid rgba(255,255,255,0.08)' }}
      >
        {[
          { icon: 'settings',      label: 'Settings' },
          { icon: 'support_agent', label: 'Support'  },
        ].map(item => (
          <div
            key={item.label}
            className="flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors"
            style={{ color: '#94a3b8' }}
            onMouseEnter={e => (e.currentTarget.style.color = '#fff')}
            onMouseLeave={e => (e.currentTarget.style.color = '#94a3b8')}
          >
            <span style={{ ...MS, fontSize: '18px' }}>{item.icon}</span>
            <span className="text-[12px] font-medium">{item.label}</span>
          </div>
        ))}
      </div>
    </aside>
  )
}
