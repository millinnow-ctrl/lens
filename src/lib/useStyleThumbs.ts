import { useEffect, useState } from 'react'
import { loadImage, renderStyled } from './engine'
import { CAMERA_STYLES } from './styles'

/**
 * Renders a small preview of every camera style through the REAL engine —
 * flash, grain, vignette, frames and all — so each style card demonstrates
 * its actual look instead of a flat CSS approximation.
 *
 * Renders are chunked across frames to keep the main thread breathing.
 */
export function useStyleThumbs(src: string | null, size = 300): Record<string, string> {
  const [thumbs, setThumbs] = useState<Record<string, string>>({})

  useEffect(() => {
    setThumbs({})
    if (!src) return
    let cancelled = false
    let raf = 0

    loadImage(src).then((img) => {
      if (cancelled) return
      const queue = [...CAMERA_STYLES]
      const next = () => {
        if (cancelled) return
        const style = queue.shift()
        if (!style) return
        const canvas = renderStyled(img, style, style.defaults, { maxSize: size })
        const url = canvas.toDataURL('image/jpeg', 0.8)
        setThumbs((prev) => ({ ...prev, [style.id]: url }))
        raf = requestAnimationFrame(next)
      }
      raf = requestAnimationFrame(next)
    })

    return () => {
      cancelled = true
      cancelAnimationFrame(raf)
    }
  }, [src, size])

  return thumbs
}
