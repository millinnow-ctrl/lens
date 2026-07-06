import { useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { IconUpload } from '../icons'
import { getStyle } from '../../lib/styles'
import { STYLE_ART } from '../../lib/styleArt'

/* the reel — signature looks chosen for range: neon night, cinematic dusk,
   warm slide film, studio portrait, noir, y2k flash. Each is a real developed
   frame, so the hero *is* the product working, not a decoration. */
const REEL = ['tokyo-neon', 'a24-still', 'kodachrome', 'gq-editorial', 'film-noir', 'y2k-digicam']
/* the headline's warm word morphs with the frame — one promise, many moods */
const WORDS = ['mood.', 'look.', 'era.', 'story.', 'glow.', 'feeling.']
/* how long each frame holds before the next develops (ms) */
const HOLD = 2900

interface Props {
  onUpload: () => void
}

export default function LiveHero({ onUpload }: Props) {
  const looks = useMemo(
    () =>
      REEL.map((id) => {
        const s = getStyle(id)
        return s && STYLE_ART[id] ? { id, name: s.name, exif: s.exif, art: STYLE_ART[id] } : null
      }).filter((x): x is NonNullable<typeof x> => !!x),
    [],
  )
  const n = looks.length

  const reduce = useRef(
    typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
  )
  const [i, setI] = useState(0)
  const [paused, setPaused] = useState(false)

  useEffect(() => {
    if (reduce.current || paused || n < 2) return
    const t = setInterval(() => setI((v) => (v + 1) % n), HOLD)
    return () => clearInterval(t)
  }, [paused, n])

  const look = looks[i] ?? looks[0]
  const word = WORDS[i % WORDS.length]

  return (
    <div className="relative rounded-[28px] overflow-hidden bg-vf border border-white/[0.06] shadow-[var(--shadow-e3)]">
      {/* viewfinder chrome strip — the readout tracks whatever is developing */}
      <div className="h-9 px-4 flex items-center justify-between gap-3 border-b border-white/[0.08]">
        <span className="flex items-center gap-2 font-mono font-semibold text-[10px] tracking-[0.14em] uppercase text-vf-chrome min-w-0">
          <span className="lm-live w-1.5 h-1.5 rounded-full bg-signal shrink-0" aria-hidden />
          <span className="truncate">
            <AnimatePresence mode="wait">
              <motion.span
                key={look.id}
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                transition={{ duration: 0.28 }}
                className="inline-block"
              >
                {look.name}
              </motion.span>
            </AnimatePresence>
          </span>
        </span>
        <span className="font-mono text-[10px] tracking-[0.08em] uppercase text-vf-chrome tabular-nums shrink-0">
          {look.exif}
        </span>
      </div>

      <div
        className="relative aspect-[4/3.6] vf-corners overflow-hidden"
        onPointerDown={() => setPaused(true)}
        onPointerUp={() => setPaused(false)}
        onPointerLeave={() => setPaused(false)}
      >
        {/* the develop reel — each frame crosses in with a wet-print shimmer */}
        <AnimatePresence>
          <motion.img
            key={look.id}
            src={look.art}
            alt=""
            draggable={false}
            initial={{ opacity: 0, scale: 1.06 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 1 }}
            transition={{ opacity: { duration: 0.7 }, scale: { duration: HOLD / 1000, ease: 'linear' } }}
            className="absolute inset-0 w-full h-full object-cover"
          />
        </AnimatePresence>
        {!reduce.current && (
          <div key={`fx-${i}`} aria-hidden className="absolute inset-0 pointer-events-none">
            <div className="lm-print-bloom absolute inset-0" />
            <div className="lm-print-sheen absolute inset-0" />
          </div>
        )}

        {/* "shot on" tag — reinforces that this is a real develop */}
        <span className="absolute top-3 left-3 z-10 flex items-center gap-1.5 rounded-full bg-black/45 backdrop-blur-md px-2.5 h-6 font-mono text-[9px] font-semibold uppercase tracking-[0.14em] text-white/90">
          <span className="w-1 h-1 rounded-full bg-signal" aria-hidden />
          Shot on LensMood
        </span>

        {/* frame pips — which look in the reel; doubles as an anticipation cue */}
        {!reduce.current && n > 1 && (
          <div className="absolute top-3 right-3 z-10 flex items-center gap-1">
            {looks.map((l, idx) => (
              <span
                key={l.id}
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
                  key={word}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -12 }}
                  transition={{ duration: 0.34, ease: [0.33, 0.02, 0.2, 1] }}
                  className="serif-accent col-start-1 row-start-1"
                >
                  {word}
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

        {/* develop timer — a thin bar filling toward the next frame, the
            anticipation beat that makes the loop hard to look away from */}
        {!reduce.current && n > 1 && (
          <div className="absolute inset-x-0 bottom-0 h-[3px] bg-white/10 z-10">
            <motion.div
              key={`bar-${i}-${paused}`}
              className="h-full bg-white/70"
              initial={{ width: '0%' }}
              animate={{ width: paused ? '0%' : '100%' }}
              transition={{ duration: paused ? 0 : HOLD / 1000, ease: 'linear' }}
            />
          </div>
        )}
      </div>
    </div>
  )
}
