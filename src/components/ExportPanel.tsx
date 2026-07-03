import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import Modal from './Modal'
import { canvasToBlob, renderStyled } from '../lib/engine'
import { HASHTAGS, randomCaption } from '../lib/captions'
import type { CameraStyle, StyleParams } from '../lib/styles'
import { useApp } from '../lib/store'

interface Props {
  open: boolean
  onClose: () => void
  source: HTMLImageElement | null
  style: CameraStyle
  params: StyleParams
  onTryAnother: () => void
}

export default function ExportPanel({ open, onClose, source, style, params, onTryAnother }: Props) {
  const { isPaid, plan } = useApp()
  const [url, setUrl] = useState<string | null>(null)
  const [blob, setBlob] = useState<Blob | null>(null)
  const [caption, setCaption] = useState('')
  const [copied, setCopied] = useState<'caption' | 'link' | null>(null)

  const hd = plan === 'pro' || plan === 'studio'

  useEffect(() => {
    if (!open || !source) return
    setCaption(randomCaption(style.id))
    let objectUrl: string | null = null
    let cancelled = false
    ;(async () => {
      const canvas = renderStyled(source, style, params, {
        maxSize: hd ? 2560 : 1600,
        watermark: !isPaid,
      })
      const b = await canvasToBlob(canvas, hd ? 0.95 : 0.9)
      if (cancelled) return
      objectUrl = URL.createObjectURL(b)
      setBlob(b)
      setUrl(objectUrl)
    })()
    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
      setUrl(null)
      setBlob(null)
    }
  }, [open, source, style, params, isPaid, hd])

  const filename = useMemo(
    () => `lensmood-${style.id}-${Date.now().toString(36)}.jpg`,
    [style.id],
  )

  const download = () => {
    if (!url) return
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
  }

  const share = async () => {
    if (blob && navigator.canShare?.({ files: [new File([blob], filename, { type: 'image/jpeg' })] })) {
      try {
        await navigator.share({
          files: [new File([blob], filename, { type: 'image/jpeg' })],
          text: `${caption} ${HASHTAGS}`,
        })
        return
      } catch {
        /* user dismissed the share sheet */
      }
    }
    download()
  }

  const copy = async (what: 'caption' | 'link') => {
    const text =
      what === 'caption'
        ? `${caption}\n\n${HASHTAGS}`
        : `https://lensmood.app/s/${style.id}-${Math.random().toString(36).slice(2, 8)}`
    try {
      await navigator.clipboard.writeText(text)
      setCopied(what)
      setTimeout(() => setCopied(null), 1500)
    } catch {
      /* clipboard unavailable */
    }
  }

  return (
    <Modal open={open} onClose={onClose} wide>
      <div className="p-6 sm:p-8">
        <p className="text-xs font-bold uppercase tracking-widest text-violet mb-1">Developed ✦</p>
        <h3 className="font-display text-2xl sm:text-3xl font-semibold mb-5">
          Your {style.name} shot
        </h3>

        <div className="grid sm:grid-cols-[1fr_260px] gap-6">
          {/* final preview */}
          <div className="relative rounded-2xl overflow-hidden bg-mist flex items-center justify-center min-h-64">
            {url ? (
              <img src={url} alt="Final export" className="lm-develop w-full max-h-[46dvh] object-contain" />
            ) : (
              <div className="py-20 text-fog text-sm lm-breathe">Developing final export…</div>
            )}
          </div>

          {/* actions */}
          <div className="flex flex-col gap-2.5">
            <button onClick={download} disabled={!url} className="pill-base pill-violet px-5 py-3 text-sm disabled:opacity-50">
              <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 3v12m0 0l-4.5-4.5M12 15l4.5-4.5M4 20h16" />
              </svg>
              Download {hd ? 'HD' : ''}
            </button>
            <button onClick={share} disabled={!url} className="pill-base pill-primary px-5 py-3 text-sm disabled:opacity-50">
              Share to TikTok / Reels
            </button>
            <button onClick={() => copy('caption')} className="pill-base pill-ghost px-5 py-3 text-sm">
              {copied === 'caption' ? '✓ Caption copied' : 'Copy caption'}
            </button>
            <button onClick={() => copy('link')} className="pill-base pill-ghost px-5 py-3 text-sm">
              {copied === 'link' ? '✓ Link copied' : 'Copy share link'}
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

            <div className="mt-2 rounded-2xl bg-mist p-4">
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
