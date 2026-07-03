import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import { loadImage, renderStyled } from '../lib/engine'
import { CAMERA_STYLES, getStyle } from '../lib/styles'
import sampleGolden from '../assets/sample-golden.svg'
import sampleStreet from '../assets/sample-street.svg'
import sampleNight from '../assets/sample-night.svg'

const SAMPLES = [sampleGolden, sampleStreet, sampleNight]

const fadeUp = {
  initial: { opacity: 0, y: 24 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: '-80px' },
  transition: { duration: 0.55, ease: 'easeOut' as const },
}

export default function LandingPage() {
  const [heroAfter, setHeroAfter] = useState<string | null>(null)

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
      <section className="relative overflow-hidden">
        <div className="absolute -top-40 -left-32 w-[34rem] h-[34rem] rounded-full bg-violet/12 blur-3xl pointer-events-none" />
        <div className="absolute top-24 -right-40 w-[30rem] h-[30rem] rounded-full bg-amber-flash/14 blur-3xl pointer-events-none" />

        <div className="max-w-7xl mx-auto px-4 sm:px-6 pt-14 sm:pt-24 pb-16 grid lg:grid-cols-2 gap-12 lg:gap-8 items-center">
          <div className="relative z-10 text-center lg:text-left">
            <motion.p
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              className="inline-flex items-center gap-2 text-[12px] font-semibold text-violet bg-violet-soft rounded-full px-3.5 py-1.5 mb-6"
            >
              ✦ The AI aesthetic camera
            </motion.p>
            <motion.h1
              initial={{ opacity: 0, y: 18 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.06 }}
              className="font-display text-[2.6rem] leading-[1.05] sm:text-6xl lg:text-[4.2rem] font-semibold tracking-tight"
            >
              Turn any photo into a{' '}
              <span className="italic bg-gradient-to-r from-violet to-[#b264ff] bg-clip-text text-transparent">
                cinematic
              </span>{' '}
              camera shot.
            </motion.h1>
            <motion.p
              initial={{ opacity: 0, y: 18 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.14 }}
              className="mt-5 text-fog text-base sm:text-lg leading-relaxed max-w-xl mx-auto lg:mx-0"
            >
              Upload a photo, choose a camera mood, and recreate the lighting, grain, color, and
              vibe of iconic camera styles. See what your photo would look like shot on a $7,000
              camera.
            </motion.p>
            <motion.div
              initial={{ opacity: 0, y: 18 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.22 }}
              className="mt-8 flex flex-wrap items-center justify-center lg:justify-start gap-3"
            >
              <Link to="/studio" className="pill-base pill-violet px-7 py-3.5 text-base">
                Try it free
              </Link>
              <button
                onClick={() => document.getElementById('styles')?.scrollIntoView({ behavior: 'smooth' })}
                className="pill-base pill-ghost px-7 py-3.5 text-base"
              >
                Explore camera styles
              </button>
            </motion.div>
            <motion.p
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 0.4 }}
              className="mt-5 text-[13px] text-fog"
            >
              5 free shots a month · no sign-up · photos never leave your browser
            </motion.p>
          </div>

          {/* hero before/after */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 24 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            transition={{ delay: 0.18, duration: 0.6, ease: 'easeOut' }}
            className="relative mx-auto w-full max-w-md lg:max-w-none"
          >
            <div className="absolute -inset-6 bg-gradient-to-tr from-violet/18 via-transparent to-amber-flash/18 rounded-[3rem] blur-2xl pointer-events-none" />
            <div className="relative rounded-[2rem] overflow-hidden shadow-2xl ring-1 ring-ink/8 lm-float">
              {heroAfter ? (
                <BeforeAfterSlider
                  before={sampleGolden}
                  after={heroAfter}
                  auto
                  afterLabel="A24 Still"
                  className="aspect-4/5"
                />
              ) : (
                <img src={sampleGolden} alt="" className="aspect-4/5 w-full object-cover" />
              )}
            </div>
            <div className="absolute -bottom-4 left-1/2 -translate-x-1/2 bg-paper shadow-lg rounded-full px-4 py-2 text-[12px] font-semibold text-ink-soft flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-violet animate-pulse" />
              Drag to compare
            </div>
          </motion.div>
        </div>
      </section>

      {/* ================= style marquee ================= */}
      <section id="styles" className="py-16 sm:py-24 scroll-mt-20">
        <motion.div {...fadeUp} className="max-w-7xl mx-auto px-4 sm:px-6 mb-10 flex items-end justify-between gap-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-violet mb-2">9 camera moods</p>
            <h2 className="font-display text-3xl sm:text-5xl font-semibold tracking-tight">
              One photo. Every era.
            </h2>
          </div>
          <Link to="/studio" className="hidden sm:inline-flex pill-base pill-primary px-5 py-2.5 text-sm shrink-0">
            Open the studio
          </Link>
        </motion.div>

        <div className="lm-marquee-pause overflow-hidden">
          <div className="lm-marquee flex gap-4 w-max pr-4">
            {[...CAMERA_STYLES, ...CAMERA_STYLES].map((style, i) => (
              <Link
                key={`${style.id}-${i}`}
                to={`/studio?style=${style.id}`}
                className="group relative w-52 sm:w-60 shrink-0 rounded-3xl overflow-hidden ring-1 ring-cloud shadow-md hover:shadow-xl hover:-translate-y-1.5 transition-all duration-300"
              >
                <div className="aspect-4/5 bg-mist">
                  <img
                    src={SAMPLES[i % SAMPLES.length]}
                    alt={style.name}
                    loading="lazy"
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                    style={{ filter: style.cardFilter }}
                    draggable={false}
                  />
                </div>
                <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-ink/85 via-ink/35 to-transparent p-4 pt-14">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="w-2.5 h-2.5 rounded-full" style={{ background: style.gradient }} />
                    <p className="text-paper font-display font-semibold text-lg leading-none">{style.name}</p>
                  </div>
                  <p className="text-paper/70 text-[12px] leading-snug">{style.tagline}</p>
                </div>
                {style.tier === 'premium' && (
                  <span className="absolute top-3 right-3 text-[10px] font-bold uppercase tracking-wide bg-violet text-paper px-2 py-1 rounded-full">
                    Pro
                  </span>
                )}
                {style.badge === 'trending' && (
                  <span className="absolute top-3 left-3 text-[10px] font-bold uppercase tracking-wide bg-amber-flash text-ink px-2 py-1 rounded-full">
                    🔥 Trending
                  </span>
                )}
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* ================= how it works ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 py-16 sm:py-24">
        <motion.h2 {...fadeUp} className="font-display text-3xl sm:text-5xl font-semibold tracking-tight text-center mb-14">
          Three steps to the shot.
        </motion.h2>
        <div className="grid sm:grid-cols-3 gap-5">
          {[
            {
              n: '01',
              title: 'Upload',
              body: 'Drop in any photo — a selfie, a night out, your dog. It never leaves your browser.',
              icon: '📤',
            },
            {
              n: '02',
              title: 'Choose a mood',
              body: 'Disposable flash, A24 still, Y2K digicam… pick the camera your photo deserved.',
              icon: '🎞️',
            },
            {
              n: '03',
              title: 'Develop & share',
              body: 'Fine-tune the grain and glow, compare before/after, export for TikTok and Reels.',
              icon: '✨',
            },
          ].map((step, i) => (
            <motion.div
              key={step.n}
              {...fadeUp}
              transition={{ ...fadeUp.transition, delay: i * 0.1 }}
              className="card p-7 hover:-translate-y-1 transition-transform duration-300"
            >
              <div className="flex items-center justify-between mb-5">
                <span className="text-3xl">{step.icon}</span>
                <span className="font-mono text-[12px] text-fog">{step.n}</span>
              </div>
              <h3 className="font-display text-xl font-semibold mb-2">{step.title}</h3>
              <p className="text-[14px] text-fog leading-relaxed">{step.body}</p>
            </motion.div>
          ))}
        </div>
      </section>

      {/* ================= viral captions ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 py-16 sm:py-20">
        <motion.div
          {...fadeUp}
          className="relative overflow-hidden rounded-[2.5rem] bg-[#0d0d12] text-paper px-6 sm:px-14 py-14 sm:py-18"
        >
          <div className="absolute -top-24 right-0 w-96 h-96 rounded-full bg-violet/25 blur-3xl pointer-events-none" />
          <div className="absolute -bottom-32 -left-16 w-96 h-96 rounded-full bg-amber-flash/15 blur-3xl pointer-events-none" />
          <div className="relative grid lg:grid-cols-2 gap-10 items-center">
            <div>
              <p className="text-xs font-bold uppercase tracking-widest text-[#a88bff] mb-3">Made to be posted</p>
              <h2 className="font-display text-3xl sm:text-4xl font-semibold tracking-tight mb-4">
                Captions included.
                <br />
                Clout not guaranteed*
              </h2>
              <p className="text-paper/60 text-[15px] leading-relaxed mb-8 max-w-md">
                Every export ships with a share card, an auto-written caption, and a link your
                friends can steal the style from. *It kind of is, though.
              </p>
              <Link to="/studio" className="pill-base bg-paper text-ink px-6 py-3 text-sm font-semibold hover:-translate-y-0.5 transition-transform">
                Make one now
              </Link>
            </div>
            <div className="space-y-3">
              {[
                'POV: your photo was shot on a $7,000 camera',
                'I turned my photo into an A24 movie still',
                'This was just a normal photo before LensMood',
              ].map((caption, i) => (
                <motion.div
                  key={caption}
                  initial={{ opacity: 0, x: 24 }}
                  whileInView={{ opacity: 1, x: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: 0.15 + i * 0.12 }}
                  className="bg-white/8 backdrop-blur border border-white/10 rounded-2xl px-5 py-4 text-[14px] flex items-center gap-3"
                >
                  <span className="text-lg shrink-0">💬</span>
                  <span className="text-paper/90">“{caption}”</span>
                </motion.div>
              ))}
            </div>
          </div>
        </motion.div>
      </section>

      {/* ================= featured mood ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 py-10">
        <motion.div {...fadeUp} className="card p-6 sm:p-8 flex flex-col sm:flex-row items-center gap-6">
          <div className="relative w-36 shrink-0 rounded-2xl overflow-hidden shadow-md">
            <img src={sampleNight} alt="" className="aspect-4/5 object-cover" style={{ filter: getStyle('a24-still')!.cardFilter }} />
            <span className="absolute top-2 left-2 text-[10px] font-bold uppercase tracking-wide bg-paper/90 text-ink px-2 py-0.5 rounded-full">
              ★ This week
            </span>
          </div>
          <div className="text-center sm:text-left">
            <p className="text-xs font-bold uppercase tracking-widest text-violet mb-1.5">Featured camera mood</p>
            <h3 className="font-display text-2xl font-semibold mb-1.5">A24 Movie Still</h3>
            <p className="text-[14px] text-fog leading-relaxed max-w-lg mb-4">
              Muted palette, cinematic shadows, soft highlights. The internet’s favorite mood this
              week — quiet, moody, devastating.
            </p>
            <Link to="/studio?style=a24-still" className="pill-base pill-primary px-5 py-2.5 text-sm">
              Shoot it
            </Link>
          </div>
        </motion.div>
      </section>

      {/* ================= pricing teaser ================= */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 py-16 sm:py-24 text-center">
        <motion.h2 {...fadeUp} className="font-display text-3xl sm:text-5xl font-semibold tracking-tight mb-4">
          Free to start. <span className="italic text-violet">$7</span> to go unlimited.
        </motion.h2>
        <motion.p {...fadeUp} className="text-fog max-w-xl mx-auto mb-8">
          5 free developments every month. Creators get unlimited exports, zero watermarks, and
          every premium camera pack.
        </motion.p>
        <motion.div {...fadeUp} className="flex justify-center gap-3">
          <Link to="/pricing" className="pill-base pill-violet px-7 py-3.5 text-base">
            See pricing
          </Link>
          <Link to="/studio" className="pill-base pill-ghost px-7 py-3.5 text-base">
            Try it free
          </Link>
        </motion.div>
      </section>
    </main>
  )
}
