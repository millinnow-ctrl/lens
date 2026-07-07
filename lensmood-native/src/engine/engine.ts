/**
 * LensMood develop engine — React Native + Skia port of the web app's
 * Canvas-2D pipeline (src/lib/engine.ts).
 *
 * The heart of LensMood: a real, deterministic photo-processing pipeline.
 * Every pass is derived from the style character + user sliders, and the
 * whole look scales with `intensity`. What you preview is exactly what you
 * export.
 *
 * PORT STRATEGY
 * -------------
 * The web engine interleaves two kinds of work on a single DOM canvas:
 *   (a) per-pixel math passes  (getImageData -> mutate Uint8ClampedArray ->
 *       putImageData) — tone LUT, white balance, colour-matrix crosstalk,
 *       split-tone, highlight desat, vibrance, shadow denoise, dither, grain,
 *       clarity; and
 *   (b) composited draw passes (ctx.filter / gradients / globalCompositeOp) —
 *       the base colour pass, DoF, smoothing, halation, warmth, tint, flash,
 *       fade, vignette, light-leak.
 *
 * Here we keep the SAME order and the SAME math, but:
 *   - The current frame lives as an immutable `SkImage` (`cur`). A single
 *     reusable offscreen `SkSurface` is the scratch canvas for the composited
 *     passes; `sync()` blits `cur` onto it with BlendMode.Src before we draw
 *     overlays, and `commit()` snapshots it back into `cur`.
 *   - Per-pixel passes read `cur` via `image.readPixels()` (RGBA_8888 /
 *     Unpremul — the same straight-alpha, row-major RGBA layout the browser's
 *     getImageData gives), run the identical arithmetic, and rebuild `cur`
 *     with `Skia.Image.MakeImage()`. Because readPixels hands back a plain
 *     Uint8Array (NOT the auto-clamping Uint8ClampedArray the web used), every
 *     store back into the buffer goes through `cl()` — round + clamp to
 *     0..255 — so the math stays byte-identical to the browser result.
 *   - `ctx.filter` CSS strings become a composed 4x5 Skia colour matrix
 *     (grayscale/sepia/hue-rotate/saturate/brightness/contrast, in CSS chain
 *     order) plus an `ImageFilter.MakeBlur`, applied through a Paint.
 *   - gradients become `Skia.Shader.MakeRadialGradient / MakeLinearGradient`;
 *     `globalCompositeOperation` becomes a `BlendMode`.
 *   - The grain / dither PRNG (`nHash`, `grainSample`, `hash32`) is verbatim,
 *     so a given (style, params, image) develops identically every time.
 *
 * Public API (what the screens call):
 *   renderStyled(image, style, params, opts) -> SkImage   (the developed frame)
 *   develop(image, style, params, opts)      -> Promise<DevelopResult>
 *                                               (encodes JPEG to cache, returns uri)
 *   loadImageFromUri(uri)                     -> Promise<SkImage | null>
 */

import {
  Skia,
  BlendMode,
  TileMode,
  ClipOp,
  ColorType,
  AlphaType,
  ImageFormat,
  FontStyle,
  type SkImage,
  type SkCanvas,
  type SkSurface,
  type SkPaint,
  type SkColorFilter,
  type SkFont,
} from '@shopify/react-native-skia'
import { File, Paths } from 'expo-file-system'
import {
  NEUTRAL_SCENE,
  type CameraStyle,
  type CompositeOperation,
  type DevelopResult,
  type LensResponse,
  type LightSource,
  type RenderOptions,
  type SceneProfile,
  type StyleParams,
} from '@/engine/types'
import { analyzeScene } from '@/engine/scene'

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

/* ------------------------------------------------------------- helpers */

const lerp = (a: number, b: number, t: number) => a + (b - a) * t
const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x)
const smoothstep = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a))
  return t * t * (3 - 2 * t)
}
/** round + clamp to a byte — replaces the auto-clamp of Uint8ClampedArray */
const cl = (v: number) => (v <= 0 ? 0 : v >= 255 ? 255 : Math.round(v))
const b255 = (v: number) => (v <= 0 ? 0 : v >= 255 ? 255 : Math.round(v))

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

/** integer white-noise hash -> [0,1). The grain PRNG — deterministic per
 *  (x,y,seed) so the same develop is reproducible, and cheap enough to run
 *  per-pixel on a full frame. */
function nHash(x: number, y: number, seed: number): number {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(seed | 0, 2246822519)) >>> 0
  h = Math.imul(h ^ (h >>> 13), 1274126177)
  h ^= h >>> 16
  return (h >>> 0) / 4294967296
}

/** three-tap average -> a soft, bell-shaped (Gaussian-ish) grain value in
 *  roughly [-0.5, 0.5]; real film grain is Gaussian, not the flat uniform
 *  noise a naive overlay produces. */
function grainSample(x: number, y: number, seed: number): number {
  return (nHash(x, y, seed) + nHash(x, y, seed + 9173) + nHash(x, y, seed + 51287)) / 3 - 0.5
}

/** r,g,b (0..255) + a (0..1) -> SkColor. Uses a CSS rgba() string so the
 *  channel order is unambiguous across react-native-skia versions. */
const color = (r: number, g: number, b: number, a = 1) =>
  Skia.Color(`rgba(${b255(r)}, ${b255(g)}, ${b255(b)}, ${clamp01(a)})`)

