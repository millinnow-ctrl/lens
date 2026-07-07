import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import Modal from './Modal'
import { IconCamera, IconFilm, IconUpload } from './icons'
import { fileToDataURL } from '../lib/engine'
import { MAX_VIDEO_SECONDS, probeVideo } from '../lib/video'
import { captureWithNativeCamera, haptic, isNative } from '../lib/native'
import { MAX_ROLL, useApp } from '../lib/store'
import sampleGolden from '../assets/sample-golden.jpg'
import sampleStreet from '../assets/sample-street.jpg'
import sampleNight from '../assets/sample-night.jpg'

const SAMPLES = [
  { src: sampleGolden, label: 'Golden hour' },
  { src: sampleStreet, label: 'Street' },
  { src: sampleNight, label: 'Night out' },
]

/** longest edge kept at ingest — plenty for a 1600px export, and it keeps a
 *  six-photo roll from pinning ~200MB of base64 in a WKWebView */
const INGEST_MAX = 2560

type RollItemLike = { url: string; name: string }

/** read a photo in, downscaling giant camera files to a sane working size.
 *  Returns null for images the pipeline must refuse (decompression bombs,
 *  dimensionless SVGs); undecodable-but-renderable files fall back to raw. */
async function ingestPhoto(file: File): Promise<string | null> {
  const raw = await fileToDataURL(file)
  const img = new Image()
  img.src = raw
  try {
    await img.decode()
  } catch {
    return raw // the browser may still render it in an <img> later
  }
  // dimensionless sources (some SVGs) wedge the render pipeline downstream
  if (!img.naturalWidth || !img.naturalHeight) return null
  // decompression-bomb guard: a cap-compliant PNG can still decode to
  // gigabytes of RGBA — refuse anything past a sane pixel budget (~50MP)
  if (img.naturalWidth * img.naturalHeight > 50_000_000) return null
  try {
    const scale = INGEST_MAX / Math.max(img.naturalWidth, img.naturalHeight)
    if (!Number.isFinite(scale) || scale >= 1) return raw
    const c = document.createElement('canvas')
    c.width = Math.round(img.naturalWidth * scale)
    c.height = Math.round(img.naturalHeight * scale)
    const ctx = c.getContext('2d')
    if (!ctx) return raw
    ctx.imageSmoothingQuality = 'high'
    ctx.drawImage(img, 0, 0, c.width, c.height)
    return c.toDataURL('image/jpeg', 0.92)
  } catch {
    return raw
  }
}

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
      const ingested = await Promise.all(images.slice(0, MAX_ROLL).map((f) => ingestPhoto(f)))
      const ok = ingested
        .map((url, i) => (url ? { url, name: images[i].name } : null))
        .filter((x): x is RollItemLike => !!x)
      if (ok.length < ingested.length) {
        setError('One of those images couldn’t be processed — it may be too large or empty.')
        if (ok.length === 0) return
      }
      if (ok.length === 1) {
        setImage(ok[0].url, ok[0].name)
      } else {
        setRoll(ok)
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
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.15, ease: 'easeOut' }}
      className="max-w-2xl"
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
        className={`hm-drop relative cursor-pointer transition-colors duration-150 px-6 py-14 sm:py-18 text-center ${
          dragOver ? 'border-violet bg-white/80' : 'hover:border-ink/30'
        }`}
      >
        <IconCamera size={40} className="relative mx-auto text-violet mb-6" />

        <h2 className="relative text-2xl sm:text-3xl font-bold tracking-[-0.02em] mb-2">
          Load your photos
        </h2>
        <p className="relative text-ink-soft text-sm sm:text-[15px] leading-relaxed mb-6 max-w-sm mx-auto">
          Up to {MAX_ROLL} at once, or a short video (Pro). Nothing leaves your
          device — the darkroom is your browser.
        </p>
        <div className="relative flex items-center justify-center gap-2.5 pointer-events-none">
          <span className="btn btn-primary">
            <IconUpload size={16} />
            Choose photos
          </span>
          <span
            className="btn btn-outline pointer-events-auto"
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
            <IconCamera size={16} />
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

      {error && <p className="mt-4 text-[13px] text-signal font-medium">{error}</p>}

      <div className="mt-8">
        <p className="text-[13.5px] font-semibold text-ink-soft mb-4">No photo handy? Try a sample</p>
        <div className="flex gap-3 sm:gap-4">
          {SAMPLES.map((sample) => (
            <button
              key={sample.label}
              onClick={() => setImage(sample.src, sample.label)}
              className="group text-left"
            >
              <span className="block w-24 sm:w-28 aspect-4/5 rounded-[14px] overflow-hidden ring-1 ring-black/[0.06] group-hover:ring-violet transition-shadow">
                <img src={sample.src} alt={sample.label} className="w-full h-full object-cover" draggable={false} />
              </span>
              <span className="block mt-1.5 font-mono font-semibold text-[10px] tracking-[0.1em] uppercase text-fog group-hover:text-ink transition-colors">
                {sample.label}
              </span>
            </button>
          ))}
        </div>
      </div>

      {/* video is a Pro feature */}
      <Modal open={videoUpsell} onClose={() => setVideoUpsell(false)}>
        <div className="p-8">
          <IconFilm size={32} className="text-ink mb-4" />
          <h3 className="text-2xl font-semibold tracking-[-0.01em] mb-2">Video moods are a Pro thing</h3>
          <p className="text-sm text-ink-soft leading-relaxed mb-6">
            Restyle short clips frame-by-frame — camcorder timestamps, film grain that dances, the
            works. Included with Pro and Studio.
          </p>
          <Link
            to="/pricing"
            onClick={() => setVideoUpsell(false)}
            className="btn btn-primary w-full mb-2"
          >
            See Pro — $15/mo
          </Link>
          <button onClick={() => setVideoUpsell(false)} className="btn btn-quiet w-full">
            Maybe later
          </button>
        </div>
      </Modal>
    </motion.div>
  )
}
