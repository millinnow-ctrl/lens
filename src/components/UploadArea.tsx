import { useCallback, useEffect, useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { fileToDataURL } from '../lib/engine'
import { useApp } from '../lib/store'
import sampleGolden from '../assets/sample-golden.svg'
import sampleStreet from '../assets/sample-street.svg'
import sampleNight from '../assets/sample-night.svg'

const SAMPLES = [
  { src: sampleGolden, label: 'Golden hour' },
  { src: sampleStreet, label: 'Street' },
  { src: sampleNight, label: 'Night out' },
]

export default function UploadArea() {
  const { setPhoto } = useApp()
  const [dragOver, setDragOver] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const acceptFile = useCallback(
    async (file: File | undefined | null) => {
      if (!file) return
      if (!file.type.startsWith('image/')) {
        setError('That doesn’t look like a photo. JPG, PNG, WebP or HEIC work best.')
        return
      }
      if (file.size > 25 * 1024 * 1024) {
        setError('That file is over 25 MB. Try a smaller export of the same shot.')
        return
      }
      setError(null)
      const dataUrl = await fileToDataURL(file)
      setPhoto(dataUrl, file.name)
    },
    [setPhoto],
  )

  // paste support — cmd+V a screenshot straight in
  useEffect(() => {
    const onPaste = (e: ClipboardEvent) => {
      const item = Array.from(e.clipboardData?.items ?? []).find((i) => i.type.startsWith('image/'))
      if (item) acceptFile(item.getAsFile())
    }
    window.addEventListener('paste', onPaste)
    return () => window.removeEventListener('paste', onPaste)
  }, [acceptFile])

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
          acceptFile(e.dataTransfer.files?.[0])
        }}
        onClick={() => inputRef.current?.click()}
        className={`relative cursor-pointer rounded-[2rem] border-2 border-dashed transition-all duration-300 px-6 py-16 sm:py-20 text-center overflow-hidden ${
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

        <h2 className="font-display text-2xl sm:text-3xl font-semibold mb-2">
          Drop a photo in
        </h2>
        <p className="text-fog text-sm sm:text-base mb-6 max-w-sm mx-auto">
          or click to browse. You can also paste a screenshot. Nothing leaves your device — the
          darkroom is your browser.
        </p>
        <span className="pill-base pill-violet px-6 py-3 text-sm pointer-events-none">
          Choose a photo
        </span>

        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => acceptFile(e.target.files?.[0])}
        />
      </div>

      {error && (
        <p className="mt-4 text-center text-sm text-red-500 font-medium">{error}</p>
      )}

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
              onClick={() => setPhoto(sample.src, sample.label)}
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
    </motion.div>
  )
}