/** map the stock data's CSS composite op onto an SkBlendMode */
function blendOf(op: CompositeOperation): BlendMode {
  switch (op) {
    case 'multiply':
      return BlendMode.Multiply
    case 'screen':
      return BlendMode.Screen
    case 'overlay':
      return BlendMode.Overlay
    case 'lighten':
      return BlendMode.Lighten
    case 'darken':
      return BlendMode.Darken
    case 'destination-out':
      return BlendMode.DstOut
    case 'source-over':
    default:
      return BlendMode.SrcOver
  }
}

/* ---------------------------------------------- CSS-filter colour matrices */
/* 4x5 colour matrices (row-major, 20 values) operating on 0..1 channels with
   0..1 offsets — exactly what Skia's ColorFilter.MakeMatrix consumes, and a
   faithful reproduction of what a browser does for each ctx.filter function.
   Values are the CSS Filter Effects / SVG feColorMatrix reference matrices. */

type Mat = number[] // length 20

const IDENTITY: Mat = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]

/** compose two matrices: apply `inner` first, then `outer` (like chained CSS
 *  filters). Both are treated as 5x5 with an implicit [0,0,0,0,1] bottom row. */
function composeMat(outer: Mat, inner: Mat): Mat {
  const A = to5x5(outer)
  const B = to5x5(inner)
  const out = new Array(25).fill(0)
  for (let r = 0; r < 5; r++)
    for (let c = 0; c < 5; c++) {
      let s = 0
      for (let k = 0; k < 5; k++) s += A[r * 5 + k] * B[k * 5 + c]
      out[r * 5 + c] = s
    }
  return from5x5(out)
}
function to5x5(m: Mat): number[] {
  return [...m, 0, 0, 0, 0, 1]
}
function from5x5(m: number[]): Mat {
  return m.slice(0, 20)
}

const brightnessMat = (b: number): Mat => [b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0]
const contrastMat = (c: number): Mat => {
  const o = 0.5 - 0.5 * c
  return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0]
}
const saturateMat = (s: number): Mat => [
  0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
  0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
  0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
  0, 0, 0, 1, 0,
]
const grayscaleMat = (a: number): Mat => {
  const k = 1 - a
  return [
    0.2126 + 0.7874 * k, 0.7152 - 0.7152 * k, 0.0722 - 0.0722 * k, 0, 0,
    0.2126 - 0.2126 * k, 0.7152 + 0.2848 * k, 0.0722 - 0.0722 * k, 0, 0,
    0.2126 - 0.2126 * k, 0.7152 - 0.7152 * k, 0.0722 + 0.9278 * k, 0, 0,
    0, 0, 0, 1, 0,
  ]
}
const sepiaMat = (a: number): Mat => {
  const k = 1 - a
  return [
    0.393 + 0.607 * k, 0.769 - 0.769 * k, 0.189 - 0.189 * k, 0, 0,
    0.349 - 0.349 * k, 0.686 + 0.314 * k, 0.168 - 0.168 * k, 0, 0,
    0.272 - 0.272 * k, 0.534 - 0.534 * k, 0.131 + 0.869 * k, 0, 0,
    0, 0, 0, 1, 0,
  ]
}
const hueRotateMat = (deg: number): Mat => {
  const r = (deg * Math.PI) / 180
  const c = Math.cos(r)
  const s = Math.sin(r)
  return [
    0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
    0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.14, 0.072 - c * 0.072 - s * 0.283, 0, 0,
    0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
    0, 0, 0, 1, 0,
  ]
}

/* --------------------------------------------------------------- tone LUT */

/**
 * The stock's full tonal response, composed into one 256-entry LUT — verbatim
 * from the web engine. gentle auto-levels -> adaptive dynamic-range recovery
 * (smart-HDR) -> metered exposure (soft pre-shoulder) -> filmic S-curve that
 * rolls highlights *below* pure white.
 */
function responseLut(
  curveAmt: number,
  ev: number,
  scene: SceneProfile,
  toneMap: number,
  adapt = 1,
): Uint8Array {
  const lut = new Uint8Array(256)
  const gain = Math.pow(2, ev)
  const lo = 0.35 * scene.p01
  const range = Math.max(0.4, 1 - 0.35 * (scene.p01 + 1 - scene.p99))
  const dr = scene.p99 - scene.p01
  const drive = toneMap * smoothstep(0.55, 0.95, dr)
  const shadowLift = drive * 0.5 * clamp01((0.45 - scene.p01) / 0.45)
  const highlightGuard = drive * 0.45 * smoothstep(0.9, 1, scene.p99)
  for (let i = 0; i < 256; i++) {
    let x = i / 255
    x = clamp01((x - lo) / range)
    if (shadowLift > 0.001) x += shadowLift * (1 - smoothstep(0, 0.55, x)) * (1 - x)
    if (highlightGuard > 0.001) x -= highlightGuard * smoothstep(0.65, 1, x) * x
    x = clamp01(x)
    let y = x * gain
    if (y > 0.82) y = 0.82 + 0.18 * (1 - Math.exp(-(y - 0.82) / 0.18))
    y = clamp01(y)
    const sC = y * y * (3 - 2 * y)
    const f = sC - 0.06 * smoothstep(0.62, 1, y)
    lut[i] = cl(255 * lerp(i / 255, lerp(y, f, curveAmt), adapt))
  }
  return lut
}

