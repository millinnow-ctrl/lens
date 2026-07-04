import { useEffect, useState } from 'react'
import { Route, Routes, useLocation } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { pageTransition } from './lib/motion'
import Nav from './components/Nav'
import Footer from './components/Footer'
import AuthModal from './components/AuthModal'
import BottomNav from './components/home/BottomNav'
import AccountSheet from './components/home/AccountSheet'
import UploadModal from './components/home/UploadModal'
import LandingPage from './pages/LandingPage'
import Home from './pages/Home'
import Studio from './pages/Studio'
import PricingPage from './pages/PricingPage'
import Dashboard from './pages/Dashboard'
import { PrivacyPage, TermsPage } from './pages/LegalPage'
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

const routeVariants = pageTransition()

export default function App() {
  const location = useLocation()
  const { pathname } = location
  const [accountOpen, setAccountOpen] = useState(false)
  const [uploadOpen, setUploadOpen] = useState(false)

  const isAppHome =
    pathname === '/home' ||
    (pathname === '/' &&
      (isNative() ||
        window.matchMedia?.('(display-mode: standalone)').matches ||
        !!import.meta.env.VITE_SINGLEFILE))

  return (
    <div className="min-h-dvh flex flex-col">
      <ScrollManager />
      {/* the app home carries its own mobile chrome */}
      <div className={isAppHome ? 'hidden md:block' : ''}>
        <Nav />
      </div>
      <div className="flex-1">
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={pathname}
            variants={routeVariants}
            initial="initial"
            animate="animate"
            exit="exit"
            style={{ willChange: 'transform, opacity' }}
          >
            <Routes location={location}>
              <Route path="/" element={<RootRoute />} />
              <Route path="/home" element={<Home />} />
              <Route path="/studio" element={<Studio />} />
              <Route path="/pricing" element={<PricingPage />} />
              <Route path="/dashboard" element={<Dashboard />} />
              <Route path="/privacy" element={<PrivacyPage />} />
              <Route path="/terms" element={<TermsPage />} />
              <Route path="*" element={<RootRoute />} />
            </Routes>
          </motion.div>
        </AnimatePresence>
      </div>
      {!isAppHome && <Footer />}
      {/* global mobile dock (the home screen embeds its own inside the frame on desktop) */}
      <div className="md:hidden">
        <BottomNav
          variant="fixed"
          onAccount={() => setAccountOpen(true)}
          onCreate={() => setUploadOpen(true)}
        />
        <UploadModal open={uploadOpen} onClose={() => setUploadOpen(false)} />
        <AccountSheet open={accountOpen} onClose={() => setAccountOpen(false)} />
      </div>
      <AuthModal />
    </div>
  )
}
