import type { StyleParams } from './styles'

/**
 * Levels — every fine-tune control speaks its own vocabulary instead of
 * 0–100 numbers. A grain that reads "Chunky" is an opinion; a grain that
 * reads "62" is a config file. Params stay numeric underneath so presets,
 * deep links and the engine are untouched — the stops are the interface.
 */

export interface LevelScale {
  /** which StyleParams field this scale drives */
  param: keyof StyleParams
  label: string
  /** stop names, low → high */
  stops: string[]
  /** engine value for each stop (same length as stops) */
  values: number[]
}

export const LEVEL_SCALES: LevelScale[] = [
  {
    param: 'intensity',
    label: 'Character',
    stops: ['Trace', 'Soft', 'Balanced', 'Full', 'Pushed'],
    values: [25, 45, 65, 82, 100],
  },
  {
    param: 'grain',
    label: 'Grain',
    stops: ['None', 'Fine', 'Soft', 'Heavy', 'Chunky'],
    values: [0, 18, 38, 62, 85],
  },
  {
    param: 'contrast',
    label: 'Contrast',
    stops: ['Flat', 'Gentle', 'Neutral', 'Punchy', 'Hard'],
    values: [22, 36, 50, 66, 82],
  },
  {
    param: 'warmth',
    label: 'Temperature',
    stops: ['Cold', 'Cool', 'Neutral', 'Warm', 'Golden'],
    values: [12, 32, 50, 68, 88],
  },
  {
    param: 'flash',
    label: 'Flash',
    stops: ['Off', 'Kiss', 'Fill', 'Party', 'Blast'],
    values: [0, 25, 50, 72, 95],
  },
  {
    param: 'shadows',
    label: 'Shadows',
    stops: ['Open', 'Lifted', 'Deep', 'Crushed'],
    values: [12, 35, 62, 86],
  },
  {
    param: 'smoothing',
    label: 'Skin',
    stops: ['Off', 'Touch', 'Studio'],
    values: [0, 30, 60],
  },
]

/** index of the stop closest to an arbitrary engine value (presets, jitter, links) */
export const nearestStop = (scale: LevelScale, value: number): number => {
  let best = 0
  let bestDist = Infinity
  scale.values.forEach((v, i) => {
    const d = Math.abs(v - value)
    if (d < bestDist) {
      bestDist = d
      best = i
    }
  })
  return best
}
