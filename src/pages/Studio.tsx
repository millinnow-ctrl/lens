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
import { loadImage, renderStyled, thumbnail } from '../lib/engine'
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
  const deepLinkUsed = useRef(false)
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
    (s: CameraStyle, presetParams?: StyleParams) => {
      if (!source && !video) return
      if (!spendCredit()) {
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

  /* deep link: /studio?style=a24-still&p=90.30.55.46.0.58.0 */
  useEffect(() => {
    const pendingStyle = searchParams.get('style')
    if (pendingStyle && (source || video) && !styleId && !deepLinkUsed.current) {
      const s = getStyle(pendingStyle)
      if (s) {
        deepLinkUsed.current = true
        beginGeneration(s, decodeParams(searchParams.get('p')) ?? undefined)
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
        <div className="text-center mb-10">
          <p className="text-xs font-bold uppercase tracking-widest text-violet mb-2">The Studio</p>
          <h1 className="font-display text-3xl sm:text-5xl font-semibold tracking-tight">
            Every photo has a mood.
            <br className="hidden sm:block" /> Let’s find yours.
          </h1>
        </div>
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
          <div className="relative rounded-[2rem] overflow-hidden bg-[#0d0d12] shadow-lg min-h-[320px] flex items-center justify-center">
            {/* subtle viewfinder chrome */}
            <div className="absolute top-3.5 left-4 z-20 flex items-center gap-2 pointer-events-none">
              <span className="font-mono text-[10px] tracking-widest text-white/50 uppercase">
                {style ? style.name : 'Original'}
              </span>
            </div>
            <div className="absolute top-3.5 right-4 z-20 font-mono text-[10px] tracking-widest text-white/40 pointer-events-none">
              {video ? 'REC · 30fps' : 'f/1.4 · ISO 400'}
            </div>

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
                  className="absolute inset-0 z-20 bg-[#0d0d12]/72 backdrop-blur-md flex flex-col items-center justify-center gap-5"
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
                        fill="#a88bff"
                        opacity={0.35 + (i / 6) * 0.65}
                        transform={`rotate(${i * 60} 24 24)`}
                      />
                    ))}
                    <circle cx="24" cy="24" r="5" fill="#fff" />
                  </motion.svg>
                  <AnimatePresence mode="wait">
                    <motion.p
                      key={stepIndex}
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -8 }}
                      className="text-white/90 text-sm font-medium tracking-wide"
                    >
                      {GENERATION_STEPS[stepIndex]}
                    </motion.p>
                  </AnimatePresence>
                  <div className="w-44 h-1 rounded-full bg-white/15 overflow-hidden">
                    <motion.div
                      className="h-full bg-violet rounded-full"
                      initial={{ width: '4%' }}
                      animate={{ width: '96%' }}
                      transition={{ duration: 2.2, ease: 'easeInOut' }}
                    />
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* roll filmstrip */}
          {roll.length > 1 && (
            <div className="mt-3 flex gap-2 overflow-x-auto no-scrollbar py-1">
              {roll.map((item, i) => (
                <button
                  key={`${item.name}-${i}`}
                  onClick={() => setActiveIndex(i)}
                  className={`relative shrink-0 w-14 aspect-4/5 rounded-lg overflow-hidden transition-all ${
                    i === activeIndex
                      ? 'ring-2 ring-violet scale-105'
                      : 'ring-1 ring-cloud opacity-70 hover:opacity-100'
                  }`}
                  aria-label={`Photo ${i + 1} of ${roll.length}`}
                >
                  <img src={item.url} alt="" className="w-full h-full object-cover" />
                </button>
              ))}
            </div>
          )}

          {/* view toggles + actions under preview */}
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <div className="inline-flex rounded-full bg-mist p-1">
              {(
                [
                  { id: 'original', label: 'Original' },
                  { id: 'result', label: 'LensMood' },
                  { id: 'compare', label: 'Compare' },
                ] as { id: View; label: string }[]
              ).map((t) => {
                const disabled =
                  (t.id !== 'original' && phase !== 'done') || (t.id === 'compare' && !!video)
                return (
                  <button
                    key={t.id}
                    disabled={disabled}
                    onClick={() => setView(t.id)}
                    className={`px-4 py-1.5 rounded-full text-[13px] font-semibold transition-all disabled:opacity-40 ${
                      view === t.id ? 'bg-paper shadow-sm text-ink' : 'text-fog hover:text-ink'
                    }`}
                  >
                    {t.label}
                  </button>
                )
              })}
            </div>

            <div className="flex items-center gap-2">
              <button onClick={clearMedia} className="pill-base pill-ghost px-4 py-2 text-[13px]">
                New photo
              </button>
              <button
                onClick={() => setExportOpen(true)}
                disabled={phase !== 'done'}
                className="pill-base pill-violet px-5 py-2 text-[13px] disabled:opacity-40"
              >
                Export & share
              </button>
            </div>
          </div>
        </div>

        {/* ---------- controls column ---------- */}
        <div className="space-y-6 min-w-0">
          <section className="card p-5">
            <div className="flex items-baseline justify-between mb-1">
              <h2 className="font-display text-lg font-semibold">Camera mood</h2>
              {!isPaid && (
                <span className="text-[11px] font-semibold text-fog">
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
                className="card p-5"
              >
                <h2 className="font-display text-lg font-semibold mb-1">Fine-tune</h2>
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
        <div className="p-8 text-center">
          <div className="text-4xl mb-3">🎞️</div>
          <h3 className="font-display text-2xl font-semibold mb-2">You’re out of free shots</h3>
          <p className="text-sm text-fog mb-6 leading-relaxed">
            Your 5 free developments reset next month — or go Creator for unlimited shots, no
            watermark, and every premium camera mood.
          </p>
          <Link to="/pricing" className="pill-base pill-violet w-full px-5 py-3 text-sm mb-2.5">
            Upgrade — from $7/mo
          </Link>
          <button
            onClick={() => setPaywall(false)}
            className="w-full text-[13px] font-medium text-fog hover:text-ink py-2 transition-colors"
          >
            Maybe later
          </button>
        </div>
      </Modal>
    </main>
  )
}
