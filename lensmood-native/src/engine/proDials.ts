/**
 * The LM-1's dial deck — the contract between the Pro Camera's controls and
 * the engine. iPhones expose no manual aperture/ISO/EV to any app (aperture
 * is physically fixed), so the dials do what makes them real here: they set
 * how the LM-1 engine develops the shot.
 */

import type { LensResponse } from '@/engine/types'

export const F_STOPS = [1.2, 1.8, 2.8, 4, 5.6, 8, 11, 16] as const
export const ISOS = [100, 200, 400, 800, 1600, 3200, 6400] as const
export const EVS = [-2, -1.3, -0.7, -0.3, 0, 0.3, 0.7, 1.3, 2] as const
export const WBS = ['AWB', 'DAYLIGHT', 'CLOUDY', 'TUNGSTEN', 'FLUOR'] as const

export interface ProDials {
  f: number
  iso: number
  ev: number
  wb: (typeof WBS)[number]
}

export interface ProEngineSettings {
  readout: string
  lensOverride: Partial<LensResponse>
  params: { grain: number; warmth: number }
}

const clampNum = (v: unknown, list: readonly number[], fallback: number) =>
  typeof v === 'number' && list.includes(v) ? v : fallback

/** parse dial settings that traveled through a router param — never trust it */
export function parseProDials(raw: string | undefined): ProDials | null {
  if (!raw) return null
  try {
    const p = JSON.parse(raw) as Partial<ProDials>
    return {
      f: clampNum(p.f, F_STOPS, 2.8),
      iso: clampNum(p.iso, ISOS, 200),
      ev: clampNum(p.ev, EVS, 0),
      wb: WBS.includes(p.wb as ProDials['wb']) ? (p.wb as ProDials['wb']) : 'AWB',
    }
  } catch {
    return null
  }
}

/** how each dial maps into a develop */
export function dialsToEngine(d: ProDials): ProEngineSettings {
  const wbWarmth = { AWB: 50, DAYLIGHT: 58, CLOUDY: 66, TUNGSTEN: 34, FLUOR: 42 }[d.wb]
  return {
    readout: `ƒ${d.f} · ISO ${d.iso} · ${d.ev > 0 ? '+' : ''}${d.ev.toFixed(1)} EV · ${d.wb}`,
    lensOverride: {
      // wide open = strong subject separation, stopped down = everything sharp
      dof: Math.min(1, Math.max(0.06, 1.45 / d.f)),
      meterBias: d.ev,
      // high ISO pushes texture; the engine's denoise stands down as it climbs
      autoIso: Math.min(1, Math.log2(d.iso / 100) / 6 + 0.15),
      shadowDenoise: Math.max(0.2, 0.95 - Math.log2(d.iso / 100) * 0.12),
      // a manual WB disables auto white balance — real camera behavior
      awb: d.wb === 'AWB' ? 0.85 : 0,
    },
    params: {
      grain: Math.round(Math.min(70, Math.max(0, Math.log2(d.iso / 100) * 11.5))),
      warmth: wbWarmth,
    },
  }
}
