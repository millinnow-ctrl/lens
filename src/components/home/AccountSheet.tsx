import { createPortal } from 'react-dom'
import { AnimatePresence, motion, type PanInfo } from 'framer-motion'
import { Link } from 'react-router-dom'
import { ApertureMark } from '../Logo'
import { IconChevronRight, IconClose } from '../icons'
import { FREE_CREDITS, useApp } from '../../lib/store'
import { springSheet } from '../../lib/motion'
import { haptic } from '../../lib/native'

/** flung down hard, or dragged past ~a third of the way → dismiss */
const shouldDismiss = (info: PanInfo) => info.offset.y > 96 || info.velocity.y > 620

interface Props {
  open: boolean
  onClose: () => void
  container?: HTMLElement | null
}

export default function AccountSheet({ open, onClose, container }: Props) {
  const { user, plan, isPaid, creditsLeft, setAuthOpen, signOut } = useApp()

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
            <div className="flex items-center justify-between mb-5">
              <div className="flex items-center gap-3">
                <span className="w-11 h-11 rounded-full bg-ink flex items-center justify-center">
                  {user ? (
                    <span className="text-white font-bold text-[16px]">{user.name.charAt(0).toUpperCase()}</span>
                  ) : (
                    <ApertureMark className="w-6 h-6" />
                  )}
                </span>
                <div>
                  <p className="text-[15px] font-bold leading-tight">{user ? user.name : 'Guest'}</p>
                  <p className="text-[12px] text-fog">
                    {isPaid ? (
                      <>
                        <span className="capitalize">{plan}</span> plan
                      </>
                    ) : (
                      'Free plan'
                    )}
                  </p>
                </div>
              </div>
              <button
                onClick={onClose}
                aria-label="Close"
                className="w-10 h-10 rounded-full bg-[#f4f1f4] flex items-center justify-center text-ink-soft"
              >
                <IconClose size={13} />
              </button>
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
              <div className="rounded-2xl bg-[#f4f1f4] p-4 mb-3">
                <div className="flex items-baseline justify-between mb-2">
                  <span className="text-[13px] font-semibold">This month’s roll</span>
                  <span className="text-[12px] tabular-nums text-ink-soft">
                    {creditsLeft} of {FREE_CREDITS} frames left
                  </span>
                </div>
                <div className="h-1.5 rounded-full bg-[rgb(60_42_24/0.1)] overflow-hidden mb-3 shadow-[inset_0_1px_1px_rgb(60_42_24/0.15)]">
                  <div
                    className="h-full rounded-full bg-clay transition-all"
                    style={{ width: `${((FREE_CREDITS - creditsLeft) / FREE_CREDITS) * 100}%` }}
                  />
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
