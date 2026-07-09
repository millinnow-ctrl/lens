import type { CameraStyle, LensResponse, StyleParams } from './styles'
import { analyzeScene, NEUTRAL_SCENE, type SceneProfile } from './scene'

export interface RenderOptions {
  /** longest edge of the output; source is downscaled to fit */
  maxSize?: number
  watermark?: boolean
  /** reuse this canvas instead of allocating one (video frame loops) */
  target?: HTMLCanvasElement
  /** jitter the grain pattern per call so video grain flickers like film */
  animateGrain?: boolean
  /** face lock (normalized) — flash centers here, smoothing stays on skin */
  focal?: { x: number; y: number; r: number } | null
  /** precomputed scene profile; omit to analyze (cached), null to disable
   *  the adaptive lens entirely */
  scene?: SceneProfile | null
  /** draw the instant-film paper frame (default true); the compare view
   *  renders a frameless companion so the wipe stays pixel-aligned */
  frame?: boolean
  /** per-shot dial overrides from the Pro Camera (ƒ→dof, EV→meterBias,
   *  ISO→autoIso, WB→awb) — merged over the stock's lens response */
  lensOverride?: Partial<LensResponse>
  /** seconds into a tape — when set, timestamped stocks burn a counting
   *  REC timecode instead of a static clock */
  time?: number
}

/** how the glass responds to a scene when the stock doesn't say otherwise */
const DEFAULT_LENS: Required<LensResponse> = {
  meterBias: 0,
  meterStrength: 0.55,
  faceWeight: 0.65,
  awb: 0.6,
  awbClamp: 0.3,
  lightHalation: 0.7,
  toneMap: 0.5,
  dof: 0.4,
  autoIso: 0.5,
  clarity: 0,
  vibrance: 0.45,
  shadowDenoise: 0.6,
  skinGlow: 0.3,
  flashStrength: 0,
  flashFalloff: 0.18,
  flashSpecular: 0.4,
  flashCool: 0.25,
  flashSpread: 1.4,
  keyVec: [0, 0],
  keyHardness: 0.35,
  fillCeiling: 0.86,
  shadowFill: 0.55,
}

type Source = HTMLImageElement | HTMLCanvasElement | ImageBitmap | HTMLVideoElement

/* ---------------------------------------------------------------- noise */

let noiseTile: HTMLCanvasElement | null = null

function getNoiseTile(): HTMLCanvasElement {
  if (noiseTile) return noiseTile
  const size = 192
  const c = document.createElement('canvas')
  c.width = size
  c.height = size
  const ctx = c.getContext('2d')!
  const img = ctx.createImageData(size, size)
  const d = img.data
  for (let i = 0; i < d.length; i += 4) {
    const v = 96 + Math.random() * 64 // mid-gray noise for overlay blending
    d[i] = v
    d[i + 1] = v
    d[i + 2] = v
    d[i + 3] = 255
  }
  ctx.putImageData(img, 0, 0)
  noiseTile = c
  return c
}

/* ------------------------------------------------------------- helpers */

const srcWidth = (s: Source) =>
  s instanceof HTMLVideoElement
    ? s.videoWidth
    : 'naturalWidth' in s
      ? s.naturalWidth || s.width
      : s.width
const srcHeight = (s: Source) =>
  s instanceof HTMLVideoElement
    ? s.videoHeight
    : 'naturalHeight' in s
      ? s.naturalHeight || s.height
      : s.height

function fitted(source: Source, maxSize: number): { w: number; h: number } {
  const sw = srcWidth(source)
  const sh = srcHeight(source)
  const scale = Math.min(1, maxSize / Math.max(sw, sh))
  // `|| 1` guards NaN from zero-dimension sources (0 * Infinity) — a wedged
  // canvas here would strand the develop overlay
  return {
    w: Math.max(1, Math.round(sw * scale) || 1),
    h: Math.max(1, Math.round(sh * scale) || 1),
  }
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t

const hexRgb = (hex: string): [number, number, number] => {
  const n = parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

/** tiny deterministic hash — keeps light leaks stable per style */
const hash32 = (str: string) => {
  let h = 0x811c9dc5
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x)
const smoothstep = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a))
  return t * t * (3 - 2 * t)
}

/** per-channel film transfer: shift ONE dye layer's shadows (sh) and highlights
 *  (hi) independently — cross-process casts, teal-shadow dyes, a highlight
 *  channel that clips before the others. A per-channel transfer function no
 *  single slider produces. Value + result on the 0..255 scale. */
function shapeCh(v: number, sh: number, hi: number): number {
  const t = v / 255
  const ws = 1 - smoothstep(0, 0.5, t)
  const wh = smoothstep(0.5, 1, t)
  return clamp01(t + sh * ws * 0.4 + hi * wh * 0.4) * 255
}

/** RGB (0..255) → HSV; h in degrees 0..360, s/v in 0..1 */
function rgb2hsv(r: number, g: number, b: number): [number, number, number] {
  const mx = Math.max(r, g, b)
  const mn = Math.min(r, g, b)
  const c = mx - mn
  let h = 0
  if (c !== 0) {
    if (mx === r) h = ((g - b) / c) % 6
    else if (mx === g) h = (b - r) / c + 2
    else h = (r - g) / c + 4
    h *= 60
    if (h < 0) h += 360
  }
  return [h, mx === 0 ? 0 : c / mx, mx / 255]
}

/** HSV (deg, 0..1, 0..1) → RGB 0..255 */
function hsv2rgb(h: number, s: number, v: number): [number, number, number] {
  h = ((h % 360) + 360) % 360
  const c = v * s
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  const m = v - c
  let r = 0
  let g = 0
  let bl = 0
  if (h < 60) { r = c; g = x } else if (h < 120) { r = x; g = c } else if (h < 180) { g = c; bl = x } else if (h < 240) { g = x; bl = c } else if (h < 300) { r = x; bl = c } else { r = c; bl = x }
  return [(r + m) * 255, (g + m) * 255, (bl + m) * 255]
}

/** shortest signed angular delta a→b in degrees, in [-180, 180] */
function angDelta(a: number, b: number): number {
  return ((((b - a) % 360) + 540) % 360) - 180
}

/** integer white-noise hash → [0,1). The grain PRNG — deterministic per
 *  (x,y,seed) so the same develop is reproducible, and cheap enough to run
 *  per-pixel on a full frame. */
function nHash(x: number, y: number, seed: number): number {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(seed | 0, 2246822519)) >>> 0
  h = Math.imul(h ^ (h >>> 13), 1274126177)
  h ^= h >>> 16
  return (h >>> 0) / 4294967296
}

/** three-tap average → a soft, bell-shaped (Gaussian-ish) grain value in
 *  roughly [-0.5, 0.5]; real film grain is Gaussian, not the flat uniform
 *  noise a naive overlay produces. */
function grainSample(x: number, y: number, seed: number): number {
  return (nHash(x, y, seed) + nHash(x, y, seed + 9173) + nHash(x, y, seed + 51287)) / 3 - 0.5
}

/* --------------------------------------------------------------- relight
 * The flash is real light on the subject, not a stamped disc. These build a
 * soft subject mask (the person's actual silhouette) that drives a per-pixel
 * relight: subject lifts, background falls to black by distance, reflective
 * highlights catch the light. Mirrored byte-for-byte in the native engine.
 */

/** classic skin predicate (RGB ∪ YCbCr), identical to the on-device subject
 *  finder — grows the relight mask onto real skin instead of a circle. */
function isSkin(r: number, g: number, b: number): boolean {
  const mx = Math.max(r, g, b)
  const mn = Math.min(r, g, b)
  if (mx > 250 || mx < 30) return false
  const rgb = r > 95 && g > 40 && b > 20 && mx - mn > 15 && Math.abs(r - g) > 15 && r > g && r > b
  const cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
  const cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
  const ycc = cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173
  return rgb || ycc
}

/** separable 3-tap box blur over a Float mask — feathers the subject edge so
 *  the relight falls off smoothly instead of cutting a hard shape. */
function featherMask(a: Float32Array, mw: number, mh: number, passes: number): Float32Array {
  const b = new Float32Array(mw * mh)
  for (let p = 0; p < passes; p++) {
    for (let y = 0; y < mh; y++)
      for (let x = 0; x < mw; x++) {
        const i = y * mw + x
        const l = x > 0 ? a[i - 1] : a[i]
        const r = x < mw - 1 ? a[i + 1] : a[i]
        b[i] = (l + a[i] + r) / 3
      }
    for (let y = 0; y < mh; y++)
      for (let x = 0; x < mw; x++) {
        const i = y * mw + x
        const u = y > 0 ? b[i - mw] : b[i]
        const dn = y < mh - 1 ? b[i + mw] : b[i]
        a[i] = (u + b[i] + dn) / 3
      }
  }
  return a
}

/** build a soft subject mask (0..1) on a small grid from the UNGRADED source:
 *  a face-locked capsule (face → torso) grown onto nearby real skin, feathered.
 *  This is what turns the flash from a disc into light on the real silhouette. */
