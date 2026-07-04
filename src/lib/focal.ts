/**
 * Focal — the app's "a little AI": on-device face detection (MediaPipe
 * BlazeFace, ~230KB model) that tells the engine where the subject is.
 * The flash pass locks its hotspot to the face and smoothing stays on
 * skin instead of smearing the frame. Photos still never leave the
 * device — the model runs in-process and loads lazily on first photo.
 */

export interface Focal {
  /** face center, normalized 0..1 */
  x: number
  y: number
  /** face radius as a fraction of the longest edge */
  r: number
}

type Detector = {
  detect(img: HTMLImageElement | HTMLCanvasElement): {
    detections: Array<{
      boundingBox?: { originX: number; originY: number; width: number; height: number }
      categories: Array<{ score: number }>
    }>
  }
}

let detectorPromise: Promise<Detector | null> | null = null

async function getDetector(): Promise<Detector | null> {
  if (!detectorPromise) {
    detectorPromise = (async () => {
      try {
        const { FilesetResolver, FaceDetector } = await import('@mediapipe/tasks-vision')
        const fileset = await FilesetResolver.forVisionTasks('/ai')
        return (await FaceDetector.createFromOptions(fileset, {
          baseOptions: { modelAssetPath: '/ai/blaze_face_short_range.tflite' },
          runningMode: 'IMAGE',
          minDetectionConfidence: 0.5,
        })) as unknown as Detector
      } catch {
        return null // wasm/model unavailable (offline preview, old browser) — engine falls back
      }
    })()
  }
  return detectorPromise
}

/** find the strongest face; null when none (or the model can't load) */
export async function detectFocal(img: HTMLImageElement): Promise<Focal | null> {
  const detector = await getDetector()
  if (!detector) return null
  try {
    const result = detector.detect(img)
    const best = result.detections
      .filter((d) => d.boundingBox)
      .sort((a, b) => (b.categories[0]?.score ?? 0) - (a.categories[0]?.score ?? 0))[0]
    if (!best?.boundingBox) return null
    const bb = best.boundingBox
    const W = img.naturalWidth || img.width
    const H = img.naturalHeight || img.height
    return {
      x: (bb.originX + bb.width / 2) / W,
      y: (bb.originY + bb.height / 2) / H,
      r: Math.max(bb.width, bb.height) / Math.max(W, H),
    }
  } catch {
    return null
  }
}
