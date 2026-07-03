import { useEffect, useRef, useState } from 'react'
import { IconPause, IconPlay } from './icons'
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
        className="absolute bottom-3 left-3 w-9 h-9 rounded-xs bg-vf/70 text-paper flex items-center justify-center hover:bg-vf/90 transition-colors"
      >
        {playing ? <IconPause size={14} /> : <IconPlay size={14} />}
      </button>
      <span className="absolute bottom-3 right-3 font-mono text-[10px] font-medium tracking-[0.12em] uppercase bg-vf/70 text-paper/90 px-2 py-1 rounded-xs pointer-events-none inline-flex items-center gap-1.5">
        <span className="w-1.5 h-1.5 rounded-full bg-signal inline-block lm-breathe" aria-hidden />
        Live
      </span>
    </div>
  )
}
