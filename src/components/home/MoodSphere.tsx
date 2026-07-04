import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { haptic } from '../../lib/native'
import type { CameraStyle } from '../../lib/styles'

interface Props {
  styles: CameraStyle[]
  thumbs: Record<string, string>
  fallbackImage: string
  tried: string[]
  /** today's featured mood id — gets the TODAY tag and the initial rest position */
  dailyId?: string
  onOpen: (style: CameraStyle) => void
  /** bump this number to trigger a slot-machine spin to a random mood */
  spinSeed?: number
  onSpinEnd?: (style: CameraStyle) => void
}

/* ---- motion spec: geometry ---- */
const CARD_W = 168
const GAP = 16
const CULL = 102 // hide past this angle; opacity hits 0 at 100 so nothing pops

/* ---- motion spec: physics ---- */
const PROJECTION_TAU = 100 // ms — iOS decelerationRate.fast
const SPRING_K = 220
const SPRING_C = 28
const TAP_SLOP = 8
const TAP_MS = 300
const MAX_TRAVEL_CARDS = 3

const mod = (v: number, m: number) => ((v % m) + m) % m

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
  const step = 360 / Math.max(n, 1)
  /* R = (w+gap) / 2·tan(π/N), clamped 240–300 so filtered subsets keep depth */
  const radius = useMemo(() => {
    if (n < 2) return 240
    return Math.min(300, Math.max(240, (CARD_W + GAP) / (2 * Math.tan(Math.PI / n))))
  }, [n])

  const cardRefs = useRef<(HTMLDivElement | null)[]>([])
  const shadowRef = useRef<HTMLDivElement>(null)

  const theta = useRef(0) // unwrapped rotation, degrees
  const vel = useRef(0) // deg / frame-ish (per ms in spring)
  const target = useRef<number | null>(null)
  const mode = useRef<'idle' | 'drag' | 'spring' | 'spin'>('idle')
  const spin = useRef<{ from: number; to: number; start: number; dur: number } | null>(null)
  const raf = useRef(0)
  const lastTime = useRef(0)
  const lastFront = useRef(0)
  const lastTick = useRef(0)
  const pointer = useRef({ x: 0, t: 0, moved: false, lastX: 0, vx: 0 })

  const [frontIdx, setFrontIdx] = useState(0)
  const frontStyle = styles[mod(frontIdx, Math.max(n, 1))]

  const reducedMotion =
    typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

  const degPerPx = step / (CARD_W + GAP) // geared: one card-width of finger = one detent

  const frontIndexFor = useCallback((rot: number) => mod(Math.round(-rot / step), n), [step, n])

  /* paint transforms straight onto the DOM — React never re-renders per frame */
  const paint = useCallback(
    (omega: number) => {
      const rot = theta.current
      for (let i = 0; i < n; i++) {
        const el = cardRefs.current[i]
        if (!el) continue
        let a = mod(i * step + rot, 360)
        if (a > 180) a -= 360
        const d = Math.abs(a)
        if (d > CULL) {
          el.style.visibility = 'hidden'
          continue
        }
        const cos = Math.max(0, Math.cos((a * Math.PI) / 180))
        el.style.visibility = 'visible'
        el.style.transform = `translate(-50%, -50%) rotateY(${a}deg) translateZ(${radius}px) translateY(${-6 * cos}px) scale(${0.94 + 0.1 * cos})`
        el.style.opacity = String(Math.max(0, 1 - Math.pow(d / 100, 1.4)))
        el.style.filter = `brightness(${1 - 0.35 * Math.min(d / 90, 1)}) saturate(${1 - 0.4 * Math.min(d / 90, 1)})`
        el.style.zIndex = String(1000 - Math.round(d))
        // per-card contact shadow, full on front, gone by 90°
        el.style.boxShadow = `0 8px 24px rgb(0 0 0 / ${(0.28 * cos).toFixed(3)})`
      }
      /* ground shadow energizes with angular speed */
      const s = shadowRef.current
      if (s) {
        const speed = Math.min(Math.abs(omega) / 5, 1)
        s.style.opacity = String(0.38 * (1 - speed * 0.4))
        s.style.transform = `translateX(-50%) scaleX(${1 + speed * 0.25}) scaleY(${1 - speed * 0.14})`
        s.style.filter = `blur(${14 + speed * 4}px)`
      }
      /* detent-midpoint crossing: label + haptic commit together */
      const front = frontIndexFor(rot)
      if (front !== lastFront.current) {
        lastFront.current = front
        setFrontIdx(front)
        const now = performance.now()
        if (mode.current !== 'idle' && now - lastTick.current > 30) {
          lastTick.current = now
          haptic('light')
        }
      }
    },
    [n, step, radius, frontIndexFor],
  )

  const tick = useCallback(
    (now: number) => {
      const dt = Math.min((now - lastTime.current) / 1000 || 0.016, 0.032)
      lastTime.current = now
      let omega = 0

      if (mode.current === 'spring' && target.current != null) {
        const delta = target.current - theta.current
        // semi-implicit euler, k=220 c=28 (ζ≈0.94 — one small overshoot)
        vel.current += (SPRING_K * delta - SPRING_C * vel.current) * dt
        theta.current += vel.current * dt
        omega = vel.current * dt
        if (Math.abs(delta) < 0.04 && Math.abs(vel.current) < 0.6) {
          theta.current = target.current
          vel.current = 0
          mode.current = 'idle'
          haptic('medium') // settle click
        }
      } else if (mode.current === 'spin' && spin.current) {
        const { from, to, start, dur } = spin.current
        const p = Math.min((now - start) / dur, 1)
        const ease = 1 - Math.pow(1 - p, 3)
        const prev = theta.current
        theta.current = from + (to - from) * ease
        omega = theta.current - prev
        if (p >= 1) {
          theta.current = to
          mode.current = 'idle'
          spin.current = null
          haptic('medium')
          onSpinEnd?.(styles[frontIndexFor(to)])
        }
      }
      paint(omega)
      if (mode.current !== 'idle') raf.current = requestAnimationFrame(tick)
    },
    [paint, styles, frontIndexFor, onSpinEnd],
  )

  const run = useCallback(() => {
    cancelAnimationFrame(raf.current)
    lastTime.current = performance.now()
    raf.current = requestAnimationFrame(tick)
  }, [tick])

  const springTo = useCallback(
    (t: number) => {
      target.current = t
      mode.current = 'spring'
      run()
    },
    [run],
  )

  /* geometry changes: rest on the daily stock, with a one-time affordance drift */
  useEffect(() => {
    const dailyIdx = Math.max(
      0,
      styles.findIndex((s) => s.id === dailyId),
    )
    const rest = -dailyIdx * step
    vel.current = 0
    lastFront.current = dailyIdx
    setFrontIdx(dailyIdx)
    if (reducedMotion) {
      theta.current = rest
      mode.current = 'idle'
      paint(0)
    } else {
      theta.current = rest - 14 // drift in once — demonstrates the swipe, then never again
      springTo(rest)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [n, dailyId])

  useEffect(() => () => cancelAnimationFrame(raf.current), [])

  /* slot-machine spin to a random (never current) mood */
  useEffect(() => {
    if (spinSeed === 0 || n < 2) return
    let t = Math.floor(Math.random() * n)
    if (t === frontIndexFor(theta.current)) t = mod(t + 1, n)
    const snapped = Math.round(theta.current / step) * step
    const align = mod(snapped + t * step, 360)
    spin.current = {
      from: theta.current,
      to: snapped - (reducedMotion ? 0 : 720) - align,
      start: performance.now(),
      dur: reducedMotion ? 300 : 2100,
    }
    mode.current = 'spin'
    haptic('medium')
    run()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spinSeed])

  /* pointer handling — geared drag, projection release */
  const onPointerDown = (e: React.PointerEvent) => {
    if (mode.current === 'spin') return
    ;(e.currentTarget as Element).setPointerCapture?.(e.pointerId)
    pointer.current = { x: e.clientX, t: performance.now(), moved: false, lastX: e.clientX, vx: 0 }
    vel.current = 0
    mode.current = 'drag'
    cancelAnimationFrame(raf.current)
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (mode.current !== 'drag') return
    const now = performance.now()
    const dx = e.clientX - pointer.current.lastX
    const dtms = Math.max(now - (pointer.current as { t: number }).t, 1)
    pointer.current.vx = pointer.current.vx * 0.6 + (dx / Math.max(dtms / 16, 0.5)) * 0.4
    pointer.current.lastX = e.clientX
    pointer.current.t = now
    if (Math.abs(e.clientX - pointer.current.x) > TAP_SLOP) pointer.current.moved = true
    theta.current += dx * degPerPx // 1:1 gearing, zero smoothing while the finger is down
    paint(dx * degPerPx)
  }
  const onPointerUp = (e: React.PointerEvent) => {
    if (mode.current !== 'drag') return
    const isTap = !pointer.current.moved && performance.now() - pointer.current.t < TAP_MS + 200
    if (isTap) {
      mode.current = 'idle'
      const el = (e.target as HTMLElement).closest('[data-sphere-idx]')
      if (el) {
        const i = Number(el.getAttribute('data-sphere-idx'))
        if (i === frontIndexFor(theta.current)) {
          haptic('medium')
          onOpen(styles[i])
          return
        }
        let a = mod(i * step + theta.current, 360)
        if (a > 180) a -= 360
        springTo(theta.current - a) // shortest way around
      }
      return
    }
    // UIKit-style projection: θ_target = θ + v·τ, clamp to ±3 cards, snap to detent
    const vDegPerMs = pointer.current.vx * degPerPx // vx ≈ px/frame → deg/frame ≈ deg/16ms
    const projected = theta.current + (vDegPerMs / 16) * PROJECTION_TAU * 6
    const maxTravel = MAX_TRAVEL_CARDS * step
    const clamped = Math.max(theta.current - maxTravel, Math.min(theta.current + maxTravel, projected))
    springTo(Math.round(clamped / step) * step)
  }

  if (n === 0) return null

  return (
    <div className="select-none">
      {/* stage */}
      <div
        className="relative h-[284px] touch-pan-y cursor-grab active:cursor-grabbing"
        style={{ perspective: '1100px', perspectiveOrigin: '50% 38%' }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        role="listbox"
        aria-label="Camera moods — swipe to browse"
        aria-activedescendant={frontStyle ? `mood-${frontStyle.id}` : undefined}
      >
        <div
          className="absolute inset-0"
          style={{ transformStyle: 'preserve-3d', transform: `translateZ(-${radius}px)` }}
        >
          {styles.map((s, i) => (
            <div
              key={s.id}
              id={`mood-${s.id}`}
              ref={(el) => {
                cardRefs.current[i] = el
              }}
              data-sphere-idx={i}
              role="option"
              aria-selected={i === frontIdx}
              className="absolute left-1/2 top-[45%] w-[168px] rounded-[14px] bg-white p-1.5 will-change-transform"
              style={{ backfaceVisibility: 'hidden' }}
            >
              <div className="relative rounded-[10px] overflow-hidden aspect-[4/5] bg-hairline pointer-events-none">
                <img
                  src={thumbs[s.id] ?? fallbackImage}
                  alt={s.name}
                  draggable={false}
                  className="w-full h-full object-cover"
                  style={thumbs[s.id] ? undefined : { filter: s.cardFilter }}
                />
                {dailyId === s.id && (
                  <span className="absolute top-1.5 left-1.5 rounded-full bg-signal text-white text-[9px] font-bold tracking-[0.08em] uppercase px-2 py-0.5">
                    Today
                  </span>
                )}
                {s.tier === 'premium' && (
                  <span className="absolute top-1.5 right-1.5 rounded-full bg-vf/75 text-white text-[8.5px] font-semibold tracking-[0.06em] uppercase px-1.5 py-0.5">
                    Pro
                  </span>
                )}
                {tried.includes(s.id) && (
                  <span
                    className="absolute bottom-1.5 right-1.5 w-4 h-4 rounded-full bg-white/90 flex items-center justify-center"
                    aria-label="Developed"
                  >
                    <svg viewBox="0 0 12 12" width="8" height="8" fill="none" stroke="#171614" strokeWidth="2" strokeLinecap="square">
                      <path d="M2.5 6.5l2.5 2.5 4.5-5" />
                    </svg>
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
        {/* grounding shadow — the wheel sits on this */}
        <div
          ref={shadowRef}
          className="absolute bottom-[2px] left-1/2 -translate-x-1/2 w-[248px] h-[26px] pointer-events-none rounded-[50%]"
          style={{
            background: 'radial-gradient(ellipse at center, rgb(0 0 0 / 1) 0%, rgb(0 0 0 / 0.35) 45%, transparent 72%)',
            opacity: 0.38,
            filter: 'blur(10px)',
          }}
          aria-hidden
        />
      </div>

      {/* front card label — fixed height, no layout shift */}
      <div className="h-[52px] text-center mt-4">
        {frontStyle && (
          <div key={frontStyle.id} className="hm-sheet">
            <button
              onClick={() => onOpen(frontStyle)}
              className="text-[15px] font-bold tracking-[-0.01em] leading-tight"
            >
              {frontStyle.name}
            </button>
            <p className="text-[11px] text-ink-soft mt-0.5">
              {frontStyle.tier === 'premium' ? 'Pro' : 'Free'} · {frontStyle.tagline}
            </p>
          </div>
        )}
      </div>

      {/* the case, compressed: filled once developed */}
      <div
        className="flex justify-center gap-1.5 mt-1"
        aria-label={`${tried.filter((t) => styles.some((s) => s.id === t)).length} of ${n} moods developed`}
      >
        {styles.map((s, i) => (
          <span
            key={s.id}
            className={`rounded-full transition-all duration-200 ${
              i === frontIdx ? 'w-3.5 h-1.5' : 'w-1.5 h-1.5'
            } ${tried.includes(s.id) ? 'bg-ink' : i === frontIdx ? 'bg-ink/50' : 'bg-ink/20'}`}
          />
        ))}
      </div>
    </div>
  )
}
