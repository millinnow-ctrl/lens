import { useLocation, useNavigate } from 'react-router-dom'
import { IconHome, IconImage, IconSparkle, IconStack, IconUser } from '../icons'
import { haptic } from '../../lib/native'

const TABS = [
  { id: 'home', label: 'Home', icon: IconHome, to: '/home' },
  { id: 'tools', label: 'AI Tools', icon: IconSparkle, to: '/studio' },
  { id: 'batch', label: 'Batch', icon: IconStack, to: '/studio?batch=1' },
  { id: 'gallery', label: 'Gallery', icon: IconImage, to: '/dashboard' },
  { id: 'account', label: 'Account', icon: IconUser, to: '#account' },
] as const

interface Props {
  /** 'fixed' docks to the viewport (real mobile); 'embedded' docks inside the demo frame */
  variant?: 'fixed' | 'embedded'
  onAccount: () => void
  className?: string
}

export default function BottomNav({ variant = 'fixed', onAccount, className = '' }: Props) {
  const { pathname, search } = useLocation()
  const navigate = useNavigate()

  const activeId = (() => {
    if (pathname === '/home' || pathname === '/') return 'home'
    if (pathname === '/studio') return search.includes('batch') ? 'batch' : 'tools'
    if (pathname === '/dashboard') return 'gallery'
    return ''
  })()

  const pos =
    variant === 'fixed'
      ? 'fixed bottom-[calc(env(safe-area-inset-bottom)+12px)] inset-x-3 z-50'
      : 'absolute bottom-4 inset-x-4 z-50'
  const fadePos = variant === 'fixed' ? 'fixed' : 'absolute'

  return (
    <>
      {/* content fades out behind the dock instead of poking through it */}
      <div
        className={`${fadePos} bottom-0 inset-x-0 h-28 z-40 pointer-events-none bg-gradient-to-t from-[#F2F2EF] from-35% via-[#F2F2EF]/80 to-transparent`}
        aria-hidden
      />
      <nav className={`${pos} hm-dock ${className}`} aria-label="App navigation">
      <div className="grid grid-cols-5 px-1 py-1.5">
        {TABS.map((t) => {
          const active = t.id === activeId
          return (
            <button
              key={t.id}
              onClick={() => {
                haptic('light')
                if (t.id === 'account') onAccount()
                else navigate(t.to)
              }}
              aria-current={active ? 'page' : undefined}
              className="flex flex-col items-center gap-1 py-1.5 transition-colors"
            >
              <span className={`flex items-center justify-center transition-colors ${active ? 'text-ink' : 'text-ink-soft/80'}`}>
                <t.icon size={17} strokeWidth={active ? 2 : 1.5} />
              </span>
              <span className={`text-[10.5px] ${active ? 'text-ink font-bold' : 'text-ink-soft font-medium'}`}>
                {t.label}
              </span>
            </button>
          )
        })}
      </div>
    </nav>
    </>
  )
}
