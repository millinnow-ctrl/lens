import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Header from '../components/home/Header'
import CategoryChips, { CATEGORY_STYLES, type CategoryId } from '../components/home/CategoryChips'
import RecentProjectCard from '../components/home/RecentProjectCard'
import MoodSphere from '../components/home/MoodSphere'
import ToolCard from '../components/home/ToolCard'
import BottomNav from '../components/home/BottomNav'
import UploadModal from '../components/home/UploadModal'
import AccountSheet from '../components/home/AccountSheet'
import PhoneFrame from '../components/home/PhoneFrame'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import { IconCheck, IconChevronRight, IconClose, IconImagePlus, IconUpload } from '../components/icons'
import { loadImage, renderStyled } from '../lib/engine'
import { dailyRecipe, dailyStyle, isDailyClaimed, jitterParams } from '../lib/lab'
import { CAMERA_STYLES, encodeParams, getStyle, type CameraStyle } from '../lib/styles'
import { useApp } from '../lib/store'
import sampleGolden from '../assets/sample-golden.jpg'
import sampleFriends from '../assets/sample-friends.jpg'
import sampleDog from '../assets/sample-dog.jpg'
import samplePrints from '../assets/sample-prints.jpg'
import sampleHandprint from '../assets/sample-handprint.jpg'
import artDisposable from '../assets/style-disposable.jpg'
import artIphoneFlash from '../assets/style-iphone-flash.jpg'
import artCamcorder from '../assets/style-camcorder-90s.jpg'
import artLeica from '../assets/style-leica-street.jpg'
import artGq from '../assets/style-gq-editorial.jpg'
import artA24 from '../assets/style-a24-still.jpg'
import artNoir from '../assets/style-film-noir.jpg'
import artY2k from '../assets/style-y2k-digicam.jpg'
import artPolaroid from '../assets/style-polaroid.jpg'
import artSuper8 from '../assets/style-super-8.jpg'
import artLomo from '../assets/style-lomo.jpg'
import artKodachrome from '../assets/style-kodachrome.jpg'
import artSecurityCam from '../assets/style-security-cam.jpg'
import artBlockbuster from '../assets/style-blockbuster.jpg'
import artPastel from '../assets/style-pastel-cinema.jpg'
import artTokyoNeon from '../assets/style-tokyo-neon.jpg'
import artPhotobooth from '../assets/style-photobooth.jpg'
import artTintype from '../assets/style-tintype.jpg'

/** tall portrait artwork for the style deck — one signature frame per look */
const STYLE_ART: Record<string, string> = {
  disposable: artDisposable,
  'iphone-flash': artIphoneFlash,
  'camcorder-90s': artCamcorder,
  'leica-street': artLeica,
  'gq-editorial': artGq,
  'a24-still': artA24,
  'film-noir': artNoir,
  'y2k-digicam': artY2k,
  polaroid: artPolaroid,
  'super-8': artSuper8,
  lomo: artLomo,
  kodachrome: artKodachrome,
  'security-cam': artSecurityCam,
  blockbuster: artBlockbuster,
  'pastel-cinema': artPastel,
  'tokyo-neon': artTokyoNeon,
  photobooth: artPhotobooth,
  tintype: artTintype,
}

const TOOLS = [
  { title: 'All looks', sub: `${CAMERA_STYLES.length} styles`, image: artLomo, to: '/studio' },
  { title: 'Video', sub: 'Restyle clips', image: artCamcorder, to: '/studio', tag: 'Pro' },
  { title: 'Batch roll', sub: 'Up to 6 photos', image: samplePrints, to: '/studio?batch=1' },
  { title: 'Presets', sub: 'Saved looks', image: sampleHandprint, to: '/dashboard' },
]

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

