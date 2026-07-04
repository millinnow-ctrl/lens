import { renderStyled } from './engine'
import type { Focal } from './focal'
import type { CameraStyle, StyleParams } from './styles'

/**
 * Share-card composers — turn a developed photo into something worth
 * posting: a 9:16 story card or a 4:5 before/after split. Everything is
 * drawn on canvas on-device, same as the develop pipeline.
 */

const roundedPath = (
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
) => {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

/** cover-draw a source canvas/image into a rect */
const drawCover = (
  ctx: CanvasRenderingContext2D,
  src: HTMLCanvasElement | HTMLImageElement,
  x: number,
  y: number,
  w: number,
  h: number,
) => {
  const sw = 'width' in src ? (src.width as number) : 0
  const sh = 'height' in src ? (src.height as number) : 0
  const scale = Math.max(w / sw, h / sh)
  const dw = sw * scale
  const dh = sh * scale
  ctx.drawImage(src, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh)
}

/** brand pill: "● LensMood" + optional style name, bottom-centered */
const drawBrandPill = (
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  label: string,
) => {
  const fs = 34
  ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`
  const tw = ctx.measureText(label).width
  const dot = 10
  const padX = 34
  const gap = 16
  const bw = tw + dot * 2 + gap + padX * 2
  const bh = fs * 2.1
  roundedPath(ctx, cx - bw / 2, cy - bh / 2, bw, bh, bh / 2)
  ctx.fillStyle = 'rgba(23,19,31,0.72)'
  ctx.fill()
  // gradient brand dot
  const g = ctx.createLinearGradient(cx - bw / 2 + padX, 0, cx - bw / 2 + padX + dot * 2, 0)
  g.addColorStop(0, '#a855f7')
  g.addColorStop(1, '#ec4899')
  ctx.fillStyle = g
  ctx.beginPath()
  ctx.arc(cx - bw / 2 + padX + dot, cy, dot, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = 'rgba(255,255,255,0.96)'
  ctx.textBaseline = 'middle'
  ctx.fillText(label, cx - bw / 2 + padX + dot * 2 + gap, cy + 2)
}

/** 1080x1920 story card: blurred backdrop, floating framed shot, brand pill */
export function makeStoryCard(
  source: HTMLImageElement,
  style: CameraStyle,
  params: StyleParams,
  opts: { watermark?: boolean; focal?: Focal | null } = {},
): HTMLCanvasElement {
  const W = 1080
  const H = 1920
  const styled = renderStyled(source, style, params, { maxSize: 1600, watermark: opts.watermark, focal: opts.focal })

  const out = document.createElement('canvas')
  out.width = W
  out.height = H
  const ctx = out.getContext('2d')!

  // backdrop: the shot itself, blown up, blurred and dimmed
  ctx.filter = 'blur(60px) brightness(0.55) saturate(1.1)'
  drawCover(ctx, styled, -80, -80, W + 160, H + 160)
  ctx.filter = 'none'

  // floating shot, fitted inside a margin with rounded corners + shadow
  const maxW = W - 160
  const maxH = H - 560
  const scale = Math.min(maxW / styled.width, maxH / styled.height)
  const dw = styled.width * scale
  const dh = styled.height * scale
  const dx = (W - dw) / 2
  const dy = (H - dh) / 2 - 60

  ctx.save()
  ctx.shadowColor = 'rgba(0,0,0,0.55)'
  ctx.shadowBlur = 90
  ctx.shadowOffsetY = 36
  roundedPath(ctx, dx, dy, dw, dh, 36)
  ctx.fillStyle = '#111'
  ctx.fill()
  ctx.restore()

  ctx.save()
  roundedPath(ctx, dx, dy, dw, dh, 36)
  ctx.clip()
  ctx.drawImage(styled, dx, dy, dw, dh)
  ctx.restore()

  drawBrandPill(ctx, W / 2, dy + dh + 130, `${style.name} — LensMood`)
  return out
}

/** 1080x1350 before/after split with labels and brand pill */
export function makeSplitCard(
  source: HTMLImageElement,
  style: CameraStyle,
  params: StyleParams,
  opts: { watermark?: boolean; focal?: Focal | null } = {},
): HTMLCanvasElement {
  const W = 1080
  const H = 1350
  const styled = renderStyled(source, style, params, { maxSize: 1600, watermark: opts.watermark, focal: opts.focal })

  const out = document.createElement('canvas')
  out.width = W
  out.height = H
  const ctx = out.getContext('2d')!

  const half = W / 2
  // left: original — clip to the left half of a cover-fit of the FULL frame,
  // so both sides show the same crop and the seam reads as one photo
  ctx.save()
  ctx.beginPath()
  ctx.rect(0, 0, half, H)
  ctx.clip()
  drawCover(ctx, source, 0, 0, W, H)
  ctx.restore()

  // right: developed
  ctx.save()
  ctx.beginPath()
  ctx.rect(half, 0, half, H)
  ctx.clip()
  drawCover(ctx, styled, 0, 0, W, H)
  ctx.restore()

  // seam
  ctx.fillStyle = 'rgba(255,255,255,0.9)'
  ctx.fillRect(half - 2, 0, 4, H)

  // corner labels
  const label = (text: string, x: number, align: 'left' | 'right') => {
    const fs = 26
    ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`
    const tw = ctx.measureText(text).width
    const padX = 22
    const bw = tw + padX * 2
    const bh = fs * 2
    const bx = align === 'left' ? x : x - bw
    roundedPath(ctx, bx, 44, bw, bh, bh / 2)
    ctx.fillStyle = 'rgba(23,19,31,0.66)'
    ctx.fill()
    ctx.fillStyle = 'rgba(255,255,255,0.95)'
    ctx.textBaseline = 'middle'
    ctx.fillText(text, bx + padX, 44 + bh / 2 + 2)
  }
  label('Before', 44, 'left')
  label(style.name, W - 44, 'right')

  drawBrandPill(ctx, W / 2, H - 96, 'LensMood')
  return out
}
