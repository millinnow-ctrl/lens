import { Link, NavLink, useLocation } from 'react-router-dom'
import Logo from './Logo'
import { useApp } from '../lib/store'

const tabs = [
  {
    to: '/',
    label: 'Home',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1Z" />
      </svg>
    ),
  },
  {
    to: '/studio',
    label: 'Studio',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="6" width="18" height="14" rx="3" />
        <circle cx="12" cy="13" r="4" />
        <path d="M8 6l1.2-2h5.6L16 6" />
      </svg>
    ),
  },
  {
    to: '/pricing',
    label: 'Pricing',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 3l2.5 5.5L20 9.3l-4 4 1 5.7-5-2.8-5 2.8 1-5.7-4-4 5.5-.8Z" />
      </svg>
    ),
  },
  {
    to: '/dashboard',
    label: 'Library',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="3" width="8" height="8" rx="2" />
        <rect x="13" y="3" width="8" height="8" rx="2" />
        <rect x="3" y="13" width="8" height="8" rx="2" />
        <rect x="13" y="13" width="8" height="8" rx="2" />
      </svg>
    ),
  },
]

export default function Nav() {
  const { creditsLeft, isPaid, plan, user, setAuthOpen } = useApp()
  const location = useLocation()

  return (
    <>
      {/* top bar */}
      <header className="sticky top-0 z-50 bg-paper/80 backdrop-blur-xl border-b border-cloud/70">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-3">
          <Link to="/" className="shrink-0">
            <Logo />
          </Link>

          <nav className="hidden md:flex items-center gap-1 text-sm font-medium text-fog">
            {[
              { to: '/studio', label: 'Studio' },
              { to: '/#styles', label: 'Camera styles' },
              { to: '/pricing', label: 'Pricing' },
              { to: '/dashboard', label: 'Library' },
            ].map((l) => (
              <Link
                key={l.label}
                to={l.to}
                className={`px-3.5 py-2 rounded-full transition-colors hover:text-ink hover:bg-mist ${
                  location.pathname === l.to ? 'text-ink bg-mist' : ''
                }`}
              >
                {l.label}
              </Link>
            ))}
          </nav>

          <div className="flex items-center gap-2">
            {!isPaid && (
              <Link
                to="/pricing"
                className="hidden sm:inline-flex items-center gap-1.5 text-xs font-semibold text-fog bg-mist rounded-full px-3 py-1.5 hover:bg-cloud transition-colors"
                title="Free shots remaining this month"
              >
                <span className="w-1.5 h-1.5 rounded-full bg-violet inline-block" />
                {creditsLeft} free {creditsLeft === 1 ? 'shot' : 'shots'} left
              </Link>
            )}
            {isPaid && (
              <span className="hidden sm:inline-flex items-center gap-1 text-xs font-bold text-violet bg-violet-soft rounded-full px-3 py-1.5 capitalize">
                {plan} ✓
              </span>
            )}
            {user ? (
              <Link
                to="/dashboard"
                className="w-9 h-9 rounded-full bg-violet text-paper font-bold text-sm flex items-center justify-center hover:scale-105 transition-transform"
                title={user.name}
              >
                {user.name.charAt(0).toUpperCase()}
              </Link>
            ) : (
              <button onClick={() => setAuthOpen(true)} className="pill-base pill-ghost px-4 py-2 text-sm">
                Sign in
              </button>
            )}
            <Link to="/studio" className="pill-base pill-primary px-4 py-2 text-sm">
              Try it free
            </Link>
          </div>
        </div>
      </header>

      {/* mobile bottom tab bar */}
      <nav className="md:hidden fixed bottom-0 inset-x-0 z-50 bg-paper/90 backdrop-blur-xl border-t border-cloud pb-[env(safe-area-inset-bottom)]">
        <div className="grid grid-cols-4">
          {tabs.map((t) => (
            <NavLink
              key={t.to}
              to={t.to}
              className={({ isActive }) =>
                `flex flex-col items-center gap-0.5 py-2.5 text-[11px] font-medium transition-colors ${
                  isActive ? 'text-violet' : 'text-fog'
                }`
              }
            >
              {t.icon}
              {t.label}
            </NavLink>
          ))}
        </div>
      </nav>
    </>
  )
}
