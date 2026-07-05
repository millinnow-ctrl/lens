import type { CameraStyle, StyleParams } from './styles'

export interface RenderOptions {
  /** longest edge of the output; source is downscaled to fit */
  maxSize?: number
  watermark?: boolean
  /** reuse this canvas instead of allocating one (video frame loops) */
  target?: HTMLCanvasElement
  /** jitter the grain pattern per call so video grain flickers like film */
  animateGrain?: boolean
  /** AI face lock (normalized) — flash centers here, smoothing stays on skin */
  focal?: { x: number; y: number; r: number } | null
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
  return { w: Math.max(1, Math.round(sw * scale)), h: Math.max(1, Math.round(sh * scale)) }
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
 * A filmic response LUT with a real shoulder: shadows compress into a soft
 * toe, midtones gain gentle contrast, and highlights roll off *below* pure
 * white (the "creamy highlight" that keeps digital clipping from giving the
 * look away). Blended from linear by `amt`.
 */
function filmicLut(amt: number): Uint8ClampedArray {
  const lut = new Uint8ClampedArray(256)
  for (let i = 0; i < 256; i++) {
    const x = i / 255
    const sC = x * x * (3 - 2 * x) // classic S (toe + shoulder)
    // pull the top down so white lands ~0.94 — emulsion never hits paper-white
    const f = sC - 0.06 * smoothstep(0.62, 1, x)
    lut[i] = Math.round(255 * lerp(x, f, amt))
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
    `contrast(${lerp(1, contrastAmt, Math.max(s, 0.35)).toFixed(3)})`,
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
  if (curveAmt > 0.02 || splitAmt > 0.02 || fringePx >= 1 || mtx || hiDesat > 0.02) {
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

    const lut = filmicLut(curveAmt)
    const doCurve = curveAmt > 0.02
    const sh = split ? hexRgb(split.shadows) : null
    const hi = split ? hexRgb(split.highlights) : null
    const doSplit = !!(sh && hi && splitAmt > 0.02)
    const k = splitAmt * 0.55
    const mAmt = mtx ? s : 0
    for (let i = 0; i < d.length; i += 4) {
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
      d[i] = r
      d[i + 1] = g
      d[i + 2] = b
    }
    ctx.putImageData(img, 0, 0)
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
    // smoothed skin keeps an emulsion texture instead of going plastic
    ctx.globalAlpha = (params.smoothing / 100) * (focal ? 0.42 : 0.3)
    ctx.filter = `blur(${(2.2 * ref).toFixed(2)}px)`
    ctx.drawImage(canvas, 0, 0)
    ctx.restore()
    ctx.filter = 'none'
  }

  /* 3 — halation: highlight-weighted bloom. Crushing the copy hard
     before the blur means only genuinely bright areas glow — light
     sources and speculars, not the whole midtone field. */
  const halation = (ch.halation ?? 0) * s
  if (halation > 0.01) {
    ctx.save()
    ctx.globalCompositeOperation = 'screen'
    ctx.globalAlpha = halation * 0.8
    // warm/red-biased bloom: the anti-halation layer failing scatters red
    // light around speculars — that orange halo is the film tell, not a
    // neutral glow. sepia + saturate push the crushed highlights warm.
    ctx.filter = `brightness(0.5) contrast(3.4) saturate(1.5) sepia(0.5) blur(${(9 * ref).toFixed(2)}px)`
    ctx.drawImage(canvas, 0, 0)
    ctx.restore()
    ctx.filter = 'none'
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

  /* 6 — flash: hot center + darkened surroundings. The AI face lock
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

  /* 8 — shadow depth / vignette */
  const vig = (params.shadows / 100) * s
  if (vig > 0.02) {
    ctx.save()
    const g = ctx.createRadialGradient(
      w / 2,
      h / 2,
      Math.min(w, h) * 0.35,
      w / 2,
      h / 2,
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
     slide film resolves fine. */
  const grain = params.grain / 100
  if (grain > 0.02) {
    if (animateGrain) {
      // video: cheap overlay tile, shifted each frame so grain dances
      const gs = Math.max(0.5, (ch.grainSize ?? 1) * ref)
      ctx.save()
      ctx.globalCompositeOperation = 'overlay'
      ctx.globalAlpha = grain * 0.5
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
      const amp = grain * 34 * (ch.grainAmp ?? 1)
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
    wx.fillStyle = '#8B5CF6'
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