/* ---------------------------------------------------- surface primitives */

function fail(msg: string): never {
  throw new Error(`[LensMood engine] ${msg}`)
}

function makeSurface(w: number, h: number): SkSurface {
  const s = Skia.Surface.MakeOffscreen(w, h)
  if (!s) fail(`could not allocate ${w}x${h} offscreen surface`)
  return s
}

function snapshot(surface: SkSurface): SkImage {
  surface.flush()
  const img = surface.makeImageSnapshot()
  if (!img) fail('makeImageSnapshot returned null')
  return img
}

/** RGBA_8888 / Unpremul straight-alpha pixels of an image, or null */
function readRGBA(img: SkImage): Uint8Array | null {
  const px = img.readPixels(0, 0, {
    width: img.width(),
    height: img.height(),
    colorType: ColorType.RGBA_8888,
    alphaType: AlphaType.Unpremul,
  })
  return px instanceof Uint8Array ? px : null
}

/** build an opaque SkImage from a straight-alpha RGBA byte buffer */
function imageFromRGBA(px: Uint8Array, w: number, h: number): SkImage {
  const data = Skia.Data.fromBytes(px)
  const img = Skia.Image.MakeImage(
    { width: w, height: h, colorType: ColorType.RGBA_8888, alphaType: AlphaType.Unpremul },
    data,
    w * 4,
  )
  if (!img) fail('MakeImage returned null')
  return img
}

/** a paint whose colour filter is the composed CSS-filter matrix (or none) */
function matrixPaint(mat: Mat | null): SkPaint {
  const p = Skia.Paint()
  p.setAntiAlias(true)
  if (mat) p.setColorFilter(Skia.ColorFilter.MakeMatrix(mat))
  return p
}

/* ---------------------------------------------------------- optional text */

function getFont(size: number, bold: boolean): SkFont | null {
  try {
    const mgr = Skia.FontMgr.System()
    if (!mgr) return null
    // an empty family name is undefined behavior on some platforms — ask for
    // a concrete platform family and fall through to sane alternates
    const styleSpec = bold ? FontStyle.Bold : FontStyle.Normal
    const tf =
      mgr.matchFamilyStyle('Menlo', styleSpec) ??
      mgr.matchFamilyStyle('Courier', styleSpec) ??
      mgr.matchFamilyStyle('sans-serif', styleSpec)
    if (!tf) return null
    return Skia.Font(tf, size)
  } catch {
    return null
  }
}

/* ------------------------------------------------------------ pipeline */

/**
 * Develop `source` with `style` + `params`. Returns the finished frame as an
 * immutable SkImage. Synchronous and deterministic.
 */
