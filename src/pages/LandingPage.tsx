import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import { IconDownload, IconFilm, IconUpload } from '../components/icons'
import { loadImage, renderStyled } from '../lib/engine'
import { CAMERA_STYLES, getStyle } from '../lib/styles'
import { useStyleThumbs } from '../lib/useStyleThumbs'
import sampleGolden from '../assets/sample-golden.jpg'
import sampleStreet from '../assets/sample-street.jpg'
import sampleNight from '../assets/sample-night.jpg'

const SAMPLES = [sampleGolden, sampleStreet, sampleNight]

const fadeUp = {
  initial: { opacity: 0, y: 12 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: '-80px' },
  transition: { duration: 0.35, ease: 'easeOut' as const },
}

const STEPS = [
  {
    n: '01',
    title: 'Upload',
    body: 'Drop in any photo — a portrait, a night out, your dog. Processing runs in your browser; nothing is uploaded.',
    icon: IconUpload,
  },
  {
    n: '02',
    title: 'Choose a mood',
    body: 'Disposable flash, A24 still, Y2K digicam. Nine cameras, one photo. Pick the one it deserved.',
    icon: IconFilm,
  },
  {
    n: '03',
    title: 'Develop and share',
    body: 'Fine-tune grain and glow, compare against the original, export for TikTok and Reels.',
    icon: IconDownload,
  },
]

const CAPTIONS = [
  'POV: your photo was shot on a $7,000 camera',
  'I turned my photo into an A24 movie still',
  'This was just a normal photo before LensMood',
]

