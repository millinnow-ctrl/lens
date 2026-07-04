import { Link, useLocation } from 'react-router-dom'
import Logo from './Logo'
import { FREE_CREDITS, useApp } from '../lib/store'

export default function Nav() {
  const { creditsLeft, isPaid, plan, user, setAuthOpen } = useApp()
  const location = useLocation()

  return (
    <>
      {/* top bar */}
      <header className="sticky top-0 z-50 bg-white/85 backdrop-blur-md border-b border-ink/5 pt-[env(safe-area-inset-top)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-3">
          <Link to="/" className="shrink-0">
            <Logo />
          </Link>

          <nav className="hidden md:flex items-center gap-1 text-[13px] font-medium">
            {[
              { to: '/studio', label: 'Studio' },
              { to: '/#styles', label: 'Camera moods' },
              { to: '/pricing', label: 'Pricing' },
              { to: '/dashboard', label: 'Library' },
            ].map((l) => {
              const active = location.pathname === l.to
              return (
                <Link
                  key={l.label}
                  to={l.to}
                  className={`inline-flex items-center px-3.5 py-1.5 rounded-full transition-colors ${
                    active
                      ? 'bg-violet/10 text-violet font-semibold'
                      : 'text-ink-soft hover:text-ink hover:bg-ink/5'
                  }`}
                >
                  {l.label}
                </Link>
              )
            })}
          </nav>

          <div className="flex items-center gap-3">
            {!isPaid && (
              <Link
                to="/pricing"
                className="hidden sm:inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-violet/10 text-violet text-[12px] font-semibold tabular-nums hover:bg-violet/15 transition-colors"
                title="Free shots remaining this month"
              >
                Roll {creditsLeft}/{FREE_CREDITS}
              </Link>
            )}
            {isPaid && (
              <span className="hidden sm:inline-flex items-center px-3 py-1 rounded-full bg-violet/10 text-violet text-[12px] font-semibold uppercase tracking-[0.04em]">
                {plan}
              </span>
            )}
            {user ? (
              <Link
                to="/dashboard"
                className="w-8 h-8 rounded-full grad-fill text-white font-semibold text-[12px] flex items-center justify-center shadow-[0_2px_8px_rgb(139_92_246/0.35)] hover:opacity-90 transition-opacity"
                title={user.name}
              >
                {user.name.charAt(0).toUpperCase()}
              </Link>
            ) : (
              <button onClick={() => setAuthOpen(true)} className="btn btn-quiet px-2 hidden sm:inline-flex">
                Sign in
              </button>
            )}
            <Link to="/studio" className="btn btn-primary">
              Open studio
            </Link>
          </div>
        </div>
      </header>

    </>
  )
}