function buildSubjectMask(
  px: Uint8ClampedArray | Uint8Array,
  mw: number,
  mh: number,
  focal: { x: number; y: number; r: number } | null,
  spread: number,
): Float32Array {
  const n = mw * mh
  const raw = new Float32Array(n)
  const fx = focal ? focal.x : 0.5
  const fy = focal ? focal.y : 0.46
  const fr = focal ? Math.max(focal.r, 0.06) : 0.6
  const sx = fr * spread * 1.35
  const sy = fr * spread * 2.4
  for (let my = 0; my < mh; my++)
    for (let mx = 0; mx < mw; mx++) {
      const i = my * mw + mx
      const nx = (mx + 0.5) / mw
      const ny = (my + 0.5) / mh
      const dx = (nx - fx) / sx
      const dy = (ny - (fy + fr * 0.7)) / sy
      const cap = clamp01(1 - (dx * dx + dy * dy))
      const p = i * 4
      const skin = isSkin(px[p], px[p + 1], px[p + 2]) ? 1 : 0
      const gate = clamp01(1.4 - Math.sqrt(dx * dx + dy * dy))
      // saliency: a sharp, high-local-contrast pixel near the lock is in-focus
      // foreground (the background is soft), so it reinforces the subject pick
      const lc = (px[p] * 0.299 + px[p + 1] * 0.587 + px[p + 2] * 0.114) / 255
      const rp = mx < mw - 1 ? p + 4 : p
      const dpp = my < mh - 1 ? p + mw * 4 : p
      const lr = (px[rp] * 0.299 + px[rp + 1] * 0.587 + px[rp + 2] * 0.114) / 255
      const ld = (px[dpp] * 0.299 + px[dpp + 1] * 0.587 + px[dpp + 2] * 0.114) / 255
      const sharp = clamp01((Math.abs(lc - lr) + Math.abs(lc - ld)) * 4)
      const sal = sharp * gate * 0.4
      raw[i] = clamp01(Math.max(cap, skin * gate * 0.85, sal))
    }
  return featherMask(raw, mw, mh, 2)
}

/** bilinear sample of the small mask at a normalized (u,v) */
function sampleMask(m: Float32Array, mw: number, mh: number, u: number, v: number): number {
  const gx = clamp01(u) * mw - 0.5
  const gy = clamp01(v) * mh - 0.5
  const x0 = Math.max(0, Math.min(mw - 1, Math.floor(gx)))
  const y0 = Math.max(0, Math.min(mh - 1, Math.floor(gy)))
  const x1 = Math.min(mw - 1, x0 + 1)
  const y1 = Math.min(mh - 1, y0 + 1)
  const fxp = clamp01(gx - x0)
  const fyp = clamp01(gy - y0)
  const top = m[y0 * mw + x0] + (m[y0 * mw + x1] - m[y0 * mw + x0]) * fxp
  const bot = m[y1 * mw + x0] + (m[y1 * mw + x1] - m[y1 * mw + x0]) * fxp
  return top + (bot - top) * fyp
}

/**
 * The stock's full tonal response, composed into one 256-entry LUT:
 * gentle auto-levels → adaptive dynamic-range recovery (the "smart HDR"
 * pass: high-contrast scenes get their crushed shadows opened and blown
 * highlights guarded, scaled by how wide the scene's range actually is) →
 * metered exposure (with a soft pre-shoulder so a push never hard-clips) →
 * the filmic S-curve whose highlights roll off *below* pure white.
 */
function responseLut(
  curveAmt: number,
  ev: number,
  scene: SceneProfile,
  toneMap: number,
  adapt = 1,
): Uint8ClampedArray {
  const lut = new Uint8ClampedArray(256)
  const gain = Math.pow(2, ev)
  // expand-only levels: murky low-contrast uploads get their footing back
  const lo = 0.35 * scene.p01
  const range = Math.max(0.4, 1 - 0.35 * (scene.p01 + 1 - scene.p99))
  // adaptive DR: only wide-range scenes trigger recovery, so a flat studio
  // shot is left alone while a backlit window shot gets its shadows back
  const dr = scene.p99 - scene.p01
  const drive = toneMap * smoothstep(0.55, 0.95, dr)
  const shadowLift = drive * 0.5 * clamp01((0.45 - scene.p01) / 0.45) // deep blacks only
  const highlightGuard = drive * 0.45 * smoothstep(0.9, 1, scene.p99) // near-clip only
  for (let i = 0; i < 256; i++) {
    let x = i / 255
    x = clamp01((x - lo) / range)
    // recover the toe (raise darks, taper to nothing by the midpoint) and
    // guard the shoulder (ease blown highlights down before they clip)
    if (shadowLift > 0.001) x += shadowLift * (1 - smoothstep(0, 0.55, x)) * (1 - x)
    if (highlightGuard > 0.001) x -= highlightGuard * smoothstep(0.65, 1, x) * x
    x = clamp01(x)
    // metered exposure with a soft shoulder above 0.82 — the electronic
    // meter turns the ring, the emulsion still owns the highlight rolloff
    let y = x * gain
    if (y > 0.82) y = 0.82 + 0.18 * (1 - Math.exp(-(y - 0.82) / 0.18))
    y = clamp01(y)
    const sC = y * y * (3 - 2 * y) // classic S (toe + shoulder)
    // pull the top down so white lands ~0.94 — emulsion never hits paper-white
    const f = sC - 0.06 * smoothstep(0.62, 1, y)
    // the whole adaptive response rides the intensity slider: at 0 the LUT
    // is a straight wire — auto-levels and the pre-shoulder included, so
    // "original" really is the original
    lut[i] = Math.round(255 * lerp(i / 255, lerp(y, f, curveAmt), adapt))
  }
  return lut
}

/* ------------------------------------------------------------ pipeline */

/**
 * The heart of LensMood: a real, deterministic photo-processing pipeline.
 * Every pass is derived from the style character + user sliders, and the
 * whole look scales with `intensity`. The same function renders previews
 * and final exports, so what you see is exactly what you download.
 */
