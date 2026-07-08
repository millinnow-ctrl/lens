import { useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { IconUpload } from '../icons'
import heroLoopMp4 from '../../assets/hero-summer.mp4'
import heroLoopWebm from '../../assets/hero-summer.webm'
import heroPoster from '../../assets/hero-summer-poster.jpg'

/* one ambient loop — a summer picnic shot through a Y2K digicam, girls
   photographing each other — holds the header. The headline's warm word
   morphs on its own beat over it. */
const WORDS = ['mood.', 'look.', 'texture.', 'glow.']
const WORD_HOLD = 3400

interface Props {
  onUpload: () => void
}

export default function LiveHero({ onUpload }: Props) {
  const reduce = useRef(
    typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
  )
  const [w, setW] = useState(0)

  useEffect(() => {
    if (reduce.current) return
    const t = setInterval(() => setW((v) => (v + 1) % WORDS.length), WORD_HOLD)
    return () => clearInterval(t)
  }, [])

  return (
    <div className="relative rounded-[28px] overflow-hidden bg-vf border border-white/[0.06] shadow-[var(--shadow-e3)]">
      {/* viewfinder chrome strip — the readout names the lens on frame */}
      <div className="h-9 px-4 flex items-center justify-between gap-3 border-b border-white/[0.08]">
        <span className="flex items-center gap-2 font-mono font-semibold text-[10px] tracking-[0.14em] uppercase text-vf-chrome min-w-0">
          <span className="lm-live w-1.5 h-1.5 rounded-full bg-signal shrink-0" aria-hidden />
          <span className="truncate">Summer Roll</span>
        </span>
        <span className="font-mono text-[10px] tracking-[0.08em] uppercase text-vf-chrome tabular-nums shrink-0">
          Y2K DIGICAM · SUNNY
        </span>
      </div>

      <div className="relative aspect-[4/3.6] vf-corners overflow-hidden">
        {reduce.current ? (
          <img
            src={heroPoster}
            alt=""
            className="absolute inset-0 w-full h-full object-cover"
            draggable={false}
          />
        ) : (
          <video
            poster={heroPoster}
            autoPlay
            muted
            loop
            playsInline
            aria-hidden
            className="absolute inset-0 w-full h-full object-cover"
          >
            {/* webm first (Chrome/Android/Firefox), mp4 for Safari/iOS */}
            <source src={heroLoopWebm} type="video/webm" />
            <source src={heroLoopMp4} type="video/mp4" />
          </video>
        )}
        {!reduce.current && (
          <div aria-hidden className="absolute inset-0 pointer-events-none">
            <div className="lm-print-bloom absolute inset-0" />
            <div className="lm-print-sheen absolute inset-0" />
          </div>
        )}

        {/* "shot on" tag — these are real frames from the engine's cameras */}
        <span className="absolute top-3 left-3 z-10 flex items-center gap-1.5 rounded-full bg-black/45 backdrop-blur-md px-2.5 h-6 font-mono text-[9px] font-semibold uppercase tracking-[0.14em] text-white/90">
          <span className="w-1 h-1 rounded-full bg-signal" aria-hidden />
          Shot on LensMood
        </span>

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
                  key={WORDS[w]}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -12 }}
                  transition={{ duration: 0.34, ease: [0.33, 0.02, 0.2, 1] }}
                  className="serif-accent col-start-1 row-start-1"
                >
                  {WORDS[w]}
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
      </div>
    </div>
  )
}
