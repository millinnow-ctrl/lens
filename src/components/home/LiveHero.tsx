import { useCallback, useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { IconUpload } from '../icons'
import heroMatcha from '../../assets/hero-ambient.mp4'
import heroAnamorphic from '../../assets/hero-anamorphic.mp4'
import heroMacro from '../../assets/hero-macro.mp4'
import heroCar from '../../assets/hero-car.mp4'
import heroPoster from '../../assets/hero-poster.jpg'

/* the reel — four ambient clips, each shot on a different lens, rotating in a
   fixed order like a lookbook. The viewfinder readout names the lens; the
   headline's warm word morphs with the frame. */
type Clip = { src: string; lens: string; exif: string; word: string; hold: number }
const CLIPS: Clip[] = [
  { src: heroMatcha, lens: 'Matcha Hour', exif: 'ƒ1.4 · 50MM · WARM', word: 'mood.', hold: 3400 },
  { src: heroAnamorphic, lens: 'Anamorphic', exif: 'T2.2 · 40MM · FLARE', word: 'look.', hold: 3200 },
  { src: heroMacro, lens: 'Macro', exif: 'ƒ2.8 · 100MM · MACRO', word: 'texture.', hold: 3200 },
  { src: heroCar, lens: 'Y2K Night', exif: 'ƒ2.0 · 35MM · NIGHT', word: 'glow.', hold: 3200 },
]

interface Props {
  onUpload: () => void
}

export default function LiveHero({ onUpload }: Props) {
  const n = CLIPS.length
  const reduce = useRef(
    typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
  )
  const [i, setI] = useState(0)
  const [paused, setPaused] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const advance = useCallback(() => setI((v) => (v + 1) % n), [n])

  /* each looping clip holds for its own beat, then crosses to the next */
  useEffect(() => {
    if (reduce.current || paused) return
    timer.current = setTimeout(advance, CLIPS[i].hold)
    return () => {
      if (timer.current) clearTimeout(timer.current)
    }
  }, [i, paused, advance])

  const clip = CLIPS[i]

  return (
    <div className="relative rounded-[28px] overflow-hidden bg-vf border border-white/[0.06] shadow-[var(--shadow-e3)]">
      {/* viewfinder chrome strip — the readout names the lens on frame */}
      <div className="h-9 px-4 flex items-center justify-between gap-3 border-b border-white/[0.08]">
        <span className="flex items-center gap-2 font-mono font-semibold text-[10px] tracking-[0.14em] uppercase text-vf-chrome min-w-0">
          <span className="lm-live w-1.5 h-1.5 rounded-full bg-signal shrink-0" aria-hidden />
          <span className="truncate">
            <AnimatePresence mode="wait">
              <motion.span
                key={i}
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                transition={{ duration: 0.28 }}
                className="inline-block"
              >
                {clip.lens}
              </motion.span>
            </AnimatePresence>
          </span>
        </span>
        <span className="font-mono text-[10px] tracking-[0.08em] uppercase text-vf-chrome tabular-nums shrink-0">
          {clip.exif}
        </span>
      </div>

      <div
        className="relative aspect-[4/3.6] vf-corners overflow-hidden"
        onPointerDown={() => setPaused(true)}
        onPointerUp={() => setPaused(false)}
        onPointerLeave={() => setPaused(false)}
      >
        {/* the reel — each clip crosses in over the last */}
        {reduce.current ? (
          <img src={heroPoster} alt="" className="absolute inset-0 w-full h-full object-cover" draggable={false} />
        ) : (
          <AnimatePresence>
            <motion.video
              key={i}
              src={clip.src}
              poster={heroPoster}
              autoPlay
              muted
              loop
              playsInline
              aria-hidden
              initial={{ opacity: 0, scale: 1.05 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0 }}
              transition={{ opacity: { duration: 0.7 }, scale: { duration: clip.hold / 1000, ease: 'linear' } }}
              className="absolute inset-0 w-full h-full object-cover"
            />
          </AnimatePresence>
        )}
        {!reduce.current && (
          <div key={`fx-${i}`} aria-hidden className="absolute inset-0 pointer-events-none">
            <div className="lm-print-bloom absolute inset-0" />
            <div className="lm-print-sheen absolute inset-0" />
          </div>
        )}

        {/* "shot on" tag — these are real frames from the engine's cameras */}
        <span className="absolute top-3 left-3 z-10 flex items-center gap-1.5 rounded-full bg-black/45 backdrop-blur-md px-2.5 h-6 font-mono text-[9px] font-semibold uppercase tracking-[0.14em] text-white/90">
          <span className="w-1 h-1 rounded-full bg-signal" aria-hidden />
          Shot on LensMood
        </span>

        {/* reel pips — which clip is playing; doubles as an anticipation cue */}
        {!reduce.current && (
          <div className="absolute top-3 right-3 z-10 flex items-center gap-1">
            {CLIPS.map((c, idx) => (
              <span
                key={c.lens}
                className={`h-1 rounded-full transition-all duration-300 ${
                  idx === i ? 'w-4 bg-white/90' : 'w-1 bg-white/35'
                }`}
                aria-hidden
              />
            ))}
          </div>
        )}

        {/* scrim carries the words */}
        <div className="absolute inset-x-0 bottom-0 h-[74%] bg-gradient-to-t from-black/85 via-black/45 to-transparent" />
        <div className="absolute inset-x-0 bottom-0 p-4">
          <h1
            className="type-display text-[30px] leading-[1.08] text-white flex flex-wrap items-baseline"
            style={{ textShadow: '0 1px 14px rgb(0 0 0 / 0.5)' }}
          >
            <span>Every photo has a&nbsp;</span>
            <span className="relative inline-grid">
              <AnimatePresence mode="wait">
                <motion.span
                  key={clip.word}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -12 }}
                  transition={{ duration: 0.34, ease: [0.33, 0.02, 0.2, 1] }}
                  className="serif-accent col-start-1 row-start-1"
                >
                  {clip.word}
                </motion.span>
              </AnimatePresence>
            </span>
          </h1>
          <p
            className="text-[13px] text-white/85 mt-1.5 leading-snug"
            style={{ textShadow: '0 1px 8px rgb(0 0 0 / 0.55)' }}
          >
            The $7,000 camera look, from your camera roll.
          </p>
          <div className="mt-4">
            <button
              onClick={onUpload}
              className="btn gap-2 border-0 btn-brass font-semibold px-5 text-[14px] whitespace-nowrap"
            >
              <IconUpload size={15} />
              Start with a photo
            </button>
          </div>
        </div>

        {/* clip timer — a thin bar filling toward the next lens */}
        {!reduce.current && (
          <div className="absolute inset-x-0 bottom-0 h-[3px] bg-white/10 z-10">
            <motion.div
              key={`bar-${i}-${paused}`}
              className="h-full bg-white/70"
              initial={{ width: '0%' }}
              animate={{ width: paused ? '0%' : '100%' }}
              transition={{ duration: paused ? 0 : clip.hold / 1000, ease: 'linear' }}
            />
          </div>
        )}
      </div>
    </div>
  )
}