export function renderStyled(
  source: Source,
  style: CameraStyle,
  params: StyleParams,
  opts: RenderOptions = {},
): HTMLCanvasElement {
  const { maxSize = 1280, watermark = false, target, animateGrain = false, focal = null, frame = true } = opts
  const { w, h } = fitted(source, maxSize)
  const ch = style.character
  const s = params.intensity / 100 // global look strength
  const ref = Math.max(w, h) / 1000 // scale-independent px unit
  // B&W INTEGRITY: on a monochrome stock every LIGHT effect must be achromatic.
  // Halation, skin glow, subsurface warmth and flash white-balance all inject
  // colour after the mono conversion — on film-noir that turned faces faintly
  // pink and broke the black-and-white promise. mono gates them to neutral.
  const mono = !!(ch.bw || ch.bwMix)

  /* 0 — the light meter reads the scene (cached: ~free on re-renders).
     `scene: null` disables adaptation; undefined means analyze. */
  const scene =
    opts.scene !== undefined ? (opts.scene ?? NEUTRAL_SCENE) : analyzeScene(source, focal)
  const lens = { ...DEFAULT_LENS, ...ch.lens, ...opts.lensOverride }
  // face-priority metering: with a subject, expose for skin like a camera does
  const keyEff =
    scene.faceLum != null ? lerp(scene.key, scene.faceLum, lens.faceWeight) : scene.key
  const meterTarget = (scene.faceLum != null ? 0.45 : 0.4) * Math.pow(2, lens.meterBias)
  // strength scales the desired correction first, then an asymmetric clamp:
  // pushes get more headroom than pulls because the soft pre-shoulder and the
  // filmic curve both protect pushed highlights, while dark party/night
  // uploads (the core use case) need real recovery to reach the stock's key
  const ev = Math.max(
    -1.25,
    Math.min(1.7, Math.log2(meterTarget / Math.max(0.02, keyEff)) * lens.meterStrength * s),
  )
  // auto white balance: neutralize the estimated cast before the stock's
  // own palette speaks — clamped, and dialed back for stocks whose charm
  // is exactly their bad AWB
  const wbK = lens.awb * s
  const wbGain = (c: number) =>
    lerp(1, Math.max(1 - lens.awbClamp, Math.min(1 + lens.awbClamp, c)), wbK)
  const Gr = wbGain(scene.illum[0])
  const Gg = wbGain(scene.illum[1])
  const Gb = wbGain(scene.illum[2])
  const doWb = Math.abs(Gr - 1) > 0.015 || Math.abs(Gg - 1) > 0.015 || Math.abs(Gb - 1) > 0.015
  const doLevels = scene.p01 > 0.02 || scene.p99 < 0.94
  // smart-HDR recovery engages only on genuinely wide-range scenes — and
  // never on the neutral fallback profile, whose placeholder percentiles
  // (p01=0, p99=1) would otherwise read as maximum dynamic range and wash
  // the blacks of exactly the renders that asked for no adaptation
  const toneMap = lens.toneMap * s
  const doTone = toneMap > 0.02 && scene.analyzed && scene.p99 - scene.p01 > 0.55

  const canvas = target ?? document.createElement('canvas')
  if (canvas.width !== w) canvas.width = w
  if (canvas.height !== h) canvas.height = h
  const ctx = canvas.getContext('2d')!
  ctx.imageSmoothingQuality = 'high'
  ctx.clearRect(0, 0, w, h)

  /* 1 — base color pass via canvas filters */
  const contrastAmt = 0.72 + (params.contrast / 100) * 0.62 // 0.72..1.34
  const filters = [
    // full mono by default intensity (80+); only easing below that keeps color
    ch.bw && !ch.bwMix ? `grayscale(${Math.min(1, s * 1.25).toFixed(3)})` : '',
    ch.sepia ? `sepia(${(ch.sepia * s).toFixed(3)})` : '',
    ch.hue ? `hue-rotate(${(ch.hue * s).toFixed(1)}deg)` : '',
    `saturate(${lerp(1, ch.saturate ?? 1, s).toFixed(3)})`,
    `brightness(${lerp(1, ch.brightness ?? 1, s).toFixed(3)})`,
    `contrast(${lerp(1, contrastAmt, s).toFixed(3)})`,
    ch.blur ? `blur(${(ch.blur * s * ref).toFixed(2)}px)` : '',
  ]
    .filter(Boolean)
    .join(' ')
  ctx.filter = filters
  ctx.drawImage(source, 0, 0, w, h)
  ctx.filter = 'none'

  /* 1.5 — film response: tone curve, split toning, channel fringe.
     This per-pixel pass is where the heavy cameras earn their drama —
     crushed blacks, colored shadows, lens fringing — and every part of
     it rides the intensity slider like the rest of the look. */
  const curveAmt = (ch.curve ?? 0) * s
  const split = ch.splitTone
  const splitAmt = (split?.amount ?? 0) * s
  // lens physics — how this stock's glass misbehaves (all optional, 0 = off)
  const optics = { ca: 0, cornerSoft: 0, distortion: 0, flareAniso: 0, ...ch.optics }
  // legacy fringe (px at 1000px ref) folds into radial CA: corner shift in px.
  // A B&W emulsion cannot record coloured fringes — CA on mono film reads as
  // edge softness, never purple edges — so the channel-split is zeroed for
  // mono stocks (barrel distortion and corner softness still apply).
  const caPx = mono ? 0 : ((ch.fringe ?? 0) + optics.ca * 3) * s * ref
  const kDist = optics.distortion * 0.09 * s
  const mtx = ch.colorMatrix // 3×3 channel crosstalk (real film mixes channels)
  const hiDesat = 0.6 * s // film bleaches highlights toward paper-white
  const doMeter = Math.abs(ev) > 0.02 || doLevels || doTone
  // vibrance: recover color on muted scenes, leave vivid ones alone — the
  // meter's saturation census drives it, so a hazy overcast upload gets its
  // color back while a neon night is untouched. Skin hues are guarded below.
  const vib =
    lens.vibrance * s * (scene.analyzed ? 0.08 + 0.92 * smoothstep(0.4, 0.12, scene.sat) : 0.08)
  const doVib = vib > 0.02 && !ch.bw
  // high-ISO chroma suppression: as the scene darkens, deep shadows give up
  // their color the way a real sensor's noise reduction does — pairs with
  // the auto-ISO grain so dark shots read "pushed", not "smeared"
  const sdn = lens.shadowDenoise * s * (scene.analyzed ? smoothstep(0.3, 0.08, scene.key) : 0)
  const doSdn = sdn > 0.02
  // per-stock colour science: hue-band saturation/luminance response — the
  // emulsion's dye preferences (Kodachrome's deep reds, Neon's cyan bloom)
  const bands = ch.bands
  const doBands = !!bands && !ch.bw && s > 0.02
  /* 1.4 — lens geometry: barrel distortion + radial chromatic aberration in
     one remap. Real glass bends the image (cheap wide lenses bow lines
     outward) and focuses wavelengths at slightly different scales (magenta/
     green fringes that GROW toward the corners, zero at center) — a filter
     recolors pixels, a lens moves them. */
  if (kDist > 0.0015 || caPx >= 0.5) {
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    const orig = new Uint8ClampedArray(d)
    const cx = w / 2
    const cy = h / 2
    const rmax = Math.sqrt(cx * cx + cy * cy)
    const caF = caPx / rmax
    const stride = w * 4
    // bilinear tap of one channel from the untouched copy
    const tap = (fx: number, fy: number, c: number): number => {
      const x0 = Math.max(0, Math.min(w - 1, Math.floor(fx)))
      const y0 = Math.max(0, Math.min(h - 1, Math.floor(fy)))
      const x1 = Math.min(w - 1, x0 + 1)
      const y1 = Math.min(h - 1, y0 + 1)
      const tx = fx - x0
      const ty = fy - y0
      const a = orig[y0 * stride + x0 * 4 + c]
      const b = orig[y0 * stride + x1 * 4 + c]
      const p = orig[y1 * stride + x0 * 4 + c]
      const q = orig[y1 * stride + x1 * 4 + c]
      return a + (b - a) * tx + (p - a + (q - b - (p - a)) * tx) * ty
    }
    for (let y = 0; y < h; y++) {
      const row = y * stride
      const dy = y - cy
      for (let x = 0; x < w; x++) {
        const dx = x - cx
        const d2 = (dx * dx + dy * dy) / (rmax * rmax)
        const sb = 1 + kDist * d2 // barrel: edges sample outward → lines bow
        const sR = sb * (1 - caF * d2)
        const sB = sb * (1 + caF * d2)
        const px = row + x * 4
        d[px] = tap(cx + dx * sR, cy + dy * sR, 0)
        if (kDist > 0.0015) d[px + 1] = tap(cx + dx * sb, cy + dy * sb, 1)
        d[px + 2] = tap(cx + dx * sB, cy + dy * sB, 2)
      }
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 1.45 — spectral B&W: a channel-weighted mono where reds render DARK
     (orthochromatic / silver-gelatin sensitivity) so lips, skin flush and warm
     fabric separate tonally — a saturation-blind grayscale cannot. Runs before
     the film response so the split-tone still tones the plate. */
  if (ch.bwMix) {
    const A = Math.min(1, s * 1.25)
    const wr = ch.bwMix[0]
    const wg = ch.bwMix[1]
    const wb = ch.bwMix[2]
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    for (let i = 0; i < d.length; i += 4) {
      const mono = wr * d[i] + wg * d[i + 1] + wb * d[i + 2]
      d[i] = lerp(d[i], mono, A)
      d[i + 1] = lerp(d[i + 1], mono, A)
      d[i + 2] = lerp(d[i + 2], mono, A)
    }
    ctx.putImageData(img, 0, 0)
  }

  // per-channel dye transfer (cross-process, teal dyes, cyan highlight clip) and
  // the low print DMax floor (instant film never reaches true black) — real
  // chemistry a global curve/fade can't do
  const cc = ch.channelCurves
  const chC = cc ? [cc.r[0] * s, cc.r[1] * s, cc.g[0] * s, cc.g[1] * s, cc.b[0] * s, cc.b[1] * s] : null
  const dmaxV = (ch.dmax ?? 0) * s
  if (curveAmt > 0.02 || splitAmt > 0.02 || mtx || hiDesat > 0.02 || doMeter || doWb || doVib || doSdn || doBands || chC || dmaxV > 0.002) {
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data

    const lut = responseLut(
      curveAmt,
      doMeter ? ev : 0,
      doLevels || doTone ? scene : NEUTRAL_SCENE,
      doTone ? toneMap : 0,
      Math.min(1, s * 1.25),
    )
    const doCurve = curveAmt > 0.02 || doMeter
    const sh = split ? hexRgb(split.shadows) : null
    const hi = split ? hexRgb(split.highlights) : null
    const doSplit = !!(sh && hi && splitAmt > 0.02)
    const k = splitAmt * 0.55
    const mAmt = mtx ? s : 0
    // ±1-level luma dither under the tone curve — breaks the banding a LUT
    // carves into smooth skies on low-grain stocks. Deterministic per pixel.
    const dither = doCurve ? 1.1 * Math.min(1, s * 1.25) : 0
    const dseed = hash32(style.id) ^ 0x9e3779b9
    for (let i = 0; i < d.length; i += 4) {
      // white balance first: the stock's palette operates on scene-neutral
      // light, so tungsten and daylight shots each land in *its* cast
      if (doWb) {
        d[i] = Math.min(255, d[i] * Gr)
        d[i + 1] = Math.min(255, d[i + 1] * Gg)
        d[i + 2] = Math.min(255, d[i + 2] * Gb)
      }
      let r = doCurve ? lut[d[i]] : d[i]
      let g = doCurve ? lut[d[i + 1]] : d[i + 1]
      let b = doCurve ? lut[d[i + 2]] : d[i + 2]
      // per-channel dye transfer runs on each layer before crosstalk mixes them
      if (chC) {
        r = shapeCh(r, chC[0], chC[1])
        g = shapeCh(g, chC[2], chC[3])
        b = shapeCh(b, chC[4], chC[5])
      }
      // channel crosstalk — how film dyes contaminate neighbouring layers
      if (mAmt) {
        const nr = mtx![0] * r + mtx![1] * g + mtx![2] * b
        const ng = mtx![3] * r + mtx![4] * g + mtx![5] * b
        const nb = mtx![6] * r + mtx![7] * g + mtx![8] * b
        r = lerp(r, nr, mAmt)
        g = lerp(g, ng, mAmt)
        b = lerp(b, nb, mAmt)
      }
      if (doSplit) {
        const lum = (r * 0.299 + g * 0.587 + b * 0.114) / 255
        const wsh = 1 - lum
        r += ((sh![0] - 128) * wsh + (hi![0] - 128) * lum) * k
        g += ((sh![1] - 128) * wsh + (hi![1] - 128) * lum) * k
        b += ((sh![2] - 128) * wsh + (hi![2] - 128) * lum) * k
      }
      // highlight desaturation + faint cream cast — the emulsion gives up
      // saturation as it approaches white instead of holding vivid color
      if (hiDesat > 0.02) {
        const L = r * 0.299 + g * 0.587 + b * 0.114
        const t = smoothstep(0.72, 1, L / 255) * hiDesat
        if (t > 0.001) {
          r = lerp(r, L, t) + t * 7
          g = lerp(g, L, t) + t * 4
          b = lerp(b, L, t)
        }
      }
      if (doVib || doSdn) {
        const L = r * 0.299 + g * 0.587 + b * 0.114
        if (doVib) {
          const mx = r > g ? (r > b ? r : b) : g > b ? g : b
          const mn = r < g ? (r < b ? r : b) : g < b ? g : b
          if (mx > 20) {
            const sat = (mx - mn) / mx
            // skin guard: warm hues in the red–yellow sextant where skin
            // lives get most of the boost withheld — faces never go orange
            let guard = 1
            if (r > g && g >= b) {
              // mx-mn is r-b here, and > 0 whenever mx > mn; the earlier +1
              // was on the 0-255 scale and compressed the hue for low-chroma
              // (muted) skin, under-protecting exactly the faces this guards
              const hue = (g - b) / (mx - mn)
              const skinW = smoothstep(0.12, 0.3, hue) * (1 - smoothstep(0.62, 0.88, hue))
              guard = 1 - 0.75 * skinW
            }
            // muted pixels get the most lift; saturated ones are left alone
            const f = 1 + vib * (1 - sat) * guard * 0.8
            r = L + (r - L) * f
            g = L + (g - L) * f
            b = L + (b - L) * f
          }
        }
        if (doSdn) {
          const t = sdn * (1 - smoothstep(13, 66, L))
          if (t > 0.003) {
            r = lerp(r, L, t)
            g = lerp(g, L, t)
            b = lerp(b, L, t)
          }
        }
      }
      if (doBands) {
        const mx2 = r > g ? (r > b ? r : b) : g > b ? g : b
        const mn2 = r < g ? (r < b ? r : b) : g < b ? g : b
        const c2 = mx2 - mn2
        if (c2 > 8) {
          // hue in sextants 0..6 (R=0, Y=1, G=2, C=3, B=4, M=5)
          let hh =
            mx2 === r ? (g - b) / c2 : mx2 === g ? (b - r) / c2 + 2 : (r - g) / c2 + 4
          if (hh < 0) hh += 6
          const i0 = hh | 0
          const i1 = (i0 + 1) % 6
          const f = hh - i0
          const bs = (bands!.sat[i0] + (bands!.sat[i1] - bands!.sat[i0]) * f) * s
          const bl = (bands!.lum[i0] + (bands!.lum[i1] - bands!.lum[i0]) * f) * s
          const L2 = r * 0.299 + g * 0.587 + b * 0.114
          if (bs) {
            const fS = 1 + bs
            r = L2 + (r - L2) * fS
            g = L2 + (g - L2) * fS
            b = L2 + (b - L2) * fS
          }
          if (bl) {
            const mul = 1 + bl * (c2 / 255) * 0.9
            r *= mul
            g *= mul
            b *= mul
          }
        }
      }
      if (dither) {
        const dn = (nHash(i, 1, dseed) - 0.5) * 2 * dither
        r += dn
        g += dn
        b += dn
      }
      // low print DMax: instant film / cheap process never reaches true black —
      // clamp the floor up, a chemistry limit rather than a lifted-fade fill
      if (dmaxV > 0.002) {
        const fl = dmaxV * 255
        r = fl + (1 - dmaxV) * r
        g = fl + (1 - dmaxV) * g
        b = fl + (1 - dmaxV) * b
      }
      d[i] = r
      d[i + 1] = g
      d[i + 2] = b
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 1.55 — palette / motivated colour: a colourist's move, not a slider. Either
     STEER every hue toward a coordinated set of anchors (storybook pastel snaps
     the world to powder pink / mint / cream) or PROTECT one hue and crush the
     chroma of all others (motivated separation — the teal survives, the rest
     drains) — with skin exempt so faces stay alive. */
  const pal = ch.palette
  if (pal && (((pal.snap ?? 0) > 0 && pal.anchors) || ((pal.crush ?? 0) > 0 && pal.keepHue != null))) {
    const snap = (pal.snap ?? 0) * s
    const crush = (pal.crush ?? 0) * s
    const anchors = pal.anchors ?? null
    const keepHue = pal.keepHue
    const kw = pal.keepWidth ?? 40
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    for (let i = 0; i < d.length; i += 4) {
      const [hue, sat, val] = rgb2hsv(d[i], d[i + 1], d[i + 2])
      if (sat < 0.04) continue // greys carry no hue to steer
      const skin = isSkin(d[i], d[i + 1], d[i + 2])
      let nh = hue
      let ns = sat
      if (anchors && snap > 0.001 && !skin) {
        let best = anchors[0]
        let bd = Math.abs(angDelta(hue, anchors[0]))
        for (let k = 1; k < anchors.length; k++) {
          const dd = Math.abs(angDelta(hue, anchors[k]))
          if (dd < bd) {
            bd = dd
            best = anchors[k]
          }
        }
        nh = hue + angDelta(hue, best) * snap
      }
      if (keepHue != null && crush > 0.001 && !skin) {
        const dist = Math.abs(angDelta(hue, keepHue))
        const outside = smoothstep(kw, kw * 1.8, dist) // 0 inside the kept band → 1 far outside
        ns = sat * (1 - crush * outside)
      }
      const [nr, ng, nb] = hsv2rgb(nh, ns, val)
      d[i] = nr
      d[i + 1] = ng
      d[i + 2] = nb
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 1.6 — finish sharpness. Two unsharp scales, both midtone-weighted so
     blacks and highlights never crunch (stills only — too heavy per-frame):
     · acutance — a fine ~2px pass applied to EVERY stock, so a develop
       always reads crisper than the upload, never softer. The "quality
       upgrade" a real lens gives.
     · clarity — the per-stock wide local contrast ("detail that bites"). */
  const clarity = lens.clarity * s
  const acutance = 0.22 * s
  if ((clarity > 0.02 || acutance > 0.02) && !animateGrain) {
    const passes: Array<[number, number]> = []
    if (acutance > 0.02) passes.push([2.2 * ref, acutance])
    if (clarity > 0.02) passes.push([14 * ref, clarity])
    for (const [radius, amt] of passes) {
      const blurC = document.createElement('canvas')
      blurC.width = w
      blurC.height = h
      const bctx = blurC.getContext('2d')!
      bctx.filter = `blur(${radius.toFixed(2)}px)`
      bctx.drawImage(canvas, 0, 0)
      bctx.filter = 'none'
      const base = ctx.getImageData(0, 0, w, h)
      const blurD = bctx.getImageData(0, 0, w, h).data
      const bd = base.data
      for (let i = 0; i < bd.length; i += 4) {
        const L = (bd[i] * 0.299 + bd[i + 1] * 0.587 + bd[i + 2] * 0.114) / 255
        const wgt = amt * (4 * L * (1 - L)) // midtones only
        if (wgt > 0.003) {
          bd[i] += (bd[i] - blurD[i]) * wgt
          bd[i + 1] += (bd[i + 1] - blurD[i + 1]) * wgt
          bd[i + 2] += (bd[i + 2] - blurD[i + 2]) * wgt
        }
      }
      ctx.putImageData(base, 0, 0)
    }
  }

  /* 1.7 — field curvature: cheap glass can't hold the whole field in focus
     at once, so the corners drift soft while the center stays crisp. A
     blurred copy is laid back over the frame through a radial mask that is
     empty at center and opens toward the corners. */
  if (optics.cornerSoft > 0.02 && s > 0.02) {
    const soft = optics.cornerSoft * s
    const cs = document.createElement('canvas')
    cs.width = w
    cs.height = h
    const cxx = cs.getContext('2d')!
    cxx.filter = `blur(${(2.6 * soft * ref + 0.8).toFixed(2)}px)`
    cxx.drawImage(canvas, 0, 0)
    cxx.filter = 'none'
    // carve the sharp center out of the blur layer
    cxx.globalCompositeOperation = 'destination-out'
    const rmax = Math.sqrt(w * w + h * h) / 2
    const hole = cxx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, rmax)
    hole.addColorStop(0, 'rgba(0,0,0,1)')
    hole.addColorStop(Math.max(0.05, 0.62 - soft * 0.2), 'rgba(0,0,0,1)')
    hole.addColorStop(1, 'rgba(0,0,0,0)')
    cxx.fillStyle = hole
    cxx.fillRect(0, 0, w, h)
    ctx.save()
    ctx.globalAlpha = Math.min(1, 0.9 * soft)
    ctx.drawImage(cs, 0, 0)
    ctx.restore()
  }

  /* 1.75 — subject separation: when the on-device model found a face, the
     lens renders a shallow depth of field — the subject stays sharp and the
     background falls softly out of focus, the way a fast prime does. A blurred
     copy is masked back in everywhere *except* a feathered ellipse on the
     subject, so nothing near the face is touched. Gated on focal, so a photo
     with no subject (a landscape) is never blurred. */
  const dof = lens.dof * s
  if (focal && dof > 0.03) {
    const fx = focal.x * w
    const fy = focal.y * h
    const fr = Math.max(focal.r * Math.max(w, h), 24)
    const bg = document.createElement('canvas')
    bg.width = w
    bg.height = h
    const bx = bg.getContext('2d')!
    // the defocus itself — radius scales with the separation amount
    bx.filter = `blur(${(3.4 * dof * ref + 1).toFixed(2)}px)`
    bx.drawImage(canvas, 0, 0)
    bx.filter = 'none'
    // specular bokeh: bright points in the defocused field bloom the way
    // real out-of-focus highlights do — crush to the speculars, blur wide,
    // screen back over the defocus. Sells the glass; midtones untouched.
    bx.save()
    bx.globalCompositeOperation = 'screen'
    bx.globalAlpha = Math.min(0.85, 0.4 + dof * 0.5)
    // crush hard before the blur so ONLY point speculars survive — a soft
    // pre-multiply let bright/backlit fields (overcast sky, windows) clip
    // through and haze the whole background instead of forming bokeh balls
    bx.filter = `brightness(0.4) contrast(3.4) blur(${(8 * dof * ref + 2).toFixed(2)}px)`
    bx.drawImage(canvas, 0, 0)
    bx.restore()
    bx.filter = 'none'
    // carve the sharp subject back out of the blurred layer: opaque at the
    // frame edge, fading to transparent across the subject. The protected
    // zone is a tall capsule — face plus the body hanging below it — because
    // a sharp face floating on a defocused torso is the fake-portrait tell.
    bx.globalCompositeOperation = 'destination-out'
    bx.save()
    bx.translate(fx, fy + fr * 1.1)
    bx.scale(1, 2.2)
    const hole = bx.createRadialGradient(0, 0, fr * 0.65, 0, 0, fr * 2.1)
    hole.addColorStop(0, 'rgba(0,0,0,1)')
    hole.addColorStop(1, 'rgba(0,0,0,0)')
    bx.fillStyle = hole
    // generous cover: transformed coords never exceed ±(w+h) on either axis
    bx.fillRect(-(w + h), -(w + h), (w + h) * 2, (w + h) * 2)
    bx.restore()
    // lay the (now subject-punched) blur back over the sharp frame
    ctx.save()
    ctx.globalAlpha = Math.min(1, 0.55 + dof * 0.45)
    ctx.drawImage(bg, 0, 0)
    ctx.restore()
  }

  /* 2 — skin smoothing: soft-blurred self-blend. With a face lock the
     blend is clipped to a feathered ellipse around the face, so texture
     elsewhere stays crisp — smoothing skin, not the world. */
  if (params.smoothing > 0) {
    ctx.save()
    if (focal) {
      const fx = focal.x * w
      const fy = focal.y * h
      const fr = Math.max(focal.r * Math.max(w, h) * 1.15, 24)
      ctx.beginPath()
      ctx.ellipse(fx, fy, fr, fr * 1.25, 0, 0, Math.PI * 2)
      ctx.clip()
    }
    // gentler than before, and grain lands on top of this pass (below), so
    // smoothed skin keeps an emulsion texture instead of going plastic.
    // rides the intensity slider like everything else: intensity 0 = original
    // without a subject lock, "beauty blur" over the whole frame is just
    // fuzz — cap it near-invisible; with a face it stays a real retouch
    ctx.globalAlpha = (params.smoothing / 100) * (focal ? 0.42 : 0.12) * Math.min(1, s * 1.25)
    ctx.filter = `blur(${(2.2 * ref).toFixed(2)}px)`
    ctx.drawImage(canvas, 0, 0)
    ctx.restore()
    ctx.filter = 'none'
  }

  /* 3 — halation: highlight-weighted bloom. Crushing the copy hard
     before the blur means only genuinely bright areas glow — light
     sources and speculars, not the whole midtone field. When the meter
     found actual light sources, the halo concentrates on them the way
     the anti-halation layer really fails: at the lamps, not everywhere. */
  const halation = (ch.halation ?? 0) * s
  if (halation > 0.01) {
    const lights = scene.lights
    const onLights = lights.length ? lens.lightHalation : 0
    // scene-adaptive bloom: at night the glow IS the look (keep 100%), but
    // on a bright day large sky regions survive the crush and the whole
    // frame would wash lighter+softer — so the base bloom stands down as
    // the scene key rises. Halos on actual lights are untouched.
    const bloomScale = scene.analyzed ? 0.35 + 0.65 * smoothstep(0.55, 0.18, scene.key) : 1
    ctx.save()
    ctx.globalCompositeOperation = 'screen'
    // trade a little of the uniform bloom for the per-source glows — but only
    // a little: the glows are localized, the base pass carries the scene
    ctx.globalAlpha = halation * 0.8 * (1 - 0.25 * onLights) * bloomScale
    // warm/red-biased bloom: the anti-halation layer failing scatters red
    // light around speculars — that orange halo is the film tell, not a
    // neutral glow. sepia + saturate push the crushed highlights warm.
    // On a B&W stock the glow must stay silver — saturate(0), no sepia.
    // crush tight: only true highlights may glow, never the midtone field
    ctx.filter = mono
      ? `brightness(0.46) contrast(3.8) saturate(0) blur(${(9 * ref).toFixed(2)}px)`
      : `brightness(0.46) contrast(3.8) saturate(1.5) sepia(0.5) blur(${(9 * ref).toFixed(2)}px)`
    ctx.drawImage(canvas, 0, 0)
    ctx.restore()
    ctx.filter = 'none'
    if (onLights > 0) {
      ctx.save()
      ctx.globalCompositeOperation = 'screen'
      for (const lt of lights) {
        const lr = Math.max(w, h) * (4 * lt.r + 0.05) * (1 + halation * 0.6)
        const a = Math.min(0.5, halation * onLights * lt.intensity * 0.9)
        if (a < 0.02) continue
        // the halo takes the light's own color (sampled from its glow ring):
        // neon halos pink or cyan, tungsten halos amber — never a stock
        // orange. The ring mean is washed toward white, so push its chroma
        // back out before brightening.
        const tMean = (lt.tint[0] + lt.tint[1] + lt.tint[2]) / 3
        // on a B&W stock the halo is silver: collapse the tint to its mean
        const chroma = (c: number) =>
          Math.min(255, Math.max(0, (tMean + (c - tMean) * (mono ? 0 : 2.6)) * 255 * 1.35))
        const r = Math.round(chroma(lt.tint[0]))
        const g = Math.round(chroma(lt.tint[1]))
        const bch = Math.round(chroma(lt.tint[2]))
        if (optics.flareAniso > 0.02) {
          // uncoated/cheap glass streaks its flare outward along the axis
          // through frame center — each glow is stretched away from center,
          // squeezed across it, so lamps at the edges smear like real flare
          const ang = Math.atan2(lt.y * h - h / 2, lt.x * w - w / 2)
          ctx.save()
          ctx.translate(lt.x * w, lt.y * h)
          ctx.rotate(ang)
          ctx.scale(1 + optics.flareAniso * 1.4 * s, Math.max(0.55, 1 - optics.flareAniso * 0.35 * s))
          const glow = ctx.createRadialGradient(0, 0, 0, 0, 0, lr)
          glow.addColorStop(0, `rgba(${r},${g},${bch},${a.toFixed(3)})`)
          glow.addColorStop(0.5, `rgba(${r},${g},${bch},${(a * 0.35).toFixed(3)})`)
          glow.addColorStop(1, `rgba(${r},${g},${bch},0)`)
          ctx.fillStyle = glow
          ctx.fillRect(-(w + h) * 2, -(w + h) * 2, (w + h) * 4, (w + h) * 4)
          ctx.restore()
        } else {
          const glow = ctx.createRadialGradient(lt.x * w, lt.y * h, 0, lt.x * w, lt.y * h, lr)
          glow.addColorStop(0, `rgba(${r},${g},${bch},${a.toFixed(3)})`)
          glow.addColorStop(0.5, `rgba(${r},${g},${bch},${(a * 0.35).toFixed(3)})`)
          glow.addColorStop(1, `rgba(${r},${g},${bch},0)`)
          ctx.fillStyle = glow
          ctx.fillRect(0, 0, w, h)
        }
      }
      ctx.restore()
    }
  }

  /* 4 — warmth: overlay color wash (warm orange / cool blue) */
  const warmth = ((params.warmth - 50) / 50) * s // -1..1
  if (Math.abs(warmth) > 0.02) {
    ctx.save()
    ctx.globalCompositeOperation = 'overlay'
    ctx.globalAlpha = Math.abs(warmth) * 0.3
    ctx.fillStyle = warmth > 0 ? '#ff8c28' : '#3c78ff'
    ctx.fillRect(0, 0, w, h)
    ctx.restore()
  }

  /* 5 — style tint */
  if (ch.tint) {
    ctx.save()
    ctx.globalCompositeOperation = ch.tint.blend
    ctx.globalAlpha = ch.tint.alpha * s
    ctx.fillStyle = ch.tint.color
    ctx.fillRect(0, 0, w, h)
    ctx.restore()
  }

  /* 6 — relight: the flash is real light on the subject, not a stamped disc.
     A soft subject mask (face → torso, grown onto skin from the ungraded
     source) drives a per-pixel relight — the subject lifts along its true
     silhouette, the background falls to black by distance², reflective
     highlights on skin/jewelry catch the light, and the lit subject shifts
     toward the flash's neutral-cool white. The flash dial and the stock's
     flashStrength drive the hard flash; flashFalloff gives available-light
     stocks a gentle subject/background separation with no flash at all. */
  const flDial = params.flash / 100
  const flash = lens.flashStrength * flDial * s
  const sep = lens.flashFalloff * s
  if ((flash > 0.004 || sep > 0.004) && !animateGrain) {
    const mmax = 128
    const mscale = mmax / Math.max(w, h)
    const mw = Math.max(2, Math.round(w * mscale))
    const mh = Math.max(2, Math.round(h * mscale))
    const mc = document.createElement('canvas')
    mc.width = mw
    mc.height = mh
    const mctx = mc.getContext('2d')!
    mctx.drawImage(source, 0, 0, mw, mh)
    const mpx = mctx.getImageData(0, 0, mw, mh).data
    const mask = buildSubjectMask(mpx, mw, mh, focal, lens.flashSpread)
    // adaptive skin reference: the flash "learns" THIS person's skin from the
    // ungraded thumb (mean luma of skin pixels near the lock), so the material
    // model measures shine/subsurface relative to their tone, not a constant
    let skinSum = 0
    let skinN = 0
    for (let i = 0; i < mw * mh; i++) {
      const p = i * 4
      if (isSkin(mpx[p], mpx[p + 1], mpx[p + 2])) {
        skinSum += (mpx[p] * 0.299 + mpx[p + 1] * 0.587 + mpx[p + 2] * 0.114) / 255
        skinN++
      }
    }
    const skinRef = skinN > mw * mh * 0.01 ? skinSum / skinN : 0.55

    // low-frequency "light + albedo" copy: blurring the graded frame separates
    // soft shading (Lb) from fine texture (detail = L - Lb). We light Lb by
    // material and re-add detail, so pores / weave / strands survive the flash.
    const bc = document.createElement('canvas')
    bc.width = w
    bc.height = h
    const bx = bc.getContext('2d')!
    bx.filter = `blur(${Math.max(1, Math.round(ref * 3))}px)`
    bx.drawImage(canvas, 0, 0)
    const blur = bx.getImageData(0, 0, w, h).data

    const spec = lens.flashSpecular
    const cool = lens.flashCool
    const glowStr = lens.skinGlow // R45: the dead field, now wired to a real skin glow
    const chiaro = (ch.chiaroscuro ?? 0) * s // noir directional-key sculpting
    // R46 lighting personality: the flash is a modeled key, not a brightener.
    // keyVec is the direction the key comes from in screen space (y down);
    // [0,0] = flat frontal on-axis flash. No trig in the hot loop (Math.sin/cos
    // aren't bit-identical across JS engines) — the direction ships as a vector.
    const kv = lens.keyVec ?? [0, 0]
    const kdx = kv[0]
    const kdy = kv[1]
    const keyHard = lens.keyHardness ?? 0.35 // how sharply lit/shadow sides diverge
    const ceiling = lens.fillCeiling ?? 0.86 // the luma the fill can never exceed
    const shadowFill = lens.shadowFill ?? 0.55 // how much of the key the shadow side keeps
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const idx = (y * w + x) * 4
        let r = d[idx]
        let g = d[idx + 1]
        let b = d[idx + 2]
        const L = (r * 0.299 + g * 0.587 + b * 0.114) / 255
        const Lb = (blur[idx] * 0.299 + blur[idx + 1] * 0.587 + blur[idx + 2] * 0.114) / 255
        const detail = L - Lb // fine texture + specular micro-spikes
        const M = sampleMask(mask, mw, mh, (x + 0.5) / w, (y + 0.5) / h)
        const far = 1 - M
        const skin = isSkin(r, g, b) ? 1 : 0
        // BACKGROUND: falls off by distance² — the flash REDISTRIBUTES light
        // (subject forward, background back), it does not raise exposure.
        const bg = 1 - (sep * 0.5 + flash * 0.6) * far * far
        // FORM: read which way the surface turns from the low-freq shading
        // gradient (∇Lb), and how much it faces the key. The lit side of the
        // form catches the key; the shadow side keeps only shadowFill of it —
        // modeled directional light, not a flat wash.
        const xl = x > 0 ? idx - 4 : idx
        const xr = x < w - 1 ? idx + 4 : idx
        const yu = y > 0 ? idx - w * 4 : idx
        const yd = y < h - 1 ? idx + w * 4 : idx
        const lbL = (blur[xl] * 0.299 + blur[xl + 1] * 0.587 + blur[xl + 2] * 0.114) / 255
        const lbR = (blur[xr] * 0.299 + blur[xr + 1] * 0.587 + blur[xr + 2] * 0.114) / 255
        const lbU = (blur[yu] * 0.299 + blur[yu + 1] * 0.587 + blur[yu + 2] * 0.114) / 255
        const lbD = (blur[yd] * 0.299 + blur[yd + 1] * 0.587 + blur[yd + 2] * 0.114) / 255
        const gLx = lbR - lbL
        const gLy = lbD - lbU
        const gmag = Math.sqrt(gLx * gLx + gLy * gLy)
        const dirDot = gmag > 0.0001 ? (gLx * kdx + gLy * kdy) / gmag : 0
        const face = 0.5 + 0.5 * dirDot // 0 = shadow side, 1 = key side
        const directional = shadowFill + (1 - shadowFill) * face
        const keyModel = 1 + keyHard * (directional - 1) // flat at keyHard 0, modeled at 1
        // FILL: add light ONLY into the headroom below this stock's ceiling, so
        // dark/mid surfaces come up while already-bright ones barely move — the
        // flash can never push the subject past the ceiling (no blinding white).
        // Available-light stocks (no hard flash) still get a soft modeled key
        // from their falloff term, so the lighting personality shapes them too.
        const litSource = flash + sep * 0.28
        const lightAmt = litSource * M * keyModel
        const roomLeft = clamp01(ceiling - L)
        const newL = L + roomLeft * lightAmt
        const lift = L > 0.001 ? newL / L : 1
        const s6 = bg * lift
        if (mono) {
          // a toned B&W print under more light gets BRIGHTER, not more COLOURED:
          // lift the luma additively so the print's tone offsets never amplify
          // (multiplying scales the chroma spread and speckles the shadows)
          const v = (r + g + b) / 3
          const add = v * (s6 - 1)
          r += add
          g += add
          b += add
        } else {
          r *= s6
          g *= s6
          b *= s6
        }
        // SPECULAR: shiny micro-highlights, scaled by remaining headroom so
        // shine sparkles without blowing to white. Skin shines soft; metal hard.
        const shine = smoothstep(0.06, 0.2, detail) * smoothstep(skinRef * 0.7, skinRef * 1.15, L)
        const material = skin ? 0.4 : 1
        const roomSpec = clamp01(1 - L)
        const specular = (flash * 0.9 + sep * 0.3) * M * shine * material * spec * roomSpec * 255
        // TEXTURE: re-add high-frequency so the lit surface reads crisp — pores,
        // fabric weave, hair — headroom-scaled so it never tips into white.
        const tex = detail * (0.4 * flash * M) * roomSpec * 255
        r += specular + tex
        g += specular + tex
        b += specular + tex
        // SKIN SUBSURFACE: flash-lit skin glows soft and faintly warm (light
        // scatters under the surface), so faces read luminous, not gray-white.
        // Tied to the light the skin actually absorbed (roomLeft·lightAmt), not
        // a flat brighten, so it follows the modeling. Purely chromatic, so a
        // B&W stock skips it — silver skin must stay silver.
        const sub = skin * roomLeft * lightAmt * 0.7
        if (!mono) {
          r += sub * 14
          b -= sub * 10
        }
        // SKIN GLOW (the lens's skin-flatter, R45 — was a dead field): a soft
        // luminous lift on face skin, strongest under flash but with a gentle
        // ambient floor when a face is locked so portrait stocks read creamy.
        // Highlights are protected so it lifts mids, never blows the face.
        // On a mono stock the glow is neutral — equal on every channel.
        const glowAmt = skin * M * glowStr * ((focal ? 0.12 : 0) + flash * 0.6)
        if (glowAmt > 0.002) {
          const glowLift = glowAmt * (1 - smoothstep(0.6, 0.95, L)) * 24
          r += glowLift
          g += glowLift * (mono ? 1 : 0.82)
          b += glowLift * (mono ? 1 : 0.64)
        }
        // CHIAROSCURO (noir): deepen the shadow-side modeling already on the
        // subject (push where the low-freq shading is dark, hold where it's lit)
        // and crush true blacks only OFF-subject, so the figure stays sculpted
        // by light instead of flat-crushed. A modeled key a contrast slider lacks.
        if (chiaro > 0.001) {
          const model = 1 - chiaro * M * (1 - smoothstep(0.28, 0.62, Lb)) * 0.7
          const bgCrush = 1 - chiaro * far * 0.4
          const cg = model * bgCrush
          r *= cg
          g *= cg
          b *= cg
        }
        // flash white balance: the lit subject cools toward ~5500K while the
        // background keeps whatever ambient cast the scene had. A B&W stock has
        // no white balance — skipping it keeps the mono promise intact.
        const pull = cool * flash * M
        if (pull > 0.002 && !mono) {
          r = r * (1 - pull * 0.06)
          b = b * (1 + pull * 0.05)
        }
        d[idx] = r
        d[idx + 1] = g
        d[idx + 2] = b
      }
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 7 — faded blacks (film lift) */
  const fade = (ch.fade ?? 0) * s
  if (fade > 0.01) {
    ctx.save()
    ctx.globalCompositeOperation = 'lighten'
    const L = Math.round(fade * 52)
    ctx.fillStyle = `rgb(${L},${L},${Math.round(L * 1.05)})`
    ctx.fillRect(0, 0, w, h)
    ctx.restore()
  }

  /* 8 — shadow depth / vignette. With a subject locked, the clear center
     rides toward them — a printer dodging the person, not the frame. */
  const vig = (params.shadows / 100) * s
  if (vig > 0.02) {
    const vx = focal ? lerp(w / 2, focal.x * w, 0.6) : w / 2
    const vy = focal ? lerp(h / 2, focal.y * h, 0.6) : h / 2
    ctx.save()
    const g = ctx.createRadialGradient(
      vx,
      vy,
      Math.min(w, h) * 0.35,
      vx,
      vy,
      Math.max(w, h) * 0.78,
    )
    g.addColorStop(0, 'rgba(8,8,12,0)')
    g.addColorStop(1, `rgba(8,8,12,${(vig * 0.55).toFixed(3)})`)
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)
    ctx.restore()
  }

  /* 8.5 — light leak: a warm flare bleeding in from one edge, position
     hashed from the style id so the leak is a signature, not a dice roll */
  const leak = (ch.leak ?? 0) * s
  if (leak > 0.02) {
    const seed = hash32(style.id)
    const fromLeft = (seed & 1) === 0
    const cy = h * (0.15 + ((seed >> 3) % 60) / 100) // 15%..75% down the edge
    const cx = fromLeft ? -w * 0.08 : w * 1.08
    const radius = Math.max(w, h) * 0.55
    ctx.save()
    ctx.globalCompositeOperation = 'screen'
    const flare = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius)
    flare.addColorStop(0, `rgba(255,120,40,${(leak * 0.55).toFixed(3)})`)
    flare.addColorStop(0.45, `rgba(255,60,60,${(leak * 0.22).toFixed(3)})`)
    flare.addColorStop(1, 'rgba(255,60,60,0)')
    ctx.fillStyle = flare
    ctx.fillRect(0, 0, w, h)
    // thin hot streak along the same edge
    const band = ctx.createLinearGradient(fromLeft ? 0 : w, 0, fromLeft ? w * 0.22 : w * 0.78, 0)
    band.addColorStop(0, `rgba(255,180,90,${(leak * 0.35).toFixed(3)})`)
    band.addColorStop(1, 'rgba(255,180,90,0)')
    ctx.fillStyle = band
    ctx.fillRect(0, 0, w, h)
    ctx.restore()
  }

  /* 8.6 — highlight shoulder (film rolloff). The flash relight, halation and
     specular all pile light into the brightest zones; with no shoulder they
     clip to a flat, identical, BLINDING white and every stock looks the same
     up top — a filter that amplified the whites, not a lens. A real emulsion
     has a SHOULDER: the top of the curve compresses (blown areas keep their
     texture) and the highlights carry the film's OWN colour. So we compress
     the top end and pull the recovered headroom toward THIS stock's highlight
     tone — which is precisely what makes each lens read individual where it is
     brightest, instead of a shared sheet of white. */
  const guard = clamp01((ch.highlightGuard ?? 0.62) * s)
  if (guard > 0.004) {
    const [hr, hg, hb] = ch.splitTone ? hexRgb(ch.splitTone.highlights) : [255, 249, 242]
    const knee = 200
    const comp = 1 - guard * 0.52 // blown excess above the knee kept at 48–100%
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    for (let i = 0; i < d.length; i += 4) {
      const r = d[i]
      const g = d[i + 1]
      const b = d[i + 2]
      const L = 0.299 * r + 0.587 * g + 0.114 * b
      if (L <= knee) continue
      const tL = knee + (L - knee) * comp // compressed luma ceiling
      const sc = tL / L
      let nr = r * sc
      let ng = g * sc
      let nb = b * sc
      const t = smoothstep(knee, 255, L) * guard * 0.42 // tone rises into the blowout
      nr += (hr - nr) * t
      ng += (hg - ng) * t
      nb += (hb - nb) * t
      d[i] = nr
      d[i + 1] = ng
      d[i + 2] = nb
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 9 — grain: size follows the stock. Wet plates and 8mm clump big;
     slide film resolves fine. Auto-ISO: a real camera pushes ISO as the
     scene darkens and the texture rises with it — dark bar shots grain up,
     daylight stays clean. Rides the measured scene key. */
  const isoBoost = scene.analyzed
    ? 1 + lens.autoIso * 1.2 * smoothstep(0.32, 0.06, scene.key)
    : 1
  const grain = params.grain / 100
  if (grain > 0.02) {
    if (animateGrain) {
      // video: cheap overlay tile, shifted each frame so grain dances
      const gs = Math.max(0.5, (ch.grainSize ?? 1) * ref)
      ctx.save()
      ctx.globalCompositeOperation = 'overlay'
      ctx.globalAlpha = Math.min(1, grain * 0.5 * Math.min(1, s * 1.25) * isoBoost)
      ctx.scale(gs, gs)
      ctx.fillStyle = ctx.createPattern(getNoiseTile(), 'repeat')!
      const ox = Math.floor(Math.random() * 192)
      const oy = Math.floor(Math.random() * 192)
      ctx.translate(-ox, -oy)
      ctx.fillRect(0, 0, w / gs + 192, h / gs + 192)
      ctx.restore()
    } else {
      // stills: luminance-weighted Gaussian grain, embedded per-pixel. Real
      // grain lives in the midtones — the emulsion saturates in deep shadow
      // and blown highlight — and is clumped to the stock's grain size. This
      // is the single biggest tell between "film" and "a noise layer".
      const img = ctx.getImageData(0, 0, w, h)
      const dd = img.data
      const gs = Math.max(1, Math.round((ch.grainSize ?? 1) * ref))
      const amp = grain * 34 * (ch.grainAmp ?? 1) * Math.min(1, s * 1.25) * isoBoost
      const chroma = ch.bw ? 0 : (ch.grainChroma ?? 0.4)
      const seed = hash32(style.id) & 0xffff
      const clumped = gs > 1
      for (let y = 0; y < h; y++) {
        const gy = clumped ? (y / gs) | 0 : y
        for (let x = 0; x < w; x++) {
          const idx = (y * w + x) * 4
          const L = (dd[idx] * 0.299 + dd[idx + 1] * 0.587 + dd[idx + 2] * 0.114) / 255
          const wgt = 0.25 + 0.75 * (4 * L * (1 - L))
          const gx = clumped ? (x / gs) | 0 : x
          const mono = grainSample(gx, gy, seed) * amp * wgt
          if (chroma) {
            dd[idx] += mono + grainSample(gx, gy, seed + 13) * amp * chroma * wgt
            dd[idx + 1] += mono + grainSample(gx, gy, seed + 37) * amp * chroma * wgt
            dd[idx + 2] += mono + grainSample(gx, gy, seed + 61) * amp * chroma * wgt
          } else {
            dd[idx] += mono
            dd[idx + 1] += mono
            dd[idx + 2] += mono
          }
        }
      }
      ctx.putImageData(img, 0, 0)
    }
  }

  /* 9.6 — analog video: chroma bleeds sideways because tape/broadcast gives
     color a fraction of luma's horizontal bandwidth (a one-pole running filter
     over Cb/Cr only — the color drags past edges while brightness stays sharp),
     plus interlace field-comb and bright tape dropout. A signal-domain artifact
     no slider can make. */
  if (ch.video) {
    const bleed = clamp01((ch.video.bleed ?? 0) * s)
    const drop = (ch.video.dropout ?? 0) * s
    const inter = (ch.video.interlace ?? 0) * s
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    const a = lerp(1, 0.09, bleed) // one-pole coeff: heavier bleed = longer chroma tail
    const vseed = hash32(style.id) ^ 0x5bd1e995
    const runLen = Math.round(w * 0.12)
    for (let y = 0; y < h; y++) {
      const row = y * w * 4
      // interlace: odd fields sampled sideways → comb teeth on vertical edges
      const shift = inter > 0.01 && (y & 1) ? Math.round(1 + inter * 4) : 0
      let cb = 128
      let cr = 128
      let seeded = false
      const rowH = nHash(0, y, vseed)
      const dropRow = drop > 0.02 && rowH < drop * 0.06
      const dseg0 = Math.floor(rowH * w)
      for (let x = 0; x < w; x++) {
        const i = row + x * 4
        const sx = x + shift >= w ? w - 1 : x + shift
        const si = row + sx * 4
        const r0 = d[si]
        const g0 = d[si + 1]
        const b0 = d[si + 2]
        const Y = 0.299 * r0 + 0.587 * g0 + 0.114 * b0
        const pcb = -0.168736 * r0 - 0.331264 * g0 + 0.5 * b0 + 128
        const pcr = 0.5 * r0 - 0.418688 * g0 - 0.081312 * b0 + 128
        if (!seeded) {
          cb = pcb
          cr = pcr
          seeded = true
        }
        cb += (pcb - cb) * a
        cr += (pcr - cr) * a
        const yout = shift ? Y * (1 - inter * 0.12) : Y // odd field runs slightly dim
        let r = yout + 1.402 * (cr - 128)
        let g = yout - 0.344136 * (cb - 128) - 0.714136 * (cr - 128)
        let b = yout + 1.772 * (cb - 128)
        if (dropRow && x >= dseg0 && x < dseg0 + runLen) {
          r = lerp(r, 235, 0.7)
          g = lerp(g, 238, 0.7)
          b = lerp(b, 235, 0.7)
        }
        d[i] = r
        d[i + 1] = g
        d[i + 2] = b
      }
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 9.7 — CCD colour crosstalk (y2k digicam): violet/green fringing blooms into
     the DARK side of high-gradient edges. Unlike optical lateral CA this is fixed
     in image space — interior edges fringe exactly as hard as the frame corners,
     the demosaic error early sensors made that no radius-based CA or clarity
     slider can reproduce. Plus light chroma quantisation that bands smooth
     gradients the way a cheap sensor's 8-bit JPEG chroma channel does. */
  if (ch.edgeFringe) {
    const fringe = clamp01((ch.edgeFringe.fringe ?? 0) * s)
    const block = clamp01((ch.edgeFringe.block ?? 0) * s)
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    const src = new Uint8Array(d) // read gradients from the untouched source
    const levels = block > 0.02 ? Math.max(6, Math.round(lerp(64, 9, block))) : 0
    const qstep = levels ? 255 / levels : 0
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4
        let r = src[i]
        let g = src[i + 1]
        let b = src[i + 2]
        if (fringe > 0.01) {
          const il = x > 0 ? i - 4 : i
          const ir = x < w - 1 ? i + 4 : i
          const iu = y > 0 ? i - w * 4 : i
          const idn = y < h - 1 ? i + w * 4 : i
          const gx =
            0.299 * src[ir] + 0.587 * src[ir + 1] + 0.114 * src[ir + 2] - (0.299 * src[il] + 0.587 * src[il + 1] + 0.114 * src[il + 2])
          const gy =
            0.299 * src[idn] + 0.587 * src[idn + 1] + 0.114 * src[idn + 2] - (0.299 * src[iu] + 0.587 * src[iu + 1] + 0.114 * src[iu + 2])
          const mag = Math.sqrt(gx * gx + gy * gy)
          const L = (0.299 * r + 0.587 * g + 0.114 * b) / 255
          const fr = fringe * smoothstep(24, 82, mag) * (1 - smoothstep(0.32, 0.68, L)) * 48
          r += fr * 0.85
          b += fr * 1.3
          g -= fr * 0.5
        }
        if (levels) {
          // quantise chroma only (Y kept full-res) → banded colour, sharp luma
          const Y = 0.299 * r + 0.587 * g + 0.114 * b
          const rq = Y + Math.round((r - Y) / qstep) * qstep
          const bq = Y + Math.round((b - Y) / qstep) * qstep
          const gq = (Y - 0.299 * rq - 0.114 * bq) / 0.587
          r = lerp(r, rq, block * 0.7)
          g = lerp(g, gq, block * 0.7)
          b = lerp(b, bq, block * 0.7)
        }
        d[i] = r
        d[i + 1] = g
        d[i + 2] = b
      }
    }
    ctx.putImageData(img, 0, 0)
  }

  /* 10 — camcorder scanlines + timestamp */
  if (ch.scanlines) {
    ctx.save()
    ctx.globalAlpha = 0.1 * s
    ctx.fillStyle = '#000'
    const step = Math.max(2, Math.round(3 * ref))
    for (let y = 0; y < h; y += step * 2) ctx.fillRect(0, y, w, step)
    ctx.restore()
  }
  if (ch.timestamp && s > 0.15) {
    const now = new Date()
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
    const hh = now.getHours() % 12 || 12
    const ampm = now.getHours() >= 12 ? 'PM' : 'AM'
    const tape = opts.time
    // on a tape, the stamp carries a counting mm:ss timecode; stills keep the clock
    const clock =
      tape != null
        ? `${Math.floor(tape / 60)}:${String(Math.floor(tape % 60)).padStart(2, '0')}`
        : `${ampm} ${hh}:${String(now.getMinutes()).padStart(2, '0')}`
    const stamp = `${months[now.getMonth()]} ${now.getDate()} ${now.getFullYear()}  ${clock}`
    ctx.save()
    ctx.font = `600 ${Math.round(26 * ref)}px ui-monospace, Menlo, monospace`
    ctx.textBaseline = 'bottom'
    ctx.shadowColor = 'rgba(255,176,0,0.9)'
    ctx.shadowBlur = 8 * ref
    ctx.fillStyle = 'rgba(255,196,64,0.95)'
    ctx.fillText(stamp, 22 * ref, h - 20 * ref)
    // ● REC blinks with tape time (deterministic), steady on stills
    if (tape == null || Math.floor(tape * 1.2) % 2 === 0) {
      ctx.fillStyle = 'rgba(255,80,64,0.95)'
      ctx.shadowColor = 'rgba(255,80,64,0.9)'
      ctx.font = `700 ${Math.round(24 * ref)}px ui-monospace, Menlo, monospace`
      ctx.fillText('● REC', 22 * ref, 46 * ref)
    }
    ctx.restore()
  }

  /* 11 — polaroid frame (re-composites onto larger canvas) */
  let out = canvas
  if (ch.polaroidFrame && s > 0.15 && frame) {
    const m = Math.round(Math.max(w, h) * 0.055)
    const bottom = Math.round(Math.max(w, h) * 0.16)
    const fc = document.createElement('canvas')
    fc.width = w + m * 2
    fc.height = h + m + bottom
    const fx = fc.getContext('2d')!
    const paper = fx.createLinearGradient(0, 0, 0, fc.height)
    paper.addColorStop(0, '#fdfcf8')
    paper.addColorStop(1, '#f3efe6')
    fx.fillStyle = paper
    fx.fillRect(0, 0, fc.width, fc.height)
    fx.save()
    fx.shadowColor = 'rgba(0,0,0,0.18)'
    fx.shadowBlur = m * 0.4
    fx.drawImage(canvas, m, m)
    fx.restore()
    out = fc
  }

  /* 12 — watermark for free exports: engraved mono plate, bottom-right */
  if (watermark) {
    const W = out.width
    const H = out.height
    const wx = out.getContext('2d')!
    const fs = Math.max(10, Math.round(Math.max(W, H) * 0.016))
    const pad = fs * 0.8
    const text = 'SHOT ON LENSMOOD'
    wx.save()
    wx.font = `500 ${fs}px 'IBM Plex Mono', ui-monospace, monospace`
    const letterSpace = fs * 0.12
    const tw = wx.measureText(text).width + letterSpace * (text.length - 1)
    const dot = fs * 0.34
    const bw = tw + pad * 2 + dot * 2 + fs * 0.5
    const bh = fs * 2.2
    const x = W - bw - fs
    const y = H - bh - fs
    wx.fillStyle = 'rgba(16,16,16,0.62)'
    wx.fillRect(x, y, bw, bh)
    // brand dot
    wx.fillStyle = '#0f7d92'
    wx.beginPath()
    wx.arc(x + pad + dot, y + bh / 2, dot, 0, Math.PI * 2)
    wx.fill()
    // letter-spaced mono text
    wx.fillStyle = 'rgba(246,245,241,0.95)'
    wx.textBaseline = 'middle'
    let cx2 = x + pad + dot * 2 + fs * 0.5
    for (const chch of text) {
      wx.fillText(chch, cx2, y + bh / 2 + fs * 0.06)
      cx2 += wx.measureText(chch).width + letterSpace
    }
    wx.restore()
  }

  return out
}

/* ------------------------------------------------------------- loading */

export function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = reject
    img.src = src
  })
}

export function fileToDataURL(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result as string)
    reader.onerror = reject
    reader.readAsDataURL(file)
  })
}

export function canvasToBlob(canvas: HTMLCanvasElement, quality = 0.92): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (b) => (b ? resolve(b) : reject(new Error('export failed'))),
      'image/jpeg',
      quality,
    )
  })
}

/** small thumbnail data-url for the dashboard history */
export function thumbnail(canvas: HTMLCanvasElement, size = 280): string {
  const scale = size / Math.max(canvas.width, canvas.height)
  const c = document.createElement('canvas')
  c.width = Math.max(1, Math.round(canvas.width * scale))
  c.height = Math.max(1, Math.round(canvas.height * scale))
  c.getContext('2d')!.drawImage(canvas, 0, 0, c.width, c.height)
  return c.toDataURL('image/jpeg', 0.7)
}
