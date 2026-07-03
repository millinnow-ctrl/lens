import { useEffect, useState } from 'react'
import { Route, Routes, useLocation } from 'react-router-dom'
import Nav from './components/Nav'
import Footer from './components/Footer'
import AuthModal from './components/AuthModal'
import BottomNav from './components/home/BottomNav'
import AccountSheet from './components/home/AccountSheet'
import LandingPage from './pages/LandingPage'
import Home from './pages/Home'
import Studio from './pages/Studio'
import PricingPage from './pages/PricingPage'
import Dashboard from './pages/Dashboard'
import { isNative } from './lib/native'

function ScrollManager() {
  const { pathname, hash } = useLocation()
  useEffect(() => {
    if (hash) {
      document.querySelector(hash)?.scrollIntoView({ behavior: 'smooth' })
    } else {
      window.scrollTo(0, 0)
    }
  }, [pathname, hash])
  return null
}

/** installed app (native shell / PWA) and single-file previews boot into the
 *  app home; the plain web root stays the marketing page */
function RootRoute() {
  const appLike =
    isNative() ||
    window.matchMedia?.('(display-mode: standalone)').matches ||
    !!import.meta.env.VITE_SINGLEFILE
  return appLike ? <Home /> : <LandingPage />
}

export default function App() {
  const { pathname } = useLocation()
  const [accountOpen, setAccountOpen] = useState(false)

  const isAppHome =
    pathname === '/home' ||
    (pathname === '/' &&
      (isNative() ||
        window.matchMedia?.('(display-mode: standalone)').matches ||
        !!import.meta.env.VITE_SINGLEFILE))

  return (
    <div className="ui-grain min-h-dvh flex flex-col">
      <ScrollManager />
      {/* the app home carries its own mobile chrome */}
      <div className={isAppHome ? 'hidden md:block' : ''}>
        <Nav />
      </div>
      <div className="flex-1">
        <Routes>
          <Route path="/" element={<RootRoute />} />
          <Route path="/home" element={<Home />} />
          <Route path="/studio" element={<Studio />} />
          <Route path="/pricing" element={<PricingPage />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="*" element={<RootRoute />} />
        </Routes>
      </div>
      {!isAppHome && <Footer />}
      {/* global mobile dock (the home screen embeds its own inside the frame on desktop) */}
      <div className="md:hidden">
        <BottomNav variant="fixed" onAccount={() => setAccountOpen(true)} />
        <AccountSheet open={accountOpen} onClose={() => setAccountOpen(false)} />
      </div>
      <AuthModal />
    </div>
  )
}
