import { useCallback, useRef } from 'react'
import { haptic } from '../lib/native'
import { nearestStop, type LevelScale } from '../lib/levels'

interface Props {
  scale: LevelScale
  value: number
  onChange: (v: number) => void
}

/**
 * StepControl — one detented dial from LevelScale. Reads like a machined
 * instrument, not a slider: the label is engraved on the left, the current
 * STOP NAME sits on the right where a number used to be, and the track snaps
 * between discrete etched detents with a haptic tick. Never shows a 0–100
 * value. The engine value stays numeric underneath (scale.values).
 */
export default function StepControl({ scale, value, onChange }: Props) {
  const trackRef = useRef<HTMLDivElement>(null)
  const lastIndex = useRef<number>(nearestStop(scale, value))

  const count = scale.stops.length
  const index = nearestStop(scale, value)
  const stopName = scale.stops[index]

  /** commit a stop index; fire a tick only when it actually changes */
  const commit = useCallback(
    (next: number) => {
      const clamped = Math.max(0, Math.min(count - 1, next))
      if (clamped !== lastIndex.current) {
        lastIndex.current = clamped
        haptic('light')
        onChange(scale.values[clamped])
      }
    },
    [count, onChange, scale.values],
  )

  /** map a client-x on the rail to the nearest stop index */
  const indexFromClientX = useCallback(
    (clientX: number): number => {
      const el = trackRef.current
      if (!el) return index
      const rect = el.getBoundingClientRect()
      const frac = rect.width > 0 ? (clientX - rect.left) / rect.width : 0
      return Math.round(Math.max(0, Math.min(1, frac)) * (count - 1))
    },
    [count, index],
  )

  const onPointerDown = useCallback(
    (e: React.PointerEvent) => {
      e.preventDefault()
      lastIndex.current = index
      ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
      commit(indexFromClientX(e.clientX))
    },
    [commit, index, indexFromClientX],
  )

  const onPointerMove = useCallback(
    (e: React.PointerEvent) => {
      if (e.buttons === 0) return
      commit(indexFromClientX(e.clientX))
    },
    [commit, indexFromClientX],
  )

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      let next = index
      if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') next = index - 1
      else if (e.key === 'ArrowRight' || e.key === 'ArrowUp') next = index + 1
      else if (e.key === 'Home') next = 0
      else if (e.key === 'End') next = count - 1
      else return
      e.preventDefault()
      commit(next)
    },
    [commit, count, index],
  )

  return (
    <div className="select-none">
      {/* engraved header row: label left, current stop name where a number was */}
      <div className="flex items-baseline justify-between mb-2">
        <span className="font-mono text-[10px] font-medium uppercase tracking-[0.16em] text-ink-soft [text-shadow:0_1px_0_rgba(255,255,255,0.7)]">
          {scale.label}
        </span>
        <span className="font-mono text-[11px] font-medium uppercase tracking-[0.12em] text-ink [text-shadow:0_1px_0_rgba(255,255,255,0.6)]">
          {stopName}
        </span>
      </div>

      {/* detented track */}
      <div
        ref={trackRef}
        role="slider"
        tabIndex={0}
        aria-label={scale.label}
        aria-valuemin={0}
        aria-valuemax={count - 1}
        aria-valuenow={index}
        aria-valuetext={stopName}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onKeyDown={onKeyDown}
        className="relative h-8 cursor-pointer touch-none rounded-md outline-none focus-visible:ring-2 focus-visible:ring-violet/50"
      >
        {/* recessed machined channel the stops are milled into */}
        <span
          aria-hidden
          className="pointer-events-none absolute left-0 right-0 top-1/2 -translate-y-1/2 h-[5px] rounded-full"
          style={{
            background: 'rgb(60 42 24 / 0.05)',
            boxShadow: 'inset 0 1px 2px rgb(60 42 24 / 0.28), inset 0 -1px 0 rgb(255 255 255 / 0.55)',
          }}
        />
        {/* the detent bed: tall machined marks, inset into the panel. There is
            deliberately NO continuous fill bar — the marks read as stops you
            snap between, not a fader you drag anywhere. */}
        {scale.stops.map((_, i) => {
          const frac = count > 1 ? i / (count - 1) : 0
          const isActive = i === index
          const passed = i < index
          return (
            <span
              key={i}
              aria-hidden
              className="pointer-events-none absolute top-1/2"
              style={{ left: `calc(${frac * 100}% ${frac === 0 ? '+ 2px' : frac === 1 ? '- 2px' : ''})`, transform: 'translate(-50%, -50%)' }}
            >
              {isActive ? (
                // active stop = a machined puck: red fill, glossy top edge,
                // shadowed underside, warm ring + drop so it sits proud of the groove
                <span className="block h-[17px] w-[17px] rounded-full bg-violet ring-1 ring-[rgb(60_42_24_/_0.35)] shadow-[inset_0_1px_0_rgb(255_255_255_/_0.55),inset_0_-2px_3px_rgb(120_18_8_/_0.55),0_2px_5px_rgb(60_42_24_/_0.45)]" />
              ) : (
                // etched detent — tall notch; passed marks read violet, upcoming ink
                <span
                  className="block w-[2px] rounded-full"
                  style={{
                    height: passed ? '15px' : '11px',
                    background: passed ? 'rgb(224 57 43 / 0.95)' : 'rgb(60 42 24 / 0.3)',
                    boxShadow: 'inset 0 1px 0 rgb(255 255 255 / 0.5)',
                  }}
                />
              )}
            </span>
          )
        })}
      </div>
    </div>
  )
}
