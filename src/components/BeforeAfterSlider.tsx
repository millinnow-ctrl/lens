import { useCallback, useEffect, useRef, useState } from 'react'

interface Props {
  before: string
  after: string
  /** gently sweep the handle until the user touches it */
  auto?: boolean
  className?: string
  beforeLabel?: string
  afterLabel?: string
  /** 'instrument' = mono slates + square handle (studio); 'soft' = pill chrome (consumer home) */
  variant?: 'instrument' | 'soft'
}

export default function BeforeAfterSlider({
  before,
  after,
  auto = false,
  className = '',
  beforeLabel = 'Original',
  afterLabel = 'LensMood',
  variant = 'instrument',
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

      {variant === 'instrument' ? (
        <>
          {/* labels — mono chrome slates */}
          <span className="absolute top-3 left-3 font-mono text-[10px] font-medium tracking-[0.12em] uppercase bg-vf/65 text-paper/90 px-2 py-1 rounded-xs pointer-events-none">
            {beforeLabel}
          </span>
          <span className="absolute top-3 right-3 font-mono text-[10px] font-medium tracking-[0.12em] uppercase bg-vf/65 text-paper px-2 py-1 rounded-xs pointer-events-none inline-flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 rounded-full bg-signal inline-block" aria-hidden />
            {afterLabel}
          </span>
        </>
      ) : (
        <>
          {/* labels — soft pills */}
          <span className="absolute top-2.5 left-2.5 text-[11px] font-semibold bg-vf/60 text-white px-2.5 py-1 rounded-full pointer-events-none">
            {beforeLabel}
          </span>
          <span className="absolute top-2.5 right-2.5 text-[11px] font-semibold bg-vf/60 text-white px-2.5 py-1 rounded-full pointer-events-none">
            {afterLabel}
          </span>
        </>
      )}

      {/* divider + handle */}
      <div
        className="absolute top-0 bottom-0 w-px bg-paper pointer-events-none"
        style={{ left: `${pos}%` }}
      >
        <div
          className={`absolute top-1/2 -translate-y-1/2 -translate-x-1/2 w-10 h-10 flex items-center justify-center text-ink ${
            variant === 'instrument'
              ? 'rounded-xs bg-surface border border-ink'
              : 'rounded-full bg-white shadow-[0_1px_2px_rgb(20_20_18/0.08),0_6px_20px_-6px_rgb(20_20_18/0.3)]'
          }`}
        >
          <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="square">
            <path d="M8 7l-5 5 5 5M16 7l5 5-5 5" />
          </svg>
        </div>
      </div>
    </div>
  )
}
