import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Header from '../components/home/Header'
import SearchBar from '../components/home/SearchBar'
import CategoryChips, { CATEGORY_STYLES, type CategoryId } from '../components/home/CategoryChips'
import RecentProjectCard from '../components/home/RecentProjectCard'
import MoodSphere from '../components/home/MoodSphere'
import ToolCard from '../components/home/ToolCard'
import FloatingCTA from '../components/home/FloatingCTA'
import BottomNav from '../components/home/BottomNav'
import UploadModal from '../components/home/UploadModal'
import AccountSheet from '../components/home/AccountSheet'
import PhoneFrame from '../components/home/PhoneFrame'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import { IconChevronRight, IconSparkle } from '../components/icons'
import { loadImage, renderStyled } from '../lib/engine'
import { dailyRecipe, dailyStyle, isDailyClaimed, jitterParams } from '../lib/lab'
import { CAMERA_STYLES, encodeParams, getStyle, type CameraStyle } from '../lib/styles'
import { useStyleThumbs } from '../lib/useStyleThumbs'
import { useApp } from '../lib/store'
import sampleGolden from '../assets/sample-golden.jpg'
import sampleStreet from '../assets/sample-street.jpg'
import sampleNight from '../assets/sample-night.jpg'
import sampleTeal from '../assets/sample-teal.jpg'
import sampleSneaker from '../assets/sample-sneaker.jpg'

const THUMB_SOURCES = [sampleGolden, sampleStreet, sampleNight]

