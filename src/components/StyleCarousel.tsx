import { motion } from 'framer-motion'
import { CAMERA_STYLES, type CameraStyle } from '../lib/styles'
import { useApp } from '../lib/store'

interface Props {
  /** image shown inside each card (the user's photo, or a sample) */
  previewSrc: string
  selectedId: string | null
  onSelect: (style: CameraStyle) => void
  showFavorites?: boolean
}

function Badge({ badge, tier }: { badge?: CameraStyle['badge']; tier: CameraStyle['tier'] }) {
  if (badge === 'trending')
    return (
      <span className="text-[10px] font-bold uppercase tracking-wide bg-amber-flash/90 text-ink px-2 py-0.5 rounded-full">
        🔥 Trending
      </span>
    )
  if (badge === 'featured')
    return (
      <span className="text-[10px] font-bold uppercase tracking-wide bg-paper/90 text-ink px-2 py-0.5 rounded-full">
        ★ This week
      </span>
    )
  if (tier === 'premium')
    return (
      <span className="text-[10px] font-bold uppercase tracking-wide bg-violet/90 text-paper px-2 py-0.5 rounded-full">
        Pro
      </span>
    )
  return null
}

export default function StyleCarousel({ previewSrc, selectedId, onSelect, showFavorites = true }: Props) {
  const { favorites, toggleFavorite } = useApp()

  return (
    <div className="flex gap-3 overflow-x-auto no-scrollbar snap-x snap-mandatory -mx-1 px-1 py-2">
      {CAMERA_STYLES.map((style) => {
        const selected = style.id === selectedId
        const fav = favorites.includes(style.id)
        return (
          <motion.button
            key={style.id}
            onClick={() => onSelect(style)}
            whileHover={{ y: -3 }}
            whileTap={{ scale: 0.97 }}
            className={`relative shrink-0 w-32 sm:w-36 snap-start rounded-2xl overflow-hidden text-left transition-shadow duration-300 ${
              selected ? 'ring-3 ring-violet shadow-[var(--shadow-glow)]' : 'ring-1 ring-cloud shadow-sm hover:shadow-md'
            }`}
            aria-pressed={selected}
          >
            <div className="relative aspect-4/5 bg-mist">
              <img
                src={previewSrc}
                alt=""
                loading="lazy"
                className="w-full h-full object-cover"
                style={{ filter: style.cardFilter }}
                draggable={false}
              />
              <div className="absolute inset-x-0 bottom-0 h-1/2 bg-gradient-to-t from-ink/75 via-ink/25 to-transparent" />
              <div className="absolute top-2 left-2">
                <Badge badge={style.badge} tier={style.tier} />
              </div>
              {showFavorites && (
                <span
                  role="button"
                  tabIndex={0}
                  onClick={(e) => {
                    e.stopPropagation()
                    toggleFavorite(style.id)
                  }}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault()
                      e.stopPropagation()
                      toggleFavorite(style.id)
                    }
                  }}
                  aria-label={fav ? 'Remove from favorites' : 'Add to favorites'}
                  className={`absolute top-2 right-2 w-7 h-7 rounded-full backdrop-blur flex items-center justify-center transition-all ${
                    fav ? 'bg-paper text-red-500 scale-110' : 'bg-ink/35 text-paper/85 hover:bg-ink/55'
                  }`}
                >
                  <svg viewBox="0 0 24 24" className="w-3.5 h-3.5" fill={fav ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2">
                    <path d="M12 21s-7.5-4.9-9.7-9A5.4 5.4 0 0 1 12 6.2 5.4 5.4 0 0 1 21.7 12c-2.2 4.1-9.7 9-9.7 9Z" />
                  </svg>
                </span>
              )}
              <div className="absolute bottom-0 inset-x-0 p-2.5">
                <p className="text-paper font-semibold text-[13px] leading-tight">{style.name}</p>
                <p className="text-paper/70 text-[10px] leading-snug mt-0.5 line-clamp-2">{style.tagline}</p>
              </div>
              {selected && (
                <motion.div
                  layoutId="style-selected-check"
                  className="absolute bottom-2 right-2 w-5 h-5 rounded-full bg-violet flex items-center justify-center"
                >
                  <svg viewBox="0 0 12 12" className="w-3 h-3 text-paper" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M2.5 6.5l2.5 2.5 4.5-5" />
                  </svg>
                </motion.div>
              )}
            </div>
          </motion.button>
        )
      })}
    </div>
  )
}
