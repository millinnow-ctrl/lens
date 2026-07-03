import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import UploadArea from '../components/UploadArea'
import StyleCarousel from '../components/StyleCarousel'
import AdjustmentPanel from '../components/AdjustmentPanel'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import ExportPanel from '../components/ExportPanel'
import Modal from '../components/Modal'
import { loadImage, renderStyled, thumbnail } from '../lib/engine'
import { GENERATION_STEPS, getStyle, type CameraStyle, type StyleParams } from '../lib/styles'
import { useApp } from '../lib/store'

type Phase = 'idle' | 'generating' | 'done'
type View = 'result' | 'original' | 'compare'

export default function Studio() {
  const {
    photo,
    setPhoto,
    styleId,
    params,
    selectStyle,
    setParams,
    creditsLeft,
    isPaid,
    spendCredit,
    addHistory,
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

  const style = getStyle(styleId)
  const generationTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const renderRaf = useRef(0)
  const pendingStyleUsed = useRef(false)

  /* load the uploaded photo into an Image element */
  useEffect(() => {
    if (!photo) {
      setSource(null)
      setResultUrl(null)
      setPhase('idle')
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

  /* deep link: /studio?style=a24-still */
  useEffect(() => {
    const pending = searchParams.get('style')
    if (pending && source && !styleId && !pendingStyleUsed.current) {
      const s = getStyle(pending)
      if (s) {
        pendingStyleUsed.current = true
        beginGeneration(s)
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [source, searchParams, styleId])

  /* re-render instantly when sliders move after the first development */
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

  const beginGeneration = useCallback(
    (s: CameraStyle, presetParams?: StyleParams) => {
      if (!source) return
      if (!spendCredit()) {
        setPaywall(true)
        return
      }
      selectStyle(s.id, presetParams)
      setView('result')
      setShutter(true)
      setTimeout(() => setShutter(false), 750)
      setPhase('generating')

      if (generationTimer.current) clearTimeout(generationTimer.current)
      generationTimer.current = setTimeout(() => {
        const effective = presetParams ?? s.defaults
        const canvas = renderStyled(source, s, effective, { maxSize: 1280 })
        setResultUrl(canvas.toDataURL('image/jpeg', 0.9))
        setPhase('done')
        addHistory({ thumb: thumbnail(canvas), styleId: s.id, styleName: s.name })
      }, 2300)
    },
    [source, spendCredit, selectStyle, addHistory],
  )

  useEffect(
    () => () => {
      if (generationTimer.current) clearTimeout(generationTimer.current)
    },
    [],
  )

  /* ------------------------------------------------ empty state */
  if (!photo) {
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
              f/1.4 · ISO 400
            </div>

            {/* image area */}
            {view === 'compare' && resultUrl && photo ? (
              <BeforeAfterSlider
                before={photo}
                after={resultUrl}
                className="w-full aspect-4/5 sm:aspect-auto sm:h-[62dvh]"
              />
            ) : (
              <div className="relative w-full flex items-center justify-center">
                <img
                  key={view === 'original' || !resultUrl ? 'orig' : resultUrl}
                  src={view === 'original' || !resultUrl ? photo : resultUrl}
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
                  {/* aperture spinner */}
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

          {/* view toggles + actions under preview */}
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <div className="inline-flex rounded-full bg-mist p-1">
              {(
                [
                  { id: 'original', label: 'Original' },
                  { id: 'result', label: 'LensMood' },
                  { id: 'compare', label: 'Compare' },
                ] as { id: View; label: string }[]
              ).map((t) => (
                <button
                  key={t.id}
                  disabled={!resultUrl && t.id !== 'original'}
                  onClick={() => setView(t.id)}
                  className={`px-4 py-1.5 rounded-full text-[13px] font-semibold transition-all disabled:opacity-40 ${
                    view === t.id ? 'bg-paper shadow-sm text-ink' : 'text-fog hover:text-ink'
                  }`}
                >
                  {t.label}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-2">
              <button onClick={() => setPhoto(null)} className="pill-base pill-ghost px-4 py-2 text-[13px]">
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
            <StyleCarousel
              previewSrc={photo}
              selectedId={styleId}
              onSelect={(s) => beginGeneration(s)}
            />
          </section>

          <AnimatePresence>
            {style && params && phase === 'done' && (
              <motion.section
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 8 }}
                className="card p-5"
              >
                <h2 className="font-display text-lg font-semibold mb-4">Fine-tune</h2>
                <AdjustmentPanel style={style} params={params} onChange={setParams} />
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
          <button onClick={() => setPaywall(false)} className="w-full text-[13px] font-medium text-fog hover:text-ink py-2 transition-colors">
            Maybe later
          </button>
        </div>
      </Modal>
    </main>
  )
}
