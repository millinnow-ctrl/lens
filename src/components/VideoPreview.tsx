import { useEffect, useRef, useState } from 'react'
import { renderStyled } from '../lib/engine'
import { videoSafeStyle } from '../lib/video'
import type { CameraStyle, StyleParams } from '../lib/styles'

interface Props {
  src: string
  /** null → play the untouched original */
  style: CameraStyle | null
  params: StyleParams | null
  className?: string
  /** fires once with a plain first-frame poster (for thumbnails / style cards) */
  onPoster?: (dataUrl: string) => void
}

/**
 * Plays the clip on a hidden <video> and re-shoots every frame through the
 * LensMood engine onto a canvas — the preview IS the pipeline, live.
 */
export default function VideoPreview({ src, style, params, className = '', onPoster }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const posterSent = useRef(false)
  const [playing, setPlaying] = useState(true)

  // latest look without restarting the rAF loop
  const look = useRef<{ style: CameraStyle | null; params: StyleParams | null }>({ style, params })
  look.current = { style: style ? videoSafeStyle(style) : null, params }

  useEffect(() => {
    posterSent.current = false
  }, [src])

  useEffect(() => {
    const video = videoRef.current
    const canvas = canvasRef.current
    if (!video || !canvas) return
    let raf = 0

    const draw = () => {
      if (video.readyState >= 2 && video.videoWidth > 0) {
        const { style: s, params: p } = look.current
        if (s && p) {
          renderStyled(video, s, p, { maxSize: 960, target: canvas, animateGrain: true })
        } else {
          const scale = Math.min(1, 960 / Math.max(video.videoWidth, video.videoHeight))
          const w = Math.round(video.videoWidth * scale)
          const h = Math.round(video.videoHeight * scale)
          if (canvas.width !== w) canvas.width = w
          if (canvas.height !== h) canvas.height = h
          canvas.getContext('2d')!.drawImage(video, 0, 0, w, h)
        }
        if (!posterSent.current && onPoster) {
          posterSent.current = true
          const c = document.createElement('canvas')
          const ps = Math.min(1, 480 / Math.max(video.videoWidth, video.videoHeight))
          c.width = Math.round(video.videoWidth * ps)
          c.height = Math.round(video.videoHeight * ps)
          c.getContext('2d')!.drawImage(video, 0, 0, c.width, c.height)
          onPoster(c.toDataURL('image/jpeg', 0.75))
        }
      }
      raf = requestAnimationFrame(draw)
    }
    raf = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(raf)
  }, [src, onPoster])

  const togglePlay = () => {
    const video = videoRef.current
    if (!video) return
    if (video.paused) {
      video.play()
      setPlaying(true)
    } else {
      video.pause()
      setPlaying(false)
    }
  }

  return (
    <div className={`relative ${className}`}>
      <video ref={videoRef} src={src} loop muted playsInline autoPlay className="hidden" />
      <canvas ref={canvasRef} className="w-full max-h-[62dvh] object-contain mx-auto" onClick={togglePlay} />
      <button
        onClick={togglePlay}
        aria-label={playing ? 'Pause' : 'Play'}
        className="absolute bottom-3 left-3 w-10 h-10 rounded-full bg-ink/55 backdrop-blur text-paper flex items-center justify-center hover:bg-ink/75 transition-colors"
      >
        {playing ? (
          <svg viewBox="0 0 24 24" className="w-4 h-4" fill="currentColor">
            <rect x="6" y="5" width="4" height="14" rx="1" />
            <rect x="14" y="5" width="4" height="14" rx="1" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" className="w-4 h-4" fill="currentColor">
            <path d="M8 5.5v13l11-6.5Z" />
          </svg>
        )}
      </button>
      <span className="absolute bottom-3 right-3 text-[10px] font-mono uppercase tracking-widest bg-ink/55 text-paper/90 backdrop-blur px-2.5 py-1 rounded-full pointer-events-none">
        Video · live
      </span>
    </div>
  )
}