export function renderStyled(
  source: SkImage,
  style: CameraStyle,
  params: StyleParams,
  opts: RenderOptions = {},
): SkImage {
  const { maxSize = 1280, watermark = false, animateGrain = false, focal = null } = opts
  const ch = style.character
  const s = params.intensity / 100 // global look strength

  // ----- fit -----
  const sw = source.width()
  const sh = source.height()
  const scale = Math.min(1, maxSize / Math.max(sw, sh))
  const w = Math.max(1, Math.round(sw * scale) || 1)
  const h = Math.max(1, Math.round(sh * scale) || 1)
  const ref = Math.max(w, h) / 1000 // scale-independent px unit

  /* 0 — the light meter reads the scene (cached). `scene: null` disables
     adaptation; undefined means analyze. */
  const scene =
    opts.scene !== undefined ? (opts.scene ?? NEUTRAL_SCENE) : analyzeScene(source, focal)
  const lens = { ...DEFAULT_LENS, ...ch.lens }
  const keyEff =
    scene.faceLum != null ? lerp(scene.key, scene.faceLum, lens.faceWeight) : scene.key
  const meterTarget = (scene.faceLum != null ? 0.45 : 0.4) * Math.pow(2, lens.meterBias)
  const ev = Math.max(
    -1.25,
    Math.min(1.7, Math.log2(meterTarget / Math.max(0.02, keyEff)) * lens.meterStrength * s),
  )
  const wbK = lens.awb * s
  const wbGain = (c: number) =>
    lerp(1, Math.max(1 - lens.awbClamp, Math.min(1 + lens.awbClamp, c)), wbK)
  const Gr = wbGain(scene.illum[0])
  const Gg = wbGain(scene.illum[1])
  const Gb = wbGain(scene.illum[2])
  const doWb = Math.abs(Gr - 1) > 0.015 || Math.abs(Gg - 1) > 0.015 || Math.abs(Gb - 1) > 0.015
  const doLevels = scene.p01 > 0.02 || scene.p99 < 0.94
  const toneMap = lens.toneMap * s
  const doTone = toneMap > 0.02 && scene.analyzed && scene.p99 - scene.p01 > 0.55

  // ----- the reusable scratch surface + current frame -----
  const surface = makeSurface(w, h)
  const canvas = surface.getCanvas()
  let cur: SkImage
  // true when `surface` no longer reflects `cur` (after a per-pixel rebuild)
  let dirty = false

  const srcPaint = Skia.Paint()
  srcPaint.setBlendMode(BlendMode.Src)
  /** blit `cur` onto the scratch surface so overlays draw on top of it */
  const sync = () => {
    if (dirty) {
      canvas.drawImage(cur, 0, 0, srcPaint)
      dirty = false
    }
  }
  /** snapshot the scratch surface back into `cur` (surface still reflects it) */
  const commit = () => {
    cur = snapshot(surface)
    dirty = false
  }
  /** replace `cur` from a per-pixel rebuild (surface now stale) */
  const setCur = (img: SkImage) => {
    cur = img
    dirty = true
  }

  const full = Skia.XYWHRect(0, 0, w, h)

  /* 1 — base colour pass: the CSS ctx.filter chain becomes one composed
     colour matrix (grayscale/sepia/hue/saturate/brightness/contrast) plus an
     ImageFilter blur, applied while downscaling the source into the frame. */
  {
    const contrastAmt = 0.72 + (params.contrast / 100) * 0.62 // 0.72..1.34
    let mat = IDENTITY
    if (ch.bw) mat = composeMat(grayscaleMat(Math.min(1, s * 1.25)), mat)
    if (ch.sepia) mat = composeMat(sepiaMat(ch.sepia * s), mat)
    if (ch.hue) mat = composeMat(hueRotateMat(ch.hue * s), mat)
    mat = composeMat(saturateMat(lerp(1, ch.saturate ?? 1, s)), mat)
    mat = composeMat(brightnessMat(lerp(1, ch.brightness ?? 1, s)), mat)
    mat = composeMat(contrastMat(lerp(1, contrastAmt, s)), mat)

    const paint = matrixPaint(mat)
    const blurSigma = ch.blur ? ch.blur * s * ref : 0
    if (blurSigma > 0.01) {
      paint.setImageFilter(Skia.ImageFilter.MakeBlur(blurSigma, blurSigma, TileMode.Clamp, null))
    }
    canvas.drawImageRect(source, Skia.XYWHRect(0, 0, sw, sh), full, paint)
    commit()
  }

  /* 1.5 — film response: white balance, tone LUT, channel crosstalk, split
     toning, highlight desat, vibrance, shadow denoise, chroma fringe, dither.
     Verbatim per-pixel math (see cl() note in the file header). */
  const curveAmt = (ch.curve ?? 0) * s
  const split = ch.splitTone
  const splitAmt = (split?.amount ?? 0) * s
  const fringePx = Math.round((ch.fringe ?? 0) * s * ref)
  const mtx = ch.colorMatrix // 3x3 channel crosstalk
  const hiDesat = 0.6 * s
  const doMeter = Math.abs(ev) > 0.02 || doLevels || doTone
  const vib =
    lens.vibrance * s * (scene.analyzed ? 0.08 + 0.92 * smoothstep(0.4, 0.12, scene.sat) : 0.08)
  const doVib = vib > 0.02 && !ch.bw
  const sdn = lens.shadowDenoise * s * (scene.analyzed ? smoothstep(0.3, 0.08, scene.key) : 0)
  const doSdn = sdn > 0.02
  if (curveAmt > 0.02 || splitAmt > 0.02 || fringePx >= 1 || mtx || hiDesat > 0.02 || doMeter || doWb || doVib || doSdn) {
    const d = readRGBA(cur)
    if (d) {
      if (fringePx >= 1) {
        // chromatic fringe: red shifts right, blue shifts left
        const orig = new Uint8Array(d)
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
      const sh2 = split ? hexRgb(split.shadows) : null
      const hi = split ? hexRgb(split.highlights) : null
      const doSplit = !!(sh2 && hi && splitAmt > 0.02)
      const k = splitAmt * 0.55
      const mAmt = mtx ? s : 0
      const dither = doCurve ? 1.1 * Math.min(1, s * 1.25) : 0
      const dseed = hash32(style.id) ^ 0x9e3779b9
      for (let i = 0; i < d.length; i += 4) {
        if (doWb) {
          d[i] = cl(d[i] * Gr)
          d[i + 1] = cl(d[i + 1] * Gg)
          d[i + 2] = cl(d[i + 2] * Gb)
        }
        let r = doCurve ? lut[d[i]] : d[i]
        let g = doCurve ? lut[d[i + 1]] : d[i + 1]
        let b = doCurve ? lut[d[i + 2]] : d[i + 2]
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
          r += ((sh2![0] - 128) * wsh + (hi![0] - 128) * lum) * k
          g += ((sh2![1] - 128) * wsh + (hi![1] - 128) * lum) * k
          b += ((sh2![2] - 128) * wsh + (hi![2] - 128) * lum) * k
        }
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
              let guard = 1
              if (r > g && g >= b) {
                const hue = (g - b) / (mx - mn)
                const skinW = smoothstep(0.12, 0.3, hue) * (1 - smoothstep(0.62, 0.88, hue))
                guard = 1 - 0.75 * skinW
              }
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
        d[i] = cl(r)
        d[i + 1] = cl(g)
        d[i + 2] = cl(b)
      }
      setCur(imageFromRGBA(d, w, h))
    }
  }

  /* 1.6 — finish sharpness. Two unsharp scales, both midtone-weighted
     (stills only — too heavy for the per-frame video path):
     · acutance — a fine ~2px pass applied to EVERY stock, so a develop
       always reads crisper than the upload, never softer.
     · clarity — the per-stock wide local contrast ("detail that bites"). */
  const clarity = lens.clarity * s
  const acutance = 0.22 * s
  if ((clarity > 0.02 || acutance > 0.02) && !animateGrain) {
    const passes: Array<[number, number]> = []
    if (acutance > 0.02) passes.push([2.2 * ref, acutance])
    if (clarity > 0.02) passes.push([14 * ref, clarity])
    for (const [radius, amt] of passes) {
      const bd = readRGBA(cur)
      if (!bd) continue
      // blurred copy of `cur`
      sync()
      const blurPaint = Skia.Paint()
      blurPaint.setImageFilter(Skia.ImageFilter.MakeBlur(radius, radius, TileMode.Clamp, null))
      // draw onto a scratch: reuse the surface (it holds cur), overdraw blurred
      canvas.drawImage(cur, 0, 0, blurPaint)
      const blurImg = snapshot(surface)
      const blurD = readRGBA(blurImg)
      // restore the sharp frame onto the surface for later stages
      dirty = true
      if (blurD) {
        for (let i = 0; i < bd.length; i += 4) {
          const L = (bd[i] * 0.299 + bd[i + 1] * 0.587 + bd[i + 2] * 0.114) / 255
          const wgt = amt * (4 * L * (1 - L))
          if (wgt > 0.003) {
            bd[i] = cl(bd[i] + (bd[i] - blurD[i]) * wgt)
            bd[i + 1] = cl(bd[i + 1] + (bd[i + 1] - blurD[i + 1]) * wgt)
            bd[i + 2] = cl(bd[i + 2] + (bd[i + 2] - blurD[i + 2]) * wgt)
          }
        }
        setCur(imageFromRGBA(bd, w, h))
      }
    }
  }

  /* 1.75 — subject separation (DoF): a blurred + specular-bloomed copy with a
     feathered capsule punched out over the subject, composited over the sharp
     frame. Built on its own surface so the punched hole keeps real alpha. */
  const dof = lens.dof * s
  if (focal && dof > 0.03) {
    const fx = focal.x * w
    const fy = focal.y * h
    const fr = Math.max(focal.r * Math.max(w, h), 24)
    const bgSurface = makeSurface(w, h)
    const bx = bgSurface.getCanvas()

    // the defocus itself — radius scales with the separation amount
    const defocusSigma = 3.4 * dof * ref + 1
    const defocusPaint = Skia.Paint()
    defocusPaint.setBlendMode(BlendMode.Src)
    defocusPaint.setImageFilter(Skia.ImageFilter.MakeBlur(defocusSigma, defocusSigma, TileMode.Clamp, null))
    bx.drawImage(cur, 0, 0, defocusPaint)

    // specular bokeh: crush hard, blur wide, screen back over the defocus
    const specSigma = 8 * dof * ref + 2
    const specPaint = Skia.Paint()
    specPaint.setBlendMode(BlendMode.Screen)
    specPaint.setAlphaf(Math.min(0.85, 0.4 + dof * 0.5))
    specPaint.setColorFilter(composeCF([brightnessMat(0.4), contrastMat(3.4)]))
    specPaint.setImageFilter(Skia.ImageFilter.MakeBlur(specSigma, specSigma, TileMode.Clamp, null))
    bx.drawImage(cur, 0, 0, specPaint)

    // carve the sharp subject back out: opaque frame edge -> transparent hole
    bx.save()
    bx.translate(fx, fy + fr * 1.1)
    bx.scale(1, 2.2)
    const outerR = fr * 2.1
    const holePaint = Skia.Paint()
    holePaint.setBlendMode(BlendMode.DstOut)
    holePaint.setShader(
      Skia.Shader.MakeRadialGradient(
        Skia.Point(0, 0),
        outerR,
        [color(0, 0, 0, 1), color(0, 0, 0, 0)],
        [(fr * 0.65) / outerR, 1],
        TileMode.Clamp,
      ),
    )
    bx.drawRect(Skia.XYWHRect(-(w + h), -(w + h), (w + h) * 2, (w + h) * 2), holePaint)
    bx.restore()
    const bgImg = snapshot(bgSurface)

    // lay the (subject-punched) blur back over the sharp frame
    sync()
    const overPaint = Skia.Paint()
    overPaint.setAlphaf(Math.min(1, 0.55 + dof * 0.45))
    canvas.drawImage(bgImg, 0, 0, overPaint)
    commit()
  }

  /* 2 — skin smoothing: soft-blurred self-blend, clipped to a face ellipse
     when a focal lock exists so texture elsewhere stays crisp. */
  if (params.smoothing > 0) {
    sync()
    canvas.save()
    if (focal) {
      const fx = focal.x * w
      const fy = focal.y * h
      const fr = Math.max(focal.r * Math.max(w, h) * 1.15, 24)
      const path = Skia.Path.Make()
      path.addOval(Skia.XYWHRect(fx - fr, fy - fr * 1.25, fr * 2, fr * 1.25 * 2))
      canvas.clipPath(path, ClipOp.Intersect, true)
    }
    const smSigma = 2.2 * ref
    const smPaint = Skia.Paint()
    // without a subject lock, "beauty blur" over the whole frame is just
    // fuzz — cap it near-invisible; with a face it stays a real retouch
    smPaint.setAlphaf((params.smoothing / 100) * (focal ? 0.42 : 0.12) * Math.min(1, s * 1.25))
    smPaint.setImageFilter(Skia.ImageFilter.MakeBlur(smSigma, smSigma, TileMode.Clamp, null))
    canvas.drawImage(cur, 0, 0, smPaint)
    canvas.restore()
    commit()
  }

  /* 3 — halation: highlight-weighted bloom, concentrated on detected lights */
  const halation = (ch.halation ?? 0) * s
  if (halation > 0.01) {
    const lights = scene.lights
    const onLights = lights.length ? lens.lightHalation : 0
    // scene-adaptive bloom: night keeps 100%, bright daylight drops to ~35%
    // so big sky regions never wash the frame lighter+softer. Per-light
    // halos are untouched.
    const bloomScale = scene.analyzed ? 0.35 + 0.65 * smoothstep(0.55, 0.18, scene.key) : 1
    sync()
    // warm/red-biased bloom: crush + saturate + sepia + wide blur, screened back
    const bloomPaint = Skia.Paint()
    bloomPaint.setBlendMode(BlendMode.Screen)
    bloomPaint.setAlphaf(halation * 0.8 * (1 - 0.25 * onLights) * bloomScale)
    // crush tight: only true highlights may glow, never the midtone field
    bloomPaint.setColorFilter(
      composeCF([brightnessMat(0.46), contrastMat(3.8), saturateMat(1.5), sepiaMat(0.5)]),
    )
    const bloomSigma = 9 * ref
    bloomPaint.setImageFilter(Skia.ImageFilter.MakeBlur(bloomSigma, bloomSigma, TileMode.Clamp, null))
    canvas.drawImage(cur, 0, 0, bloomPaint)

    if (onLights > 0) {
      for (const lt of lights) {
        const lr = Math.max(w, h) * (4 * lt.r + 0.05) * (1 + halation * 0.6)
        const a = Math.min(0.5, halation * onLights * lt.intensity * 0.9)
        if (a < 0.02) continue
        // the halo takes the light's own colour, pushed back out from the
        // washed ring mean, then brightened
        const tMean = (lt.tint[0] + lt.tint[1] + lt.tint[2]) / 3
        const chroma = (c: number) => Math.min(255, Math.max(0, (tMean + (c - tMean) * 2.6) * 255 * 1.35))
        const r = Math.round(chroma(lt.tint[0]))
        const g = Math.round(chroma(lt.tint[1]))
        const bch = Math.round(chroma(lt.tint[2]))
        const glowPaint = Skia.Paint()
        glowPaint.setBlendMode(BlendMode.Screen)
        glowPaint.setShader(
          Skia.Shader.MakeRadialGradient(
            Skia.Point(lt.x * w, lt.y * h),
            lr,
            [color(r, g, bch, a), color(r, g, bch, a * 0.35), color(r, g, bch, 0)],
            [0, 0.5, 1],
            TileMode.Clamp,
          ),
        )
        canvas.drawRect(full, glowPaint)
      }
    }
    commit()
  }

  /* 4 — warmth: overlay colour wash (warm orange / cool blue) */
  const warmth = ((params.warmth - 50) / 50) * s // -1..1
  if (Math.abs(warmth) > 0.02) {
    sync()
    fillRect(canvas, full, warmth > 0 ? color(255, 140, 40, 1) : color(60, 120, 255, 1), Math.abs(warmth) * 0.3, BlendMode.Overlay)
    commit()
  }

  /* 5 — style tint */
  if (ch.tint) {
    sync()
    const [tr, tg, tb] = hexRgb(ch.tint.color)
    fillRect(canvas, full, color(tr, tg, tb, 1), ch.tint.alpha * s, blendOf(ch.tint.blend))
    commit()
  }

  /* 6 — flash: hot centre + darkened surroundings (locked to the subject) */
  const flash = (params.flash / 100) * s
  if (flash > 0.02) {
    const cx = (focal ? focal.x : 0.5) * w
    const cy = (focal ? focal.y : 0.42) * h
    const r = Math.max(w, h) * (focal ? Math.max(0.5, focal.r * 4.5) : 0.72)
    sync()
    // hot core (screen)
    const hot = Skia.Paint()
    hot.setBlendMode(BlendMode.Screen)
    hot.setShader(
      Skia.Shader.MakeRadialGradient(
        Skia.Point(cx, cy),
        r,
        [color(255, 250, 240, flash * 0.55), color(255, 244, 228, flash * 0.22), color(255, 244, 228, 0)],
        [0, 0.45, 1],
        TileMode.Clamp,
      ),
    )
    canvas.drawRect(full, hot)
    // darkened surround (multiply)
    const dk = Math.round(255 - flash * 110)
    const outerR = r * 1.15
    const dark = Skia.Paint()
    dark.setBlendMode(BlendMode.Multiply)
    dark.setShader(
      Skia.Shader.MakeRadialGradient(
        Skia.Point(cx, cy),
        outerR,
        [color(255, 255, 255, 1), color(dk, dk, Math.round(dk * 1.02), 1)],
        [(r * 0.45) / outerR, 1],
        TileMode.Clamp,
      ),
    )
    canvas.drawRect(full, dark)
    commit()
  }

  /* 7 — faded blacks (film lift) */
  const fade = (ch.fade ?? 0) * s
  if (fade > 0.01) {
    sync()
    const L = Math.round(fade * 52)
    fillRect(canvas, full, color(L, L, Math.round(L * 1.05), 1), 1, BlendMode.Lighten)
    commit()
  }

  /* 8 — shadow depth / vignette (rides toward the subject when locked) */
  const vig = (params.shadows / 100) * s
  if (vig > 0.02) {
    const vx = focal ? lerp(w / 2, focal.x * w, 0.6) : w / 2
    const vy = focal ? lerp(h / 2, focal.y * h, 0.6) : h / 2
    const inner = Math.min(w, h) * 0.35
    const outer = Math.max(w, h) * 0.78
    sync()
    const vp = Skia.Paint()
    vp.setShader(
      Skia.Shader.MakeRadialGradient(
        Skia.Point(vx, vy),
        outer,
        [color(8, 8, 12, 0), color(8, 8, 12, vig * 0.55)],
        [inner / outer, 1],
        TileMode.Clamp,
      ),
    )
    canvas.drawRect(full, vp)
    commit()
  }

  /* 8.5 — light leak: a warm flare from one edge, hashed from the style id */
  const leak = (ch.leak ?? 0) * s
  if (leak > 0.02) {
    const seed = hash32(style.id)
    const fromLeft = (seed & 1) === 0
    const cy = h * (0.15 + ((seed >> 3) % 60) / 100)
    const cx = fromLeft ? -w * 0.08 : w * 1.08
    const radius = Math.max(w, h) * 0.55
    sync()
    const flare = Skia.Paint()
    flare.setBlendMode(BlendMode.Screen)
    flare.setShader(
      Skia.Shader.MakeRadialGradient(
        Skia.Point(cx, cy),
        radius,
        [color(255, 120, 40, leak * 0.55), color(255, 60, 60, leak * 0.22), color(255, 60, 60, 0)],
        [0, 0.45, 1],
        TileMode.Clamp,
      ),
    )
    canvas.drawRect(full, flare)
    const band = Skia.Paint()
    band.setBlendMode(BlendMode.Screen)
    band.setShader(
      Skia.Shader.MakeLinearGradient(
        Skia.Point(fromLeft ? 0 : w, 0),
        Skia.Point(fromLeft ? w * 0.22 : w * 0.78, 0),
        [color(255, 180, 90, leak * 0.35), color(255, 180, 90, 0)],
        [0, 1],
        TileMode.Clamp,
      ),
    )
    canvas.drawRect(full, band)
    commit()
  }

  /* 9 — grain: luminance-weighted Gaussian grain, embedded per-pixel, clumped
     to the stock's grain size and pushed by the measured scene key (auto-ISO).
     Verbatim PRNG. (M1 is stills-only; animateGrain just jitters the seed.) */
  const isoBoost = scene.analyzed
    ? 1 + lens.autoIso * 1.2 * smoothstep(0.32, 0.06, scene.key)
    : 1
  const grain = params.grain / 100
  if (grain > 0.02) {
    const dd = readRGBA(cur)
    if (dd) {
      const gs = Math.max(1, Math.round((ch.grainSize ?? 1) * ref))
      const amp = grain * 34 * (ch.grainAmp ?? 1) * Math.min(1, s * 1.25) * isoBoost
      const chroma = ch.bw ? 0 : (ch.grainChroma ?? 0.4)
      let seed = hash32(style.id) & 0xffff
      if (animateGrain) seed = (seed + ((Math.random() * 0xffff) | 0)) & 0xffff
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
            dd[idx] = cl(dd[idx] + mono + grainSample(gx, gy, seed + 13) * amp * chroma * wgt)
            dd[idx + 1] = cl(dd[idx + 1] + mono + grainSample(gx, gy, seed + 37) * amp * chroma * wgt)
            dd[idx + 2] = cl(dd[idx + 2] + mono + grainSample(gx, gy, seed + 61) * amp * chroma * wgt)
          } else {
            dd[idx] = cl(dd[idx] + mono)
            dd[idx + 1] = cl(dd[idx + 1] + mono)
            dd[idx + 2] = cl(dd[idx + 2] + mono)
          }
        }
      }
      setCur(imageFromRGBA(dd, w, h))
    }
  }

  /* 10 — camcorder scanlines + timestamp */
  if (ch.scanlines) {
    sync()
    const step = Math.max(2, Math.round(3 * ref))
    const linePaint = Skia.Paint()
    linePaint.setColor(color(0, 0, 0, 1))
    linePaint.setAlphaf(0.1 * s)
    for (let y = 0; y < h; y += step * 2) canvas.drawRect(Skia.XYWHRect(0, y, w, step), linePaint)
    commit()
  }
  if (ch.timestamp && s > 0.15) {
    sync()
    if (drawTimestamp(canvas, w, h, ref)) commit()
  }

  /* 11 — polaroid frame (re-composites onto a larger surface) */
  let outImg = cur
  let outW = w
  let outH = h
  let outSurface: SkSurface = surface
  if (ch.polaroidFrame && s > 0.15) {
    sync()
    const m = Math.round(Math.max(w, h) * 0.055)
    const bottom = Math.round(Math.max(w, h) * 0.16)
    const fw = w + m * 2
    const fh = h + m + bottom
    const fs = makeSurface(fw, fh)
    const fc = fs.getCanvas()
    const paperPaint = Skia.Paint()
    paperPaint.setShader(
      Skia.Shader.MakeLinearGradient(
        Skia.Point(0, 0),
        Skia.Point(0, fh),
        [color(0xfd, 0xfc, 0xf8, 1), color(0xf3, 0xef, 0xe6, 1)],
        [0, 1],
        TileMode.Clamp,
      ),
    )
    fc.drawRect(Skia.XYWHRect(0, 0, fw, fh), paperPaint)
    fc.drawImage(cur, m, m)
    outImg = snapshot(fs)
    outW = fw
    outH = fh
    outSurface = fs
  }

  /* 12 — watermark for free exports: engraved mono plate, bottom-right */
  if (watermark) {
    const oc = outSurface.getCanvas()
    // ensure the surface reflects outImg before we draw on top of it
    oc.drawImage(outImg, 0, 0, srcPaint)
    drawWatermark(oc, outW, outH)
    outImg = snapshot(outSurface)
  }

  return outImg
}

