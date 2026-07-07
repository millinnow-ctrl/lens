import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Header from '../components/home/Header'
import CategoryChips, { CATEGORY_STYLES, type CategoryId } from '../components/home/CategoryChips'
import RecentProjectCard from '../components/home/RecentProjectCard'
import MoodSphere from '../components/home/MoodSphere'
import LiveHero from '../components/home/LiveHero'
import ToolCard from '../components/home/ToolCard'
import BottomNav from '../components/home/BottomNav'
import UploadModal from '../components/home/UploadModal'
import AccountSheet from '../components/home/AccountSheet'
import PhoneFrame from '../components/home/PhoneFrame'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import { ApertureMark } from '../components/Logo'
import { IconCheck, IconChevronRight, IconClose } from '../components/icons'
import { sectionStagger, sectionChild } from '../lib/motion'
import { loadImage, renderStyled } from '../lib/engine'
import { dailyRecipe, dailyStyle, isDailyClaimed, jitterParams } from '../lib/lab'
import { CAMERA_STYLES, encodeParams, getStyle, type CameraStyle } from '../lib/styles'
import { useApp } from '../lib/store'
import { STYLE_ART } from '../lib/styleArt'
import sampleGolden from '../assets/sample-golden.jpg'
import sampleFriends from '../assets/sample-friends.jpg'
import sampleDog from '../assets/sample-dog.jpg'
import samplePrints from '../assets/sample-prints.jpg'
import sampleHandprint from '../assets/sample-handprint.jpg'


/* collection milestones — celebrated once each, positive framing only */
const MILESTONE_KEY = 'lensmood.milestone.v1'
const MILESTONES = [6, 12, 18] as const
const MILESTONE_COPY: Record<number, string> = {
  6: '6 of 18 looks shot — a third of the case.',
  12: '12 of 18 — the case is filling up.',
  18: '18 of 18 — full case. Every look, shot.',
}

const readMilestone = (): number => {
  try {
    return Number(localStorage.getItem(MILESTONE_KEY) ?? 0) || 0
  } catch {
    return 0
  }
}

const writeMilestone = (m: number) => {
  try {
    if (m > readMilestone()) localStorage.setItem(MILESTONE_KEY, String(m))
  } catch {
    /* storage unavailable */
  }
}

