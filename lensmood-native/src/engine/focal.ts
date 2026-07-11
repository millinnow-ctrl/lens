/**
 * Focal — where the subject is, so the engine can lock metering/flash/DoF/
 * relight to the face and keep smoothing on skin.
 *
 * On the web this runs MediaPipe BlazeFace in-process. The native port ships
 * a classical, dependency-free subject finder that runs in Expo Go: a
 * skin-probability mask over a small thumbnail, flood-filled into blobs, the
 * best blob scored by size / shape / fill / position. It is deliberately
 * conservative — portraits in reasonable light get a confident lock, and
 * anything ambiguous returns null, which is exactly the pre-R37 behavior
 * (flash centers frame, smoothing covers the whole image, DoF is skipped).
 * Apple Vision via a dev build is the planned upgrade; swap the body of
 * `detectFocal` and the scene meter + engine pick it up unchanged.
 */

import { Skia, AlphaType, ColorType, type SkImage } from '@shopify/react-native-skia'
import { detectFacesVision, visionAvailable } from '../../modules/lensmood-vision'
import type { Focal } from '@/engine/types'

export type { Focal }

const THUMB = 160

/** downscale into an offscreen surface and pull RGBA back (same idiom as
 *  scene.ts — kept local so the two meters stay independently portable) */
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

/** skin probability: the classic RGB rule ∪ a YCbCr chroma band. Both are
 *  tone-inclusive by design (the union is what published detectors use). */
function isSkin(r: number, g: number, b: number): boolean {
  const mx = Math.max(r, g, b)
  const mn = Math.min(r, g, b)
  // blown or near-black pixels carry no chroma evidence
  if (mx > 250 || mx < 30) return false
  const rgb = r > 95 && g > 40 && b > 20 && mx - mn > 15 && Math.abs(r - g) > 15 && r > g && r > b
  const cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
  const cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
  const ycc = cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173
  return rgb || ycc
}

interface Blob {
  mass: number
  minX: number
  maxX: number
  minY: number
  maxY: number
  sumX: number
  sumY: number
}

const cache = new WeakMap<object, Focal | null>()

/**
 * Find the strongest face/subject region and return its normalized center +
 * radius, or null when nothing is confident enough. Pure, ~ms on a 160px
 * thumb, cached per image.
 */
export async function detectFocal(image: SkImage, uri?: string): Promise<Focal | null> {
  const hit = cache.get(image as object)
  if (hit !== undefined) return hit
  // real on-device ML first (Apple Vision, full builds); heuristic fallback
  let result: Focal | null = null
  if (uri && visionAvailable) {
    result = await detectVision(uri)
  }
  if (!result) result = detect(image)
  cache.set(image as object, result)
  return result
}

/** map the strongest Vision face to the engine's Focal contract */
async function detectVision(uri: string): Promise<Focal | null> {
  const faces = await detectFacesVision(uri)
  if (!faces || faces.length === 0) return null
  // the biggest confident face carries the shot
  const best = faces
    .filter((f) => f.confidence > 0.3)
    .sort((a, b) => b.w * b.h - a.w * a.h)[0]
  if (!best) return null
  return {
    x: best.x + best.w / 2,
    y: best.y + best.h / 2,
    // Vision boxes hug the face; pad a touch so hair/jaw stay inside the lock.
    // w is a fraction of image width ≈ fraction of the longest edge for the
    // portrait shots this app lives on.
    r: Math.max(best.w, best.h) * 0.62,
  }
}

function detect(source: SkImage): Focal | null {
  try {
    const sw = source.width()
    const sh = source.height()
    if (!sw || !sh) return null
    const scale = THUMB / Math.max(sw, sh)
    const w = Math.max(4, Math.round(sw * scale))
    const h = Math.max(4, Math.round(sh * scale))
    const px = thumbPixels(source, w, h)
    if (!px) return null
    const n = w * h

    /* mask */
    const mask = new Uint8Array(n)
    let skinCount = 0
    for (let i = 0; i < n; i++) {
      const j = i * 4
      if (isSkin(px[j], px[j + 1], px[j + 2])) {
        mask[i] = 1
        skinCount++
      }
    }
    // almost-no-skin or skin-everywhere frames (sand, wood, desert) carry no
    // subject evidence — bail before blob work
    if (skinCount < n * 0.02 || skinCount > n * 0.55) return null

    /* flood-fill 4-connected blobs (same approach as the light meter) */
    const seen = new Uint8Array(n)
    const stack: number[] = []
    const blobs: Blob[] = []
    for (let start = 0; start < n; start++) {
      if (!mask[start] || seen[start]) continue
      const blob: Blob = {
        mass: 0,
        minX: w,
        maxX: 0,
        minY: h,
        maxY: 0,
        sumX: 0,
        sumY: 0,
      }
      stack.push(start)
      seen[start] = 1
      while (stack.length) {
        const idx = stack.pop()!
        const x = idx % w
        const y = (idx / w) | 0
        blob.mass++
        blob.sumX += x
        blob.sumY += y
        if (x < blob.minX) blob.minX = x
        if (x > blob.maxX) blob.maxX = x
        if (y < blob.minY) blob.minY = y
        if (y > blob.maxY) blob.maxY = y
        if (x > 0 && mask[idx - 1] && !seen[idx - 1]) (seen[idx - 1] = 1), stack.push(idx - 1)
        if (x < w - 1 && mask[idx + 1] && !seen[idx + 1]) (seen[idx + 1] = 1), stack.push(idx + 1)
        if (y > 0 && mask[idx - w] && !seen[idx - w]) (seen[idx - w] = 1), stack.push(idx - w)
        if (y < h - 1 && mask[idx + w] && !seen[idx + w]) (seen[idx + w] = 1), stack.push(idx + w)
      }
      blobs.push(blob)
    }

    /* score: plausible face/subject regions only */
    let best: Blob | null = null
    let bestScore = 0
    for (const b of blobs) {
      const areaFrac = b.mass / n
      if (areaFrac < 0.02 || areaFrac > 0.5) continue
      const bw = b.maxX - b.minX + 1
      const bh = b.maxY - b.minY + 1
      const aspect = bh / bw
      if (aspect < 0.6 || aspect > 2.4) continue // faces read tallish
      const fill = b.mass / (bw * bh)
      if (fill < 0.35) continue // stringy regions are not faces
      const cy = b.sumY / b.mass / h
      if (cy > 0.85) continue // subjects don't live on the bottom edge
      // upper-middle prior: strongest near cy≈0.38, fades toward edges
      const posBonus = 1 - Math.min(1, Math.abs(cy - 0.38) / 0.55) * 0.5
      const score = b.mass * fill * posBonus
      if (score > bestScore) {
        bestScore = score
        best = b
      }
    }
    if (!best || bestScore < n * 0.012) return null

    const bw = best.maxX - best.minX + 1
    const bh = best.maxY - best.minY + 1
    // the skin blob often includes neck/shoulders — report a face-scaled
    // radius, clamped so a false lock can never dominate the frame
    const r = Math.min(0.45, Math.max(0.08, (Math.max(bw, bh) / Math.max(w, h)) * 0.62))
    return {
      x: best.sumX / best.mass / w,
      y: best.sumY / best.mass / h,
      r,
    }
  } catch {
    return null
  }
}
