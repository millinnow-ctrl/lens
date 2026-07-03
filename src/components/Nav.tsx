import { Link, useLocation } from 'react-router-dom'
import Logo from './Logo'
import { FREE_CREDITS, useApp } from '../lib/store'

export default function Nav() {
  const { creditsLeft, isPaid, plan, user, setAuthOpen } = useApp()
  const location = useLocation()

  return (
    <>
      {/* top bar */}
      <header className="sticky top-0 z-50 bg-paper border-b border-hairline pt-[env(safe-area-inset-top)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-3">
          <Link to="/" className="shrink-0">
            <Logo />
          </Link>

          <nav className="hidden md:flex items-center gap-6 text-[13px] font-medium">
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
                  className={`inline-flex items-center gap-1.5 transition-colors ${
                    active ? 'text-ink' : 'text-ink-soft hover:text-ink'
                  }`}
                >
                  {active && <span className="w-1.5 h-1.5 rounded-full bg-signal inline-block" />}
                  {l.label}
                </Link>
              )
            })}
          </nav>

          <div className="flex items-center gap-3">
            {!isPaid && (
              <Link
                to="/pricing"
                className="hidden sm:inline font-mono text-[11px] tracking-[0.08em] text-ink-soft hover:text-ink transition-colors tabular-nums"
                title="Free shots remaining this month"
              >
                {creditsLeft}/{FREE_CREDITS} FREE
              </Link>
            )}
            {isPaid && (
              <span className="hidden sm:inline font-mono text-[11px] tracking-[0.08em] text-signal uppercase">
                {plan}
              </span>
            )}
            {user ? (
              <Link
                to="/dashboard"
                className="w-8 h-8 rounded-xs border border-ink text-ink font-semibold text-[12px] flex items-center justify-center hover:bg-ink hover:text-surface transition-colors"
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
