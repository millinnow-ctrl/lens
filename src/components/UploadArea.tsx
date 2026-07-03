import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import Modal from './Modal'
import { fileToDataURL } from '../lib/engine'
import { MAX_VIDEO_SECONDS, probeVideo } from '../lib/video'
import { captureWithNativeCamera, haptic, isNative } from '../lib/native'
import { MAX_ROLL, useApp } from '../lib/store'
import sampleGolden from '../assets/sample-golden.svg'
import sampleStreet from '../assets/sample-street.svg'
import sampleNight from '../assets/sample-night.svg'

const SAMPLES = [
  { src: sampleGolden, label: 'Golden hour' },
  { src: sampleStreet, label: 'Street' },
  { src: sampleNight, label: 'Night out' },
]

export default function UploadArea() {
  const { setImage, setRoll, setVideo, hasVideoPlan } = useApp()
  const [dragOver, setDragOver] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [videoUpsell, setVideoUpsell] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const cameraRef = useRef<HTMLInputElement>(null)

  const acceptFiles = useCallback(
    async (list: FileList | File[] | null | undefined) => {
      const files = Array.from(list ?? [])
      if (files.length === 0) return
      setError(null)

      const video = files.find((f) => f.type.startsWith('video/'))
      if (video) {
        if (!hasVideoPlan) {
          setVideoUpsell(true)
          return
        }
        if (video.size > 120 * 1024 * 1024) {
          setError('That video is over 120 MB — trim it down and try again.')
          return
        }
        const url = URL.createObjectURL(video)
        try {
          const meta = await probeVideo(url)
          if (meta.duration > MAX_VIDEO_SECONDS + 1) {
            URL.revokeObjectURL(url)
            setError(`Keep clips under ${MAX_VIDEO_SECONDS}s — that one is ${Math.round(meta.duration)}s.`)
            return
          }
        } catch {
          URL.revokeObjectURL(url)
          setError('That video format didn’t open. MP4 or MOV work best.')
          return
        }
        haptic('light')
        setVideo(url, video.name)
        return
      }

      const images = files.filter((f) => f.type.startsWith('image/'))
      if (images.length === 0) {
        setError('That doesn’t look like a photo or video. JPG, PNG, WebP, MP4 or MOV work best.')
        return
      }
      const oversize = images.find((f) => f.size > 25 * 1024 * 1024)
      if (oversize) {
        setError('Photos over 25 MB are a lot — try a smaller export of the same shot.')
        return
      }
      haptic('light')
      const urls = await Promise.all(images.slice(0, MAX_ROLL).map((f) => fileToDataURL(f)))
      if (urls.length === 1) {
        setImage(urls[0], images[0].name)
      } else {
        setRoll(urls.map((url, i) => ({ url, name: images[i].name })))
      }
    },
    [hasVideoPlan, setImage, setRoll, setVideo],
  )

  // paste support — cmd+V a screenshot straight in
  useEffect(() => {
    const onPaste = (e: ClipboardEvent) => {
      const items = Array.from(e.clipboardData?.items ?? [])
        .filter((i) => i.type.startsWith('image/'))
        .map((i) => i.getAsFile())
        .filter((f): f is File => !!f)
      if (items.length) acceptFiles(items)
    }
    window.addEventListener('paste', onPaste)
    return () => window.removeEventListener('paste', onPaste)
  }, [acceptFiles])

  const openCamera = async () => {
    haptic('medium')
    const dataUrl = await captureWithNativeCamera()
    if (dataUrl) {
      setImage(dataUrl, 'camera')
      return
    }
    if (!isNative()) cameraRef.current?.click()
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className="max-w-2xl mx-auto"
    >
      <div
        onDragOver={(e) => {
          e.preventDefault()
          setDragOver(true)
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault()
          setDragOver(false)
          acceptFiles(e.dataTransfer.files)
        }}
        onClick={() => inputRef.current?.click()}
        className={`relative cursor-pointer rounded-[2rem] border-2 border-dashed transition-all duration-300 px-6 py-14 sm:py-18 text-center overflow-hidden ${
          dragOver
            ? 'border-violet bg-violet-soft scale-[1.01] shadow-[var(--shadow-glow)]'
            : 'border-cloud bg-mist/60 hover:border-violet/50 hover:bg-violet-soft/40'
        }`}
      >
        {/* soft aperture glow */}
        <div className="absolute -top-24 left-1/2 -translate-x-1/2 w-96 h-96 rounded-full bg-violet/10 blur-3xl pointer-events-none" />

        <motion.div
          animate={dragOver ? { scale: 1.08, rotate: 3 } : { scale: 1, rotate: 0 }}
          className="mx-auto w-20 h-20 rounded-3xl bg-paper shadow-lg flex items-center justify-center mb-6"
        >
          <svg viewBox="0 0 24 24" className="w-9 h-9 text-violet" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="6" width="18" height="14" rx="3" />
            <circle cx="12" cy="13" r="4" />
            <path d="M8 6l1.2-2h5.6L16 6" />
          </svg>
        </motion.div>

        <h2 className="font-display text-2xl sm:text-3xl font-semibold mb-2">Drop photos or a clip in</h2>
        <p className="text-fog text-sm sm:text-base mb-6 max-w-sm mx-auto">
          Up to {MAX_ROLL} photos at once, or a short video (Pro). You can also paste a screenshot.
          Nothing leaves your device — the darkroom is your browser.
        </p>
        <div className="flex items-center justify-center gap-2.5 pointer-events-none">
          <span className="pill-base pill-violet px-6 py-3 text-sm">Choose photos</span>
          <span
            className="pill-base pill-ghost bg-paper px-5 py-3 text-sm pointer-events-auto"
            role="button"
            tabIndex={0}
            onClick={(e) => {
              e.stopPropagation()
              openCamera()
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault()
                e.stopPropagation()
                openCamera()
              }
            }}
          >
            <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="6" width="18" height="14" rx="3" />
              <circle cx="12" cy="13" r="4" />
              <path d="M8 6l1.2-2h5.6L16 6" />
            </svg>
            Take a photo
          </span>
        </div>

        <input
          ref={inputRef}
          type="file"
          accept="image/*,video/mp4,video/quicktime,video/webm"
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
      </div>

      {error && <p className="mt-4 text-center text-sm text-red-500 font-medium">{error}</p>}

      <div className="mt-8">
        <p className="text-center text-xs font-semibold uppercase tracking-widest text-fog mb-4">
          No photo handy? Try a sample
        </p>
        <div className="flex justify-center gap-3 sm:gap-4">
          {SAMPLES.map((sample, i) => (
            <motion.button
              key={sample.label}
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.15 + i * 0.08 }}
              whileHover={{ y: -4, scale: 1.03 }}
              whileTap={{ scale: 0.97 }}
              onClick={() => setImage(sample.src, sample.label)}
              className="group relative w-24 sm:w-28 aspect-4/5 rounded-2xl overflow-hidden shadow-md"
            >
              <img src={sample.src} alt={sample.label} className="w-full h-full object-cover" />
              <span className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-ink/70 to-transparent text-paper text-[11px] font-semibold py-2 text-center">
                {sample.label}
              </span>
            </motion.button>
          ))}
        </div>
      </div>

      {/* video is a Pro feature */}
      <Modal open={videoUpsell} onClose={() => setVideoUpsell(false)}>
        <div className="p-8 text-center">
          <div className="text-4xl mb-3">🎬</div>
          <h3 className="font-display text-2xl font-semibold mb-2">Video moods are a Pro thing</h3>
          <p className="text-sm text-fog mb-6 leading-relaxed">
            Restyle short clips frame-by-frame — camcorder timestamps, film grain that dances, the
            works. Included with Pro and Studio.
          </p>
          <Link to="/pricing" onClick={() => setVideoUpsell(false)} className="pill-base pill-violet w-full px-5 py-3 text-sm mb-2.5">
            See Pro — $15/mo
          </Link>
          <button onClick={() => setVideoUpsell(false)} className="w-full text-[13px] font-medium text-fog hover:text-ink py-2 transition-colors">
            Maybe later
          </button>
        </div>
      </Modal>
    </motion.div>
  )
}
