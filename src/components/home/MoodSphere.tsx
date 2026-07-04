import { useCallback, useEffect, useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { haptic } from '../../lib/native'
import { deckCard, springPress } from '../../lib/motion'
import type { CameraStyle } from '../../lib/styles'

interface Props {
  styles: CameraStyle[]
  thumbs: Record<string, string>
  fallbackImage: string
  tried: string[]
  /** today's featured mood id — tagged and used as the initial rest position */
  dailyId?: string
  onOpen: (style: CameraStyle) => void
  /** bump this number to scroll-spin to a random mood */
  spinSeed?: number
  onSpinEnd?: (style: CameraStyle) => void
}

const CARD_W = 112
const GAP = 14
/** signed-distance clamp — cards beyond this ride the ring's far edge */
const REACH = 2.2
/** resting opacity of the wide elliptical ground shadow — softness comes
    from the gradient falloff itself (filter:blur on translucent layers
    fails to rasterize on some GPUs, so the blur is baked into the stops) */
const GROUND_OPACITY = 1

/**
 * Look picker — the hero carousel. Native scroll-snap with a 3D ring
 * treatment: cards turn around a rotating sphere (rotateY + a cosine
 * crown arc + cosine scale falloff), grounded by a wide soft ground
 * shadow that squashes and fades with scroll velocity.
 */
export default function MoodSphere({
  styles,
  thumbs,
  fallbackImage,
  tried,
  dailyId,
  onOpen,
  spinSeed = 0,
  onSpinEnd,
}: Props) {
  const n = styles.length
  const scrollerRef = useRef<HTMLDivElement>(null)
  const cardRefs = useRef<(HTMLDivElement | null)[]>([])
  const groundRef = useRef<HTMLDivElement>(null)
  const raf = useRef(0)
  const settleTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastFront = useRef(-1)
  const spinning = useRef(false)
  /* scroll velocity tracking — drives the ground-shadow squash */
  const lastX = useRef(0)
  const lastPaintT = useRef(0)
  const vel = useRef(0)

  const [frontIdx, setFrontIdx] = useState(0)
  const frontStyle = styles[Math.min(frontIdx, n - 1)]
  const [reduceMotion] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches,
  )

  /* depth pass — runs on scroll, writes transforms directly */
  const paint = useCallback(() => {
    const el = scrollerRef.current
    if (!el) return
    const mid = el.scrollLeft + el.clientWidth / 2

    /* velocity (px/ms, smoothed) → the wide ground shadow stretches
       and fades while the ring spins fast, springs back on settle */
    const now = performance.now()
    const dt = Math.max(1, now - lastPaintT.current)
    const v = Math.abs(el.scrollLeft - lastX.current) / dt
    lastPaintT.current = now
    lastX.current = el.scrollLeft
    vel.current = vel.current * 0.75 + v * 0.25
    const ground = groundRef.current
    if (ground && !reduceMotion) {
      const k = Math.min(vel.current / 2.5, 1) // ~2.5px/ms = full squash
      ground.style.transform = `scaleX(${(1 + 0.08 * k).toFixed(3)}) scaleY(${(1 - 0.18 * k).toFixed(3)})`
      ground.style.opacity = (GROUND_OPACITY * (1 - 0.3 * k)).toFixed(3)
    }

    let nearest = 0
    let nearestDist = Infinity
    for (let i = 0; i < n; i++) {
      const card = cardRefs.current[i]
      if (!card) continue
      const c = card.offsetLeft + card.offsetWidth / 2
      const d = (c - mid) / (CARD_W + GAP) // in card units, signed
      const abs = Math.abs(d)
      if (abs < nearestDist) {
        nearestDist = abs
        nearest = i
      }
      const t = Math.min(abs, REACH)
      const arc = Math.cos((t / REACH) * (Math.PI / 2)) // 1 center → 0 far edge
      const scale = 0.86 + 0.38 * arc // 1.24 center → 0.86 far edge
      if (reduceMotion) {
        card.style.transform = `scale(${scale.toFixed(4)})`
      } else {
        const tilt = -Math.max(-REACH, Math.min(REACH, d)) * 16 // ring rotation
        const y = 10 - 24 * arc // crown arc: -14px lift center → +10px sink edge
        card.style.transform = `translateY(${y.toFixed(2)}px) rotateY(${tilt.toFixed(2)}deg) scale(${scale.toFixed(4)})`
        card.style.filter = abs > 1.6 ? 'blur(0.5px)' : ''
      }
      card.style.opacity = (1 - 0.45 * (t / REACH)).toFixed(3) // 1 → 0.55
      card.style.zIndex = String(100 - Math.round(abs * 10))
    }
    if (nearest !== lastFront.current) {
      const moved = lastFront.current !== -1
      lastFront.current = nearest
      setFrontIdx(nearest)
      if (moved) haptic('light')
    }
  }, [n, reduceMotion])

  const onScroll = useCallback(() => {
    cancelAnimationFrame(raf.current)
    raf.current = requestAnimationFrame(paint)
    if (settleTimer.current) clearTimeout(settleTimer.current)
    settleTimer.current = setTimeout(() => {
      /* settled — spring the ground shadow back to rest */
      vel.current = 0
      const ground = groundRef.current
      if (ground) {
        ground.style.transform = 'scaleX(1) scaleY(1)'
        ground.style.opacity = String(GROUND_OPACITY)
      }
      if (spinning.current) {
        spinning.current = false
        haptic('medium')
        onSpinEnd?.(styles[lastFront.current] ?? styles[0])
      }
    }, 140)
  }, [paint, styles, onSpinEnd])

  const scrollToIndex = useCallback((i: number, smooth = true) => {
    const el = scrollerRef.current
    const card = cardRefs.current[i]
    if (!el || !card) return
    el.scrollTo({
      left: card.offsetLeft + card.offsetWidth / 2 - el.clientWidth / 2,
      behavior: smooth ? 'smooth' : 'auto',
    })
  }, [])

  /* rest on today's featured look — or the middle of a filtered deck, so
     the stage never opens with a bare left half */
  useEffect(() => {
    const found = styles.findIndex((s) => s.id === dailyId)
    const idx = found > 0 ? found : Math.floor(n / 2)
    lastFront.current = -1
    requestAnimationFrame(() => {
      scrollToIndex(idx, false)
      paint()
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [n, dailyId])

  useEffect(
    () => () => {
      cancelAnimationFrame(raf.current)
      if (settleTimer.current) clearTimeout(settleTimer.current)
    },
    [],
  )

  /* surprise: fling-spin to a random other mood — travel 5+ cards when
     the deck allows so the ring visibly rotates before settling */
  useEffect(() => {
    if (spinSeed === 0 || n < 2) return
    const cur = Math.max(0, lastFront.current)
    const minDist = Math.min(5, n - 1)
    let t = Math.floor(Math.random() * n)
    let guard = 0
    while (Math.abs(t - cur) < minDist && guard++ < 60) t = Math.floor(Math.random() * n)
    if (Math.abs(t - cur) < minDist) t = cur < (n - 1) / 2 ? n - 1 : 0 // farthest end
    spinning.current = true
    haptic('medium')
    scrollToIndex(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spinSeed])

  if (n === 0) return null

  return (
    <div className="select-none">
      <div className="relative">
        {/* orbit line — the elliptical gradient track the deck rides on */}
        <svg
          viewBox="0 0 400 90"
          preserveAspectRatio="none"
          className="absolute inset-x-[-6%] bottom-1 w-[112%] h-[74px] pointer-events-none"
          aria-hidden
        >
          <defs>
            <linearGradient id="orbit" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stopColor="#60a5fa" stopOpacity="0" />
              <stop offset="0.2" stopColor="#8b5cf6" stopOpacity="0.275" />
              <stop offset="0.5" stopColor="#d946ef" stopOpacity="0.35" />
              <stop offset="0.8" stopColor="#ec4899" stopOpacity="0.275" />
              <stop offset="1" stopColor="#ec4899" stopOpacity="0" />
            </linearGradient>
          </defs>
          <ellipse cx="200" cy="45" rx="192" ry="38" fill="none" stroke="url(#orbit)" strokeWidth="2" />
        </svg>

        <div
          ref={scrollerRef}
          onScroll={onScroll}
          className="flex items-center gap-[14px] overflow-x-auto no-scrollbar snap-x snap-mandatory pt-12 pb-6"
          style={{
            paddingInline: `calc(50% - ${CARD_W / 2}px)`,
            /* perspective lives here — it only reaches direct children,
               and the cards are this element's direct children */
            perspective: '950px',
            perspectiveOrigin: '50% 40%',
          }}
          role="listbox"
          aria-label="Camera styles — swipe to browse"
          aria-activedescendant={frontStyle ? `mood-${frontStyle.id}` : undefined}
        >
          {styles.map((s, i) => {
            const isFront = i === frontIdx
            return (
              <div
                key={s.id}
                id={`mood-${s.id}`}
                ref={(el) => {
                  cardRefs.current[i] = el
                }}
                role="option"
                aria-selected={isFront}
                onClick={() => (isFront ? onOpen(s) : scrollToIndex(i))}
                className={`relative snap-center shrink-0 w-[112px] rounded-[22px] p-[2px] cursor-pointer transition-shadow duration-300 ${
                  isFront ? 'bg-white/80 aura' : 'bg-transparent'
                }`}
                style={{ willChange: 'transform' }}
              >
                {/* entrance + press wrapper — composes with the ring transform
                    written on the parent by paint(); never touches it. cards
                    settle up on mount, the centered card springs on press */}
                <motion.div
                  variants={deckCard(i)}
                  initial="initial"
                  animate="animate"
                  whileTap={isFront ? { scale: 0.94, transition: springPress } : undefined}
                  className="rounded-[20px]"
                >
                <div className="relative rounded-[20px] overflow-hidden aspect-[10/23] bg-vf pointer-events-none">
                  <img
                    src={thumbs[s.id] ?? fallbackImage}
                    alt={s.name}
                    draggable={false}
                    className="w-full h-full object-cover"
                    style={thumbs[s.id] ? undefined : { filter: s.cardFilter }}
                  />
                  {/* label scrim */}
                  <div className="absolute inset-x-0 bottom-0 h-[52%] bg-gradient-to-t from-black/75 via-black/25 to-transparent" />
                  <div className="absolute inset-x-0 bottom-0 px-2 pb-2 text-center">
                    <p className="text-white font-semibold text-[12.5px] leading-tight drop-shadow-sm">
                      {s.name}
                      {s.tier === 'premium' && (
                        <span className="text-white/60 text-[10px] font-medium whitespace-nowrap"> · Pro</span>
                      )}
                    </p>
                    <p className="text-white/70 text-[9.5px] leading-tight mt-0.5">{s.tagline}</p>
                  </div>
                  {dailyId === s.id && (
                    <span className="absolute top-1.5 left-1.5 rounded-full bg-violet text-white text-[8.5px] font-bold tracking-[0.05em] uppercase px-1.5 py-0.5">
                      Today
                    </span>
                  )}
                  {tried.includes(s.id) && (
                    <span
                      className="absolute bottom-9 right-1.5 w-[18px] h-[18px] rounded-full bg-white/95 flex items-center justify-center"
                      aria-label="Used"
                    >
                      <svg
                        viewBox="0 0 12 12"
                        width="9"
                        height="9"
                        fill="none"
                        stroke="#8b5cf6"
                        strokeWidth="1.8"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M2.5 6.5l2.5 2.5 4.5-5" />
                      </svg>
                    </span>
                  )}
                </div>
                </motion.div>
              </div>
            )
          })}
        </div>

        {/* wide soft ground shadow — grounds the whole ring; squashes and
            fades with scroll velocity (written directly in paint()) */}
        <div
          ref={groundRef}
          className="absolute w-[280px] h-[30px] pointer-events-none rounded-[50%]"
          style={{
            left: '50%',
            marginLeft: '-140px',
            bottom: '-9px',
            zIndex: 1, // paints above the scroller layer, below the cards (z ≥ 78)
            background:
              'radial-gradient(ellipse 50% 50% at center, rgb(0 0 0 / 0.30) 0%, rgb(0 0 0 / 0.22) 40%, rgb(0 0 0 / 0.09) 72%, rgb(0 0 0 / 0) 100%)',
            opacity: GROUND_OPACITY,
            transition: 'transform 180ms ease-out, opacity 180ms ease-out',
            willChange: 'transform, opacity',
          }}
          aria-hidden
        />
        {/* crisp contact shadow under the raised center card */}
        <div
          className="absolute left-1/2 -translate-x-1/2 bottom-[6px] w-[130px] h-[12px] pointer-events-none rounded-[50%]"
          style={{
            zIndex: 1,
            background:
              'radial-gradient(ellipse 50% 50% at center, rgb(76 29 149 / 0.38) 0%, rgb(76 29 149 / 0.24) 55%, rgb(76 29 149 / 0) 100%)',
          }}
          aria-hidden
        />
      </div>

      {/* page dots — collapses to a counter once the deck grows past ten */}
      {n <= 10 ? (
        <div
          className="flex justify-center gap-1.5 mt-1"
          aria-label={`${tried.filter((t) => styles.some((s) => s.id === t)).length} of ${n} looks used`}
        >
          {styles.map((s, i) => (
            <span
              key={s.id}
              className={`rounded-full transition-all duration-200 ${
                i === frontIdx ? 'w-2 h-2 bg-ink' : 'w-1.5 h-1.5 bg-ink/15'
              } ${tried.includes(s.id) && i !== frontIdx ? 'bg-ink/40' : ''}`}
            />
          ))}
        </div>
      ) : (
        <p className="text-center text-[11.5px] font-semibold text-fog tabular-nums mt-1">
          <span className="text-ink">{frontIdx + 1}</span> / {n}
          <span className="mx-1.5 text-ink/20">·</span>
          {tried.filter((t) => styles.some((s) => s.id === t)).length} tried
        </p>
      )}
    </div>
  )
}
