import { useLocation, useNavigate } from 'react-router-dom'
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
  { id: 'create', label: 'Create', icon: IconPlusCircle, iconFill: undefined, to: '#create' },
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
                <span className="-mt-7 w-[52px] h-[52px] rounded-full bg-ink text-[#fbf6eb] flex items-center justify-center border border-white/10 shadow-[var(--shadow-e3)]">
                  <svg viewBox="0 0 24 24" width={24} height={24} fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" aria-hidden>
                    <path d="M12 5v14M5 12h14" />
                  </svg>
                </span>
              ) : (
                <Icon size={21} className={active ? 'text-violet' : 'text-fog'} />
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