const sectionIn = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
}

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
    <div className="pb-[112px]">
      <Header onAccount={onAccount} />

      {/* start with a photo — the hero drop zone */}
      <motion.section {...sectionIn} transition={{ duration: 0.3 }} className="mt-2 px-5">
        <div className="hm-drop overflow-hidden">
          <button onClick={onUpload} className="relative z-10 w-full flex flex-col items-center px-6 pt-7 pb-7">
            <IconImagePlus size={44} strokeWidth={1.5} className="text-violet" />
            <h1 className="type-display text-[26px] mt-3.5">Start with a photo</h1>
            <p className="text-[14px] text-ink-soft mt-1.5">Drop in a photo and choose a camera mood.</p>
            <span className="glow-ring mt-5 inline-block">
              <span className="btn btn-hero btn-lg gap-2.5 border-0">
                <IconUpload size={17} />
                Upload photo
              </span>
            </span>
          </button>
        </div>
      </motion.section>

      {/* camera styles — the deck */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.05 }} className="mt-7">
        <div className="flex items-center justify-between px-5">
          <h2 className="text-[19px] font-bold tracking-[-0.02em]">Camera styles</h2>
          <button
            onClick={() => setSpinSeed((s) => s + 1)}
            className="hm-pill hm-press h-8 px-3.5 text-[13px] font-semibold text-ink-soft"
          >
            Surprise me
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
        <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.07 }} className="mt-7 px-5">
          <div className="hm-pill flex items-center gap-2.5 rounded-full pl-4 pr-2 py-2.5">
            <IconCheck size={14} className="shrink-0 text-violet" />
            <p className="flex-1 min-w-0 truncate text-[12.5px] font-semibold text-ink-soft">
              {MILESTONE_COPY[milestone]}
            </p>
            <button
              onClick={dismissMilestone}
              aria-label="Dismiss milestone"
              className="hm-press shrink-0 flex items-center justify-center w-7 h-7 rounded-full text-fog"
            >
              <IconClose size={13} />
            </button>
          </div>
        </motion.section>
      )}

      {/* recent edits */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.08 }} className="mt-7 px-5">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-[19px] font-bold tracking-[-0.02em]">Recent edits</h2>
          <Link to="/dashboard" className="flex items-center gap-0.5 text-[13.5px] font-semibold text-ink-soft">
            See all
            <IconChevronRight size={13} />
          </Link>
        </div>
        <div className="grid grid-cols-2 gap-3">
          {recents.length > 0 ? (
            recents.map((h) => (
              <RecentProjectCard
                key={h.id}
                to={`/studio?style=${h.styleId}`}
                image={h.thumb}
                label={h.styleName}
                sublabel={timeAgo(h.date)}
              />
            ))
          ) : (
            <>
              <RecentProjectCard
                to="/studio?style=iphone-flash"
                image={sampleFriends}
                label="iPhone Flash"
                sublabel="Try this look"
                filter={getStyle('iphone-flash')?.cardFilter}
                chip="Example"
              />
              <div className="-rotate-[0.6deg]">
                <RecentProjectCard
                  to="/studio?style=a24-still"
                  image={sampleDog}
                  label="A24 Still"
                  sublabel="Try this look"
                  filter={getStyle('a24-still')?.cardFilter}
                  chip="Example"
                />
              </div>
            </>
          )}
        </div>
      </motion.section>

      {/* today's free look */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.1 }} className="mt-7 px-5">
        <div className="relative overflow-hidden bg-vf rounded-[24px] p-4 flex items-center gap-3">
          <div
            className="absolute -top-10 -right-8 w-40 h-40 rounded-full pointer-events-none"
            style={{
              background:
                'radial-gradient(closest-side, rgb(139 92 246 / 0.4), rgb(236 72 153 / 0.16), transparent)',
              filter: 'blur(10px)',
            }}
            aria-hidden
          />
          <div className="relative flex-1 min-w-0">
            <div className="flex items-center gap-2.5">
              <p className="text-[11px] font-bold tracking-[0.1em] uppercase grad-text">Free look of the day</p>
              {streak.count >= 1 && (
                <p className="text-[10.5px] font-semibold text-vf-chrome tabular-nums">
                  Day {streak.count} streak
                </p>
              )}
            </div>
            <p className="text-white font-bold text-[16px] mt-1 leading-tight truncate">{daily.name}</p>
            <p className="text-[11px] text-vf-chrome mt-0.5 tabular-nums truncate">
              The case: {tried.length}/{CAMERA_STYLES.length}
            </p>
            <p className="text-[12px] text-vf-chrome mt-0.5 truncate">Ends at midnight</p>
          </div>
          <button
            onClick={() =>
              navigate(`/studio?style=${daily.id}&p=${encodeParams(dailyRecipe())}${dailyDone ? '' : '&daily=1'}`)
            }
            className={`hm-press relative shrink-0 h-10 px-5 rounded-full text-[13.5px] font-semibold ${
              dailyDone ? 'bg-white/12 text-white/80' : 'bg-white text-ink'
            }`}
          >
            {dailyDone ? 'Shot today' : 'Shoot free'}
          </button>
        </div>
      </motion.section>

      {/* tools */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.12 }} className="mt-7 px-5">
        <h2 className="text-[19px] font-bold tracking-[-0.02em] mb-3">Tools</h2>
        <div className="grid grid-cols-2 gap-3">
          {TOOLS.map((t) => (
            <ToolCard key={t.title} {...t} />
          ))}
        </div>
      </motion.section>

      {/* before & after */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.15 }} className="mt-7 px-5">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-[19px] font-bold tracking-[-0.02em]">Before & after</h2>
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
    </div>
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
