import { useCallback, useEffect, useRef, useState } from 'react'
import { haptic } from '../../lib/native'
import { IconSparkle } from '../icons'
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

/**
 * Look picker — the hero carousel. Native scroll-snap with a stage
 * treatment: the centered card rises, grows and earns the gradient
 * glow ring; side cards fall back on a soft elliptical orbit line.
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
  const raf = useRef(0)
  const settleTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastFront = useRef(-1)
  const spinning = useRef(false)

  const [frontIdx, setFrontIdx] = useState(0)
  const frontStyle = styles[Math.min(frontIdx, n - 1)]

  /* depth pass — runs on scroll, writes transforms directly */
  const paint = useCallback(() => {
    const el = scrollerRef.current
    if (!el) return
    const mid = el.scrollLeft + el.clientWidth / 2
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
      const focus = 1 - Math.min(abs, 1) // 1 at center → 0 one card away
      const scale = 1 + focus * 0.24
      const lift = focus * 10
      const tilt = Math.max(-1.5, Math.min(1.5, d)) * -6
      card.style.transform = `translateY(${-lift}px) scale(${scale}) rotateY(${tilt}deg)`
      card.style.opacity = String(1 - Math.min(abs / 3.5, 0.2))
      card.style.zIndex = String(100 - Math.round(abs * 10))
    }
    if (nearest !== lastFront.current) {
      const moved = lastFront.current !== -1
      lastFront.current = nearest
      setFrontIdx(nearest)
      if (moved) haptic('light')
    }
  }, [n])

  const onScroll = useCallback(() => {
    cancelAnimationFrame(raf.current)
    raf.current = requestAnimationFrame(paint)
    if (settleTimer.current) clearTimeout(settleTimer.current)
    settleTimer.current = setTimeout(() => {
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

  /* rest on today's featured look */
  useEffect(() => {
    const idx = Math.max(
      0,
      styles.findIndex((s) => s.id === dailyId),
    )
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

  /* surprise: scroll-spin to a random other mood */
  useEffect(() => {
    if (spinSeed === 0 || n < 2) return
    let t = Math.floor(Math.random() * n)
    if (t === lastFront.current) t = (t + 1) % n
    spinning.current = true
    haptic('medium')
    scrollToIndex(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spinSeed])

  if (n === 0) return null

  return (
    <div className="select-none">
      <div className="relative" style={{ perspective: '1100px' }}>
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
              <stop offset="0.2" stopColor="#8b5cf6" stopOpacity="0.55" />
              <stop offset="0.5" stopColor="#d946ef" stopOpacity="0.7" />
              <stop offset="0.8" stopColor="#ec4899" stopOpacity="0.55" />
              <stop offset="1" stopColor="#ec4899" stopOpacity="0" />
            </linearGradient>
          </defs>
          <ellipse cx="200" cy="45" rx="192" ry="38" fill="none" stroke="url(#orbit)" strokeWidth="2" />
        </svg>
        {/* drifting sparkles around the stage */}
        <IconSparkle
          size={15}
          className="lm-twinkle absolute top-1 left-[calc(50%+86px)] text-orchid pointer-events-none z-[110]"
        />
        <IconSparkle
          size={12}
          className="lm-twinkle absolute bottom-9 left-[calc(50%-118px)] text-magenta pointer-events-none z-[110]"
          style={{ animationDelay: '1.2s' }}
        />

        <div
          ref={scrollerRef}
          onScroll={onScroll}
          className="flex items-center gap-[14px] overflow-x-auto no-scrollbar snap-x snap-mandatory pt-12 pb-7"
          style={{ paddingInline: `calc(50% - ${CARD_W / 2}px)` }}
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
                  isFront ? 'grad-fill aura' : 'bg-transparent'
                }`}
                style={{ willChange: 'transform' }}
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
                    <p className="text-white font-semibold text-[12.5px] leading-tight drop-shadow-sm">{s.name}</p>
                    <p className="text-white/70 text-[9.5px] leading-tight mt-0.5">{s.tagline}</p>
                  </div>
                  {dailyId === s.id && (
                    <span className="absolute top-1.5 left-1.5 rounded-full grad-fill text-white text-[8.5px] font-bold tracking-[0.05em] uppercase px-1.5 py-0.5">
                      Today
                    </span>
                  )}
                  {s.tier === 'premium' && (
                    <span className="absolute top-1.5 right-1.5 rounded-full bg-black/50 backdrop-blur-sm text-white text-[8.5px] font-semibold tracking-[0.04em] uppercase px-1.5 py-0.5">
                      Pro
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
              </div>
            )
          })}
        </div>

        {/* soft contact shadow under the raised center card */}
        <div
          className="absolute left-1/2 -translate-x-1/2 bottom-[6px] w-[130px] h-[12px] pointer-events-none rounded-[50%]"
          style={{
            background: 'radial-gradient(ellipse at center, rgb(76 29 149 / 0.9) 0%, transparent 70%)',
            opacity: 0.18,
            filter: 'blur(5px)',
          }}
          aria-hidden
        />
      </div>

      {/* page dots */}
      <div
        className="flex justify-center gap-1.5 mt-1"
        aria-label={`${tried.filter((t) => styles.some((s) => s.id === t)).length} of ${n} looks used`}
      >
        {styles.map((s, i) => (
          <span
            key={s.id}
            className={`rounded-full transition-all duration-200 ${
              i === frontIdx ? 'w-2 h-2 bg-violet' : 'w-1.5 h-1.5 bg-ink/15'
            } ${tried.includes(s.id) && i !== frontIdx ? 'bg-violet/40' : ''}`}
          />
        ))}
      </div>
    </div>
  )
}
