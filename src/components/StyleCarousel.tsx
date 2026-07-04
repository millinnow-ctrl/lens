import { CAMERA_STYLES, type CameraStyle } from '../lib/styles'
import { IconHeart } from './icons'
import { useApp } from '../lib/store'
import { STYLE_ART } from '../lib/styleArt'

interface Props {
  /** kept for call-site compatibility — used only as an ultimate fallback if a
   *  style has no signature artwork. Cards never render the user's photo. */
  previewSrc: string
  selectedId: string | null
  onSelect: (style: CameraStyle) => void
  showFavorites?: boolean
}

function Badge({ badge }: { badge?: CameraStyle['badge'] }) {
  if (badge === 'trending') return <span className="tag tag-chrome">Trending</span>
  if (badge === 'featured') return <span className="tag tag-chrome">This week</span>
  return null
}

export default function StyleCarousel({ previewSrc, selectedId, onSelect, showFavorites = true }: Props) {
  const { favorites, toggleFavorite } = useApp()
  // one camera at a time: cards show each look's signature artwork — the
  // user's photo only ever enters a look when they explicitly develop it

  return (
    <div className="flex gap-3 overflow-x-auto no-scrollbar snap-x snap-mandatory -mx-1 px-1 py-2">
      {CAMERA_STYLES.map((style, i) => {
        const selected = style.id === selectedId
        const fav = favorites.includes(style.id)
        const index = `LM·${String(i + 1).padStart(2, '0')}`
        return (
          <button
            key={style.id}
            onClick={() => onSelect(style)}
            className={`group relative shrink-0 w-36 snap-start rounded-[18px] bg-surface border text-left transition-all duration-150 ${
              selected
                ? 'border-ink ring-2 ring-ink/45 scale-[1.02] shadow-[0_6px_18px_-6px_rgb(0_0_0/0.6)]'
                : 'border-white/[0.07] hover:border-white/20'
            }`}
            aria-pressed={selected}
          >
            <div className="relative aspect-4/5 overflow-hidden rounded-t-[17px]">
              <img
                src={STYLE_ART[style.id] ?? previewSrc}
                alt=""
                loading="lazy"
                className="w-full h-full object-cover"
                style={STYLE_ART[style.id] ? undefined : { filter: style.cardFilter }}
                draggable={false}
              />
              <div className="absolute top-1.5 right-1.5">
                <Badge badge={style.badge} />
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
                  className={`absolute top-1.5 left-1.5 w-6 h-6 rounded-full bg-vf/60 backdrop-blur-sm flex items-center justify-center transition-opacity duration-150 focus:opacity-100 ${
                    fav ? 'opacity-100 text-magenta' : 'opacity-0 group-hover:opacity-100 text-white'
                  }`}
                >
                  <IconHeart size={13} fill={fav ? 'currentColor' : 'none'} />
                </span>
              )}
            </div>
            <div className="px-2.5 pt-2 pb-2.5">
              <p className="flex items-center gap-1.5 font-mono text-[10px] font-medium tracking-[0.1em] uppercase text-fog">
                {index}
                {selected && <span className="w-1.5 h-1.5 rounded-full bg-ink inline-block" aria-hidden />}
              </p>
              <p className="font-semibold text-[13px] leading-tight mt-1 text-ink">
                {style.name}
                {style.tier === 'premium' && (
                  <span className="text-fog text-[10px] font-medium whitespace-nowrap"> · Pro</span>
                )}
              </p>
              <p className="text-fog text-[11px] leading-snug mt-0.5 line-clamp-2 min-h-[2.6em]">{style.tagline}</p>
            </div>
          </button>
        )
      })}
    </div>
  )
}
