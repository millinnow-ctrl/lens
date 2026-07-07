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
  const { maxSize = 1280, watermark = false, target, animateGrain = false, focal = null } = opts
  const { w, h } = fitted(source, maxSize)
  const ch = style.character
  const s = params.intensity / 100 // global look strength
  const ref = Math.max(w, h) / 1000 // scale-independent px unit

  /* 0 — the light meter reads the scene (cached: ~free on re-renders).
     `scene: null` disables adaptation; undefined means analyze. */
  const scene =
    opts.scene !== undefined ? (opts.scene ?? NEUTRAL_SCENE) : analyzeScene(source, focal)
  const lens = { ...DEFAULT_LENS, ...ch.lens }
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
    ch.bw ? `grayscale(${Math.min(1, s * 1.25).toFixed(3)})` : '',
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
  const fringePx = Math.round((ch.fringe ?? 0) * s * ref)
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
  if (curveAmt > 0.02 || splitAmt > 0.02 || fringePx >= 1 || mtx || hiDesat > 0.02 || doMeter || doWb || doVib || doSdn) {
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data

    if (fringePx >= 1) {
      // chromatic fringe: red shifts right, blue shifts left
      const orig = new Uint8ClampedArray(d)
      const stride = w * 4
      for (let y = 0; y < h; y++) {
        const row = y * stride
        for (let x = 0; x < w; x++) {
          const px = row + x * 4
          const xr = Math.max(0, x - fringePx)
          const xb = Math.min(w - 1, x + fringePx)
          d[px] = orig[row + xr * 4]
          d[px + 2] = orig[row + xb * 4 + 2]
        }
      }
    }

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
      if (dither) {
        const dn = (nHash(i, 1, dseed) - 0.5) * 2 * dither
        r += dn
        g += dn
        b += dn
      }
      d[i] = r
      d[i + 1] = g
      d[i + 2] = b
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
    // crush tight: only true highlights may glow, never the midtone field
    ctx.filter = `brightness(0.46) contrast(3.8) saturate(1.5) sepia(0.5) blur(${(9 * ref).toFixed(2)}px)`
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
        const chroma = (c: number) => Math.min(255, Math.max(0, (tMean + (c - tMean) * 2.6) * 255 * 1.35))
        const r = Math.round(chroma(lt.tint[0]))
        const g = Math.round(chroma(lt.tint[1]))
        const bch = Math.round(chroma(lt.tint[2]))
        const glow = ctx.createRadialGradient(lt.x * w, lt.y * h, 0, lt.x * w, lt.y * h, lr)
        glow.addColorStop(0, `rgba(${r},${g},${bch},${a.toFixed(3)})`)
        glow.addColorStop(0.5, `rgba(${r},${g},${bch},${(a * 0.35).toFixed(3)})`)
        glow.addColorStop(1, `rgba(${r},${g},${bch},0)`)
        ctx.fillStyle = glow
        ctx.fillRect(0, 0, w, h)
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

  /* 6 — flash: hot center + darkened surroundings. The face lock
     puts the hotspot on the subject the way a real on-camera flash
     reads a face, instead of assuming center-frame. */
  const flash = (params.flash / 100) * s
  if (flash > 0.02) {
    const cx = (focal ? focal.x : 0.5) * w
    const cy = (focal ? focal.y : 0.42) * h
    const r = Math.max(w, h) * (focal ? Math.max(0.5, focal.r * 4.5) : 0.72)
    ctx.save()
    ctx.globalCompositeOperation = 'screen'
    const hot = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
    hot.addColorStop(0, `rgba(255,250,240,${(flash * 0.55).toFixed(3)})`)
    hot.addColorStop(0.45, `rgba(255,244,228,${(flash * 0.22).toFixed(3)})`)
    hot.addColorStop(1, 'rgba(255,244,228,0)')
    ctx.fillStyle = hot
    ctx.fillRect(0, 0, w, h)
    ctx.restore()

    ctx.save()
    ctx.globalCompositeOperation = 'multiply'
    const dark = ctx.createRadialGradient(cx, cy, r * 0.45, cx, cy, r * 1.15)
    dark.addColorStop(0, 'rgba(255,255,255,1)')
    const dk = Math.round(255 - flash * 110)
    dark.addColorStop(1, `rgb(${dk},${dk},${Math.round(dk * 1.02)})`)
    ctx.fillStyle = dark
    ctx.fillRect(0, 0, w, h)
    ctx.restore()
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
    const stamp = `${months[now.getMonth()]} ${now.getDate()} ${now.getFullYear()}  ${ampm} ${hh}:${String(now.getMinutes()).padStart(2, '0')}`
    ctx.save()
    ctx.font = `600 ${Math.round(26 * ref)}px ui-monospace, Menlo, monospace`
    ctx.textBaseline = 'bottom'
    ctx.shadowColor = 'rgba(255,176,0,0.9)'
    ctx.shadowBlur = 8 * ref
    ctx.fillStyle = 'rgba(255,196,64,0.95)'
    ctx.fillText(stamp, 22 * ref, h - 20 * ref)
    ctx.fillStyle = 'rgba(255,80,64,0.95)'
    ctx.shadowColor = 'rgba(255,80,64,0.9)'
    ctx.font = `700 ${Math.round(24 * ref)}px ui-monospace, Menlo, monospace`
    ctx.fillText('● REC', 22 * ref, 46 * ref)
    ctx.restore()
  }

  /* 11 — polaroid frame (re-composites onto larger canvas) */
  let out = canvas
  if (ch.polaroidFrame && s > 0.15) {
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
