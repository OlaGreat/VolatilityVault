'use client'

import Link from 'next/link'
import { useEffect } from 'react'

export default function HomePage() {
  // Spotlight cursor tracking
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      document.querySelectorAll<HTMLElement>('.spotlight-card').forEach(card => {
        const r = card.getBoundingClientRect()
        card.style.setProperty('--mouse-x', `${e.clientX - r.left}px`)
        card.style.setProperty('--mouse-y', `${e.clientY - r.top}px`)
      })
    }
    document.addEventListener('mousemove', handler)
    return () => document.removeEventListener('mousemove', handler)
  }, [])

  // Header scroll behaviour
  useEffect(() => {
    const header = document.getElementById('home-header')
    if (!header) return
    const onScroll = () => {
      if (window.scrollY > 50) {
        header.style.backgroundColor = 'rgba(5,8,20,0.95)'
      } else {
        header.style.backgroundColor = 'rgba(5,8,20,0.8)'
      }
    }
    window.addEventListener('scroll', onScroll)
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <>
      {/* ── Global styles scoped to this page ── */}
      <style>{`
        .hm-root {
          background-color: #050814;
          color: #dfe1f4;
          overflow-x: hidden;
          font-family: 'Inter', sans-serif;
        }
        .threads-bg {
          background-image: radial-gradient(circle at 2px 2px, rgba(255,255,255,0.03) 1px, transparent 0);
          background-size: 40px 40px;
        }
        .shape-grid-bg {
          background-image:
            linear-gradient(rgba(255,255,255,0.02) 1px, transparent 1px),
            linear-gradient(90deg, rgba(255,255,255,0.02) 1px, transparent 1px);
          background-size: 20px 20px;
        }
        .spotlight-card {
          background: rgba(255,255,255,0.03);
          backdrop-filter: blur(20px);
          border: 1px solid rgba(255,255,255,0.08);
          position: relative;
          overflow: hidden;
          transition: all 0.3s cubic-bezier(0.4,0,0.2,1);
        }
        .spotlight-card::before {
          content: '';
          position: absolute;
          inset: 0;
          background: radial-gradient(800px circle at var(--mouse-x,50%) var(--mouse-y,50%), rgba(255,255,255,0.03), transparent 40%);
          z-index: 0;
          pointer-events: none;
        }
        .spotlight-card:hover {
          border-color: rgba(255,255,255,0.15);
          background: rgba(255,255,255,0.05);
        }
        .btn-primary {
          background: #dfe1f4;
          color: #050814;
          transition: transform 0.2s ease;
          display: inline-block;
          text-align: center;
        }
        .btn-primary:hover { transform: translateY(-1px); }
        .btn-secondary {
          border: 1px solid rgba(255,255,255,0.1);
          backdrop-filter: blur(10px);
          display: inline-block;
          text-align: center;
        }
        .stepper-line {
          height: 2px;
          background: rgba(255,255,255,0.1);
          position: absolute;
          top: 24px;
          left: 12.5%;
          right: 12.5%;
          z-index: 0;
        }
        .ms {
          font-family: 'Material Symbols Outlined';
          font-weight: normal;
          font-style: normal;
          font-size: 24px;
          line-height: 1;
          letter-spacing: normal;
          text-transform: none;
          display: inline-block;
          white-space: nowrap;
          word-wrap: normal;
          direction: ltr;
          font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
          -webkit-font-smoothing: antialiased;
        }
      `}</style>

      <div className="hm-root threads-bg min-h-screen">

        {/* ── Header ── */}
        <header
          id="home-header"
          className="fixed top-0 w-full z-50 backdrop-blur-xl border-b shadow-sm transition-colors duration-300"
          style={{ backgroundColor: 'rgba(5,8,20,0.8)', borderColor: 'rgba(60,73,76,0.1)' }}
        >
          <div className="flex justify-between items-center h-16 sm:h-20 px-4 sm:px-8 max-w-7xl mx-auto">
            {/* Logo */}
            <div className="text-xl sm:text-3xl font-bold tracking-tighter" style={{ color: '#8aebff' }}>
              VolatilityVault
            </div>

            {/* Nav links — hidden on mobile */}
            <nav className="hidden md:flex items-center space-x-8">
              <Link href="/deposit" className="text-base font-bold border-b-2 pb-1 transition-colors"
                style={{ color: '#8aebff', borderColor: '#8aebff' }}>
                Deposit
              </Link>
              <Link href="/positions" className="text-base transition-colors hover:text-white"
                style={{ color: '#bbc9cd' }}>
                Positions
              </Link>
              <Link href="/buffer" className="text-base transition-colors hover:text-white"
                style={{ color: '#bbc9cd' }}>
                Buffer
              </Link>
            </nav>

            {/* CTA button */}
            <Link href="/deposit"
              className="px-4 sm:px-6 py-1.5 sm:py-2 rounded-lg text-xs sm:text-sm font-medium active:scale-95 transition-all duration-300"
              style={{ backgroundColor: '#8aebff', color: '#00363e' }}>
              Launch App
            </Link>
          </div>
        </header>

        <main className="pt-16 sm:pt-20">

          {/* ── Hero ── */}
          <section className="px-4 sm:px-8 max-w-7xl mx-auto py-10 sm:py-16">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-10 items-center">

              {/* Left copy */}
              <div className="space-y-5 sm:space-y-6">
                <span className="inline-block px-4 py-1 rounded-full border text-xs sm:text-sm font-medium tracking-wide"
                  style={{ borderColor: 'rgba(60,73,76,0.2)', backgroundColor: '#171b28', color: '#8aebff' }}>
                  AI-Powered LP Protection on Uniswap V4
                </span>
                <h1 className="text-3xl sm:text-4xl lg:text-5xl font-bold leading-tight max-w-2xl">
                  Protect LP Capital During Market Volatility
                </h1>
                <p className="text-base sm:text-lg leading-relaxed max-w-xl" style={{ color: '#bbc9cd' }}>
                  VolatilityVault is the first Uniswap V4 hook that taxes arbitrageurs predictively —
                  detecting cross-chain storms before they land, charging the actors causing damage,
                  and returning that yield back to liquidity providers.
                </p>
                <div className="flex flex-col sm:flex-row gap-3 sm:gap-4 pt-2">
                  <Link href="/deposit" className="btn-primary px-8 py-3 rounded-xl text-sm font-bold">
                    Launch App
                  </Link>
                  <Link href="/buffer" className="btn-secondary px-8 py-3 rounded-xl text-sm" style={{ color: '#dfe1f4' }}>
                    View Buffer
                  </Link>
                </div>
              </div>

              {/* Right — vault status card */}
              <div className="spotlight-card p-6 sm:p-10 rounded-2xl relative group">
                {/* Live ping */}
                <div className="absolute top-0 right-0 p-4 sm:p-6">
                  <span className="flex h-3 w-3">
                    <span className="animate-ping absolute inline-flex h-3 w-3 rounded-full opacity-75"
                      style={{ backgroundColor: '#8aebff' }}></span>
                    <span className="relative inline-flex rounded-full h-3 w-3"
                      style={{ backgroundColor: '#8aebff' }}></span>
                  </span>
                </div>

                <div className="space-y-6 sm:space-y-10 relative z-10">
                  <div className="flex items-center justify-between">
                    <h3 className="text-lg sm:text-xl font-semibold">Vault Status</h3>
                    <span className="text-xs" style={{ color: '#bbc9cd' }}>Live · Ethereum Sepolia</span>
                  </div>

                  <div className="grid grid-cols-3 gap-3 sm:gap-4">
                    <div className="space-y-1">
                      <p className="text-xs uppercase tracking-wider" style={{ color: '#bbc9cd' }}>Risk Score</p>
                      <p className="text-2xl sm:text-3xl font-semibold" style={{ color: '#8aebff' }}>0–100</p>
                      <p className="text-[10px]" style={{ color: '#8aebff' }}>AI-Scored Live</p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-xs uppercase tracking-wider" style={{ color: '#bbc9cd' }}>Dynamic Fee</p>
                      <p className="text-md sm:text-xl font-semibold">0.05–0.50%</p>
                      <p className="text-[10px]" style={{ color: '#bbc9cd' }}>Volatility Adj.</p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-xs uppercase tracking-wider" style={{ color: '#bbc9cd' }}>Buffer</p>
                      <p className="text-2xl sm:text-3xl font-semibold">Active</p>
                      <p className="text-[10px]" style={{ color: '#bbc9cd' }}>Storm Fees Locked</p>
                    </div>
                  </div>

                  <div className="h-28 sm:h-32 w-full rounded-lg overflow-hidden border relative"
                    style={{ backgroundColor: '#0a0e1a', borderColor: 'rgba(60,73,76,0.1)' }}>
                    <div className="absolute inset-0 opacity-20 bg-gradient-to-t"
                      style={{ backgroundImage: 'linear-gradient(to top, rgba(138,235,255,0.2), transparent)' }}></div>
                    <img
                      className="w-full h-full object-cover"
                      src="https://lh3.googleusercontent.com/aida-public/AB6AXuDWW1Ij0Ys81UTvZRKFDhEj2utkeNMYDoSV_kfXOJvQMJ9hlMK83H80soaDkvLQMYLHkLdZlKpqPEd_ehRMQexJKZ9QbajxUlVIWA6Gm4hV-c6dSVRMwrBosUE7hLMlH9aTXDxVwccgsZE87ws-YU9dqs00J78cBOVpbviPDpfugGrMsYWvkbEvugmCZaD1_wzK_tdWAtLeuyU1I9oEP7DIRn9ifDrmcOpEV4_BYG1mSJE7GTNtKfTGbklGRGDGK0TVKZyPaBzYA64"
                      alt="VRS volatility chart"
                    />
                  </div>
                </div>
              </div>
            </div>
          </section>

          {/* ── Trust strip ── */}
          <section className="border-y py-6 sm:py-10"
            style={{ borderColor: 'rgba(60,73,76,0.1)', backgroundColor: 'rgba(10,14,26,0.3)' }}>
            <div className="px-4 sm:px-8 max-w-7xl mx-auto">
              <div className="flex flex-wrap justify-between items-center gap-6 sm:gap-10 opacity-40 grayscale">
                <div className="flex items-center gap-2">
                  <span className="ms text-3xl sm:text-4xl">database</span>
                  <span className="text-base sm:text-xl font-semibold">Ethereum</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="ms text-3xl sm:text-4xl">hub</span>
                  <span className="text-base sm:text-xl font-semibold">Uniswap V4</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="ms text-3xl sm:text-4xl">psychology</span>
                  <span className="text-base sm:text-xl font-semibold">AI Risk Engine</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="ms text-3xl sm:text-4xl">security</span>
                  <span className="text-base sm:text-xl font-semibold">Yield Buffer</span>
                </div>
              </div>
            </div>
          </section>

          {/* ── Metrics ── */}
          <section className="shape-grid-bg py-10 sm:py-16 relative overflow-hidden">
            <div className="px-4 sm:px-8 max-w-7xl mx-auto">
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 sm:gap-6">

                <div className="spotlight-card p-6 sm:p-10 rounded-xl">
                  <p className="text-xs sm:text-sm mb-3 sm:mb-4" style={{ color: '#bbc9cd' }}>Fee Range</p>
                  <p className="text-3xl sm:text-4xl font-bold">0.05–0.50%</p>
                  <p className="text-xs mt-2 flex items-center gap-1" style={{ color: '#8aebff' }}>
                    <span className="ms" style={{ fontSize: '16px' }}>trending_up</span>
                    AI-Controlled Per Swap
                  </p>
                </div>

                <div className="spotlight-card p-6 sm:p-10 rounded-xl">
                  <p className="text-xs sm:text-sm mb-3 sm:mb-4" style={{ color: '#bbc9cd' }}>Risk Score Range</p>
                  <p className="text-3xl sm:text-4xl font-bold">0–100</p>
                  <p className="text-xs mt-2 flex items-center gap-1" style={{ color: '#8aebff' }}>
                    <span className="ms" style={{ fontSize: '16px' }}>trending_up</span>
                    Pushed by Reactive RSC
                  </p>
                </div>

                <div className="spotlight-card p-6 sm:p-10 rounded-xl">
                  <p className="text-xs sm:text-sm mb-3 sm:mb-4" style={{ color: '#bbc9cd' }}>Chains Monitored</p>
                  <p className="text-3xl sm:text-4xl font-bold">5</p>
                  <p className="text-xs mt-2 flex items-center gap-1" style={{ color: '#8aebff' }}>
                    <span className="ms" style={{ fontSize: '16px' }}>auto_awesome</span>
                    Cross-Chain Price Gaps
                  </p>
                </div>

                <div className="spotlight-card p-6 sm:p-10 rounded-xl">
                  <p className="text-xs sm:text-sm mb-3 sm:mb-4" style={{ color: '#bbc9cd' }}>Payout Strategies</p>
                  <p className="text-3xl sm:text-4xl font-bold">3</p>
                  <p className="text-xs mt-2 flex items-center gap-1" style={{ color: '#8aebff' }}>
                    <span className="ms" style={{ fontSize: '16px' }}>group</span>
                    Daily · Lump Sum · Reinvest
                  </p>
                </div>

              </div>
            </div>
          </section>

          {/* ── Features ── */}
          <section className="py-10 sm:py-16 px-4 sm:px-8 max-w-7xl mx-auto">
            <div className="mb-8 sm:mb-10">
              <h2 className="text-3xl sm:text-4xl font-bold mb-3 sm:mb-4">Institutional Intelligence</h2>
              <p className="text-base sm:text-lg max-w-xl" style={{ color: '#bbc9cd' }}>
                Engineered to handle the most extreme market conditions with mathematical precision.
              </p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 sm:gap-6">

              <div className="spotlight-card p-6 sm:p-10 rounded-2xl space-y-3 sm:space-y-4">
                <span className="ms text-3xl sm:text-4xl" style={{ color: '#8aebff' }}>query_stats</span>
                <h3 className="text-lg sm:text-xl font-semibold">Intelligent Risk Engine</h3>
                <p className="text-sm sm:text-base" style={{ color: '#bbc9cd' }}>
                  Real-time volatility analysis across 5 chains continuously recalculates optimal
                  liquidity bounds to prevent impermanent loss.
                </p>
              </div>

              <div className="spotlight-card p-6 sm:p-10 rounded-2xl space-y-3 sm:space-y-4">
                <span className="ms text-3xl sm:text-4xl" style={{ color: '#8aebff' }}>payments</span>
                <h3 className="text-lg sm:text-xl font-semibold">Dynamic Fee Optimization</h3>
                <p className="text-sm sm:text-base" style={{ color: '#bbc9cd' }}>
                  Automatically adjusts swap fees from 0.05% to 0.50% during high volatility to
                  compensate liquidity providers for increased risk.
                </p>
              </div>

              <div className="spotlight-card p-6 sm:p-10 rounded-2xl space-y-3 sm:space-y-4 sm:col-span-2 md:col-span-1">
                <span className="ms text-3xl sm:text-4xl" style={{ color: '#8aebff' }}>shield_with_heart</span>
                <h3 className="text-lg sm:text-xl font-semibold">Yield Buffer Protection</h3>
                <p className="text-sm sm:text-base" style={{ color: '#bbc9cd' }}>
                  A dedicated vault captures storm fees, earns yield on Aave / Morpho, then
                  distributes to LPs with compounded returns once calm returns.
                </p>
              </div>

            </div>
          </section>

          {/* ── How It Works (Stepper) ── */}
          <section className="py-10 sm:py-16 border-y"
            style={{ backgroundColor: 'rgba(10,14,26,0.5)', borderColor: 'rgba(60,73,76,0.1)' }}>
            <div className="px-4 sm:px-8 max-w-7xl mx-auto">
              <h2 className="text-3xl sm:text-4xl font-bold mb-10 sm:mb-16 text-center">
                Seamless Capital Deployment
              </h2>

              <div className="relative grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-8 sm:gap-10">
                {/* Connector line — desktop only */}
                <div className="hidden lg:block stepper-line"></div>

                {/* Step 1 */}
                <div className="relative z-10 flex flex-col items-center text-center">
                  <div className="w-12 h-12 rounded-full flex items-center justify-center mb-5 border-4"
                    style={{ backgroundColor: '#8aebff', borderColor: '#050814' }}>
                    <span className="ms text-xl" style={{ color: '#00363e' }}>wallet</span>
                  </div>
                  <h4 className="text-lg sm:text-xl font-semibold mb-2">Deposit Liquidity</h4>
                  <p className="text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                    Connect wallet on Sepolia, approve VTKA + VTKB, and set your yield intent.
                  </p>
                </div>

                {/* Step 2 */}
                <div className="relative z-10 flex flex-col items-center text-center">
                  <div className="w-12 h-12 rounded-full flex items-center justify-center mb-5 border-2"
                    style={{ backgroundColor: '#262937', borderColor: '#8aebff' }}>
                    <span className="ms text-xl" style={{ color: '#8aebff' }}>visibility</span>
                  </div>
                  <h4 className="text-lg sm:text-xl font-semibold mb-2">Reactive Monitors Volatility</h4>
                  <p className="text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                    Reactive Network RSC tracks 5 chains and pushes a live VRS score 0–100 to the oracle.
                  </p>
                </div>

                {/* Step 3 */}
                <div className="relative z-10 flex flex-col items-center text-center">
                  <div className="w-12 h-12 rounded-full flex items-center justify-center mb-5 border-2"
                    style={{ backgroundColor: '#262937', borderColor: '#3c494c' }}>
                    <span className="ms text-xl" style={{ color: '#bbc9cd' }}>account_balance</span>
                  </div>
                  <h4 className="text-lg sm:text-xl font-semibold mb-2">Buffer Earns Yield</h4>
                  <p className="text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                    Storm fees are routed to Aave / Morpho via the yield buffer, compounding until calm.
                  </p>
                </div>

                {/* Step 4 */}
                <div className="relative z-10 flex flex-col items-center text-center">
                  <div className="w-12 h-12 rounded-full flex items-center justify-center mb-5 border-2"
                    style={{ backgroundColor: '#262937', borderColor: '#3c494c' }}>
                    <span className="ms text-xl" style={{ color: '#bbc9cd' }}>verified_user</span>
                  </div>
                  <h4 className="text-lg sm:text-xl font-semibold mb-2">LP Receives Protection</h4>
                  <p className="text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                    When VRS drops to calm, Reactive triggers distribution — LPs collect fees + yield.
                  </p>
                </div>
              </div>
            </div>
          </section>

          {/* ── Dashboard Preview ── */}
          <section className="py-10 sm:py-16 px-4 sm:px-8 max-w-7xl mx-auto">
            <div className="mb-8 sm:mb-10 text-center">
              <h2 className="text-3xl sm:text-4xl font-bold">Sophisticated Control</h2>
              <p className="text-base sm:text-lg mt-2" style={{ color: '#bbc9cd' }}>
                Manage VTKA / VTKB positions, yield buffer, and risk score from one unified interface.
              </p>
            </div>

            <div className="spotlight-card p-4 sm:p-6 md:p-10 rounded-3xl border shadow-2xl"
              style={{ borderColor: 'rgba(60,73,76,0.2)' }}>
              <div className="rounded-2xl border overflow-hidden"
                style={{ backgroundColor: '#050814', borderColor: 'rgba(60,73,76,0.1)' }}>

                {/* Window chrome */}
                <div className="border-b p-3 sm:p-6 flex justify-between items-center"
                  style={{ borderColor: 'rgba(60,73,76,0.1)', backgroundColor: '#0a0e1a' }}>
                  <div className="flex gap-2 sm:gap-4 items-center">
                    <div className="w-3 h-3 rounded-full" style={{ backgroundColor: '#ffb4ab' }}></div>
                    <div className="w-3 h-3 rounded-full bg-yellow-500"></div>
                    <div className="w-3 h-3 rounded-full bg-green-500"></div>
                    <span className="ml-2 sm:ml-4 text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                      VolatilityVault / Dashboard · VTKA–VTKB Pool
                    </span>
                  </div>
                  <div className="flex gap-2 sm:gap-4">
                    <div className="h-6 sm:h-8 w-16 sm:w-24 rounded-lg" style={{ backgroundColor: '#1b1f2c' }}></div>
                    <div className="h-6 sm:h-8 w-6 sm:w-8 rounded-lg" style={{ backgroundColor: '#1b1f2c' }}></div>
                  </div>
                </div>

                {/* Dashboard body */}
                <div className="p-4 sm:p-6 md:p-10 grid grid-cols-1 lg:grid-cols-12 gap-4 sm:gap-6 md:gap-10">

                  {/* Left panel */}
                  <div className="lg:col-span-8 space-y-4 sm:space-y-6 md:space-y-10">

                    {/* Chart */}
                    <div className="h-40 sm:h-52 md:h-64 w-full rounded-xl relative overflow-hidden group"
                      style={{ backgroundColor: '#171b28' }}>
                      <img
                        className="w-full h-full object-cover opacity-80 group-hover:scale-105 transition-transform duration-700"
                        src="https://lh3.googleusercontent.com/aida-public/AB6AXuD75HSXF97TRg1QZlDKwT9HnoDVjY0SAowlPlshkasVLnkTCtBL7GE9YNGBJRsbDiCw5NVaRbRjbjsNRnD0l3vR5Q9cdWLVl0eMLT_UVVeTjxAOQrxQry_tQSQjXO-eGwnrXZ7D6oTXlzrZZkmUD9jQLoAZ-VNGVV4k7esrQjVL9EvrQZtzWM6fdyGIRWCjWUcqBI--Bg-b0o5jfKd_EOn-dnPW5vwI7bSU5249W4CJwL_PUrAK0kNV3PW9BGM56zSZMi-xP1-6plg"
                        alt="VolatilityVault dashboard"
                      />
                      <div className="absolute inset-0 bg-gradient-to-t from-[#050814] to-transparent"></div>
                      <div className="absolute bottom-0 left-0 p-3 sm:p-6">
                        <h4 className="text-base sm:text-xl font-semibold">VRS Live Feed</h4>
                        <p className="text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                          Fee tier updates per swap · Reactive RSC oracle
                        </p>
                      </div>
                    </div>

                    {/* Stats row */}
                    <div className="grid grid-cols-2 gap-3 sm:gap-6">
                      <div className="p-3 sm:p-6 rounded-xl border"
                        style={{ backgroundColor: '#1b1f2c', borderColor: 'rgba(60,73,76,0.05)' }}>
                        <p className="text-xs uppercase mb-2" style={{ color: '#bbc9cd' }}>Buffer Status</p>
                        <div className="flex items-center gap-3 sm:gap-4">
                          <div className="w-full h-2 rounded-full overflow-hidden" style={{ backgroundColor: '#313442' }}>
                            <div className="w-[84%] h-full rounded-full"
                              style={{ backgroundColor: '#8aebff', boxShadow: '0 0 10px rgba(138,235,255,0.4)' }}></div>
                          </div>
                          <span className="text-xs sm:text-sm font-medium">84%</span>
                        </div>
                      </div>
                      <div className="p-3 sm:p-6 rounded-xl border"
                        style={{ backgroundColor: '#1b1f2c', borderColor: 'rgba(60,73,76,0.05)' }}>
                        <p className="text-xs uppercase mb-2" style={{ color: '#bbc9cd' }}>Yield Overview</p>
                        <p className="text-base sm:text-xl font-semibold" style={{ color: '#8aebff' }}>
                          Active Epoch
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Right panel */}
                  <div className="lg:col-span-4 space-y-4 sm:space-y-6 md:space-y-10">

                    {/* Positions */}
                    <div className="p-3 sm:p-6 rounded-xl border"
                      style={{ backgroundColor: '#262937', borderColor: 'rgba(60,73,76,0.1)' }}>
                      <h4 className="text-xs sm:text-sm font-medium mb-3 sm:mb-6">Active Pool Positions</h4>
                      <div className="space-y-2 sm:space-y-4">
                        <div className="flex justify-between items-center p-2 sm:p-4 rounded-lg border"
                          style={{ backgroundColor: '#050814', borderColor: 'rgba(60,73,76,0.05)' }}>
                          <span className="text-xs sm:text-sm">VTKA / VTKB Range</span>
                          <span className="px-2 py-1 rounded text-[10px] font-bold"
                            style={{ backgroundColor: 'rgba(138,235,255,0.1)', color: '#8aebff' }}>ACTIVE</span>
                        </div>
                        <div className="flex justify-between items-center p-2 sm:p-4 rounded-lg border"
                          style={{ backgroundColor: '#050814', borderColor: 'rgba(60,73,76,0.05)' }}>
                          <span className="text-xs sm:text-sm">Yield Buffer Share</span>
                          <span className="px-2 py-1 rounded text-[10px] font-bold"
                            style={{ backgroundColor: 'rgba(138,235,255,0.1)', color: '#8aebff' }}>EARNING</span>
                        </div>
                        <div className="flex justify-between items-center p-2 sm:p-4 rounded-lg border opacity-50"
                          style={{ backgroundColor: '#050814', borderColor: 'rgba(60,73,76,0.05)' }}>
                          <span className="text-xs sm:text-sm">Claim (prev epoch)</span>
                          <span className="px-2 py-1 rounded text-[10px] font-bold"
                            style={{ backgroundColor: '#313442', color: '#bbc9cd' }}>PENDING</span>
                        </div>
                      </div>
                    </div>

                    {/* Risk summary */}
                    <div className="p-3 sm:p-6 rounded-xl" style={{ backgroundColor: '#8aebff', color: '#00363e' }}>
                      <h4 className="text-xs sm:text-sm font-medium mb-2 sm:mb-4">Risk Summary</h4>
                      <p className="text-3xl sm:text-4xl font-bold">CALM</p>
                      <p className="text-xs mt-2 sm:mt-4 opacity-80">
                        VRS is low. Fees at minimum 0.05%. Ideal conditions for adding liquidity.
                      </p>
                    </div>
                  </div>

                </div>
              </div>
            </div>
          </section>

          {/* ── Comparison table ── */}
          <section className="py-10 sm:py-16 px-4 sm:px-8 max-w-7xl mx-auto">
            <h2 className="text-3xl sm:text-4xl font-bold mb-10 sm:mb-16 text-center">
              Engineered for Dominance
            </h2>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b" style={{ borderColor: 'rgba(60,73,76,0.1)' }}>
                    <th className="py-4 sm:py-10 text-sm sm:text-xl font-semibold">Feature</th>
                    <th className="py-4 sm:py-10 text-sm sm:text-xl font-semibold" style={{ color: '#bbc9cd' }}>
                      Traditional LP
                    </th>
                    <th className="py-4 sm:py-10 text-sm sm:text-xl font-semibold" style={{ color: '#8aebff' }}>
                      VolatilityVault
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    { feature: 'Impermanent Loss Risk', trad: 'Uncapped / High', vv: 'AI-Mitigated' },
                    { feature: 'Fee Management',        trad: 'Static Tier Based', vv: 'Real-time Dynamic' },
                    { feature: 'Capital Efficiency',    trad: 'Manual Rebalancing', vv: 'Automated JIT Range' },
                    { feature: 'Principal Insurance',   trad: 'None', vv: 'Embedded Yield Buffer' },
                  ].map(row => (
                    <tr key={row.feature}
                      className="border-b hover:bg-white/[0.02] transition-colors"
                      style={{ borderColor: 'rgba(60,73,76,0.05)' }}>
                      <td className="py-3 sm:py-6 text-xs sm:text-base font-semibold">{row.feature}</td>
                      <td className="py-3 sm:py-6 text-xs sm:text-base" style={{ color: '#bbc9cd' }}>{row.trad}</td>
                      <td className="py-3 sm:py-6 text-xs sm:text-base" style={{ color: '#8aebff' }}>
                        <span className="flex items-center gap-2">
                          <span className="ms" style={{ fontSize: '18px' }}>verified</span>
                          {row.vv}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          {/* ── Final CTA ── */}
          <section className="py-10 sm:py-16 relative overflow-hidden">
            <div className="absolute inset-0 shape-grid-bg opacity-30"></div>
            <div className="px-4 sm:px-8 max-w-4xl mx-auto text-center relative z-10 space-y-6 sm:space-y-10">
              <h2 className="text-3xl sm:text-5xl font-bold">
                Protect Liquidity With Intelligence
              </h2>
              <p className="text-sm sm:text-lg" style={{ color: '#bbc9cd' }}>
                Join LPs on Ethereum Sepolia testing the first AI-driven volatility hook on Uniswap V4 —
                automated fee control, storm protection, and compounding yield in one.
              </p>
              <div className="flex flex-col sm:flex-row justify-center gap-3 sm:gap-4 pt-2">
                <Link href="/dashboard"
                  className="btn-primary px-8 sm:px-16 py-4 sm:py-6 rounded-xl text-base sm:text-xl font-bold">
                  Launch App
                </Link>
                <Link href="/buffer"
                  className="btn-secondary px-8 sm:px-16 py-4 sm:py-6 rounded-xl text-base sm:text-xl"
                  style={{ color: '#dfe1f4' }}>
                  Explore Buffer
                </Link>
              </div>
            </div>
          </section>

        </main>

        {/* ── Footer ── */}
        <footer className="w-full pt-10 sm:pt-16 pb-6 sm:pb-10 border-t"
          style={{ borderColor: 'rgba(60,73,76,0.1)', backgroundColor: '#0a0e1a' }}>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-6 sm:gap-8 px-4 sm:px-8 max-w-7xl mx-auto">

            <div className="col-span-2 md:col-span-1 space-y-3 sm:space-y-4">
              <div className="text-lg sm:text-xl font-bold" style={{ color: '#dfe1f4' }}>VolatilityVault</div>
              <p className="text-xs sm:text-sm leading-relaxed" style={{ color: '#bbc9cd' }}>
                AI-powered LP protection on Uniswap V4. Built for the Reactive Network hackathon.
                Deployed on Ethereum Sepolia.
              </p>
            </div>

            <div>
              <h4 className="text-xs font-bold mb-4 sm:mb-6 uppercase tracking-widest opacity-60">App</h4>
              <ul className="space-y-3 sm:space-y-4 text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                <li><Link href="/deposit" className="hover:text-white transition-colors">Add Liquidity</Link></li>
                <li><Link href="/positions" className="hover:text-white transition-colors">My Positions</Link></li>
                <li><Link href="/buffer" className="hover:text-white transition-colors">Yield Buffer</Link></li>
              </ul>
            </div>

            <div>
              <h4 className="text-xs font-bold mb-4 sm:mb-6 uppercase tracking-widest opacity-60">Protocol</h4>
              <ul className="space-y-3 sm:space-y-4 text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                <li>
                  <a href="https://sepolia.etherscan.io/address/0x63Ce6162Af038c903fc21ECBE090A690eD5b85C0"
                    target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">
                    Hook Contract ↗
                  </a>
                </li>
                <li>
                  <a href="https://sepolia.etherscan.io/address/0x2704187fbE9a0617312B5Eb7399508E760821BBc"
                    target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">
                    Yield Buffer ↗
                  </a>
                </li>
                <li>
                  <a href="https://sepolia.etherscan.io/address/0x172c86F5b964d7836Cf055A76f5Ad316f0297198"
                    target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">
                    VRS Oracle ↗
                  </a>
                </li>
              </ul>
            </div>

            <div>
              <h4 className="text-xs font-bold mb-4 sm:mb-6 uppercase tracking-widest opacity-60">Built With</h4>
              <ul className="space-y-3 sm:space-y-4 text-xs sm:text-sm" style={{ color: '#bbc9cd' }}>
                <li>Uniswap V4 Hooks</li>
                <li>Reactive Network</li>
                <li>Aave / Morpho</li>
                <li>Next.js + wagmi</li>
              </ul>
            </div>

          </div>
        </footer>

      </div>
    </>
  )
}
