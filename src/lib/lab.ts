import { CAMERA_STYLES, type CameraStyle, type StyleParams } from './styles'

/**
 * "The Lab" — deterministic daily mechanics. Everything derives from the date,
 * so every user worldwide sees the same Today's Stock (screenshots match =
 * free social proof) and nothing needs a server.
 */

const LAB_KEY = 'lensmood.lab.v1'

interface LabState {
  dailyClaimed: string | null
}

function readLab(): LabState {
  try {
    const raw = JSON.parse(localStorage.getItem(LAB_KEY) ?? '{}') as Partial<LabState>
    return { dailyClaimed: raw.dailyClaimed ?? null }
  } catch {
    return { dailyClaimed: null }
  }
}

function writeLab(s: LabState) {
  try {
    localStorage.setItem(LAB_KEY, JSON.stringify(s))
  } catch {
    /* storage unavailable */
  }
}

export const todayKey = () => new Date().toISOString().slice(0, 10)

/** FNV-1a — tiny, stable string hash */
function fnv1a(str: string): number {
  let h = 0x811c9dc5
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

/** the whole world gets the same stock today — pass a Date (or YYYY-MM-DD key) to peek at another day */
export function dailyStyle(date: string | Date = todayKey()): CameraStyle {
  const key = typeof date === 'string' ? date : date.toISOString().slice(0, 10)
  return CAMERA_STYLES[fnv1a(key) % CAMERA_STYLES.length]
}

/** date-seeded recipe: the style's defaults, nudged so each day tastes different */
export function dailyRecipe(date = todayKey()): StyleParams {
  const style = dailyStyle(date)
  const jitter = (key: string, spread: number) => {
    const r = (fnv1a(date + key) % 1000) / 1000 // 0..1
    return Math.round((r - 0.5) * 2 * spread)
  }
  const clamp = (v: number) => Math.max(0, Math.min(100, v))
  const d = style.defaults
  return {
    ...d,
    intensity: clamp(d.intensity + jitter('i', 10)),
    grain: clamp(d.grain + jitter('g', 12)),
    warmth: clamp(d.warmth + jitter('w', 8)),
    contrast: clamp(d.contrast + jitter('c', 8)),
    shadows: clamp(d.shadows + jitter('s', 10)),
  }
}

export const isDailyClaimed = () => readLab().dailyClaimed === todayKey()

export const claimDaily = () => writeLab({ ...readLab(), dailyClaimed: todayKey() })

/** genuinely random slider jitter — surprise is the point of a blind shot */
export function jitterParams(style: CameraStyle): StyleParams {
  const clamp = (v: number) => Math.max(0, Math.min(100, v))
  const j = (spread: number) => Math.round((Math.random() - 0.5) * 2 * spread)
  const d = style.defaults
  return {
    ...d,
    intensity: clamp(d.intensity + j(12)),
    grain: clamp(d.grain + j(14)),
    warmth: clamp(d.warmth + j(10)),
    contrast: clamp(d.contrast + j(8)),
    shadows: clamp(d.shadows + j(10)),
  }
}
