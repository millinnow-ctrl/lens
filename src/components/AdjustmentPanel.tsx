import { useEffect, useRef, useState } from 'react'
import { IconCheck, IconReset, IconSpinner } from './icons'
import StepControl from './StepControl'
import { LEVEL_SCALES } from '../lib/levels'
import { QUICK_PRESETS, type CameraStyle, type StyleParams } from '../lib/styles'
import { useApp } from '../lib/store'

interface Props {
  style: CameraStyle
  params: StyleParams
  onChange: (p: StyleParams) => void
  /** notify the preview to play a brief "re-developing" beat on a recipe change */
  onReprocess?: () => void
}

/** how long the develop indicator lingers after a recipe change (ms) */
const DEVELOP_MS = 520

export default function AdjustmentPanel({ style, params, onChange, onReprocess }: Props) {
  const { savePreset } = useApp()
  const [activePreset, setActivePreset] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  /** id of the control currently "developing" (a preset id, or 'reset') */
  const [busy, setBusy] = useState<string | null>(null)
  const busyTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(
    () => () => {
      if (busyTimer.current) clearTimeout(busyTimer.current)
    },
    [],
  )

  /* apply a recipe and run the develop beat: the new params land immediately
     (the preview re-renders now), and the spinner marks the pass as work in
     flight for half a second — the engine really is re-metering the frame */
  const develop = (id: string, next: StyleParams) => {
    onChange(next)
    onReprocess?.()
    setBusy(id)
    if (busyTimer.current) clearTimeout(busyTimer.current)
    busyTimer.current = setTimeout(() => setBusy(null), DEVELOP_MS)
  }

  return (
    <div className="space-y-6">
      {/* recipes — recessed engraved plates milled into the panel, not pills */}
      <div>
        <p className="font-mono text-[10px] font-medium uppercase tracking-[0.16em] text-fog [text-shadow:0_1px_0_rgba(255,255,255,0.7)] mb-2.5">
          Recipes
        </p>
        <div className="flex flex-wrap gap-2">
          {QUICK_PRESETS.map((p) => {
            const on = activePreset === p.id
            const loading = busy === p.id
            return (
              <button
                key={p.id}
                onClick={() => {
                  setActivePreset(p.id)
                  develop(p.id, p.apply({ ...style.defaults }))
                }}
                aria-pressed={on}
                aria-busy={loading}
                className={`inline-flex items-center gap-1.5 h-8 px-3 rounded-[7px] font-mono text-[10.5px] font-medium uppercase tracking-[0.1em] border transition-all duration-150 active:scale-[0.97] ${
                  on
                    ? 'bg-ink text-[#fbf6eb] border-ink shadow-[0_1px_3px_rgb(60_42_24_/_0.4),inset_0_1px_0_rgb(255_255_255_/_0.15)]'
                    : 'text-ink-soft border-[rgb(60_42_24/0.22)] hover:border-[rgb(60_42_24/0.4)] bg-transparent'
                }`}
              >
                {loading ? (
                  <IconSpinner size={11} className="lm-spin shrink-0" />
                ) : (
                  on && <span className="w-1.5 h-1.5 rounded-full bg-signal" aria-hidden />
                )}
                {p.name}
              </button>
            )
          })}
        </div>
      </div>

      {/* etched divider between preset shelf and the dials */}
      <div
        aria-hidden
        className="h-px bg-[rgb(23_19_31_/_0.08)] shadow-[0_1px_0_rgba(255,255,255,0.7)]"
      />

      {/* detented dials — fixed order, never reflow (muscle memory) */}
      <div className="space-y-5">
        {LEVEL_SCALES.map((scale) => (
          <StepControl
            key={scale.param}
            scale={scale}
            value={params[scale.param]}
            onChange={(v) => {
              setActivePreset(null)
              onChange({ ...params, [scale.param]: v })
            }}
          />
        ))}
      </div>

      <div className="flex items-center justify-between gap-3 pt-1">
        {/* reset — a real pressable control: a circular wind-back key + label */}
        <button
          onClick={() => {
            setActivePreset(null)
            develop('reset', { ...style.defaults })
          }}
          aria-busy={busy === 'reset'}
          className="group inline-flex items-center gap-2 h-8 pl-1 pr-3 rounded-full border border-[rgb(60_42_24/0.2)] bg-transparent hover:border-[rgb(60_42_24/0.4)] active:scale-[0.97] transition-all duration-150"
        >
          <span className="grid place-items-center w-6 h-6 rounded-full bg-[rgb(60_42_24/0.08)] text-ink-soft group-hover:text-ink transition-colors">
            {busy === 'reset' ? (
              <IconSpinner size={12} className="lm-spin" />
            ) : (
              <IconReset size={13} />
            )}
          </span>
          <span className="font-mono text-[10px] font-medium uppercase tracking-[0.14em] text-fog group-hover:text-ink transition-colors">
            Reset to {style.name}
          </span>
        </button>
        <button
          onClick={() => {
            savePreset(`${style.name} · mine`)
            setSaved(true)
            setTimeout(() => setSaved(false), 1600)
          }}
          className="btn btn-sm btn-outline"
        >
          {saved ? (
            <>
              <IconCheck size={13} /> Saved
            </>
          ) : (
            'Save preset'
          )}
        </button>
      </div>
    </div>
  )
}
