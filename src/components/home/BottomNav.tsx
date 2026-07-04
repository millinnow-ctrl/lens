import { useLocation, useNavigate } from 'react-router-dom'
import { IconHome, IconImage, IconPlusCircle, IconStyles, IconUser } from '../icons'
import { haptic } from '../../lib/native'

const TABS = [
  { id: 'home', label: 'Home', icon: IconHome, to: '/home' },
  { id: 'styles', label: 'Styles', icon: IconStyles, to: '/studio' },
  { id: 'create', label: 'Create', icon: IconPlusCircle, to: '#create' },
  { id: 'gallery', label: 'Gallery', icon: IconImage, to: '/dashboard' },
  { id: 'account', label: 'Account', icon: IconUser, to: '#account' },
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
              className="flex flex-col items-center gap-1 py-1"
            >
              <t.icon
                size={t.id === 'create' ? 23 : 21}
                strokeWidth={active ? 1.9 : 1.6}
                className={active ? 'text-violet' : 'text-fog'}
              />
              <span
                className={`text-[10.5px] leading-none ${active ? 'text-violet font-semibold' : 'text-fog font-medium'}`}
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