/* --------------------------------------------------------- draw helpers */

/** solid-colour full-frame fill at a given alpha + blend mode (ctx.fillRect) */
function fillRect(canvas: SkCanvas, rect: ReturnType<typeof Skia.XYWHRect>, c: ReturnType<typeof Skia.Color>, alpha: number, blend: BlendMode) {
  const p = Skia.Paint()
  p.setColor(c)
  p.setAlphaf(clamp01(alpha))
  p.setBlendMode(blend)
  canvas.drawRect(rect, p)
}

/** compose a list of CSS-filter matrices (applied left-to-right) into one
 *  Skia ColorFilter */
function composeCF(mats: Mat[]): SkColorFilter {
  let m = IDENTITY
  for (const next of mats) m = composeMat(next, m)
  return Skia.ColorFilter.MakeMatrix(m)
}

function drawTimestamp(canvas: SkCanvas, w: number, h: number, ref: number): boolean {
  const font = getFont(Math.round(26 * ref), true)
  const recFont = getFont(Math.round(24 * ref), true)
  if (!font) return false
  const now = new Date()
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
  const hh = now.getHours() % 12 || 12
  const ampm = now.getHours() >= 12 ? 'PM' : 'AM'
  const stamp = `${months[now.getMonth()]} ${now.getDate()} ${now.getFullYear()}  ${ampm} ${hh}:${String(now.getMinutes()).padStart(2, '0')}`
  const stampPaint = Skia.Paint()
  stampPaint.setColor(color(255, 196, 64, 0.95))
  canvas.drawText(stamp, 22 * ref, h - 20 * ref, stampPaint, font)
  if (recFont) {
    const recPaint = Skia.Paint()
    recPaint.setColor(color(255, 80, 64, 0.95))
    canvas.drawText('● REC', 22 * ref, 46 * ref, recPaint, recFont)
  }
  return true
}

