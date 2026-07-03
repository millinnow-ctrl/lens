import type { CameraStyle, StyleParams } from './styles'

export interface RenderOptions {
  /** longest edge of the output; source is downscaled to fit */
  maxSize?: number
  watermark?: boolean
  /** reuse this canvas instead of allocating one (video frame loops) */
  target?: HTMLCanvasElement
  /** jitter the grain pattern per call so video grain flickers like film */
  animateGrain?: boolean
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
  const { maxSize = 1280, watermark = false, target, animateGrain = false } = opts
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
    ch.bw ? `grayscale(${s})` : '',
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

  /* 2 — skin smoothing: soft-blurred self-blend */
  if (params.smoothing > 0) {
    ctx.save()
    ctx.globalAlpha = (params.smoothing / 100) * 0.4
    ctx.filter = `blur(${(2.5 * ref).toFixed(2)}px)`
    ctx.drawImage(canvas, 0, 0)
    ctx.restore()
    ctx.filter = 'none'
  }

  /* 3 — halation / bloom: blurred bright self-blend in screen mode */
  const halation = (ch.halation ?? 0) * s
  if (halation > 0.01) {
    ctx.save()
    ctx.globalCompositeOperation = 'screen'
    ctx.globalAlpha = halation * 0.5
    ctx.filter = `blur(${(7 * ref).toFixed(2)}px) brightness(1.15) contrast(1.25)`
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

  /* 6 — flash: hot center + darkened surroundings */
  const flash = (params.flash / 100) * s
  if (flash > 0.02) {
    const cx = w * 0.5
    const cy = h * 0.42
    const r = Math.max(w, h) * 0.72
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

  /* 9 — grain */
  const grain = params.grain / 100
  if (grain > 0.02) {
    ctx.save()
    ctx.globalCompositeOperation = 'overlay'
    ctx.globalAlpha = grain * 0.55
    ctx.fillStyle = ctx.createPattern(getNoiseTile(), 'repeat')!
    if (animateGrain) {
      // shift the tile a random amount each frame so video grain dances
      const ox = Math.floor(Math.random() * 192)
      const oy = Math.floor(Math.random() * 192)
      ctx.translate(-ox, -oy)
      ctx.fillRect(0, 0, w + 192, h + 192)
    } else {
      ctx.fillRect(0, 0, w, h)
    }
    ctx.restore()
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
    // record dot
    wx.fillStyle = '#E1251B'
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
