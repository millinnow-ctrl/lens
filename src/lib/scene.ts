/**
 * Scene — the light meter behind the lens.
 *
 * One tiny deterministic analysis pass per image (a ≤96px downscale) that
 * tells the engine what a real camera's electronics would know about the
 * scene: how bright it is, what color the light is, where the actual light
 * sources sit, and how bright the subject's face is. The render pipeline
 * responds the way film hardware does — metered exposure before the tone
 * curve, illuminant-relative color, halation that lives on the lights.
 *
 * Everything here is closed-form math on pixels. Nothing generative.
 */

import type { Focal } from './focal'

export interface LightSource {
  /** normalized center, 0..1 of frame */
  x: number
  y: number
  /** blob radius as a fraction of the longest edge */
  r: number
  /** 0..1 — how hot the blob's peak burns above the specular threshold */
  intensity: number
  /** the light's true color, sampled on the glow annulus around the clipped
   *  core (the core itself is blown white) — [r,g,b] 0..1 */
  tint: [number, number, number]
}

export interface SceneProfile {
  /** false for the neutral fallback — adaptive passes that would otherwise
   *  misread the placeholder percentiles must check this */
  analyzed: boolean
  /** log-average luminance, 0..1 — the meter's reading of the scene key */
  key: number
  p01: number
  p50: number
  p99: number
  /** white-balance gains [r, g, b], luma-preserving (never change exposure) */
  illum: [number, number, number]
  /** up to 5 detected light sources, largest energy first */
  lights: LightSource[]
  /** mean luminance under the face ellipse, when a face was found */
  faceLum: number | null
}

/** neutral profile — what `scene: null` and failed analysis fall back to */
export const NEUTRAL_SCENE: SceneProfile = {
  analyzed: false,
  key: 0.4,
  p01: 0,
  p50: 0.4,
  p99: 1,
  illum: [1, 1, 1],
  lights: [],
  faceLum: null,
}

type Source = HTMLImageElement | HTMLCanvasElement | ImageBitmap | HTMLVideoElement

const THUMB = 96
const LUMA_R = 0.299
const LUMA_G = 0.587
const LUMA_B = 0.114

/* profile cache — keyed on the source element identity + the focal reading.
   Slider re-renders reuse the profile (no flicker), a video element keeps
   its first analyzed frame for the whole clip, and the 1280px preview and
   1600px export of the same <img> share one profile. */
const cache = new WeakMap<object, { focalKey: string; profile: SceneProfile }>()

const focalKeyOf = (focal?: Focal | null) =>
  focal ? `${focal.x.toFixed(3)},${focal.y.toFixed(3)},${focal.r.toFixed(3)}` : 'none'

/**
 * Analyze a scene. Pure and synchronous — ~1ms on a 96px thumb.
 * Results are cached per (source, focal) so repeat calls are free.
 */
export function analyzeScene(source: Source, focal?: Focal | null): SceneProfile {
  const fKey = focalKeyOf(focal)
  const hit = cache.get(source as object)
  if (hit && hit.focalKey === fKey) return hit.profile

  let profile: SceneProfile
  try {
    profile = analyze(source, focal ?? null)
  } catch {
    profile = NEUTRAL_SCENE
  }
  // an undecoded video frame reads as pure black — don't let it lock the
  // clip's exposure; return neutral now and analyze again next call
  if (profile.key < 0.004 && profile.p99 < 0.02) return NEUTRAL_SCENE
  cache.set(source as object, { focalKey: fKey, profile })
  return profile
}