const timeAgo = (t: number) => {
  const m = Math.max(1, Math.round((Date.now() - t) / 60000))
  if (m < 60) return `Edited ${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `Edited ${h}h ago`
  const d = Math.round(h / 24)
  return `Edited ${d}d ago`
}

function useIsDesktop() {
  const [desktop, setDesktop] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(min-width: 768px)').matches,
  )
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 768px)')
    const fn = (e: MediaQueryListEvent) => setDesktop(e.matches)
    mq.addEventListener('change', fn)
    return () => mq.removeEventListener('change', fn)
  }, [])
  return desktop
}

/* section reveal choreography — a container staggers its children top-down;
   each section rises softly into place. Presets live in ../lib/motion and
   collapse to opacity-only under prefers-reduced-motion. */
const staggerVariants = sectionStagger()
const childVariants = sectionChild()

function HomeContent({
  onAccount,
  onUpload,
  category,
  setCategory,
}: {
  onAccount: () => void
  onUpload: () => void
  category: CategoryId
  setCategory: (c: CategoryId) => void
}) {
  const { history, tried, streak } = useApp()
  const navigate = useNavigate()
  const [spinSeed, setSpinSeed] = useState(0)
  const daily = dailyStyle()
  const dailyDone = isDailyClaimed()

  /* one-time milestone strip — highest newly-crossed milestone, shown once */
  const [milestone, setMilestone] = useState<number | null>(() => {
    const last = readMilestone()
    return [...MILESTONES].reverse().find((m) => tried.length >= m && m > last) ?? null
  })
  useEffect(() => {
    if (milestone == null) return
    // persist on unmount too, so the strip shows at most once per milestone
    return () => writeMilestone(milestone)
  }, [milestone])
  const dismissMilestone = () => {
    if (milestone != null) writeMilestone(milestone)
    setMilestone(null)
  }

  const openMood = (style: CameraStyle) => navigate(`/studio?style=${style.id}`)
  const onSpinEnd = (style: CameraStyle) => {
    // let the landing read for a beat, then develop with a surprise recipe
    setTimeout(() => {
      navigate(`/studio?style=${style.id}&p=${encodeParams(jitterParams(style))}`)
    }, 550)
  }

  /* demo strip: the golden sample developed as Film Noir, by the real engine */
  const [demoAfter, setDemoAfter] = useState<string | null>(null)
  useEffect(() => {
    let cancelled = false
    loadImage(sampleGolden).then((img) => {
      if (cancelled) return
      const noir = getStyle('film-noir')!
      const canvas = renderStyled(img, noir, { ...noir.defaults, intensity: 100 }, { maxSize: 720 })
      setDemoAfter(canvas.toDataURL('image/jpeg', 0.85))
    })
    return () => {
      cancelled = true
    }
  }, [])

  const moods = useMemo(
    () =>
      category === 'all'
        ? CAMERA_STYLES
        : CAMERA_STYLES.filter((s) => CATEGORY_STYLES[category].includes(s.id)),
    [category],
  )

  const recents = history.slice(0, 4)

  return (
    <motion.div
      className="pb-[112px]"
      variants={staggerVariants}
      initial="initial"
      animate="animate"
    >
      <Header onAccount={onAccount} />

      {/* hero — a lookbook reel of ambient clips, each shot on a different
          lens, rotating under the headline so the first view is alive */}
      <motion.section variants={childVariants} className="mt-1 px-5">
        <LiveHero onUpload={onUpload} />
      </motion.section>

      {/* the case, in motion — a slow ticker of all 18 cameras filing past.
          Tap a name to open that look; press-and-hold pauses the roll. */}
      <motion.section variants={childVariants} className="mt-5 border-y border-hairline">
        <div className="lm-ticker py-2.5" aria-label="All 18 cameras">
          {[0, 1].map((track) => (
            <div key={track} className="lm-ticker-track" aria-hidden={track === 1}>
              {CAMERA_STYLES.map((s) => (
                <button
                  key={`${track}-${s.id}`}
                  tabIndex={track === 1 ? -1 : 0}
                  onClick={() => openMood(s)}
                  className="flex items-center shrink-0 font-mono font-semibold text-[10px] tracking-[0.14em] uppercase text-ink-soft whitespace-nowrap"
                >
                  <span className="px-3">{s.name}</span>
                  <span className="w-1 h-1 rounded-full bg-signal/60" aria-hidden />
                </button>
              ))}
            </div>
          ))}
        </div>
      </motion.section>

      {/* camera styles — the deck */}
      <motion.section variants={childVariants} className="mt-8">
        <p className="px-5 font-mono font-semibold text-[10px] tracking-[0.18em] uppercase text-fog mb-1">
          The case · 18 cameras
        </p>
        <div className="flex items-center justify-between px-5">
          <h2 className="type-display text-[22px]">Explore looks</h2>
          <span className="flex-1 mx-3 h-px bg-ink/10 self-center" aria-hidden />
          <button
            onClick={() => setSpinSeed((s) => s + 1)}
            className="hm-pill hm-press h-8 px-3.5 text-[13px] font-semibold text-ink-soft"
          >
            Spin the case
          </button>
        </div>
        <CategoryChips active={category} onSelect={setCategory} />
        {moods.length > 0 ? (
          <MoodSphere
            styles={moods}
            thumbs={STYLE_ART}
            fallbackImage={sampleGolden}
            tried={tried}
            dailyId={daily.id}
            onOpen={openMood}
            spinSeed={spinSeed}
            onSpinEnd={onSpinEnd}
          />
        ) : (
          <div className="mx-5 mt-4 hm-tile px-5 py-5 text-[13px] text-ink-soft">Nothing here yet.</div>
        )}
      </motion.section>

      {/* milestone moment — true, once per milestone, dismissible */}
      {milestone != null && (
        <motion.section variants={childVariants} className="mt-8 px-5">
          <div className="hm-pill flex items-center gap-2.5 rounded-full pl-4 pr-2 py-2.5">
            <IconCheck size={14} className="shrink-0 text-violet" />
            <p className="flex-1 min-w-0 truncate text-[12.5px] font-semibold text-ink-soft">
              {MILESTONE_COPY[milestone]}
            </p>
            <button
              onClick={dismissMilestone}
              aria-label="Dismiss milestone"
              className="hit hm-press shrink-0 flex items-center justify-center w-7 h-7 rounded-full text-fog"
            >
              <IconClose size={13} />
            </button>
          </div>
        </motion.section>
      )}

      {/* recent edits */}
      <motion.section variants={childVariants} className="mt-8 px-5">
        <p className="font-mono font-semibold text-[10px] tracking-[0.18em] uppercase text-fog mb-1">Recent develops</p>
        <div className="flex items-center justify-between mb-3">
          <h2 className="type-display text-[21px]">Your roll</h2>
          <span className="flex-1 mx-3 h-px bg-ink/10 self-center" aria-hidden />
          <Link to="/dashboard" className="flex items-center gap-0.5 text-[13.5px] font-semibold text-ink-soft">
            See all
            <IconChevronRight size={13} />
          </Link>
        </div>
        <div className="grid grid-cols-2 gap-x-3 gap-y-4">
          {recents.length > 0 ? (
            recents.map((h, i) => (
              <RecentProjectCard
                key={h.id}
                index={i}
                to={`/studio?style=${h.styleId}`}
                image={h.thumb}
                label={h.styleName}
                sublabel={timeAgo(h.date)}
              />
            ))
          ) : (
            <>
              <RecentProjectCard
                index={0}
                to="/studio?style=iphone-flash"
                image={sampleFriends}
                label="iPhone Flash"
                sublabel="Try it"
                filter={getStyle('iphone-flash')?.cardFilter}
                chip="Sample"
              />
              <RecentProjectCard
                index={1}
                to="/studio?style=a24-still"
                image={sampleDog}
                label="A24 Still"
                sublabel="Try it"
                filter={getStyle('a24-still')?.cardFilter}
                chip="Sample"
              />
            </>
          )}
        </div>
      </motion.section>

      {/* today's free look — a warm clay "darkroom slip" with the day's frame
          pinned to it as a little instant print (tactile, physical, on-brand) */}
      <motion.section variants={childVariants} className="mt-8 px-5">
        <div className="relative overflow-hidden rounded-[22px] bg-gradient-to-br from-clay to-clay-deep shadow-e2 [box-shadow:var(--shadow-e2)]">
          <div className="texture-film absolute inset-0 opacity-40 mix-blend-overlay pointer-events-none" aria-hidden />
          {/* warm rim-light catching the top edge */}
          <div className="absolute inset-x-0 top-0 h-px bg-white/25" aria-hidden />
          <div className="relative flex items-center gap-4 p-4 pr-3.5 min-h-[112px]">
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="inline-flex items-center gap-1 text-[10.5px] font-bold tracking-[0.12em] uppercase text-white/90">
                  <span className="w-1.5 h-1.5 rounded-full bg-white/90 animate-none" aria-hidden />
                  Free today
                </span>
                {streak.count >= 1 && (
                  <span className="text-[10.5px] font-semibold text-white/60 tabular-nums">· Day {streak.count}</span>
                )}
              </div>
              <p className="type-display text-white text-[22px] mt-1 leading-tight truncate">{daily.name}</p>
              <p className="text-[11.5px] text-white/70 mt-0.5 tabular-nums truncate">
                Ends at midnight · {tried.length}/{CAMERA_STYLES.length} in the case
              </p>
              <button
                onClick={() =>
                  navigate(`/studio?style=${daily.id}&p=${encodeParams(dailyRecipe())}${dailyDone ? '' : '&daily=1'}`)
                }
                className={`hm-press mt-3 inline-flex items-center gap-1.5 h-9 px-4 rounded-full text-[13px] font-semibold border ${
                  dailyDone
                    ? 'bg-white/10 border-white/20 text-white/85'
                    : 'bg-[rgb(28_12_8/0.3)] border-white/35 text-white backdrop-blur-[10px] shadow-[inset_0_1px_0_rgb(255_255_255/0.35),0_2px_8px_rgb(60_20_10/0.35)]'
                }`}
              >
                {dailyDone ? 'Shot today' : 'Shoot it'}
              </button>
            </div>
            {/* the day's frame as a pinned instant print, leaning on the slip */}
            <div className="shrink-0 -rotate-3 rounded-[7px] bg-[#fdfbf7] p-1.5 pb-3.5 shadow-[0_10px_22px_-6px_rgb(60_20_10/0.5)] [box-shadow:0_10px_22px_-6px_rgb(60_20_10/0.5),inset_0_1px_0_rgb(255_255_255/0.8)]">
              <img
                src={STYLE_ART[daily.id] ?? sampleGolden}
                alt=""
                draggable={false}
                className="w-[68px] aspect-4/5 object-cover rounded-[3px]"
              />
            </div>
          </div>
        </div>
      </motion.section>

      {/* tools — one wide, two small; shapes vary on purpose */}
      <motion.section variants={childVariants} className="mt-8 px-5">
        <p className="font-mono font-semibold text-[10px] tracking-[0.18em] uppercase text-fog mb-1">The darkroom</p>
        <div className="flex items-center mb-3">
          <h2 className="type-display text-[21px]">Tools</h2>
          <span className="flex-1 ml-3 h-px bg-ink/10 self-center" aria-hidden />
        </div>
        <ToolCard
          to="/studio"
          title="Video"
          sub="Restyle a clip, frame by frame"
          image={STYLE_ART['camcorder-90s']}
          tag="Pro"
          ratio="aspect-[21/9]"
          film
        />
        {/* uneven two-up — different widths, the narrow one set lower */}
        <div className="grid grid-cols-[1.28fr_1fr] gap-3 mt-3 items-start">
          <ToolCard to="/studio?batch=1" title="Batch roll" sub="Up to 6 photos" image={samplePrints} />
          <div className="mt-3">
            <ToolCard to="/dashboard" title="Presets" sub="Saved looks" image={sampleHandprint} ratio="aspect-[16/11.5]" />
          </div>
        </div>
      </motion.section>

      {/* before & after */}
      <motion.section variants={childVariants} className="mt-8 px-5">
        <p className="font-mono font-semibold text-[10px] tracking-[0.18em] uppercase text-fog mb-1">LM engine · live</p>
        <div className="flex items-center justify-between mb-3">
          <h2 className="type-display text-[21px]">Before & after</h2>
          <span className="flex-1 mx-3 h-px bg-ink/10 self-center" aria-hidden />
          <Link
            to="/studio?style=film-noir"
            className="flex items-center gap-0.5 text-[13.5px] font-semibold text-ink-soft"
          >
            Open studio
            <IconChevronRight size={13} />
          </Link>
        </div>
        <div className="rounded-[22px] overflow-hidden">
          {demoAfter ? (
            <BeforeAfterSlider
              before={sampleGolden}
              after={demoAfter}
              auto
              afterLabel="Film Noir"
              variant="soft"
              className="aspect-[4/3]"
            />
          ) : (
            <img src={sampleGolden} alt="" className="aspect-[4/3] w-full object-cover" />
          )}
        </div>
        <p className="px-1 pt-2.5 text-[12px] text-fog">
          Film Noir — drag to compare. Rendered on your phone, nothing uploaded.
        </p>
      </motion.section>

      {/* colophon — the maker's mark at the end of the roll (doubles as a
          visible build stamp so you always know which cut you're holding) */}
      <motion.section variants={childVariants} className="mt-10 px-5 flex flex-col items-center gap-1.5">
        <ApertureMark className="w-7 h-7 opacity-80" />
        <p className="font-mono font-semibold text-[9.5px] tracking-[0.2em] uppercase text-fog tabular-nums text-center">
          LensMood · Cut R28 “Deep Color”
        </p>
        <p className="font-mono font-semibold text-[9.5px] tracking-[0.2em] uppercase text-fog/80 text-center">
          Made in the darkroom
        </p>
      </motion.section>
    </motion.div>
  )
}

export default function Home() {
  const isDesktop = useIsDesktop()
  const [category, setCategory] = useState<CategoryId>('all')
  const [uploadOpen, setUploadOpen] = useState(false)
  const [accountOpen, setAccountOpen] = useState(false)

  const content = (
    <HomeContent
      onAccount={() => setAccountOpen(true)}
      onUpload={() => setUploadOpen(true)}
      category={category}
      setCategory={setCategory}
    />
  )

  if (isDesktop) {
    return (
      <main className="hm-canvas min-h-dvh">
        <div className="max-w-6xl mx-auto grid xl:grid-cols-[1fr_auto] items-center gap-8 px-6">
          {/* demo-page framing so the phone never floats in a void */}
          <div className="hidden xl:block max-w-md">
            <p className="text-[12px] font-bold tracking-[0.12em] uppercase grad-text mb-4">The app</p>
            <h1 className="type-display text-5xl mb-5">The studio in your pocket.</h1>
            <p className="text-[15px] leading-[1.6] text-ink-soft mb-8">
              This is LensMood’s home screen, running live — swipe the styles, open the upload
              sheet, develop a photo. Everything you tap here is the real product.
            </p>
            <div className="flex gap-3">
              <Link to="/studio" className="btn btn-primary btn-lg">
                Open the studio
              </Link>
              <Link to="/pricing" className="btn btn-outline btn-lg">
                Pricing
              </Link>
            </div>
          </div>
          <PhoneFrame
            chrome={(container) => (
              <>
                <BottomNav
                  variant="embedded"
                  onAccount={() => setAccountOpen(true)}
                  onCreate={() => setUploadOpen(true)}
                />
                <UploadModal open={uploadOpen} onClose={() => setUploadOpen(false)} container={container} />
                <AccountSheet open={accountOpen} onClose={() => setAccountOpen(false)} container={container} />
              </>
            )}
          >
            {content}
          </PhoneFrame>
        </div>
      </main>
    )
  }

  return (
    <main className="hm-canvas min-h-dvh">
      {content}
      <UploadModal open={uploadOpen} onClose={() => setUploadOpen(false)} />
      <AccountSheet open={accountOpen} onClose={() => setAccountOpen(false)} />
    </main>
  )
}