export default function LandingPage() {
  const [heroAfter, setHeroAfter] = useState<string | null>(null)
  // every marquee card shows its real developed look, not a CSS approximation
  const marqueeThumbs = useStyleThumbs(sampleGolden, 480)

  /* develop the hero "after" image with the real engine */
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const img = await loadImage(sampleGolden)
      const a24 = getStyle('a24-still')!
      const canvas = renderStyled(img, a24, { ...a24.defaults, intensity: 90 }, { maxSize: 900 })
      if (!cancelled) setHeroAfter(canvas.toDataURL('image/jpeg', 0.88))
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <main className="pb-24 md:pb-0">
      {/* ================= hero ================= */}
      <section>
        <div className="max-w-7xl mx-auto px-4 sm:px-6 pt-14 sm:pt-20 pb-16 grid lg:grid-cols-12 gap-12 lg:gap-10 items-center">
          <div className="lg:col-span-6">
            <motion.p
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, ease: 'easeOut' }}
              className="mb-6"
            >
              <span className="tag tag-signal">The aesthetic camera</span>
            </motion.p>
            <motion.h1
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.05, duration: 0.35, ease: 'easeOut' }}
              className="type-display text-[clamp(2.5rem,6vw,4.5rem)]"
            >
              Turn any photo into a <span className="grad-text">cinematic</span> camera shot.
            </motion.h1>
            <motion.p
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.12, duration: 0.35, ease: 'easeOut' }}
              className="mt-6 text-[15px] leading-[1.6] text-ink-soft max-w-[52ch]"
            >
              Upload a photo, choose a camera mood, and recreate the lighting, grain, and color of
              the cameras that defined an era. See what your photo looks like shot on a $7,000
              camera.
            </motion.p>
            <motion.div
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.18, duration: 0.35, ease: 'easeOut' }}
              className="mt-8 flex flex-wrap items-center gap-3"
            >
              <span className="glow-ring inline-flex">
                <Link to="/studio" className="btn btn-primary btn-lg border-0">
                  Try it free
                </Link>
              </span>
              <button
                onClick={() => document.getElementById('styles')?.scrollIntoView({ behavior: 'smooth' })}
                className="btn btn-outline btn-lg"
              >
                Explore camera moods
              </button>
            </motion.div>
            <motion.p
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 0.3, duration: 0.35 }}
              className="mt-10 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-[13px] font-medium text-fog"
            >
              {['5 free shots/mo', 'No sign-up', 'On-device processing'].map((t, i) => (
                <span key={t} className="inline-flex items-center gap-3">
                  {i > 0 && <span className="w-1 h-1 rounded-full bg-violet/50" aria-hidden />}
                  {t}
                </span>
              ))}
            </motion.p>
          </div>

          {/* hero before/after — viewfinder frame */}
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.15, duration: 0.4, ease: 'easeOut' }}
            className="lg:col-span-6 w-full max-w-md mx-auto lg:max-w-[460px] lg:ml-auto"
          >
            <div className="bg-vf rounded-[24px] overflow-hidden shadow-[0_2px_8px_rgb(23_19_31/0.10),0_28px_64px_-24px_rgb(139_92_246/0.45)]">
              <div className="h-9 px-4 flex items-center justify-between border-b border-white/10">
                <span className="inline-flex items-center gap-2 font-mono text-[10px] tracking-[0.14em] text-vf-chrome">
                  <span className="w-1.5 h-1.5 rounded-full bg-signal lm-breathe" />
                  LM ENGINE — LIVE
                </span>
                <span className="font-mono text-[10px] tracking-[0.14em] text-vf-chrome">A24 STILL</span>
              </div>
              <div className="vf-corners p-2 sm:p-3">
                {heroAfter ? (
                  <BeforeAfterSlider
                    before={sampleGolden}
                    after={heroAfter}
                    auto
                    afterLabel="A24 Still"
                    className="aspect-4/5 rounded-[14px] overflow-hidden"
                  />
                ) : (
                  <img
                    src={sampleGolden}
                    alt=""
                    className="aspect-4/5 w-full object-cover rounded-[14px]"
                  />
                )}
              </div>
            </div>
            <p className="mt-3 text-[12px] text-fog text-center">
              Drag to compare — A24 Still applied by the LensMood engine, live
            </p>
          </motion.div>
        </div>
      </section>

      {/* ================= style marquee ================= */}
      <section id="styles" className="py-14 sm:py-20 scroll-mt-20">
        <motion.div
          {...fadeUp}
          className="max-w-7xl mx-auto px-4 sm:px-6 mb-10 flex items-end justify-between gap-4"
        >
          <div>
            <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-3 tabular-nums">
              Camera moods · {String(CAMERA_STYLES.length).padStart(2, '0')}
            </p>
            <h2 className="type-display text-3xl sm:text-5xl">
              One photo. <span className="grad-text">Every era.</span>
            </h2>
          </div>
          <Link to="/studio" className="btn btn-outline hidden sm:inline-flex shrink-0">
            Try them on your photo
          </Link>
        </motion.div>

        <div className="lm-marquee-pause overflow-hidden relative">
          {/* bleed-edge fades so cards never appear chopped mid-label */}
          <div className="absolute inset-y-0 left-0 w-12 sm:w-20 z-10 bg-gradient-to-r from-paper to-transparent pointer-events-none" />
          <div className="absolute inset-y-0 right-0 w-12 sm:w-20 z-10 bg-gradient-to-l from-paper to-transparent pointer-events-none" />
          <div className="lm-marquee flex gap-4 w-max px-2 py-4 pr-4">
            {[...CAMERA_STYLES, ...CAMERA_STYLES].map((style, i) => (
              <Link
                key={`${style.id}-${i}`}
                to={`/studio?style=${style.id}`}
                className="group w-52 sm:w-60 shrink-0 bg-surface rounded-[20px] border border-ink/5 p-2 shadow-[0_2px_10px_rgb(23_19_31/0.04)] hover:-translate-y-1 hover:shadow-[0_14px_32px_-8px_rgb(139_92_246/0.25)] transition-[box-shadow,transform] duration-200 ease-out"
              >
                <div className="relative aspect-4/5 overflow-hidden rounded-[14px] bg-vf">
                  <img
                    src={marqueeThumbs[style.id] ?? SAMPLES[i % SAMPLES.length]}
                    alt={style.name}
                    loading="lazy"
                    className="w-full h-full object-cover"
                    style={marqueeThumbs[style.id] ? undefined : { filter: style.cardFilter }}
                    draggable={false}
                  />
                  {style.tier === 'premium' && (
                    <span className="tag tag-chrome absolute top-2 right-2">PRO</span>
                  )}
                </div>
                <div className="px-2 pt-3 pb-2">
                  <div className="flex items-center justify-between gap-2">
                    <span className="label-mono tabular-nums">
                      LM·{String((i % CAMERA_STYLES.length) + 1).padStart(2, '0')}
                    </span>
                    {style.badge === 'trending' && <span className="tag tag-signal">TRENDING</span>}
                  </div>
                  <p className="mt-1.5 text-[14px] font-semibold leading-snug">{style.name}</p>
                  <p className="mt-0.5 text-[12px] text-fog leading-snug">{style.tagline}</p>
                </div>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* ================= how it works ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 py-16 sm:py-24">
        <motion.div {...fadeUp} className="mb-12">
          <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-3">
            How it works
          </p>
          <h2 className="type-display text-3xl sm:text-5xl">
            Three steps to <span className="grad-text">the shot.</span>
          </h2>
        </motion.div>
        <div className="grid sm:grid-cols-3 gap-4 sm:gap-5">
          {STEPS.map((step, i) => (
            <motion.div
              key={step.n}
              {...fadeUp}
              transition={{ ...fadeUp.transition, delay: i * 0.08 }}
              className="panel p-6 sm:p-7"
            >
              <div className="flex items-center justify-between">
                <span className="w-11 h-11 rounded-2xl bg-violet/10 text-violet flex items-center justify-center">
                  <step.icon size={20} />
                </span>
                <span className="text-[12px] font-semibold text-fog tabular-nums">{step.n}</span>
              </div>
              <h3 className="mt-5 text-[17px] font-semibold">{step.title}</h3>
              <p className="mt-2 text-[14px] text-fog leading-relaxed">{step.body}</p>
            </motion.div>
          ))}
        </div>
      </section>

      {/* ================= captions band ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6">
        <div className="bg-vf rounded-[28px] overflow-hidden px-6 sm:px-12 py-14 sm:py-16 grid lg:grid-cols-2 gap-12 items-center">
          <motion.div {...fadeUp}>
            <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-orchid mb-3">
              Made to be posted
            </p>
            <h2 className="type-display text-3xl sm:text-4xl text-paper mb-4">
              Captions <span className="grad-text">included.</span>
            </h2>
            <p className="text-[15px] leading-[1.6] text-vf-chrome max-w-md mb-8">
              Every export ships with a share card, an auto-written caption, and a link your friends
              can copy the style from. The jokes live in the captions, not the interface.
            </p>
            <Link to="/studio" className="btn btn-lg bg-white text-ink border-0 hover:bg-paper">
              Make one now
            </Link>
          </motion.div>
          <div className="space-y-3">
            {CAPTIONS.map((caption, i) => (
              <motion.div
                key={caption}
                initial={{ opacity: 0, y: 8 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: 0.1 + i * 0.08, duration: 0.3, ease: 'easeOut' }}
                className="rounded-2xl bg-white/5 border border-white/10 px-4 py-3.5 flex items-baseline gap-3"
              >
                <span className="font-mono text-[11px] tracking-[0.1em] text-vf-chrome tabular-nums shrink-0">
                  C·{String(i + 1).padStart(2, '0')}
                </span>
                <span className="text-[14px] text-paper/90">“{caption}”</span>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ================= featured mood ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 py-12 sm:py-16">
        <motion.div {...fadeUp} className="panel p-6 sm:p-8 flex flex-col sm:flex-row sm:items-center gap-6">
          <div className="w-28 sm:w-32 shrink-0 rounded-2xl overflow-hidden">
            <img
              src={marqueeThumbs['a24-still'] ?? sampleNight}
              alt="A24 Movie Still sample"
              className="aspect-4/5 w-full object-cover"
              style={marqueeThumbs['a24-still'] ? undefined : { filter: getStyle('a24-still')!.cardFilter }}
            />
          </div>
          <div>
            <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-2">
              Featured this week
            </p>
            <h3 className="text-2xl font-semibold tracking-[-0.01em] mb-1.5">A24 Movie Still</h3>
            <p className="text-[14px] text-ink-soft leading-relaxed max-w-lg mb-4">
              Muted palette, cinematic shadows, soft highlights. This week’s most-developed mood —
              quiet, moody, devastating.
            </p>
            <Link to="/studio?style=a24-still" className="btn btn-outline">
              Shoot it
            </Link>
          </div>
        </motion.div>
      </section>

      {/* ================= pricing teaser ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 pb-16 sm:pb-24">
        <div className="pt-12 sm:pt-16 grid lg:grid-cols-12 gap-10 items-start">
          <div className="lg:col-span-7">
            <motion.h2 {...fadeUp} className="type-display text-3xl sm:text-5xl mb-4 max-w-3xl">
              Free to start.
              <br />
              $7&#8202;/&#8202;month to go <span className="grad-text">unlimited.</span>
            </motion.h2>
            <motion.p {...fadeUp} className="text-[15px] leading-[1.6] text-ink-soft max-w-xl mb-8">
              5 free developments every month. Creators get unlimited exports, no watermarks, and
              every premium camera pack.
            </motion.p>
            <motion.div {...fadeUp} className="flex flex-wrap gap-3">
              <Link to="/studio" className="btn btn-primary btn-lg">
                Try it free
              </Link>
              <Link to="/pricing" className="btn btn-outline btn-lg">
                See pricing
              </Link>
            </motion.div>
          </div>
          {/* spec sheet */}
          <motion.dl {...fadeUp} className="lg:col-span-5 grid grid-cols-2 gap-3 sm:gap-4">
            {[
              { v: '09', k: 'Camera moods' },
              { v: '30s', k: 'Video clips' },
              { v: '00', k: 'Uploads — on-device' },
              { v: '∞', k: 'Retakes' },
            ].map((s) => (
              <div key={s.k} className="panel p-5">
                <dt className="sr-only">{s.k}</dt>
                <dd className="text-3xl font-bold tracking-tight tabular-nums leading-none mb-2">
                  {s.v}
                </dd>
                <dd className="text-[12px] font-medium text-fog">{s.k}</dd>
              </div>
            ))}
          </motion.dl>
        </div>
      </section>
    </main>
  )
}
