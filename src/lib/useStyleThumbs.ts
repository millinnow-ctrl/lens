import { useEffect, useMemo, useState } from 'react'
import { loadImage, renderStyled } from './engine'
import { CAMERA_STYLES } from './styles'

/**
 * Renders a small preview of every camera style through the REAL engine —
 * flash, grain, vignette, frames and all — so each style card demonstrates
 * its actual look instead of a flat CSS approximation.
 *
 * Pass one source to tell the "one photo, every era" story, or several to
 * give a shelf visual variety (sources rotate per style).
 * Renders are chunked across frames to keep the main thread breathing.
 */
export function useStyleThumbs(src: string | string[] | null, size = 300): Record<string, string> {
  const [thumbs, setThumbs] = useState<Record<string, string>>({})
  const srcs = useMemo(() => (src == null ? [] : Array.isArray(src) ? src : [src]), [src])
  const key = srcs.join('|')

  useEffect(() => {
    setThumbs({})
    if (srcs.length === 0) return
    let cancelled = false
    let raf = 0

    Promise.all(srcs.map(loadImage)).then((imgs) => {
      if (cancelled) return
      const queue = CAMERA_STYLES.map((style, i) => ({ style, img: imgs[i % imgs.length] }))
      const next = () => {
        if (cancelled) return
        const item = queue.shift()
        if (!item) return
        const canvas = renderStyled(item.img, item.style, item.style.defaults, { maxSize: size })
        const url = canvas.toDataURL('image/jpeg', 0.8)
        setThumbs((prev) => ({ ...prev, [item.style.id]: url }))
        raf = requestAnimationFrame(next)
      }
      raf = requestAnimationFrame(next)
    })

    return () => {
      cancelled = true
      cancelAnimationFrame(raf)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, size])

  return thumbs
}
