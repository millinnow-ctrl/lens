import { renderStyled } from './engine'
import type { CameraStyle, StyleParams } from './styles'

/** Polaroid frames resize the output canvas, which breaks captureStream —
 *  strip photo-only character flags when treating a style as a video look. */
export function videoSafeStyle(style: CameraStyle): CameraStyle {
  if (!style.character.polaroidFrame) return style
  return { ...style, character: { ...style.character, polaroidFrame: false } }
}

export const MAX_VIDEO_SECONDS = 30

export interface VideoMeta {
  duration: number
  width: number
  height: number
}

/**
 * Streamed/recorded WebMs report duration=Infinity until you seek past the
 * end (a long-standing Chromium quirk) — nudge the element until it knows.
 */
function resolveDuration(v: HTMLVideoElement): Promise<number> {
  if (Number.isFinite(v.duration)) return Promise.resolve(v.duration)
  return new Promise((resolve) => {
    const done = () => {
      v.ontimeupdate = null
      const d = v.duration
      v.currentTime = 0
      resolve(Number.isFinite(d) ? d : 0)
    }
    v.ontimeupdate = done
    setTimeout(done, 1500) // give up gracefully — 0 means "unknown, allow"
    v.currentTime = 1e7
  })
}

export function probeVideo(url: string): Promise<VideoMeta> {
  return new Promise((resolve, reject) => {
    const v = document.createElement('video')
    v.preload = 'metadata'
    v.muted = true
    v.onloadedmetadata = async () => {
      const duration = await resolveDuration(v)
      resolve({ duration, width: v.videoWidth, height: v.videoHeight })
    }
    v.onerror = () => reject(new Error('unreadable video'))
    v.src = url
  })
}

function pickMimeType(): string | undefined {
  const candidates = [
    'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
    'video/mp4',
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
  ]
  return candidates.find((t) => window.MediaRecorder && MediaRecorder.isTypeSupported(t))
}

export function videoExportSupported(): boolean {
  return (
    typeof window.MediaRecorder !== 'undefined' &&
    typeof HTMLCanvasElement.prototype.captureStream === 'function' &&
    !!pickMimeType()
  )
}

export interface RenderVideoOptions {
  sourceUrl: string
  style: CameraStyle
  params: StyleParams
  watermark: boolean
  maxSize?: number
  onProgress?: (fraction: number) => void
  signal?: AbortSignal
}

export interface RenderedVideo {
  blob: Blob
  extension: 'mp4' | 'webm'
}

/**
 * Re-shoots the whole clip through the LensMood engine: plays the source video
 * muted in the background, styles every frame onto a canvas, and records the
 * canvas stream (plus the original audio track when the browser exposes one).
 */
export function renderStyledVideo(opts: RenderVideoOptions): Promise<RenderedVideo> {
  const { sourceUrl, style, params, watermark, maxSize = 1280, onProgress, signal } = opts
  const safeStyle = videoSafeStyle(style)

  return new Promise((resolve, reject) => {
    const mimeType = pickMimeType()
    if (!mimeType) {
      reject(new Error('Video recording is not supported in this browser.'))
      return
    }

    const video = document.createElement('video')
    video.playsInline = true
    video.muted = false
    video.volume = 0 // keep the audio track alive for capture without audible playback
    video.crossOrigin = 'anonymous'
    video.src = sourceUrl

    const canvas = document.createElement('canvas')
    let raf = 0
    let recorder: MediaRecorder | null = null
    const chunks: Blob[] = []
    let settled = false

    const cleanup = () => {
      cancelAnimationFrame(raf)
      video.pause()
      video.removeAttribute('src')
      video.load()
    }
    const stopRecorder = () => {
      try {
        if (recorder && recorder.state !== 'inactive') recorder.stop()
      } catch {
        /* already stopped */
      }
    }
    const fail = (err: Error) => {
      if (settled) return
      settled = true
      stopRecorder()
      cleanup()
      reject(err)
    }

    signal?.addEventListener('abort', () => fail(new Error('cancelled')))

    video.onerror = () => fail(new Error('Could not read that video.'))
    video.onloadedmetadata = async () => {
      const duration = await resolveDuration(video)
      // first styled frame sizes the canvas before we start capturing
      renderStyled(video, safeStyle, params, { maxSize, watermark, target: canvas })

      const stream = canvas.captureStream(30)
      // borrow the source audio when the platform allows it
      type Capturable = HTMLVideoElement & { captureStream?: () => MediaStream }
      try {
        const av = (video as Capturable).captureStream?.()
        av?.getAudioTracks().forEach((t) => stream.addTrack(t))
      } catch {
        /* silent export */
      }

      recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 8_000_000 })
      recorder.ondataavailable = (e) => e.data.size > 0 && chunks.push(e.data)
      recorder.onstop = () => {
        if (settled) return
        settled = true
        cleanup()
        onProgress?.(1)
        resolve({
          blob: new Blob(chunks, { type: mimeType.split(';')[0] }),
          extension: mimeType.includes('mp4') ? 'mp4' : 'webm',
        })
      }

      const tick = () => {
        if (settled) return
        if (video.readyState >= 2) {
          renderStyled(video, safeStyle, params, {
            maxSize,
            watermark,
            target: canvas,
            animateGrain: true,
            time: video.currentTime,
          })
          if (duration > 0) onProgress?.(Math.min(0.99, video.currentTime / duration))
        }
        raf = requestAnimationFrame(tick)
      }

      video.onended = () => {
        cancelAnimationFrame(raf)
        // let the recorder flush its last chunk
        setTimeout(stopRecorder, 120)
      }

      try {
        await video.play()
      } catch {
        // autoplay policy blocked un-muted playback — export silently instead
        try {
          video.muted = true
          await video.play()
        } catch {
          fail(new Error('Playback was blocked — tap the export button again.'))
          return
        }
      }
      recorder.start(500)
      tick()
    }
  })
}
