import { useCallback, useEffect, useRef, useState } from 'react'

interface Props {
  before: string
  after: string
  /** gently sweep the handle until the user touches it */
  auto?: boolean
  className?: string
  beforeLabel?: string
  afterLabel?: string
}

export default function BeforeAfterSlider({
  before,
  after,
  auto = false,
  className = '',
  beforeLabel = 'Original',
  afterLabel = 'LensMood',
}: Props) {
  const [pos, setPos] = useState(50)
  const [engaged, setEngaged] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const dragging = useRef(false)

  // idle sweep animation
  useEffect(() => {
    if (!auto || engaged) return
    let raf = 0
    const start = performance.now()
    const tick = (t: number) => {
      const e = (t - start) / 1000
      setPos(50 + Math.sin(e * 0.7) * 26)
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [auto, engaged])

  const updateFromClientX = useCallback((clientX: number) => {
    const el = ref.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    const p = ((clientX - rect.left) / rect.width) * 100
    setPos(Math.max(2, Math.min(98, p)))
  }, [])

  const onPointerDown = (e: React.PointerEvent) => {
    setEngaged(true)
    dragging.current = true
    ;(e.target as Element).setPointerCapture?.(e.pointerId)
    updateFromClientX(e.clientX)
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (dragging.current) updateFromClientX(e.clientX)
  }
  const onPointerUp = () => {
    dragging.current = false
  }

  return (
    <div
      ref={ref}
      className={`relative overflow-hidden select-none touch-none cursor-ew-resize ${className}`}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      role="slider"
      aria-label="Before and after comparison"
      aria-valuenow={Math.round(pos)}
    >
      <img src={before} alt="Before" className="absolute inset-0 w-full h-full object-cover" draggable={false} />
      <div
        className="absolute inset-0"
        style={{ clipPath: `inset(0 0 0 ${pos}%)` }}
      >
        <img src={after} alt="After" className="absolute inset-0 w-full h-full object-cover" draggable={false} />
      </div>

      {/* labels */}
      <span className="absolute top-3 left-3 text-[11px] font-semibold uppercase tracking-wider bg-ink/50 text-paper/95 backdrop-blur px-2.5 py-1 rounded-full pointer-events-none">
        {beforeLabel}
      </span>
      <span className="absolute top-3 right-3 text-[11px] font-semibold uppercase tracking-wider bg-violet/85 text-paper backdrop-blur px-2.5 py-1 rounded-full pointer-events-none inline-flex items-center gap-1">
        <svg viewBox="0 0 12 12" className="w-2.5 h-2.5" fill="currentColor" aria-hidden>
          <circle cx="6" cy="6" r="5" fill="none" stroke="currentColor" strokeWidth="1.4" />
          <circle cx="6" cy="6" r="2" />
        </svg>
        {afterLabel}
      </span>

      {/* divider + handle */}
      <div
        className="absolute top-0 bottom-0 w-0.5 bg-paper/90 shadow-[0_0_12px_rgba(0,0,0,0.35)] pointer-events-none"
        style={{ left: `${pos}%` }}
      >
        <div className="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 w-11 h-11 rounded-full bg-paper shadow-lg flex items-center justify-center text-ink">
          <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M8 7l-5 5 5 5M16 7l5 5-5 5" />
          </svg>
        </div>
      </div>
    </div>
  )
}
