import { useEffect } from 'react'
import { Route, Routes, useLocation } from 'react-router-dom'
import Nav from './components/Nav'
import Footer from './components/Footer'
import AuthModal from './components/AuthModal'
import LandingPage from './pages/LandingPage'
import Studio from './pages/Studio'
import PricingPage from './pages/PricingPage'
import Dashboard from './pages/Dashboard'

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

export default function App() {
  return (
    <div className="ui-grain min-h-dvh flex flex-col">
      <ScrollManager />
      <Nav />
      <div className="flex-1">
        <Routes>
          <Route path="/" element={<LandingPage />} />
          <Route path="/studio" element={<Studio />} />
          <Route path="/pricing" element={<PricingPage />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="*" element={<LandingPage />} />
        </Routes>
      </div>
      <Footer />
      <AuthModal />
    </div>
  )
}
