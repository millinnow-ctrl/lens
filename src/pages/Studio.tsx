import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
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
import { detectFocal, type Focal } from '../lib/focal'
import { analyzeScene, sceneLabel } from '../lib/scene'
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
    history,
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
  /* presentation-only: play the wet-print reveal once when a develop lands,
     not on every slider re-render. Does not touch develop timing/logic. */
  const [revealing, setRevealing] = useState(false)
  /* brief "re-metering" badge shown when a recipe/reset is applied — the
     engine really does re-run the scene pass, and this makes the work felt */
  const [reprocessing, setReprocessing] = useState(false)
  const reprocessTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const onReprocess = useCallback(() => {
    setReprocessing(true)
    if (reprocessTimer.current) clearTimeout(reprocessTimer.current)
    reprocessTimer.current = setTimeout(() => setReprocessing(false), 520)
  }, [])

  const style = getStyle(styleId)
  const generationTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const renderRaf = useRef(0)
  /** the exact search string already honored — lets a NEW deep link fire even
   *  when a style from earlier in the session is still selected */
  const deepLinkHandled = useRef<string | null>(null)
  const hasMedia = !!photo || !!video

  /* load the active photo into an Image element, then let the on-device
     face model find the subject (silently — the engine works without it) */
  const [focal, setFocal] = useState<Focal | null>(null)
  /* the meter's reading of the loaded photo — the AI showing its work in the
     viewfinder chrome. Cached per (image, focal), so this is ~free. */
  const meterReading = useMemo(() => {
    if (!source) return null
    const label = sceneLabel(analyzeScene(source, focal))
    return focal ? `${label} · FACE` : label
  }, [source, focal])
  useEffect(() => {
    // cancel any develop still counting down for the PREVIOUS photo — without
    // this, switching photo (or "New photo") mid-develop lets the stale timer
    // fire 2.3s later with the old source in its closure, painting the wrong
    // image and logging a phantom history entry
    if (generationTimer.current) {
      clearTimeout(generationTimer.current)
      generationTimer.current = null
    }
    setResultUrl(null)
    setPhase('idle')
    setView('result')
    setFocal(null)
    if (!photo) {
      setSource(null)
      return
    }
    let cancelled = false
    loadImage(photo).then((img) => {
      if (cancelled) return
      setSource(img)
      detectFocal(img).then((f) => {
        if (!cancelled) setFocal(f)
      })
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
      // the very first develop is always on the house — the aha moment
      // must never sit behind the meter
      const firstShot = history.length === 0
      if (!freeShot && !firstShot && !spendCredit()) {
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
          const canvas = renderStyled(source, s, effective, { maxSize: 1280, focal })
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
    [source, video, videoPoster, focal, history.length, spendCredit, selectStyle, addHistory],
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

  /* re-render instantly when sliders move after the first development (photos).
     One persistent scratch canvas is reused across re-renders — halves the
     transient allocation spike per slider move (matters in a WKWebView). */
  const scratchCanvas = useRef<HTMLCanvasElement | null>(null)
  useEffect(() => {
    if (phase !== 'done' || !source || !style || !params) return
    cancelAnimationFrame(renderRaf.current)
    renderRaf.current = requestAnimationFrame(() => {
      if (!scratchCanvas.current) scratchCanvas.current = document.createElement('canvas')
      const canvas = renderStyled(source, style, params, {
        maxSize: 1280,
        focal,
        target: scratchCanvas.current,
      })
      setResultUrl(canvas.toDataURL('image/jpeg', 0.9))
    })
    return () => cancelAnimationFrame(renderRaf.current)
  }, [params, phase, source, style, focal])

  /* fire the wet-print reveal exactly once per finished develop. Keyed off
     the phase flip (not resultUrl) so slider edits update instantly without
     re-running the emergence. Presentation only — no effect on timing. */
  useEffect(() => {
    if (phase !== 'done') {
      setRevealing(false)
      return
    }
    setRevealing(true)
    const reduce =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    const t = setTimeout(() => setRevealing(false), reduce ? 300 : 2000)
    return () => clearTimeout(t)
  }, [phase])

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
      if (reprocessTimer.current) clearTimeout(reprocessTimer.current)
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
    <main className="max-w-7xl mx-auto px-4 sm:px-6 py-6 sm:py-10 pb-[calc(env(safe-area-inset-bottom)+132px)] md:pb-16">
      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_400px] gap-6 lg:gap-8 items-start">
        {/* ---------- preview column ---------- */}
        <div className="lg:sticky lg:top-20 min-w-0">
          <div className="bg-vf rounded-[24px] overflow-hidden shadow-[0_2px_12px_rgb(23_19_31/0.10),inset_0_1px_0_rgb(255_255_255/0.07)]">
            {/* viewfinder chrome strip — etched machined bezel */}
            <div className="h-9 px-4 flex items-center justify-between gap-3 border-b border-white/[0.08]">
              <span className="font-mono font-semibold text-[10px] tracking-[0.16em] uppercase text-vf-chrome truncate">
                {style ? style.name : 'Original'}
                {meterReading && <span className="text-vf-chrome/70"> · {meterReading}</span>}
              </span>
              <span className="flex items-center gap-2 font-mono font-semibold text-[10px] tracking-[0.16em] uppercase text-vf-chrome tabular-nums shrink-0">
                {video && <span className="w-1.5 h-1.5 rounded-full bg-[#E1251B] inline-block" aria-hidden />}
                {focal && !video && <span className="text-violet">AF·FACE</span>}
                <span>{video ? 'REC · 30FPS' : (style?.exif ?? 'READY · NO MOOD')}</span>
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
                fitToImage
                className="w-full aspect-4/5"
              />
            ) : (
              <div className="relative w-full flex items-center justify-center">
                <img
                  key={showOriginal ? 'orig' : resultUrl}
                  src={showOriginal || !resultUrl ? photo! : resultUrl}
                  alt="Preview"
                  className={`w-full max-h-[62dvh] object-contain ${
                    phase === 'done' && view === 'result' && revealing ? 'lm-print-resolve' : ''
                  }`}
                  draggable={false}
                />
                {/* wet-print reveal — sheen, developer bloom and settling grain,
                    played once as the print resolves (unmounts when it clears) */}
                {phase === 'done' && view === 'result' && revealing && (
                  <div aria-hidden className="absolute inset-0 pointer-events-none overflow-hidden">
                    <div className="lm-print-bloom absolute inset-0" />
                    <div className="lm-print-grain absolute inset-0" />
                    <div className="lm-print-sheen absolute inset-0" />
                  </div>
                )}
              </div>
            )}

            {/* shutter flash */}
            {shutter && <div className="absolute inset-0 bg-white z-30 lm-shutter-flash pointer-events-none" />}

            {/* re-metering badge — light, corner-anchored, only on recipe changes */}
            <AnimatePresence>
              {reprocessing && phase === 'done' && (
                <motion.div
                  initial={{ opacity: 0, y: 4 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: 4 }}
                  transition={{ duration: 0.18, ease: 'easeOut' }}
                  className="absolute top-3 left-3 z-30 flex items-center gap-2 rounded-full bg-[#08060c]/80 backdrop-blur-md px-3 h-8 pointer-events-none"
                >
                  <span className="lm-spin w-3 h-3 rounded-full border-2 border-white/25 border-t-white/90" aria-hidden />
                  <span className="font-mono text-[9.5px] font-semibold uppercase tracking-[0.16em] text-white/90">
                    Re-metering
                  </span>
                </motion.div>
              )}
            </AnimatePresence>

            {/* developing overlay */}
            <AnimatePresence>
              {phase === 'generating' && (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.35, ease: 'easeOut' }}
                  className="absolute inset-0 z-20 bg-[#08060c]/[0.97] flex flex-col items-center justify-center gap-5 overflow-hidden"
                >
                  {/* darkroom atmosphere — warm safelight flicker, tray vignette,
                      grain drifting, and developer washing down the frame */}
                  <div aria-hidden className="lm-safelight absolute inset-0 pointer-events-none" />
                  <div aria-hidden className="lm-darkroom-vignette absolute inset-0 pointer-events-none" />
                  <div aria-hidden className="lm-darkroom-grain absolute inset-0 pointer-events-none" />
                  <div aria-hidden className="lm-darkroom-sweep absolute inset-0 pointer-events-none" />

                  {/* iris emblem — a quiet mechanical iris breathing in the safelight */}
                  <div aria-hidden className="lm-iris relative">
                    <svg viewBox="0 0 48 48" className="w-12 h-12">
                      {[...Array(6)].map((_, i) => (
                        <path
                          key={i}
                          d="M24 6 A18 18 0 0 1 39.6 15 L27 21.6 A6 6 0 0 0 24 21 Z"
                          fill="#ffffff"
                          opacity={0.26 + (i / 6) * 0.5}
                          transform={`rotate(${i * 60} 24 24)`}
                        />
                      ))}
                      <circle cx="24" cy="24" r="4.5" fill="#5f7247" />
                    </svg>
                  </div>
                  <div className="relative flex flex-col items-center gap-2">
                    <AnimatePresence mode="wait">
                      <motion.p
                        key={stepIndex}
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0, y: -8 }}
                        className="font-mono text-[11px] tracking-[0.14em] uppercase text-white/90"
                      >
                        {style ? `${style.name} — ` : ''}
                        {GENERATION_STEPS[stepIndex]}
                      </motion.p>
                    </AnimatePresence>
                    {/* the camera's exif readout, ticking like a meter needle */}
                    {style && (
                      <motion.p
                        animate={{ opacity: [0.35, 0.75, 0.35] }}
                        transition={{ repeat: Infinity, duration: 1.15, ease: 'easeInOut' }}
                        className="font-mono font-semibold text-[10px] tracking-[0.2em] uppercase tabular-nums text-[#b5c98f]/80"
                      >
                        {style.exif}
                      </motion.p>
                    )}
                  </div>
                  {/* thin develop line running the bottom edge of the viewfinder */}
                  <div className="absolute bottom-0 inset-x-0 h-[2px] bg-white/[0.06] overflow-hidden">
                    <motion.div
                      className="h-full grad-fill lm-develop-line"
                      initial={{ width: '2%' }}
                      animate={{ width: '98%' }}
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
                      className={`font-mono font-semibold text-[10px] tracking-[0.1em] tabular-nums text-center ${
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
            <div className="flex w-full sm:w-auto sm:inline-flex items-center gap-0.5 rounded-full bg-[rgb(60_42_24/0.07)] p-1 shadow-[inset_0_1px_2px_rgb(60_42_24/0.16)]">
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
                    className={`px-4 h-8 font-mono text-[11px] tracking-[0.12em] uppercase rounded-full transition-[background-color,color,box-shadow,transform] duration-150 flex-1 sm:flex-none ${
                      active
                        ? // solid machined pill — fill + scale + soft shadow, stays lifted even while siblings disable
                          'bg-white text-ink shadow-[0_1px_4px_rgb(23_19_31/0.16)] scale-[1.02]'
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
              <button
                onClick={clearMedia}
                className="btn btn-quiet font-mono text-[11px] tracking-[0.14em] uppercase"
              >
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
              <h2 className="type-display text-[21px]">Camera mood</h2>
              {!isPaid && (
                <span className="font-mono font-semibold text-[10px] tracking-[0.1em] uppercase text-fog tabular-nums">
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
                <h2 className="type-display text-[21px] mb-1">Fine-tune</h2>
                {video && (
                  <p className="text-[12px] text-fog mb-3">Adjustments apply to the clip live.</p>
                )}
                <div className={video ? '' : 'mt-3'}>
                  <AdjustmentPanel
                    style={style}
                    params={params}
                    onChange={setParams}
                    onReprocess={onReprocess}
                  />
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
          focal={focal}
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