function drawWatermark(canvas: SkCanvas, W: number, H: number) {
  try {
    const fs = Math.max(10, Math.round(Math.max(W, H) * 0.016))
    const font = getFont(fs, false)
    const text = 'SHOT ON LENSMOOD'
    const pad = fs * 0.8
    const dot = fs * 0.34
    const tw = font ? font.measureText(text).width : text.length * fs * 0.6
    const bw = tw + pad * 2 + dot * 2 + fs * 0.5
    const bh = fs * 2.2
    const x = W - bw - fs
    const y = H - bh - fs
    // plate
    const plate = Skia.Paint()
    plate.setColor(color(16, 16, 16, 0.62))
    canvas.drawRect(Skia.XYWHRect(x, y, bw, bh), plate)
    // brand dot
    const dotPaint = Skia.Paint()
    dotPaint.setColor(color(0x0f, 0x7d, 0x92, 1))
    dotPaint.setAntiAlias(true)
    canvas.drawCircle(x + pad + dot, y + bh / 2, dot, dotPaint)
    // text
    if (font) {
      const txt = Skia.Paint()
      txt.setColor(color(246, 245, 241, 0.95))
      canvas.drawText(text, x + pad + dot * 2 + fs * 0.5, y + bh / 2 + fs * 0.32, txt, font)
    }
  } catch {
    // watermark is best-effort; never fail a develop over it
  }
}

