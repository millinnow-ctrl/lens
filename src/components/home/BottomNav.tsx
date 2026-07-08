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
                  {/* the LM-1 — a 3D drawing of a Canon-class DSLR: inked outlines,
                      graphite body, the signature red ring on the lens */}
                  <svg viewBox="0 0 32 32" width={32} height={32} aria-hidden>
                    <defs>
                      <linearGradient id="lmBody" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0" stopColor="#95a4b1" />
                        <stop offset="0.3" stopColor="#5f7080" />
                        <stop offset="1" stopColor="#1e2933" />
                      </linearGradient>
                      <linearGradient id="lmPrism" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0" stopColor="#7a8b99" />
                        <stop offset="1" stopColor="#2b3843" />
                      </linearGradient>
                      <linearGradient id="lmGrip" x1="0" y1="0" x2="1" y2="0">
                        <stop offset="0" stopColor="#161f28" />
                        <stop offset="1" stopColor="#3d4c5e" />
                      </linearGradient>
                      <radialGradient id="lmGlass" cx="0.38" cy="0.34" r="0.85">
                        <stop offset="0" stopColor="#4585b3" />
                        <stop offset="0.5" stopColor="#143650" />
                        <stop offset="1" stopColor="#07121d" />
                      </radialGradient>
                    </defs>
                    {/* pentaprism hump — the EOS silhouette, rounded */}
                    <path d="M11 8.4c0-2 1.6-3.6 3.4-3.6h3.2c1.8 0 3.4 1.6 3.4 3.6Z" fill="url(#lmPrism)" stroke="#0d151c" strokeWidth="0.7" />
                    {/* shutter nub + mode dial */}
                    <rect x="5.4" y="5.9" width="4.2" height="2.9" rx="1.4" fill="#0e7487" stroke="#0d151c" strokeWidth="0.6" />
                    <rect x="23" y="6.1" width="3.8" height="2.5" rx="1.1" fill="#4a5a68" stroke="#0d151c" strokeWidth="0.6" />
                    {/* body — inked outline reads as a drawing */}
                    <rect x="2.4" y="8.2" width="27.2" height="18.2" rx="3.8" fill="url(#lmBody)" stroke="#0d151c" strokeWidth="0.9" />
                    {/* grip with finger notch */}
                    <path d="M25.4 9.6h2c1.1 0 2 .9 2 2v11.2c0 1.1-.9 2-2 2h-2c-.7 0-1.2-.7-1-1.4.8-2.4.8-9.9 0-12.4-.2-.7.3-1.4 1-1.4Z" fill="url(#lmGrip)" stroke="#0d151c" strokeWidth="0.7" />
                    {/* lens barrel */}
                    <circle cx="14.4" cy="17.3" r="7.6" fill="#0c141c" stroke="#0d151c" strokeWidth="0.9" />
                    {/* THE red ring */}
                    <circle cx="14.4" cy="17.3" r="6.5" fill="none" stroke="#d92b2b" strokeWidth="1.5" />
                    <circle cx="14.4" cy="17.3" r="5.2" fill="none" stroke="#45535f" strokeWidth="0.9" />
                    {/* glass + glint */}
                    <circle cx="14.4" cy="17.3" r="4.2" fill="url(#lmGlass)" />
                    <ellipse cx="12.8" cy="15.5" rx="1.7" ry="1.1" fill="rgba(255,255,255,0.6)" />
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
