import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { Providers } from '@/components/Providers'
import { Navbar } from '@/components/Navbar'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'VolatilityVault',
  description: 'AI-powered LP protection on Uniswap V4',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <head>
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200"
        />
      </head>
      <body
        className={inter.className}
        style={{ backgroundColor: '#050814', color: '#f1f5f9', minHeight: '100vh', overflowX: 'hidden' }}
      >
        <Providers>
          <Navbar />
          {/*
            No global max-width or padding here.
            - Dashboard (/) manages its own sidebar + full-width layout.
            - Deposit / Positions / Buffer each use their own max-w containers.
          */}
          <div className="w-full">
            {children}
          </div>
        </Providers>
      </body>
    </html>
  )
}
