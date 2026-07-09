import { useEffect, useState } from 'react'
import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
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
import PrintRoom from './pages/PrintRoom'
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

  /* surfaces that live behind the dock on mobile: one chrome system per
     viewport — marketing header on desktop, dock on phones. Stacking both
     reads like a website wearing an app costume. */
  const isAppSurface =
    isAppHome || pathname === '/studio' || pathname === '/pricing' || pathname === '/dashboard'

  return (
    <div className="min-h-dvh flex flex-col">
      <ScrollManager />
      <div className={isAppSurface ? 'hidden md:block' : ''}>
        <Nav />
      </div>
      {/* app surfaces draw edge-to-edge on iOS (paper flows under the status
          bar); this wrapper supplies the one true safe-area offset — the
          native shell no longer double-insets on top of it */}
      <div className={`flex-1 ${isAppSurface ? 'pt-[env(safe-area-inset-top)] md:pt-0' : ''}`}>
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
              <Route path="/print" element={<PrintRoom />} />
              <Route path="/pricing" element={<PricingPage />} />
              <Route path="/dashboard" element={<Dashboard />} />
              <Route path="/privacy" element={<PrivacyPage />} />
              <Route path="/terms" element={<TermsPage />} />
              {/* mistyped URLs correct themselves instead of silently
                  impersonating the landing page */}
              <Route path="*" element={<Navigate to="/" replace />} />
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
