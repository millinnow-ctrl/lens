import { AnimatePresence, motion } from 'framer-motion'
import { useEffect, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { IconClose } from './icons'

interface ModalProps {
  open: boolean
  onClose: () => void
  children: ReactNode
  wide?: boolean
}

export default function Modal({ open, onClose, children, wide = false }: ModalProps) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [open, onClose])

  return createPortal(
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-100 flex items-end sm:items-center justify-center p-0 sm:p-6"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15, ease: 'easeOut' }}
        >
          <div className="absolute inset-0 bg-vf/55 texture-film" onClick={onClose} aria-hidden />
          <motion.div
            initial={{ y: 24, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 16, opacity: 0 }}
            transition={{ duration: 0.15, ease: 'easeOut' }}
            className={`relative w-full ${wide ? 'max-w-2xl' : 'max-w-md'} bg-surface border border-hairline rounded-t-sm sm:rounded-none shadow-[var(--shadow-modal)] max-h-[92dvh] overflow-y-auto`}
          >
            <button
              onClick={onClose}
              aria-label="Close"
              className="absolute top-4 right-4 z-10 w-8 h-8 rounded-xs border border-hairline hover:border-ink text-ink flex items-center justify-center transition-colors"
            >
              <IconClose size={14} />
            </button>
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>,
    document.body,
  )
}
