import { useState } from 'react'
import { IconCheck } from './icons'
import StepControl from './StepControl'
import { LEVEL_SCALES } from '../lib/levels'
import { QUICK_PRESETS, type CameraStyle, type StyleParams } from '../lib/styles'
import { useApp } from '../lib/store'

interface Props {
  style: CameraStyle
  params: StyleParams
  onChange: (p: StyleParams) => void
}

export default function AdjustmentPanel({ style, params, onChange }: Props) {
  const { savePreset } = useApp()
  const [activePreset, setActivePreset] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  return (
    <div className="space-y-6">
      {/* recipes — recessed engraved plates milled into the panel, not pills */}
      <div>
        <p className="font-mono text-[10px] font-medium uppercase tracking-[0.16em] text-fog [text-shadow:0_1px_0_rgb(0_0_0/0.4)] mb-2.5">
          Recipes
        </p>
        <div className="grid grid-cols-3 gap-1.5 rounded-[12px] bg-black/20 p-1.5 shadow-[inset_0_1px_2px_rgb(0_0_0/0.45)]">
          {QUICK_PRESETS.map((p) => {
            const on = activePreset === p.id
            return (
              <button
                key={p.id}
                onClick={() => {
                  setActivePreset(p.id)
                  onChange(p.apply({ ...style.defaults }))
                }}
                aria-pressed={on}
                className={`h-8 rounded-[8px] font-mono text-[10.5px] font-medium uppercase tracking-[0.1em] transition-all duration-150 active:scale-[0.97] ${
                  on
                    ? 'bg-violet text-white shadow-[0_1px_3px_rgb(76_29_149_/_0.4),inset_0_1px_0_rgb(255_255_255_/_0.3)]'
                    : 'text-ink-soft [text-shadow:0_1px_0_rgb(0_0_0/0.35)] hover:bg-white/[0.06]'
                }`}
              >
                {p.name}
              </button>
            )
          })}
        </div>
      </div>

      {/* etched divider between preset shelf and the dials */}
      <div
        aria-hidden
        className="h-px bg-white/[0.07] shadow-[0_1px_0_rgb(0_0_0/0.4)]"
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
        <button
          onClick={() => {
            setActivePreset(null)
            onChange({ ...style.defaults })
          }}
          className="font-mono text-[10px] font-medium uppercase tracking-[0.14em] text-fog hover:text-ink transition-colors"
        >
          Reset to {style.name}
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
