import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import Header from '../components/home/Header'
import SearchBar from '../components/home/SearchBar'
import CategoryChips, { CATEGORY_STYLES, type CategoryId } from '../components/home/CategoryChips'
import RecentProjectCard from '../components/home/RecentProjectCard'
import ToolCard from '../components/home/ToolCard'
import FloatingCTA from '../components/home/FloatingCTA'
import BottomNav from '../components/home/BottomNav'
import UploadModal from '../components/home/UploadModal'
import AccountSheet from '../components/home/AccountSheet'
import PhoneFrame from '../components/home/PhoneFrame'
import BeforeAfterSlider from '../components/BeforeAfterSlider'
import { IconChevronRight } from '../components/icons'
import { loadImage, renderStyled } from '../lib/engine'
import { CAMERA_STYLES, getStyle } from '../lib/styles'
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
  const { history } = useApp()
  const thumbs = useStyleThumbs(THUMB_SOURCES, 360)

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

      {/* keep creating */}
      <motion.section {...sectionIn} transition={{ duration: 0.3, delay: 0.05 }} className="mt-6">
        <div className="flex items-center justify-between px-4 mb-2.5">
          <h2 className="text-[17px] font-bold tracking-[-0.01em]">
            {showResume ? 'Keep creating' : 'Camera moods'}
          </h2>
          <Link to="/studio" className="flex items-center gap-0.5 text-[13px] font-semibold text-ink-soft">
            See all
            <IconChevronRight size={12} />
          </Link>
        </div>
        <div className="flex gap-3 overflow-x-auto no-scrollbar snap-x px-4 pb-1">
          {showResume &&
            history.slice(0, 3).map((h) => (
              <RecentProjectCard
                key={h.id}
                to={`/studio?style=${h.styleId}`}
                image={h.thumb}
                label={h.styleName}
                sublabel="Resume"
              />
            ))}
          {moods.map((s) => (
            <RecentProjectCard
              key={s.id}
              to={`/studio?style=${s.id}`}
              image={thumbs[s.id] ?? sampleGolden}
              filter={thumbs[s.id] ? undefined : s.cardFilter}
              label={s.name}
              sublabel={s.tier === 'premium' ? 'Pro' : 'Free'}
            />
          ))}
          {moods.length === 0 && (
            <div className="hm-tile px-4 py-5 text-[13px] text-ink-soft">
              Nothing matches “{query}” here yet.
            </div>
          )}
        </div>
      </motion.section>

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