const TOOLS = [
  { title: 'Browse moods', sub: 'All nine looks', image: sampleTeal, to: '/studio' },
  { title: 'Video moods', sub: 'Restyle clips', image: sampleNight, to: '/studio', tag: 'Pro' },
  { title: 'Batch roll', sub: 'Up to 6 photos', image: sampleSneaker, to: '/studio?batch=1' },
  { title: 'Saved presets', sub: 'Your looks', image: sampleStreet, to: '/dashboard' },
]

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
  query,
  setQuery,
  category,
  setCategory,
}: {
  onAccount: () => void
  query: string
  setQuery: (v: string) => void
  category: CategoryId
  setCategory: (c: CategoryId) => void
}) {
  const { history, tried, streak } = useApp()
  const thumbs = useStyleThumbs(THUMB_SOURCES, 360)
  const navigate = useNavigate()
  const [spinSeed, setSpinSeed] = useState(0)
  const daily = dailyStyle()
  const dailyDone = isDailyClaimed()

  const openMood = (style: CameraStyle) => navigate(`/studio?style=${style.id}`)
  const onSpinEnd = (style: CameraStyle) => {
    // let the landing read for a beat, then develop with a surprise recipe
    setTimeout(() => {
      navigate(`/studio?style=${style.id}&p=${encodeParams(jitterParams(style))}`)
    }, 550)
  }

  /* hero demo: the golden sample developed as an A24 still, by the real engine */
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

  const moods = useMemo(() => {
    const inCategory =
      category === 'all'
        ? CAMERA_STYLES
        : CAMERA_STYLES.filter((s) => CATEGORY_STYLES[category].includes(s.id))
    const q = query.trim().toLowerCase()
    if (!q) return inCategory
    return inCategory.filter(
      (s) => s.name.toLowerCase().includes(q) || s.tagline.toLowerCase().includes(q),
    )
  }, [category, query])

  const showResume = history.length > 0 && category === 'all' && !query.trim()

  return (
    <div className="pb-[216px]">
      <Header onAccount={onAccount} />
      <SearchBar value={query} onChange={setQuery} />
      <CategoryChips active={category} onSelect={setCategory} />

      {/* the mood sphere */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.05 }} className="mt-5">
        <div className="flex items-center justify-between px-4 mb-1">
          <h2 className="text-[17px] font-bold tracking-[-0.01em]">Camera moods</h2>
          <button
            onClick={() => setSpinSeed((v) => v + 1)}
            className="flex items-center gap-1.5 text-[13px] font-semibold text-ink"
          >
            <IconSparkle size={14} className="text-signal" />
            Surprise me
          </button>
        </div>
        {moods.length > 0 ? (
          <MoodSphere
            styles={moods}
            thumbs={thumbs}
            fallbackImage={sampleGolden}
            tried={tried}
            dailyId={daily.id}
            onOpen={openMood}
            spinSeed={spinSeed}
            onSpinEnd={onSpinEnd}
          />
        ) : (
          <div className="mx-4 hm-tile px-4 py-5 text-[13px] text-ink-soft">
            Nothing matches “{query}” here yet.
          </div>
        )}
      </motion.section>

      {/* today's stock — free daily develop, gone at midnight */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.08 }} className="mt-5 px-4">
        <div className="bg-vf rounded-[20px] p-4 flex items-center gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2.5">
              <p className="font-mono text-[10px] font-semibold tracking-[0.14em] uppercase text-signal">
                Today’s stock — gone at midnight
              </p>
              {streak.count >= 1 && (
                <p className="flex items-center gap-1 font-mono text-[10px] tracking-[0.1em] uppercase text-vf-chrome tabular-nums">
                  <span className="w-1.5 h-1.5 rounded-full bg-signal inline-block" />
                  Day {String(streak.count).padStart(2, '0')} on roll
                </p>
              )}
            </div>
            <p className="text-white font-bold text-[15px] mt-1 leading-tight truncate">{daily.name}</p>
            <p className="font-mono text-[10px] tracking-[0.06em] text-vf-chrome mt-0.5 tabular-nums truncate">
              INT {String(dailyRecipe().intensity).padStart(2, '0')} · GRN{' '}
              {String(dailyRecipe().grain).padStart(2, '0')} · WRM{' '}
              {String(dailyRecipe().warmth).padStart(2, '0')}
            </p>
          </div>
          <button
            onClick={() =>
              navigate(`/studio?style=${daily.id}&p=${encodeParams(dailyRecipe())}${dailyDone ? '' : '&daily=1'}`)
            }
            className={`hm-press shrink-0 h-10 px-4 rounded-full text-[13px] font-semibold ${
              dailyDone ? 'bg-white/12 text-white/80' : 'bg-white text-ink'
            }`}
          >
            {dailyDone ? 'Shot today' : 'Shoot free'}
          </button>
        </div>
      </motion.section>

      {/* keep creating — resume shelf (only when there's history) */}
      {showResume && (
        <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.08 }} className="mt-6">
          <div className="flex items-center justify-between px-4 mb-2.5">
            <h2 className="text-[17px] font-bold tracking-[-0.01em]">Keep creating</h2>
            <Link to="/dashboard" className="flex items-center gap-0.5 text-[13px] font-semibold text-ink-soft">
              See all
              <IconChevronRight size={12} />
            </Link>
          </div>
          <div className="flex gap-3 overflow-x-auto no-scrollbar snap-x px-4 pb-1">
            {history.slice(0, 6).map((h) => (
              <RecentProjectCard
                key={h.id}
                to={`/studio?style=${h.styleId}`}
                image={h.thumb}
                label={h.styleName}
                sublabel="Resume"
              />
            ))}
          </div>
        </motion.section>
      )}

      {/* start with a tool */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.1 }} className="mt-6 px-4">
        <div className="flex items-center justify-between mb-2.5">
          <h2 className="text-[17px] font-bold tracking-[-0.01em]">Start with a tool</h2>
        </div>
        <div className="grid grid-cols-2 gap-3">
          {TOOLS.map((t) => (
            <ToolCard key={t.title} {...t} />
          ))}
        </div>
      </motion.section>

      {/* transform a photo */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.15 }} className="mt-6 px-4">
        <div className="flex items-center justify-between mb-2.5">
          <h2 className="text-[17px] font-bold tracking-[-0.01em]">Transform a photo</h2>
          <Link to="/studio?style=film-noir" className="flex items-center gap-0.5 text-[13px] font-semibold text-ink-soft">
            Open studio
            <IconChevronRight size={12} />
          </Link>
        </div>
        <div className="hm-card p-2">
          <div className="rounded-[14px] overflow-hidden">
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
          <p className="px-2.5 pt-2.5 pb-1.5 text-[11px] text-ink-soft">
            Drag the line — the LensMood engine developing Film Noir, live on-device.
          </p>
        </div>
      </motion.section>
    </div>
  )
}

export default function Home() {
  const isDesktop = useIsDesktop()
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState<CategoryId>('all')
  const [uploadOpen, setUploadOpen] = useState(false)
  const [accountOpen, setAccountOpen] = useState(false)

  const content = (
    <HomeContent
      onAccount={() => setAccountOpen(true)}
      query={query}
      setQuery={setQuery}
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
            <p className="label-mono mb-4">The app</p>
            <h1 className="type-display text-5xl mb-5">The studio in your pocket.</h1>
            <p className="text-[15px] leading-[1.6] text-ink-soft mb-8">
              This is LensMood’s home screen, running live — search the moods, filter the
              shelves, open the upload sheet. Everything you tap here is the real product.
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
                <FloatingCTA variant="embedded" onClick={() => setUploadOpen(true)} />
                <BottomNav variant="embedded" onAccount={() => setAccountOpen(true)} />
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
      <FloatingCTA variant="fixed" onClick={() => setUploadOpen(true)} />
      <UploadModal open={uploadOpen} onClose={() => setUploadOpen(false)} />
      <AccountSheet open={accountOpen} onClose={() => setAccountOpen(false)} />
    </main>
  )
}
