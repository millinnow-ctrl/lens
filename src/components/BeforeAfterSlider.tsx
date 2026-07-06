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
  /** size the frame to the photo's own aspect ratio (never crop), capped at
   *  this max height — for comparing the user's real photo in the studio */
  fitToImage?: boolean
  maxH?: string
}

export default function BeforeAfterSlider({
  before,
  after,
  auto = false,
  className = '',
  beforeLabel = 'Original',
  afterLabel = 'LensMood',
  variant = 'instrument',
  fitToImage = false,
  maxH = '62dvh',
}: Props) {
  const [pos, setPos] = useState(50)
  const [engaged, setEngaged] = useState(false)
  /** the before image's natural aspect — drives the frame when fitToImage */
  const [ratio, setRatio] = useState<number | null>(null)
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

  /* fit-to-image: the frame takes the photo's own aspect ratio (so nothing
     is ever cropped out of the comparison) and is capped to maxH — the width
     cap keeps aspect-ratio honest when the height clamp would win */
  const frameStyle =
    fitToImage && ratio
      ? {
          aspectRatio: String(ratio),
          maxHeight: maxH,
          maxWidth: `calc(${maxH} * ${ratio})`,
          margin: '0 auto',
        }
      : undefined

  return (
    <div
      ref={ref}
      className={`relative overflow-hidden select-none touch-none cursor-ew-resize ${className}`}
      style={frameStyle}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      role="slider"
      aria-label="Before and after comparison"
      aria-valuenow={Math.round(pos)}
    >
      <img
        src={before}
        alt="Before"
        className="absolute inset-0 w-full h-full object-cover"
        draggable={false}
        onLoad={(e) => {
          const img = e.currentTarget
          if (img.naturalWidth && img.naturalHeight) setRatio(img.naturalWidth / img.naturalHeight)
        }}
      />
      <div
        className="absolute inset-0"
        style={{ clipPath: `inset(0 0 0 ${pos}%)` }}
      >
        <img
          src={after}
          alt="After"
          /* in fit mode the frame matches the original's ratio; the developed
             print can differ (polaroid borders), so contain — never crop it */
          className={`absolute inset-0 w-full h-full ${fitToImage ? 'object-contain bg-vf' : 'object-cover'}`}
          draggable={false}
        />
      </div>

      {variant === 'instrument' ? (
        <>
          {/* labels — mono chrome slates, machined edge */}
          <span className="absolute top-3 left-3 font-mono text-[10px] font-medium tracking-[0.12em] uppercase tag-glass text-white/85 px-2.5 py-1 rounded-full pointer-events-none">
            {beforeLabel}
          </span>
          <span className="absolute top-3 right-3 font-mono text-[10px] font-medium tracking-[0.12em] uppercase tag-glass text-white px-2.5 py-1 rounded-full pointer-events-none inline-flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 rounded-full bg-signal inline-block" aria-hidden />
            {afterLabel}
          </span>
        </>
      ) : (
        <>
          {/* labels — soft mono pills, machined edge */}
          <span className="absolute top-2.5 left-2.5 font-mono text-[10px] font-medium tracking-[0.12em] uppercase tag-glass text-white/85 px-2.5 py-1 rounded-full pointer-events-none">
            {beforeLabel}
          </span>
          <span className="absolute top-2.5 right-2.5 font-mono text-[10px] font-medium tracking-[0.12em] uppercase tag-glass text-white px-2.5 py-1 rounded-full pointer-events-none inline-flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 rounded-full bg-signal inline-block" aria-hidden />
            {afterLabel}
          </span>
        </>
      )}

      {/* divider + handle — a machined disc riding a hairline rail */}
      <div
        className="absolute top-0 bottom-0 w-px bg-paper/90 pointer-events-none shadow-[0_0_0_0.5px_rgb(23_19_31/0.25)]"
        style={{ left: `${pos}%` }}
      >
        <div
          className={`absolute top-1/2 -translate-y-1/2 -translate-x-1/2 w-10 h-10 flex items-center justify-center text-ink rounded-full bg-white ring-1 ${
            variant === 'instrument'
              ? 'ring-ink/10 shadow-[inset_0_1px_0_rgb(255_255_255/0.9),inset_0_-1px_0_rgb(23_19_31/0.06),0_1px_2px_rgb(23_19_31/0.25),0_8px_20px_-8px_rgb(23_19_31/0.5)]'
              : 'ring-ink/[0.06] shadow-[inset_0_1px_0_rgb(255_255_255/0.9),0_1px_2px_rgb(23_19_31/0.08),0_6px_20px_-6px_rgb(23_19_31/0.3)]'
          }`}
        >
          <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <path d="M8 7l-5 5 5 5M16 7l5 5-5 5" />
          </svg>
        </div>
      </div>
    </div>
  )
}
