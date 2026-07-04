import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import UploadArea from '../components/UploadArea'
import StyleCarousel from '../components/StyleCarousel'
import AdjustmentPanel from '../components/AdjustmentPanel'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import VideoPreview from '../components/VideoPreview'
import ExportPanel from '../components/ExportPanel'
import Modal from '../components/Modal'
import { IconFilm } from '../components/icons'
import { loadImage, renderStyled, thumbnail } from '../lib/engine'
import { claimDaily, dailyStyle, isDailyClaimed } from '../lib/lab'
import { haptic } from '../lib/native'
import {
  GENERATION_STEPS,
  decodeParams,
  getStyle,
  type CameraStyle,
  type StyleParams,
} from '../lib/styles'
import { useApp } from '../lib/store'

type Phase = 'idle' | 'generating' | 'done'
type View = 'result' | 'original' | 'compare'

export default function Studio() {
  const {
    photo,
    roll,
    activeIndex,
    setActiveIndex,
    video,
    clearMedia,
    styleId,
    params,
    selectStyle,
    setParams,
    creditsLeft,
    isPaid,
    spendCredit,
    addHistory,
    pendingPreset,
    setPendingPreset,
  } = useApp()
  const [searchParams] = useSearchParams()

  const [source, setSource] = useState<HTMLImageElement | null>(null)
  const [phase, setPhase] = useState<Phase>('idle')
  const [stepIndex, setStepIndex] = useState(0)
  const [resultUrl, setResultUrl] = useState<string | null>(null)
  const [view, setView] = useState<View>('result')
  const [exportOpen, setExportOpen] = useState(false)
  const [paywall, setPaywall] = useState(false)
  const [shutter, setShutter] = useState(false)
  const [videoPoster, setVideoPoster] = useState<string | null>(null)

  const style = getStyle(styleId)
  const generationTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const renderRaf = useRef(0)
  /** the exact search string already honored — lets a NEW deep link fire even
   *  when a style from earlier in the session is still selected */
  const deepLinkHandled = useRef<string | null>(null)
  const hasMedia = !!photo || !!video

  /* load the active photo into an Image element */
  useEffect(() => {
    setResultUrl(null)
    setPhase('idle')
    setView('result')
    if (!photo) {
      setSource(null)
      return
    }
    let cancelled = false
    loadImage(photo).then((img) => {
      if (!cancelled) setSource(img)
    })
    return () => {
      cancelled = true
    }
  }, [photo])

  useEffect(() => {
    if (!video) setVideoPoster(null)
  }, [video])

  const beginGeneration = useCallback(
    (s: CameraStyle, presetParams?: StyleParams, freeShot = false) => {
      if (!source && !video) return
      if (!freeShot && !spendCredit()) {
        setPaywall(true)
        return
      }
      haptic('medium')
      selectStyle(s.id, presetParams)
      setView('result')
      setShutter(true)
      setTimeout(() => setShutter(false), 750)
      setPhase('generating')

      if (generationTimer.current) clearTimeout(generationTimer.current)
      generationTimer.current = setTimeout(() => {
        const effective = presetParams ?? s.defaults
        if (source) {
          const canvas = renderStyled(source, s, effective, { maxSize: 1280 })
          setResultUrl(canvas.toDataURL('image/jpeg', 0.9))
          addHistory({ thumb: thumbnail(canvas), styleId: s.id, styleName: s.name })
        } else if (videoPoster) {
          // videos develop live — the history thumb comes from a styled poster frame
          loadImage(videoPoster).then((poster) => {
            const canvas = renderStyled(poster, s, effective, { maxSize: 480 })
            addHistory({ thumb: thumbnail(canvas), styleId: s.id, styleName: `${s.name} · video` })
          })
        }
        setPhase('done')
        haptic('light')
      }, 2300)
    },
    [source, video, videoPoster, spendCredit, selectStyle, addHistory],
  )

  /* deep link: /studio?style=a24-still&p=90.30.55.46.0.58.0 (&daily=1 = today's free stock) */
  useEffect(() => {
    const pendingStyle = searchParams.get('style')
    const key = searchParams.toString()
    if (
      pendingStyle &&
      (source || video) &&
      styleId !== pendingStyle &&
      deepLinkHandled.current !== key
    ) {
      const s = getStyle(pendingStyle)
      if (s) {
        deepLinkHandled.current = key
        const freeShot =
          searchParams.get('daily') === '1' && s.id === dailyStyle().id && !isDailyClaimed()
        if (freeShot) claimDaily()
        beginGeneration(s, decodeParams(searchParams.get('p')) ?? undefined, freeShot)
      }
    }
  }, [source, video, searchParams, styleId, beginGeneration])

  /* saved preset chosen from the dashboard */
  useEffect(() => {
    if (!pendingPreset || (!source && !video) || styleId) return
    const s = getStyle(pendingPreset.styleId)
    setPendingPreset(null)
    if (s) beginGeneration(s, pendingPreset.params)
  }, [pendingPreset, source, video, styleId, beginGeneration, setPendingPreset])

  /* re-render instantly when sliders move after the first development (photos) */
  useEffect(() => {
    if (phase !== 'done' || !source || !style || !params) return
    cancelAnimationFrame(renderRaf.current)
    renderRaf.current = requestAnimationFrame(() => {
      const canvas = renderStyled(source, style, params, { maxSize: 1280 })
      setResultUrl(canvas.toDataURL('image/jpeg', 0.9))
    })
    return () => cancelAnimationFrame(renderRaf.current)
  }, [params, phase, source, style])

  /* rotating progress copy while "developing" */
  useEffect(() => {
    if (phase !== 'generating') return
    setStepIndex(0)
    const iv = setInterval(() => {
      setStepIndex((i) => Math.min(i + 1, GENERATION_STEPS.length - 1))
    }, 480)
    return () => clearInterval(iv)
  }, [phase])

  useEffect(
    () => () => {
      if (generationTimer.current) clearTimeout(generationTimer.current)
    },
    [],
  )

  /* ------------------------------------------------ empty state */
  if (!hasMedia) {
    return (
      <main className="max-w-7xl mx-auto px-4 sm:px-6 py-12 sm:py-20 pb-28">
        <div className="mb-10">
          <p className="text-[12px] font-bold tracking-[0.12em] uppercase grad-text mb-3">The Studio</p>
          <h1 className="type-display text-3xl sm:text-5xl">
            Every photo has a mood.
            <br className="hidden sm:block" /> Let’s find yours.
          </h1>
        </div>
        <hr className="rule mb-10" />
        <UploadArea />
      </main>
    )
  }

  const showOriginal = view === 'original' || (!!photo && !resultUrl)
  const carouselPreview = photo ?? videoPoster

  /* ------------------------------------------------ editor */
  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 py-6 sm:py-10 pb-28 md:pb-16">
      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_400px] gap-6 lg:gap-8 items-start">
        {/* ---------- preview column ---------- */}
        <div className="lg:sticky lg:top-20 min-w-0">
          <div className="bg-vf rounded-[24px] overflow-hidden shadow-[0_2px_12px_rgb(23_19_31/0.10)]">
            {/* viewfinder chrome strip */}
            <div className="h-9 px-4 flex items-center justify-between gap-3 border-b border-white/12">
              <span className="font-mono text-[10px] tracking-[0.14em] uppercase text-vf-chrome truncate">
                {style ? style.name : 'Original'}
              </span>
              <span className="flex items-center gap-1.5 font-mono text-[10px] tracking-[0.14em] uppercase text-vf-chrome tabular-nums shrink-0">
                {video && <span className="w-1.5 h-1.5 rounded-full bg-[#E1251B] inline-block" aria-hidden />}
                {video ? 'REC · 30FPS' : (style?.exif ?? 'READY · NO MOOD')}
              </span>
            </div>

            <div className="relative vf-corners overflow-hidden min-h-[320px] flex items-center justify-center">
            {/* media area */}
            {video ? (
              <VideoPreview
                src={video}
                style={showOriginal || phase !== 'done' ? null : (style ?? null)}
                params={showOriginal || phase !== 'done' ? null : params}
                className="w-full"
                onPoster={setVideoPoster}
              />
            ) : view === 'compare' && resultUrl && photo ? (
              <BeforeAfterSlider
                before={photo}
                after={resultUrl}
                className="w-full aspect-4/5 sm:aspect-auto sm:h-[62dvh]"
              />
            ) : (
              <div className="relative w-full flex items-center justify-center">
                <img
                  key={showOriginal ? 'orig' : resultUrl}
                  src={showOriginal || !resultUrl ? photo! : resultUrl}
                  alt="Preview"
                  className={`w-full max-h-[62dvh] object-contain ${
                    phase === 'done' && view === 'result' ? 'lm-develop' : ''
                  }`}
                  draggable={false}
                />
              </div>
            )}

            {/* shutter flash */}
            {shutter && <div className="absolute inset-0 bg-white z-30 lm-shutter-flash pointer-events-none" />}

            {/* developing overlay */}
            <AnimatePresence>
              {phase === 'generating' && (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="absolute inset-0 z-20 bg-vf/85 flex flex-col items-center justify-center gap-5"
                >
                  <motion.svg
                    viewBox="0 0 48 48"
                    className="w-14 h-14"
                    animate={{ rotate: 360 }}
                    transition={{ repeat: Infinity, duration: 2.4, ease: 'linear' }}
                  >
                    {[...Array(6)].map((_, i) => (
                      <path
                        key={i}
                        d="M24 6 A18 18 0 0 1 39.6 15 L27 21.6 A6 6 0 0 0 24 21 Z"
                        fill="#ffffff"
                        opacity={0.35 + (i / 6) * 0.65}
                        transform={`rotate(${i * 60} 24 24)`}
                      />
                    ))}
                    <circle cx="24" cy="24" r="5" fill="#8b5cf6" />
                  </motion.svg>
                  <AnimatePresence mode="wait">
                    <motion.p
                      key={stepIndex}
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -8 }}
                      className="font-mono text-[11px] tracking-[0.14em] uppercase text-white/90"
                    >
                      {GENERATION_STEPS[stepIndex]}
                    </motion.p>
                  </AnimatePresence>
                  <div className="w-44 h-1 rounded-full bg-white/15 overflow-hidden">
                    <motion.div
                      className="h-full rounded-full grad-fill"
                      initial={{ width: '4%' }}
                      animate={{ width: '96%' }}
                      transition={{ duration: 2.2, ease: 'easeInOut' }}
                    />
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
            </div>
          </div>

          {/* roll filmstrip */}
          {roll.length > 1 && (
            <div className="mt-3 flex gap-2.5 overflow-x-auto no-scrollbar py-1">
              {roll.map((item, i) => {
                const active = i === activeIndex
                return (
                  <button
                    key={`${item.name}-${i}`}
                    onClick={() => setActiveIndex(i)}
                    className="shrink-0 flex flex-col items-stretch gap-1 group"
                    aria-label={`Photo ${i + 1} of ${roll.length}`}
                  >
                    <span
                      className={`block w-14 aspect-4/5 rounded-xl overflow-hidden transition-[opacity,transform] ${
                        active
                          ? 'ring-2 ring-violet ring-offset-2 ring-offset-paper scale-[1.02]'
                          : 'ring-1 ring-hairline opacity-70 group-hover:opacity-100'
                      }`}
                    >
                      <img src={item.url} alt="" className="w-full h-full object-cover" draggable={false} />
                    </span>
                    <span className={`block h-1 rounded-full ${active ? 'grad-fill' : 'bg-transparent'}`} aria-hidden />
                    <span
                      className={`font-mono text-[10px] tracking-[0.1em] tabular-nums text-center ${
                        active ? 'text-ink' : 'text-fog'
                      }`}
                    >
                      {String(i + 1).padStart(2, '0')}
                    </span>
                  </button>
                )
              })}
            </div>
          )}

          {/* view toggles + actions under preview */}
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <div className="flex w-full sm:w-auto sm:inline-flex items-center gap-0.5 rounded-full bg-black/5 p-1">
              {(
                [
                  { id: 'original', label: 'Original' },
                  { id: 'result', label: 'LensMood' },
                  { id: 'compare', label: 'Compare' },
                ] as { id: View; label: string }[]
              ).map((t) => {
                const disabled =
                  (t.id !== 'original' && phase !== 'done') || (t.id === 'compare' && !!video)
                const active = view === t.id
                return (
                  <button
                    key={t.id}
                    disabled={disabled}
                    onClick={() => setView(t.id)}
                    className={`px-4 h-8 text-[13px] font-semibold rounded-full transition-colors flex-1 sm:flex-none ${
                      active
                        ? 'bg-white text-ink shadow-[0_1px_3px_rgb(23_19_31/0.12)]' // selected pill stays lifted even while others disable
                        : disabled
                          ? 'text-fog/60'
                          : 'text-ink-soft hover:text-ink'
                    }`}
                  >
                    {t.label}
                  </button>
                )
              })}
            </div>

            <div className="flex items-center gap-2 w-full sm:w-auto justify-between sm:justify-end">
              <button onClick={clearMedia} className="btn btn-quiet">
                New photo
              </button>
              {phase === 'done' ? (
                <span className="glow-ring inline-flex">
                  <button onClick={() => setExportOpen(true)} className="btn btn-hero">
                    Export
                  </button>
                </span>
              ) : (
                <button disabled className="btn btn-primary">
                  Export
                </button>
              )}
            </div>
          </div>
        </div>

        {/* ---------- controls column ---------- */}
        <div className="space-y-6 min-w-0">
          <section className="panel p-5">
            <div className="flex items-baseline justify-between mb-1">
              <h2 className="text-lg font-semibold tracking-[-0.01em]">Camera mood</h2>
              {!isPaid && (
                <span className="font-mono text-[10px] tracking-[0.1em] uppercase text-fog tabular-nums">
                  {creditsLeft} free {creditsLeft === 1 ? 'shot' : 'shots'} left
                </span>
              )}
            </div>
            <p className="text-[13px] text-fog mb-3">
              {style ? style.description : 'Pick a style — we’ll develop your photo in it.'}
            </p>
            {carouselPreview && (
              <StyleCarousel
                previewSrc={carouselPreview}
                selectedId={styleId}
                onSelect={(s) => beginGeneration(s)}
              />
            )}
          </section>

          <AnimatePresence>
            {style && params && phase === 'done' && (
              <motion.section
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 8 }}
                className="panel p-5"
              >
                <h2 className="text-lg font-semibold tracking-[-0.01em] mb-1">Fine-tune</h2>
                {video && (
                  <p className="text-[12px] text-fog mb-3">Adjustments apply to the clip live.</p>
                )}
                <div className={video ? '' : 'mt-3'}>
                  <AdjustmentPanel style={style} params={params} onChange={setParams} />
                </div>
              </motion.section>
            )}
          </AnimatePresence>
        </div>
      </div>

      {/* export modal */}
      {style && params && (
        <ExportPanel
          open={exportOpen}
          onClose={() => setExportOpen(false)}
          source={source}
          videoSrc={video}
          style={style}
          params={params}
          onTryAnother={() => {
            setView('result')
            window.scrollTo({ top: 0, behavior: 'smooth' })
          }}
        />
      )}

      {/* paywall */}
      <Modal open={paywall} onClose={() => setPaywall(false)}>
        <div className="p-8">
          <IconFilm size={32} className="text-violet mb-4" />
          <h3 className="text-2xl font-semibold tracking-[-0.01em] mb-2">You’re out of free shots</h3>
          <p className="text-sm text-ink-soft leading-relaxed mb-6">
            Your 5 free developments reset next month — or go Creator for unlimited shots, no
            watermark, and every premium camera mood.
          </p>
          <Link to="/pricing" className="btn btn-primary w-full mb-2">
            Upgrade — from $7/mo
          </Link>
          <button onClick={() => setPaywall(false)} className="btn btn-quiet w-full">
            Maybe later
          </button>
        </div>
      </Modal>
    </main>
  )
}
