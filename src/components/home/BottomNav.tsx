import { motion } from 'framer-motion'
import { useLocation, useNavigate } from 'react-router-dom'
import { springPress } from '../../lib/motion'
import {
  IconHome,
  IconHomeFill,
  IconImage,
  IconImageFill,
  IconPlusCircle,
  IconStyles,
  IconStylesFill,
  IconUser,
  IconUserFill,
} from '../icons'
import { haptic } from '../../lib/native'

const TABS = [
  { id: 'home', label: 'Home', icon: IconHome, iconFill: IconHomeFill, to: '/home' },
  { id: 'styles', label: 'Styles', icon: IconStyles, iconFill: IconStylesFill, to: '/studio' },
  { id: 'create', label: 'Camera', icon: IconPlusCircle, iconFill: undefined, to: '#create' },
  { id: 'gallery', label: 'Gallery', icon: IconImage, iconFill: IconImageFill, to: '/dashboard' },
  { id: 'account', label: 'Account', icon: IconUser, iconFill: IconUserFill, to: '#account' },
] as const

interface Props {
  /** 'fixed' floats over the viewport (real mobile); 'embedded' floats inside the demo frame */
  variant?: 'fixed' | 'embedded'
  onAccount: () => void
  onCreate?: () => void
  className?: string
}

export default function BottomNav({ variant = 'fixed', onAccount, onCreate, className = '' }: Props) {
  const { pathname } = useLocation()
  const navigate = useNavigate()

  const activeId = (() => {
    if (pathname === '/home' || pathname === '/') return 'home'
    if (pathname === '/studio') return 'styles'
    if (pathname === '/dashboard') return 'gallery'
    return ''
  })()

  const pos =
    variant === 'fixed'
      ? 'fixed bottom-[calc(env(safe-area-inset-bottom)+10px)] inset-x-4 z-50'
      : 'absolute bottom-3 inset-x-3 z-50'

  return (
    <nav className={`${pos} hm-dock ${className}`} aria-label="App navigation">
      <div className="grid grid-cols-5 py-2">
        {TABS.map((t) => {
          const active = t.id === activeId
          const Icon = active && t.iconFill ? t.iconFill : t.icon
          return (
            <button
              key={t.id}
              onClick={() => {
                haptic('light')
                if (t.id === 'account') onAccount()
                else if (t.id === 'create') onCreate?.()
                else navigate(t.to)
              }}
              aria-current={active ? 'page' : undefined}
              className="hm-press flex flex-col items-center gap-1 py-1"
            >
              {t.id === 'create' ? (
                <motion.span
                  whileTap={{ scale: 0.85 }}
                  transition={springPress}
                  className="-mt-7 w-[52px] h-[52px] rounded-full bg-ink text-[#fbf6eb] flex items-center justify-center border border-white/10 shadow-[var(--shadow-e3)]"
                >
                  {/* the LM-1 — a dimensional DSLR, not the generic outline camera */}
                  <svg viewBox="0 0 32 32" width={32} height={32} aria-hidden>
                    <defs>
                      <linearGradient id="lmBody" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0" stopColor="#8d9ca9" />
                        <stop offset="0.28" stopColor="#5c6d7c" />
                        <stop offset="1" stopColor="#232f3a" />
                      </linearGradient>
                      <linearGradient id="lmPrism" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0" stopColor="#6e7f8d" />
                        <stop offset="1" stopColor="#2b3843" />
                      </linearGradient>
                      <linearGradient id="lmGrip" x1="0" y1="0" x2="1" y2="0">
                        <stop offset="0" stopColor="#1c2833" />
                        <stop offset="1" stopColor="#39485a" />
                      </linearGradient>
                      <radialGradient id="lmGlass" cx="0.38" cy="0.34" r="0.85">
                        <stop offset="0" stopColor="#3f7fae" />
                        <stop offset="0.5" stopColor="#173a55" />
                        <stop offset="1" stopColor="#081420" />
                      </radialGradient>
                    </defs>
                    <path d="M11.4 8.2 12.8 5h6.4l1.4 3.2Z" fill="url(#lmPrism)" />
                    <rect x="5.6" y="5.8" width="4" height="2.8" rx="1.3" fill="#0e7487" />
                    <rect x="23" y="6" width="3.6" height="2.4" rx="1" fill="#4a5a68" />
                    <rect x="2.6" y="8.2" width="26.8" height="18" rx="3.6" fill="url(#lmBody)" />
                    <rect x="25.2" y="9.6" width="4.2" height="15.2" rx="2" fill="url(#lmGrip)" />
                    <circle cx="14.6" cy="17.2" r="7.4" fill="#0c141c" stroke="#9aa9b5" strokeWidth="0.9" />
                    <circle cx="14.6" cy="17.2" r="5.6" fill="none" stroke="#45535f" strokeWidth="1" />
                    <circle cx="14.6" cy="17.2" r="4.3" fill="url(#lmGlass)" />
                    <ellipse cx="12.9" cy="15.4" rx="1.7" ry="1.1" fill="rgba(255,255,255,0.55)" />
                  </svg>
                </motion.span>
              ) : (
                // active tab sits in a soft gray pill, like an iOS tab bar
                <span
                  className={`flex items-center justify-center rounded-full px-3.5 h-7 transition-colors ${
                    active ? 'bg-[rgb(23_36_45/0.06)]' : ''
                  }`}
                >
                  <Icon size={21} className={active ? 'text-violet' : 'text-fog'} />
                </span>
              )}
              <span
                className={`text-[10.5px] leading-none ${
                  t.id === 'create'
                    ? 'text-ink font-semibold'
                    : active
                      ? 'text-violet font-semibold'
                      : 'text-fog font-medium'
                }`}
              >
                {t.label}
              </span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
