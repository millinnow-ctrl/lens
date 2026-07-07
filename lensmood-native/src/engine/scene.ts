/**
 * Scene — the light meter behind the lens (React Native + Skia port).
 *
 * One tiny deterministic analysis pass per image (a <=96px downscale) that
 * tells the engine what a real camera's electronics would know about the
 * scene: how bright it is, what color the light is, where the actual light
 * sources sit, and how bright the subject's face is. The render pipeline
 * responds the way film hardware does — metered exposure before the tone
 * curve, illuminant-relative color, halation that lives on the lights.
 *
 * Everything here is closed-form math on pixels. Nothing generative. This is
 * a byte-for-byte port of the web app's src/lib/scene.ts, with the only
 * difference being the pixel source: instead of a DOM <canvas>.getImageData()
 * we downscale the SkImage into an offscreen Skia surface and readPixels().
 * The RGBA / row-major pixel layout is identical, so the math is verbatim.
 */

import {
  Skia,
  ColorType,
  AlphaType,
  type SkImage,
} from '@shopify/react-native-skia'
import {
  NEUTRAL_SCENE,
  type Focal,
  type LightSource,
  type SceneProfile,
} from '@/engine/types'

/** the meter's one-word reading of a scene — shown in the studio viewfinder
 *  so the person can see the lens thinking. Rule-based, from the profile. */
export function sceneLabel(p: SceneProfile): string {
  if (!p.analyzed) return 'READING'
  if (p.key < 0.1) return 'NIGHT'
  if (p.faceLum != null && p.key - p.faceLum > 0.15) return 'BACKLIT'
  if (p.key < 0.26) return 'LOW LIGHT'
  // cast direction only — the meter can't know tungsten from golden hour,
  // so it says what it actually measured and never guesses wrong
  if (p.illum[2] > 1.18) return 'WARM LIGHT'
  if (p.illum[0] > 1.18) return 'COOL LIGHT'
  if (p.sat < 0.1) return 'MUTED'
  if (p.p99 - p.p01 < 0.45) return 'FLAT'
  return 'DAYLIGHT'
}

const THUMB = 96
const LUMA_R = 0.299
const LUMA_G = 0.587
const LUMA_B = 0.114

/* profile cache — keyed on the SkImage identity + the focal reading.
   Slider re-renders reuse the profile (no flicker), and the 1280px preview
   and larger export of the same image share one profile. */
const cache = new WeakMap<object, { focalKey: string; profile: SceneProfile }>()

const focalKeyOf = (focal?: Focal | null) =>
  focal ? `${focal.x.toFixed(3)},${focal.y.toFixed(3)},${focal.r.toFixed(3)}` : 'none'

/**
 * Analyze a scene. Pure and synchronous — ~1ms on a 96px thumb.
 * Results are cached per (image, focal) so repeat calls are free.
 */
export function analyzeScene(source: SkImage, focal?: Focal | null): SceneProfile {
  const fKey = focalKeyOf(focal)
  const hit = cache.get(source as object)
  if (hit && hit.focalKey === fKey) return hit.profile

  let profile: SceneProfile
  try {
    profile = analyze(source, focal ?? null)
  } catch {
    profile = NEUTRAL_SCENE
  }
  // a not-yet-decoded frame reads as pure black — don't let it lock the
  // exposure; return neutral now and analyze again next call
  if (profile.key < 0.004 && profile.p99 < 0.02) return NEUTRAL_SCENE
  cache.set(source as object, { focalKey: fKey, profile })
  return profile
}

/** downscale the SkImage into a THUMB-sized offscreen surface and pull the
 *  RGBA bytes back (unpremultiplied straight alpha — matches getImageData). */
function thumbPixels(source: SkImage, w: number, h: number): Uint8Array | null {
  const surface = Skia.Surface.MakeOffscreen(w, h)
  if (!surface) return null
  const canvas = surface.getCanvas()
  const paint = Skia.Paint()
  paint.setAntiAlias(true)
  canvas.drawImageRect(
    source,
    Skia.XYWHRect(0, 0, source.width(), source.height()),
    Skia.XYWHRect(0, 0, w, h),
    paint,
  )
  surface.flush()
  const snap = surface.makeImageSnapshot()
  const px = snap.readPixels(0, 0, {
    width: w,
    height: h,
    colorType: ColorType.RGBA_8888,
    alphaType: AlphaType.Unpremul,
  })
  return px instanceof Uint8Array ? px : null
}

function analyze(source: SkImage, focal: Focal | null): SceneProfile {
  const sw = source.width()
  const sh = source.height()
  if (!sw || !sh) return NEUTRAL_SCENE

  const scale = THUMB / Math.max(sw, sh)
  const w = Math.max(2, Math.round(sw * scale))
  const h = Math.max(2, Math.round(sh * scale))
  const px = thumbPixels(source, w, h)
  if (!px) return NEUTRAL_SCENE
  const n = w * h

  /* ---- pass 1: luminance stats + shades-of-gray illuminant (p = 6) ---- */
  const hist = new Uint32Array(64)
  let logSum = 0
  let er = 0
  let eg = 0
  let eb = 0
  let mid = 0
  let satSum = 0
  let satCnt = 0
  const lum = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const r = px[i * 4] / 255
    const g = px[i * 4 + 1] / 255
    const b = px[i * 4 + 2] / 255
    const L = LUMA_R * r + LUMA_G * g + LUMA_B * b
    lum[i] = L
    logSum += Math.log(Math.max(L, 0.001))
    hist[Math.min(63, (L * 64) | 0)]++
    // saturation census — near-black pixels excluded (their hue is noise)
    const mx = r > g ? (r > b ? r : b) : g > b ? g : b
    if (mx > 0.06) {
      const mn = r < g ? (r < b ? r : b) : g < b ? g : b
      satSum += (mx - mn) / mx
      satCnt++
    }
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

  return {
    analyzed: true,
    key,
    p01,
    p50,
    p99,
    illum,
    sat: satCnt > n * 0.05 ? satSum / satCnt : 0.35,
    lights,
    faceLum,
  }
}
