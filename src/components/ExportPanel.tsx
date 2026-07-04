import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import Modal from './Modal'
import { IconDownload, IconShare } from './icons'
import { canvasToBlob, renderStyled } from '../lib/engine'
import { makeSplitCard, makeStoryCard } from '../lib/shareCards'
import { renderStyledVideo, videoExportSupported } from '../lib/video'
import { deliverFile, haptic } from '../lib/native'
import { HASHTAGS, randomCaption } from '../lib/captions'
import { dailyStyle, isDailyClaimed } from '../lib/lab'
import type { Focal } from '../lib/focal'
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
  /** AI face lock from the studio — keeps exports identical to the preview */
  focal?: Focal | null
  onTryAnother: () => void
}

export default function ExportPanel({
  open,
  onClose,
  source,
  videoSrc,
  style,
  params,
  focal = null,
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
  /** stays true after the first successful save/share so the next-look hook can linger */
  const [exported, setExported] = useState(false)
  const abortRef = useRef<AbortController | null>(null)

  const hd = plan === 'pro' || plan === 'studio'
  const isVideo = !!videoSrc

  /** photo exports come in three cuts: the shot, a 9:16 story card, a 4:5 split */
  const [format, setFormat] = useState<'photo' | 'story' | 'split'>('photo')
  useEffect(() => {
    if (open) {
      setFormat('photo')
      setExported(false)
    }
  }, [open])

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
          const canvas =
            format === 'story'
              ? makeStoryCard(source, style, params, { watermark: !isPaid, focal })
              : format === 'split'
                ? makeSplitCard(source, style, params, { watermark: !isPaid, focal })
                : renderStyled(source, style, params, {
                    maxSize: hd ? 2560 : 1600,
                    watermark: !isPaid,
                    focal,
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
  }, [open, source, videoSrc, style, params, isPaid, hd, format, focal])

  const filename = useMemo(
    () =>
      `lensmood-${style.id}${format === 'photo' ? '' : `-${format}`}-${Date.now().toString(36)}.${extension}`,
    [style.id, extension, format],
  )

  const send = useCallback(
    async (withCaption: boolean) => {
      if (!blob) return
      haptic('light')
      const res = await deliverFile(blob, filename, withCaption ? `${caption} ${HASHTAGS}` : undefined)
      if (res.ok) {
        setExported(true)
        setDelivered(
          res.via === 'download'
            ? 'Saved to downloads'
            : res.via === 'open'
              ? 'Opened — long-press to save'
              : 'Sent to share sheet',
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
        <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-ink-soft mb-1.5">
          Developed
        </p>
        <h3 className="type-display text-2xl sm:text-3xl mb-5">
          Your {style.name} {isVideo ? 'clip' : 'shot'}
        </h3>

        <div className="grid sm:grid-cols-[1fr_260px] gap-6">
          {/* final preview */}
          <div className="relative bg-vf rounded-[20px] overflow-hidden flex items-center justify-center min-h-64">
            {url ? (
              isVideo ? (
                <video src={url} controls autoPlay loop playsInline className="lm-develop w-full max-h-[46dvh] object-contain bg-vf" />
              ) : (
                <img src={url} alt="Final export" className="lm-develop w-full max-h-[46dvh] object-contain" />
              )
            ) : renderError ? (
              <div className="py-16 px-6 text-center text-sm text-vf-chrome">{renderError}</div>
            ) : (
              <div className="py-20 px-8 w-full text-center">
                <p className="font-mono text-[11px] uppercase tracking-[0.14em] text-vf-chrome lm-breathe mb-4">
                  {isVideo ? 'Re-shooting every frame…' : 'Developing final export…'}
                </p>
                {isVideo && (
                  <div className="w-full max-w-56 mx-auto flex items-center gap-3">
                    <div className="flex-1 h-1 rounded-full bg-white/15 overflow-hidden">
                      <div
                        className="h-full rounded-full bg-violet transition-[width] duration-200"
                        style={{ width: `${Math.round(progress * 100)}%` }}
                      />
                    </div>
                    <span className="font-mono text-[11px] tabular-nums text-vf-chrome">
                      {Math.round(progress * 100)}%
                    </span>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* actions */}
          <div className="flex flex-col gap-2.5">
            {!isVideo && (
              <div
                className="grid grid-cols-3 bg-black/20 rounded-full p-1 shadow-[inset_0_1px_2px_rgb(0_0_0/0.4)]"
                role="tablist"
                aria-label="Export format"
              >
                {(
                  [
                    { id: 'photo', label: 'Photo' },
                    { id: 'story', label: 'Story' },
                    { id: 'split', label: 'Split' },
                  ] as const
                ).map((f) => (
                  <button
                    key={f.id}
                    role="tab"
                    aria-selected={format === f.id}
                    onClick={() => setFormat(f.id)}
                    className={`h-8 rounded-full text-[12.5px] font-semibold transition-colors ${
                      format === f.id ? 'bg-white text-paper shadow-sm' : 'text-ink-soft'
                    }`}
                  >
                    {f.label}
                  </button>
                ))}
              </div>
            )}
            {rendering || !url ? (
              <button disabled className="btn btn-primary w-full">
                <IconDownload size={15} />
                {isVideo ? `Save video (.${extension})` : hd ? 'Save HD photo' : 'Save photo'}
              </button>
            ) : (
              <span className="glow-ring flex w-full">
                <button onClick={() => send(false)} className="btn btn-hero w-full">
                  <IconDownload size={15} />
                  {isVideo ? `Save video (.${extension})` : hd ? 'Save HD photo' : 'Save photo'}
                </button>
              </span>
            )}
            <button onClick={() => send(true)} disabled={rendering || !url} className="btn btn-outline w-full">
              <IconShare size={15} />
              Share to TikTok / Reels
            </button>
            <div className="border-t border-hairline mt-1 pt-1.5 grid grid-cols-2">
              <button onClick={() => copy('caption')} className="btn btn-quiet text-[12.5px]">
                {copied === 'caption' ? 'Copied' : 'Copy caption'}
              </button>
              <button onClick={() => copy('link')} className="btn btn-quiet text-[12.5px]">
                {copied === 'link' ? 'Copied' : 'Copy style link'}
              </button>
            </div>
            <button
              onClick={() => {
                onClose()
                onTryAnother()
              }}
              className="btn btn-quiet w-full"
            >
              Try another style
            </button>

            {delivered && (
              <p className="text-center text-[12px] font-semibold text-violet">{delivered}</p>
            )}

            {/* next-trigger: the (true, deterministic) free look that's up next */}
            {exported &&
              (isDailyClaimed() ? (
                <p className="text-center text-[12px] text-fog">
                  Tomorrow’s free look:{' '}
                  <span className="font-semibold text-violet">
                    {dailyStyle(new Date(Date.now() + 86_400_000)).name}
                  </span>{' '}
                  — it unlocks at midnight.
                </p>
              ) : (
                <p className="text-center text-[12px] text-fog">
                  Today’s free look is still waiting —{' '}
                  <span className="font-semibold text-violet">{dailyStyle().name}</span>.
                </p>
              ))}

            <div className="mt-1 panel p-4">
              <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-fog mb-1.5">Caption</p>
              <p className="text-[13px] text-ink-soft leading-relaxed">“{caption}”</p>
            </div>

            {!isPaid && (
              <p className="text-[12px] text-fog leading-relaxed">
                Free exports carry a small “Shot on LensMood” mark.{' '}
                <Link to="/pricing" onClick={onClose} className="text-ink underline underline-offset-2">
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
