import { createPortal } from 'react-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { Link } from 'react-router-dom'
import { ApertureMark } from '../Logo'
import { IconChevronRight, IconClose } from '../icons'
import { FREE_CREDITS, useApp } from '../../lib/store'

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
            initial={{ y: 48 }}
            animate={{ y: 0 }}
            exit={{ y: 64, opacity: 0 }}
            transition={{ duration: 0.22, ease: [0.2, 0.9, 0.3, 1] }}
            className="relative w-full max-w-md bg-white rounded-t-[24px] px-5 pt-3 pb-[calc(env(safe-area-inset-bottom)+20px)] shadow-2xl"
          >
            <div className="w-9 h-1 rounded-full bg-hairline mx-auto mb-4" aria-hidden />
            <div className="flex items-center justify-between mb-5">
              <div className="flex items-center gap-3">
                <span className="w-11 h-11 rounded-full bg-ink flex items-center justify-center">
                  {user ? (
                    <span className="text-white font-bold text-[16px]">{user.name.charAt(0).toUpperCase()}</span>
                  ) : (
                    <ApertureMark className="w-6 h-6" dark />
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
                className="w-8 h-8 rounded-full bg-[#F2F2EF] flex items-center justify-center text-ink-soft"
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
                className="hm-press w-full flex items-center justify-center h-11 rounded-full bg-ink text-white text-[14px] font-semibold mb-3"
              >
                Sign in
              </button>
            )}

            {!isPaid && (
              <div className="rounded-2xl bg-[#F2F2EF] p-4 mb-3">
                <div className="flex items-baseline justify-between mb-2">
                  <span className="text-[13px] font-semibold">Free shots</span>
                  <span className="text-[12px] tabular-nums text-ink-soft">
                    {creditsLeft} of {FREE_CREDITS} left
                  </span>
                </div>
                <div className="h-1 rounded-full bg-[#E4E4DF] overflow-hidden mb-3">
                  <div
                    className="h-full rounded-full bg-ink/60 transition-all"
                    style={{ width: `${(creditsLeft / FREE_CREDITS) * 100}%` }}
                  />
                </div>
                <Link
                  to="/pricing"
                  onClick={onClose}
                  className="flex items-center justify-between text-[13px] font-semibold text-ink"
                >
                  Upgrade — from $7/mo
                  <IconChevronRight size={13} className="text-fog" />
                </Link>
              </div>
            )}

            <div className="divide-y divide-hairline/70">
              {[
                { label: 'Your library', to: '/dashboard' },
                { label: 'Plans & pricing', to: '/pricing' },
                { label: 'Open the studio', to: '/studio' },
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
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )

  return container ? sheet : createPortal(sheet, document.body)
}
