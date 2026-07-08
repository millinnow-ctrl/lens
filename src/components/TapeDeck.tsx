/**
 * TapeDeck — the camcorder's own loading bay. Where the photo studio says
 * "load your photos", the deck is a live viewfinder with no tape in it:
 * analog static, a blinking ● REC, and the burned-in VCR clock. Drop a clip
 * (or tap) and it develops through the 90s Camcorder — counting timecode,
 * tape grain, scanlines.
 */

import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import Modal from './Modal'
import { IconFilm } from './icons'
import { MAX_VIDEO_SECONDS, probeVideo } from '../lib/video'
import { haptic } from '../lib/native'
import { useApp } from '../lib/store'

const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']

function vcrClock(d: Date) {
  const hh = d.getHours() % 12 || 12
  const ampm = d.getHours() >= 12 ? 'PM' : 'AM'
  return {
    time: `${ampm} ${hh}:${String(d.getMinutes()).padStart(2, '0')}`,
    date: `${MONTHS[d.getMonth()]}.${String(d.getDate()).padStart(2, '0')}.${d.getFullYear()}`,
  }
}

export default function TapeDeck() {
  const { setVideo, hasVideoPlan } = useApp()
  const [dragOver, setDragOver] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [upsell, setUpsell] = useState(false)
  const [clock, setClock] = useState(() => vcrClock(new Date()))
  const inputRef = useRef<HTMLInputElement>(null)

  /* the OSD clock ticks like the real thing — once a minute */
  useEffect(() => {
    const t = setInterval(() => setClock(vcrClock(new Date())), 15000)
    return () => clearInterval(t)
  }, [])

  const acceptFiles = useCallback(
    async (list: FileList | File[] | null | undefined) => {
      const files = Array.from(list ?? [])
      const video = files.find((f) => f.type.startsWith('video/'))
      setError(null)
      if (!video) {
        if (files.length) setError('The deck only takes tape — MP4 or MOV clips work best.')
        return
      }
      if (!hasVideoPlan) {
        setUpsell(true)
        return
      }
      if (video.size > 120 * 1024 * 1024) {
        setError('That tape is over 120 MB — trim it down and try again.')
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
        setError('That tape didn’t open. MP4 or MOV work best.')
        return
      }
      haptic('light')
      setVideo(url, video.name)
    },
    [hasVideoPlan, setVideo],
  )

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
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            inputRef.current?.click()
          }
        }}
        aria-label="Load a tape — drop a video clip or click to choose one"
        className={`relative cursor-pointer overflow-hidden rounded-[20px] border transition-colors duration-150 aspect-video select-none ${
          dragOver ? 'border-violet' : 'border-white/15 hover:border-white/35'
        }`}
      >
        {/* the dead-channel signal */}
        <div className="lm-vhs-static absolute inset-0" aria-hidden />
        <div className="lm-vhs-scan absolute inset-0" aria-hidden />
        <div className="vf-corners absolute inset-3 pointer-events-none" aria-hidden />

        {/* OSD chrome — REC blinks, the clock is burned in */}
        <span className="lm-vhs-blink absolute top-4 left-5 font-mono font-bold text-[15px] tracking-[0.1em] text-[#ff5040]" style={{ textShadow: '0 0 8px rgba(255,80,64,0.9)' }}>
          ● REC
        </span>
        <span className="absolute top-4 right-5 text-right font-mono font-bold text-[14px] leading-[1.35] tracking-[0.12em] text-[#f4f2e8]" style={{ textShadow: '0 0 6px rgba(255,240,200,0.75)' }}>
          {clock.time}
          <br />
          {clock.date}
        </span>

        {/* the invitation */}
        <div className="absolute inset-0 flex flex-col items-center justify-center text-center px-6">
          <p className="font-mono font-bold text-[26px] sm:text-[32px] tracking-[0.22em] text-[#f4f2e8]" style={{ textShadow: '0 0 10px rgba(255,240,200,0.65)' }}>
            INSERT TAPE
          </p>
          <p className="mt-2 font-mono text-[12px] sm:text-[13px] tracking-[0.08em] text-white/70 max-w-xs">
            Drop a clip or tap — up to {MAX_VIDEO_SECONDS}s. It develops like 1994: counting
            timecode, tape grain, scanlines.
          </p>
          <span className="btn btn-primary mt-6 pointer-events-none">
            <IconFilm size={16} />
            Load a tape
          </span>
        </div>

        <input
          ref={inputRef}
          type="file"
          accept="video/mp4,video/quicktime,video/webm"
          className="hidden"
          onChange={(e) => {
            acceptFiles(e.target.files)
            e.target.value = ''
          }}
        />
      </div>

      {error && <p className="mt-4 text-[13px] text-signal font-medium">{error}</p>}

      <Modal open={upsell} onClose={() => setUpsell(false)}>
        <div className="p-8">
          <IconFilm size={32} className="text-ink mb-4" />
          <h3 className="text-2xl font-semibold tracking-[-0.01em] mb-2">The camcorder is a Pro thing</h3>
          <p className="text-sm text-ink-soft leading-relaxed mb-6">
            Every clip develops like a 1994 tape — counting REC timecode, tape grain that dances,
            scanlines. Included with Pro and Studio.
          </p>
          <div className="flex gap-2.5">
            <Link to="/pricing" className="btn btn-primary">
              See Pro plans
            </Link>
            <button onClick={() => setUpsell(false)} className="btn btn-outline">
              Not now
            </button>
          </div>
        </div>
      </Modal>
    </motion.div>
  )
}
