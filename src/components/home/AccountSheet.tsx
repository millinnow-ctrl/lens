import { createPortal } from 'react-dom'
import { AnimatePresence, motion, type PanInfo } from 'framer-motion'
import { Link } from 'react-router-dom'
import { ApertureMark } from '../Logo'
import { IconChevronRight, IconClose } from '../icons'
import { FREE_CREDITS, useApp } from '../../lib/store'
import { springSheet } from '../../lib/motion'
import { haptic } from '../../lib/native'
import { useSheetOpen } from '../../lib/useSheetOpen'

/** flung down hard, or dragged past ~a third of the way → dismiss */
const shouldDismiss = (info: PanInfo) => info.offset.y > 96 || info.velocity.y > 620

interface Props {
  open: boolean
  onClose: () => void
  container?: HTMLElement | null
}

export default function AccountSheet({ open, onClose, container }: Props) {
  const { user, plan, isPaid, creditsLeft, setAuthOpen, signOut } = useApp()
  useSheetOpen(open && !container)

  const sheet = (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
          className={`${container ? 'absolute' : 'fixed'} inset-0 z-[80] flex items-end justify-center`}
        >
          <div className="absolute inset-0 bg-vf/45" onClick={onClose} aria-hidden />
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={springSheet}
            drag="y"
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.6 }}
            dragMomentum={false}
            onDragEnd={(_e, info) => {
              if (shouldDismiss(info)) {
                haptic('light')
                onClose()
              }
            }}
            className="relative w-full max-w-md bg-surface rounded-t-[28px] px-5 pt-3 pb-[calc(env(safe-area-inset-bottom)+20px)] shadow-[0_-8px_44px_rgb(60_42_24/0.4),inset_0_1px_0_rgb(255_255_255/0.6)] cursor-grab active:cursor-grabbing"
          >
            <div className="w-11 h-[5px] rounded-full bg-ink/15 mx-auto mb-4" aria-hidden />
            {/* house grammar: mono eyebrow, serif name, magazine rule */}
            <div className="flex items-start justify-between mb-5">
              <div className="min-w-0 flex-1">
                <p className="font-mono font-semibold text-[10px] tracking-[0.18em] uppercase text-fog mb-1">
                  The counter · {isPaid ? `${plan} plan` : 'Free plan'}
                </p>
                <div className="flex items-center">
                  <h2 className="type-display text-[24px] leading-tight truncate">
                    {user ? user.name : 'Your darkroom'}
                  </h2>
                  <span className="flex-1 ml-3 mr-2 h-px bg-ink/10 self-center" aria-hidden />
                </div>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <span className="w-10 h-10 rounded-full bg-ink flex items-center justify-center">
                  {user ? (
                    <span className="text-white font-bold text-[15px]">{user.name.charAt(0).toUpperCase()}</span>
                  ) : (
                    <ApertureMark className="w-5 h-5" />
                  )}
                </span>
                <button
                  onClick={onClose}
                  aria-label="Close"
                  className="w-10 h-10 rounded-full bg-[#efece5] flex items-center justify-center text-ink-soft"
                >
                  <IconClose size={13} />
                </button>
              </div>
            </div>

            {!user && (
              <button
                onClick={() => {
                  onClose()
                  setAuthOpen(true)
                }}
                className="hm-press aura-soft w-full flex items-center justify-center h-11 rounded-full bg-ink text-white text-[14px] font-semibold mb-3"
              >
                Sign in
              </button>
            )}

            {!isPaid && (
              <div className="rounded-2xl bg-[#f4f0e8] border border-[rgb(60_42_24/0.08)] p-4 mb-3">
                <div className="flex items-baseline justify-between mb-2.5">
                  <span className="text-[14px] font-semibold">This month’s roll</span>
                  <span className="font-mono text-[10px] tracking-[0.06em] uppercase tabular-nums text-fog">
                    {creditsLeft} of {FREE_CREDITS} left
                  </span>
                </div>
                {/* the roll as frames, not a progress bar: filled = still loaded */}
                <div className="flex items-center gap-1.5 mb-3" aria-hidden>
                  {Array.from({ length: FREE_CREDITS }, (_, i) => {
                    const loaded = i < creditsLeft
                    return (
                      <span
                        key={i}
                        className="h-[18px] flex-1 max-w-[34px] rounded-[3px] transition-colors"
                        style={{
                          background: loaded ? 'var(--color-ink)' : 'transparent',
                          border: loaded ? 'none' : '1px solid rgb(60 42 24 / 0.25)',
                          boxShadow: loaded ? 'inset 0 1px 0 rgb(255 255 255 / 0.15)' : 'none',
                        }}
                      />
                    )
                  })}
                </div>
                <Link
                  to="/pricing"
                  onClick={onClose}
                  className="flex items-center justify-between text-[13px] font-semibold text-ink"
                >
                  <span>
                    Go <span className="text-clay font-bold">Creator</span> — $7/mo
                  </span>
                  <IconChevronRight size={13} className="text-fog" />
                </Link>
              </div>
            )}

            <div className="divide-y divide-hairline/70">
              {[
                { label: 'Your library', to: '/dashboard' },
                { label: 'Plans & pricing', to: '/pricing' },
                { label: 'Open the studio', to: '/studio' },
                { label: 'Privacy', to: '/privacy' },
                { label: 'Terms', to: '/terms' },
              ].map((l) => (
                <Link
                  key={l.label}
                  to={l.to}
                  onClick={onClose}
                  className="flex items-center justify-between py-3 text-[14px] font-medium"
                >
                  {l.label}
                  <IconChevronRight size={14} className="text-fog" />
                </Link>
              ))}
              {user && (
                <button
                  onClick={() => {
                    signOut()
                    onClose()
                  }}
                  className="w-full text-left py-3 text-[14px] font-medium text-signal"
                >
                  Sign out
                </button>
              )}
              {/* App Store 5.1.1(v): account creation requires in-app deletion */}
              <button
                onClick={() => {
                  if (!window.confirm('Delete your account and all local data? This cannot be undone.'))
                    return
                  try {
                    localStorage.clear()
                  } catch {
                    /* storage unavailable */
                  }
                  window.location.assign('/')
                }}
                className="w-full text-left py-3 text-[14px] font-medium text-[#c62828]"
              >
                Delete account & data
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )

  return container ? sheet : createPortal(sheet, document.body)
}
