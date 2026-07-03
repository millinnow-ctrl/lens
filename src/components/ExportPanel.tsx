import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import Modal from './Modal'
import { canvasToBlob, renderStyled } from '../lib/engine'
import { renderStyledVideo, videoExportSupported } from '../lib/video'
import { deliverFile, haptic } from '../lib/native'
import { HASHTAGS, randomCaption } from '../lib/captions'
import { encodeParams, type CameraStyle, type StyleParams } from '../lib/styles'
import { useApp } from '../lib/store'

interface Props {
  open: boolean
  onClose: () => void
  source: HTMLImageElement | null
  /** when set, we're exporting a clip instead of a photo */
  videoSrc?: string | null
  style: CameraStyle
  params: StyleParams
  onTryAnother: () => void
}

export default function ExportPanel({
  open,
  onClose,
  source,
  videoSrc,
  style,
  params,
  onTryAnother,
}: Props) {
  const { isPaid, plan } = useApp()
  const [url, setUrl] = useState<string | null>(null)
  const [blob, setBlob] = useState<Blob | null>(null)
  const [extension, setExtension] = useState<'jpg' | 'mp4' | 'webm'>('jpg')
  const [caption, setCaption] = useState('')
  const [copied, setCopied] = useState<'caption' | 'link' | null>(null)
  const [progress, setProgress] = useState(0)
  const [renderError, setRenderError] = useState<string | null>(null)
  const [delivered, setDelivered] = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  const hd = plan === 'pro' || plan === 'studio'
  const isVideo = !!videoSrc

  useEffect(() => {
    if (!open) return
    setCaption(randomCaption(style.id))
    setProgress(0)
    setRenderError(null)
    setDelivered(null)
    let objectUrl: string | null = null
    let cancelled = false

    ;(async () => {
      try {
        if (videoSrc) {
          if (!videoExportSupported()) {
            setRenderError('This browser can’t record video exports — the preview still works.')
            return
          }
          abortRef.current = new AbortController()
          const out = await renderStyledVideo({
            sourceUrl: videoSrc,
            style,
            params,
            watermark: !isPaid,
            maxSize: hd ? 1280 : 960,
            onProgress: (f) => !cancelled && setProgress(f),
            signal: abortRef.current.signal,
          })
          if (cancelled) return
          objectUrl = URL.createObjectURL(out.blob)
          setBlob(out.blob)
          setExtension(out.extension)
          setUrl(objectUrl)
          haptic('medium')
        } else if (source) {
          const canvas = renderStyled(source, style, params, {
            maxSize: hd ? 2560 : 1600,
            watermark: !isPaid,
          })
          const b = await canvasToBlob(canvas, hd ? 0.95 : 0.9)
          if (cancelled) return
          objectUrl = URL.createObjectURL(b)
          setBlob(b)
          setExtension('jpg')
          setUrl(objectUrl)
        }
      } catch (e) {
        if (!cancelled && (e as Error).message !== 'cancelled') {
          setRenderError((e as Error).message || 'Export failed — try again.')
        }
      }
    })()

    return () => {
      cancelled = true
      abortRef.current?.abort()
      if (objectUrl) URL.revokeObjectURL(objectUrl)
      setUrl(null)
      setBlob(null)
    }
  }, [open, source, videoSrc, style, params, isPaid, hd])

  const filename = useMemo(
    () => `lensmood-${style.id}-${Date.now().toString(36)}.${extension}`,
    [style.id, extension],
  )

  const send = useCallback(
    async (withCaption: boolean) => {
      if (!blob) return
      haptic('light')
      const res = await deliverFile(blob, filename, withCaption ? `${caption} ${HASHTAGS}` : undefined)
      if (res.ok) {
        setDelivered(
          res.via === 'download'
            ? '✓ Saved to downloads'
            : res.via === 'open'
              ? '✓ Opened — long-press to save'
              : '✓ Sent to share sheet',
        )
        setTimeout(() => setDelivered(null), 2400)
      }
    },
    [blob, filename, caption],
  )

  const copy = async (what: 'caption' | 'link') => {
    const text =
      what === 'caption'
        ? `${caption}\n\n${HASHTAGS}`
        : `${window.location.origin}/studio?style=${style.id}&p=${encodeParams(params)}`
    try {
      await navigator.clipboard.writeText(text)
      setCopied(what)
      setTimeout(() => setCopied(null), 1500)
    } catch {
      /* clipboard unavailable */
    }
  }

  const rendering = !url && !renderError

  return (
    <Modal open={open} onClose={onClose} wide>
      <div className="p-6 sm:p-8">
        <p className="text-xs font-bold uppercase tracking-widest text-violet mb-1">Developed ✦</p>
        <h3 className="font-display text-2xl sm:text-3xl font-semibold mb-5">
          Your {style.name} {isVideo ? 'clip' : 'shot'}
        </h3>

        <div className="grid sm:grid-cols-[1fr_260px] gap-6">
          {/* final preview */}
          <div className="relative rounded-2xl overflow-hidden bg-mist flex items-center justify-center min-h-64">
            {url ? (
              isVideo ? (
                <video src={url} controls autoPlay loop playsInline className="lm-develop w-full max-h-[46dvh] object-contain bg-ink" />
              ) : (
                <img src={url} alt="Final export" className="lm-develop w-full max-h-[46dvh] object-contain" />
              )
            ) : renderError ? (
              <div className="py-16 px-6 text-center text-sm text-fog">{renderError}</div>
            ) : (
              <div className="py-20 px-8 w-full text-center">
                <p className="text-fog text-sm lm-breathe mb-4">
                  {isVideo ? 'Re-shooting every frame…' : 'Developing final export…'}
                </p>
                {isVideo && (
                  <div className="w-full max-w-56 mx-auto h-1.5 rounded-full bg-cloud overflow-hidden">
                    <div
                      className="h-full bg-violet rounded-full transition-[width] duration-200"
                      style={{ width: `${Math.round(progress * 100)}%` }}
                    />
                  </div>
                )}
              </div>
            )}
          </div>

          {/* actions */}
          <div className="flex flex-col gap-2.5">
            <button onClick={() => send(false)} disabled={rendering || !url} className="pill-base pill-violet px-5 py-3 text-sm disabled:opacity-50">
              <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 3v12m0 0l-4.5-4.5M12 15l4.5-4.5M4 20h16" />
              </svg>
              {isVideo ? `Save video (.${extension})` : hd ? 'Save HD photo' : 'Save photo'}
            </button>
            <button onClick={() => send(true)} disabled={rendering || !url} className="pill-base pill-primary px-5 py-3 text-sm disabled:opacity-50">
              Share to TikTok / Reels
            </button>
            <button onClick={() => copy('caption')} className="pill-base pill-ghost px-5 py-3 text-sm">
              {copied === 'caption' ? '✓ Caption copied' : 'Copy caption'}
            </button>
            <button onClick={() => copy('link')} className="pill-base pill-ghost px-5 py-3 text-sm">
              {copied === 'link' ? '✓ Style link copied' : 'Copy style link'}
            </button>
            <button
              onClick={() => {
                onClose()
                onTryAnother()
              }}
              className="pill-base pill-ghost px-5 py-3 text-sm"
            >
              Try another style
            </button>

            {delivered && <p className="text-center text-[13px] font-semibold text-violet">{delivered}</p>}

            <div className="mt-1 rounded-2xl bg-mist p-4">
              <p className="text-[11px] font-bold uppercase tracking-widest text-fog mb-1.5">Caption</p>
              <p className="text-[13px] text-ink-soft leading-relaxed">“{caption}”</p>
            </div>

            {!isPaid && (
              <p className="text-[12px] text-fog leading-relaxed">
                Free exports carry a small “Shot on LensMood” mark.{' '}
                <Link to="/pricing" onClick={onClose} className="text-violet font-semibold hover:underline">
                  Go Creator
                </Link>{' '}
                to remove it.
              </p>
            )}
          </div>
        </div>
      </div>
    </Modal>
  )
}