function analyze(source: Source, focal: Focal | null): SceneProfile {
  const sw =
    source instanceof HTMLVideoElement
      ? source.videoWidth
      : (source as HTMLImageElement).naturalWidth || (source as HTMLCanvasElement).width
  const sh =
    source instanceof HTMLVideoElement
      ? source.videoHeight
      : (source as HTMLImageElement).naturalHeight || (source as HTMLCanvasElement).height
  if (!sw || !sh) return NEUTRAL_SCENE

  const scale = THUMB / Math.max(sw, sh)
  const w = Math.max(2, Math.round(sw * scale))
  const h = Math.max(2, Math.round(sh * scale))
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) return NEUTRAL_SCENE
  ctx.drawImage(source as CanvasImageSource, 0, 0, w, h)
  const px = ctx.getImageData(0, 0, w, h).data
  const n = w * h

  /* ---- pass 1: luminance stats + shades-of-gray illuminant (p = 6) ---- */
  const hist = new Uint32Array(64)
  let logSum = 0
  let er = 0
  let eg = 0
  let eb = 0
  let mid = 0
  const lum = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const r = px[i * 4] / 255
    const g = px[i * 4 + 1] / 255
    const b = px[i * 4 + 2] / 255
    const L = LUMA_R * r + LUMA_G * g + LUMA_B * b
    lum[i] = L
    logSum += Math.log(Math.max(L, 0.001))
    hist[Math.min(63, (L * 64) | 0)]++
    if (L > 0.04 && L < 0.96) {
      // Minkowski p=6 — between gray-world and white-patch; clipped pixels
      // excluded so a blown sky doesn't read as "blue light"
      const r6 = r * r * r
      const g6 = g * g * g
      const b6 = b * b * b
      er += r6 * r6
      eg += g6 * g6
      eb += b6 * b6
      mid++
    }
  }
  const key = Math.exp(logSum / n)

  const pct = (q: number): number => {
    const target = q * n
    let acc = 0
    for (let bin = 0; bin < 64; bin++) {
      acc += hist[bin]
      if (acc >= target) return (bin + 0.5) / 64
    }
    return 1
  }
  const p01 = pct(0.01)
  const p50 = pct(0.5)
  const p99 = pct(0.99)

  let illum: [number, number, number] = [1, 1, 1]
  if (mid > n * 0.05) {
    const mr = Math.pow(er / mid, 1 / 6)
    const mg = Math.pow(eg / mid, 1 / 6)
    const mb = Math.pow(eb / mid, 1 / 6)
    if (mr > 0.001 && mg > 0.001 && mb > 0.001) {
      let gr = mg / mr
      let gb = mg / mb
      // luma-preserving: WB must never change exposure (that's the meter's job)
      const lumaGain = LUMA_R * gr + LUMA_G + LUMA_B * gb
      gr /= lumaGain
      gb /= lumaGain
      illum = [gr, 1 / lumaGain, gb]
    }
  }

  /* ---- pass 2: light sources — connected blobs above the specular knee ---- */
  const T = Math.max(0.9, 0.98 * p99)
  let bright = 0
  for (let i = 0; i < n; i++) if (lum[i] >= T) bright++
  let lights: LightSource[] = []
  // >20% of the frame above threshold = ambient brightness (sky, wall), not sources
  if (bright > 0 && bright < n * 0.2) {
    const label = new Int32Array(n).fill(-1)
    const blobs: { mass: number; sx: number; sy: number; count: number; peak: number }[] = []
    const stack: number[] = []
    for (let i = 0; i < n; i++) {
      if (lum[i] < T || label[i] !== -1) continue
      const id = blobs.length
      const blob = { mass: 0, sx: 0, sy: 0, count: 0, peak: 0 }
      blobs.push(blob)
      stack.length = 0
      stack.push(i)
      label[i] = id
      while (stack.length) {
        const j = stack.pop()!
        const jx = j % w
        const jy = (j / w) | 0
        blob.mass += lum[j] - T
        if (lum[j] > blob.peak) blob.peak = lum[j]
        blob.sx += jx
        blob.sy += jy
        blob.count++
        if (jx > 0 && label[j - 1] === -1 && lum[j - 1] >= T) (label[j - 1] = id), stack.push(j - 1)
        if (jx < w - 1 && label[j + 1] === -1 && lum[j + 1] >= T) (label[j + 1] = id), stack.push(j + 1)
        if (jy > 0 && label[j - w] === -1 && lum[j - w] >= T) (label[j - w] = id), stack.push(j - w)
        if (jy < h - 1 && label[j + w] === -1 && lum[j + w] >= T) (label[j + w] = id), stack.push(j + w)
      }
    }
    const kept = blobs
      .filter((b) => b.count >= 2)
      .sort((a, b) => b.mass - a.mass)
      .slice(0, 5)
      .map((b) => ({
        x: b.sx / b.count,
        y: b.sy / b.count,
        rPx: Math.sqrt(b.count / Math.PI),
        peak: b.peak,
        // tint accumulators — filled by the annulus pass below
        tr: 0,
        tg: 0,
        tb: 0,
        tn: 0,
      }))
    /* the light's color lives in the glow ring AROUND the clipped core (the
       core itself reads pure white) — one cheap pass over the near-bright
       band, attributed to the closest blob within reach */
    if (kept.length) {
      const lo = T * 0.6
      for (let i = 0; i < n; i++) {
        const L = lum[i]
        if (L < lo || L >= T) continue
        const x = i % w
        const y = (i / w) | 0
        for (const k of kept) {
          const dx = x - k.x
          const dy = y - k.y
          const reach = (k.rPx + 2) * 2.5
          if (dx * dx + dy * dy <= reach * reach) {
            k.tr += px[i * 4]
            k.tg += px[i * 4 + 1]
            k.tb += px[i * 4 + 2]
            k.tn++
            break
          }
        }
      }
    }
    lights = kept.map((k) => ({
      x: k.x / w,
      y: k.y / h,
      r: k.rPx / Math.max(w, h),
      intensity: Math.min(1, (k.peak - T) / Math.max(0.02, 1 - T)),
      tint:
        k.tn > 3
          ? ([k.tr / k.tn / 255, k.tg / k.tn / 255, k.tb / k.tn / 255] as [number, number, number])
          : ([1, 0.72, 0.45] as [number, number, number]), // warm default
    }))
  }

  /* ---- pass 3: face luminance under the focal ellipse ---- */
  let faceLum: number | null = null
  if (focal) {
    const cx = focal.x * w
    const cy = focal.y * h
    const rr = Math.max(2, focal.r * Math.max(w, h))
    let sum = 0
    let cnt = 0
    const x0 = Math.max(0, Math.floor(cx - rr))
    const x1 = Math.min(w - 1, Math.ceil(cx + rr))
    const y0 = Math.max(0, Math.floor(cy - rr))
    const y1 = Math.min(h - 1, Math.ceil(cy + rr))
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const dx = (x - cx) / rr
        const dy = (y - cy) / (rr * 1.25) // faces are taller than wide
        if (dx * dx + dy * dy <= 1) {
          sum += lum[y * w + x]
          cnt++
        }
      }
    }
    if (cnt > 4) faceLum = sum / cnt
  }

  return { analyzed: true, key, p01, p50, p99, illum, lights, faceLum }
}