/* ------------------------------------------------------------- encode/IO */

/**
 * Develop and persist. Renders the frame, encodes a JPEG, writes it to the
 * cache directory, and returns the Skia-agnostic DevelopResult the develop /
 * export screens consume.
 */
export async function develop(
  source: SkImage,
  style: CameraStyle,
  params: StyleParams,
  opts: RenderOptions = {},
): Promise<DevelopResult> {
  const img = renderStyled(source, style, params, opts)
  const bytes = img.encodeToBytes(ImageFormat.JPEG, 92)
  const name = `lensmood-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`
  const file = new File(Paths.cache, name)
  // the new expo-file-system File.write() does NOT auto-create the file
  if (!file.exists) file.create()
  file.write(bytes)
  return { uri: file.uri, width: img.width(), height: img.height() }
}

/**
 * Load an image from a file:// / content:// / http(s) URI into an SkImage.
 * Screens pass the picked-photo URI here, then hand the SkImage to
 * renderStyled / analyzeScene.
 */
export async function loadImageFromUri(uri: string): Promise<SkImage | null> {
  try {
    const data = await Skia.Data.fromURI(uri)
    const img = Skia.Image.MakeImageFromEncoded(data)
    return img ?? null
  } catch {
    return null
  }
}

/** re-export so screens can type light sources without importing scene.ts */
export type { LightSource }
