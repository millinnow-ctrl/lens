import { useState } from 'react'
import { IconCheck } from './icons'
import { QUICK_PRESETS, type CameraStyle, type StyleParams } from '../lib/styles'
import { useApp } from '../lib/store'

const SLIDERS: { key: keyof StyleParams; label: string }[] = [
  { key: 'intensity', label: 'Style intensity' },
  { key: 'grain', label: 'Grain' },
  { key: 'contrast', label: 'Contrast' },
  { key: 'warmth', label: 'Warmth' },
  { key: 'flash', label: 'Flash strength' },
  { key: 'shadows', label: 'Shadow depth' },
  { key: 'smoothing', label: 'Skin smoothing' },
]

interface Props {
  style: CameraStyle
  params: StyleParams
  onChange: (p: StyleParams) => void
}

export default function AdjustmentPanel({ style, params, onChange }: Props) {
  const { savePreset } = useApp()
  const [activePreset, setActivePreset] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  const set = (key: keyof StyleParams, value: number) => {
    setActivePreset(null)
    onChange({ ...params, [key]: value })
  }

  return (
    <div className="space-y-5">
      {/* quick presets */}
      <div>
        <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-fog mb-2.5">Quick presets</p>
        <div className="grid grid-cols-3 gap-2">
          {QUICK_PRESETS.map((p) => (
            <button
              key={p.id}
              onClick={() => {
                setActivePreset(p.id)
                onChange(p.apply({ ...style.defaults }))
              }}
              className={`btn btn-sm w-full ${activePreset === p.id ? 'btn-primary' : 'btn-outline'}`}
            >
              {p.name}
            </button>
          ))}
        </div>
      </div>

      {/* sliders */}
      <div className="space-y-3.5">
        {SLIDERS.map(({ key, label }) => (
          <label key={key} className="block">
            <span className="flex items-baseline justify-between mb-1">
              <span className="text-[13px] font-medium text-ink-soft">{label}</span>
              <span className="value-mono">{params[key]}</span>
            </span>
            <input
              type="range"
              min={0}
              max={100}
              value={params[key]}
              onChange={(e) => set(key, Number(e.target.value))}
              className="lm-slider"
              style={{ ['--fill' as string]: `${params[key]}%` }}
              aria-label={label}
            />
          </label>
        ))}
      </div>

      <div className="flex items-center justify-between gap-3 pt-1">
        <button
          onClick={() => {
            setActivePreset(null)
            onChange({ ...style.defaults })
          }}
          className="text-[13px] font-medium text-fog hover:text-ink transition-colors"
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
