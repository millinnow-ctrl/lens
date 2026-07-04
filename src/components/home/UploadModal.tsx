import { useRef } from 'react'
import { createPortal } from 'react-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'
import { IconCamera, IconClose, IconFilm, IconUpload } from '../icons'
import { fileToDataURL } from '../../lib/engine'
import { captureWithNativeCamera, haptic, isNative } from '../../lib/native'
import { MAX_ROLL, useApp } from '../../lib/store'
import sampleGolden from '../../assets/sample-golden.jpg'
import sampleStreet from '../../assets/sample-street.jpg'
import sampleNight from '../../assets/sample-night.jpg'
import sampleConcert from '../../assets/sample-concert.jpg'
import sampleBrunch from '../../assets/sample-brunch.jpg'
import sampleFriends from '../../assets/sample-friends.jpg'

const SAMPLES = [
  { src: sampleFriends, label: 'Friends' },
  { src: sampleConcert, label: 'Concert' },
  { src: sampleBrunch, label: 'Brunch' },
  { src: sampleGolden, label: 'Golden hour' },
  { src: sampleStreet, label: 'Street' },
  { src: sampleNight, label: 'Night out' },
]

interface Props {
  open: boolean
  onClose: () => void
  /** render inside the desktop demo frame instead of the document body */
  container?: HTMLElement | null
}

export default function UploadModal({ open, onClose, container }: Props) {
  const { setImage, setRoll } = useApp()
  const navigate = useNavigate()
  const inputRef = useRef<HTMLInputElement>(null)
  const cameraRef = useRef<HTMLInputElement>(null)

  const finish = () => {
    onClose()
    navigate('/studio')
  }

  const acceptFiles = async (list: FileList | null) => {
    const images = Array.from(list ?? []).filter((f) => f.type.startsWith('image/'))
    if (images.length === 0) return
    haptic('light')
    const urls = await Promise.all(images.slice(0, MAX_ROLL).map((f) => fileToDataURL(f)))
    if (urls.length === 1) setImage(urls[0], images[0].name)
    else setRoll(urls.map((url, i) => ({ url, name: images[i].name })))
    finish()
  }

  const openCamera = async () => {
    haptic('medium')
    const dataUrl = await captureWithNativeCamera()
    if (dataUrl) {
      setImage(dataUrl, 'camera')
      finish()
      return
    }
    if (!isNative()) cameraRef.current?.click()
  }

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
            className="relative w-full max-w-md bg-white rounded-t-[28px] px-5 pt-3 pb-[calc(env(safe-area-inset-bottom)+20px)] shadow-2xl"
          >
            <div className="w-10 h-[5px] rounded-full bg-ink/10 mx-auto mb-4" aria-hidden />
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-[17px] font-bold tracking-[-0.01em]">Start from a photo</h3>
              <button
                onClick={onClose}
                aria-label="Close"
                className="w-8 h-8 rounded-full bg-[#f4f1f4] flex items-center justify-center text-ink-soft"
              >
                <IconClose size={13} />
              </button>
            </div>

            <div className="space-y-2.5">
              <button
                onClick={openCamera}
                className="hm-press aura-soft w-full flex items-center gap-3.5 rounded-2xl bg-ink text-white px-4 py-3.5"
              >
                <span className="w-9 h-9 rounded-full bg-white/12 flex items-center justify-center">
                  <IconCamera size={17} />
                </span>
                <span className="text-left">
                  <span className="block text-[14px] font-semibold">Take a photo</span>
                  <span className="block text-[11px] text-white/75">Shoot and restyle it instantly</span>
                </span>
              </button>
              <button
                onClick={() => inputRef.current?.click()}
                className="hm-press w-full flex items-center gap-3.5 rounded-2xl bg-[#f4f1f4] px-4 py-3.5"
              >
                <span className="w-9 h-9 rounded-full bg-white flex items-center justify-center text-ink">
                  <IconUpload size={17} />
                </span>
                <span className="text-left">
                  <span className="block text-[14px] font-semibold">Choose from library</span>
                  <span className="block text-[11.5px] text-fog">Up to {MAX_ROLL} photos at once</span>
                </span>
              </button>
            </div>

            <p className="flex items-center gap-2 mt-5 mb-2.5 text-[12px] font-semibold text-fog">
              <IconFilm size={12} />
              Or try a sample
            </p>
            <div className="grid grid-cols-3 gap-2.5">
              {SAMPLES.map((s) => (
                <button
                  key={s.label}
                  onClick={() => {
                    haptic('light')
                    setImage(s.src, s.label)
                    finish()
                  }}
                  className="hm-press rounded-xl overflow-hidden relative aspect-square"
                >
                  <img src={s.src} alt={s.label} className="w-full h-full object-cover" draggable={false} />
                  <span className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-vf/85 via-vf/40 to-transparent text-white text-[10px] font-semibold pt-3 pb-1.5 text-center">
                    {s.label}
                  </span>
                </button>
              ))}
            </div>

            <input
              ref={inputRef}
              type="file"
              accept="image/*"
              multiple
              className="hidden"
              onChange={(e) => {
                acceptFiles(e.target.files)
                e.target.value = ''
              }}
            />
            <input
              ref={cameraRef}
              type="file"
              accept="image/*"
              capture="environment"
              className="hidden"
              onChange={(e) => {
                acceptFiles(e.target.files)
                e.target.value = ''
              }}
            />
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )

  return container ? sheet : createPortal(sheet, document.body)
}
