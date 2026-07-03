import { IconCamera, IconFilm, IconGrid, IconPlay, IconTag } from '../icons'

export const CATEGORIES = [
  { id: 'all', label: 'All', icon: IconGrid },
  { id: 'film', label: 'Film', icon: IconFilm },
  { id: 'flash', label: 'Flash', icon: IconCamera },
  { id: 'video', label: 'Video', icon: IconPlay },
  { id: 'editorial', label: 'Editorial', icon: IconTag },
] as const

export type CategoryId = (typeof CATEGORIES)[number]['id']

/** which camera moods belong to which shelf */
export const CATEGORY_STYLES: Record<CategoryId, string[]> = {
  all: [],
  film: ['disposable', 'leica-street', 'a24-still', 'film-noir', 'polaroid'],
  flash: ['iphone-flash', 'y2k-digicam', 'disposable'],
  video: ['camcorder-90s', 'iphone-flash', 'y2k-digicam'],
  editorial: ['gq-editorial', 'leica-street', 'a24-still'],
}

interface Props {
  active: CategoryId
  onSelect: (id: CategoryId) => void
}

export default function CategoryChips({ active, onSelect }: Props) {
  return (
    <div className="relative">
      <div className="flex gap-2 overflow-x-auto no-scrollbar px-4 pt-4 pb-1" role="tablist" aria-label="Mood categories">
        {CATEGORIES.map((c) => (
          <button
            key={c.id}
            role="tab"
            aria-selected={active === c.id}
            data-active={active === c.id}
            onClick={() => onSelect(c.id)}
            className="hm-chip shrink-0"
          >
            {active === c.id && <c.icon size={13} />}
            {c.label}
          </button>
        ))}
        <span className="shrink-0 w-2" aria-hidden />
      </div>
      {/* right-edge scroll affordance */}
      <div className="absolute inset-y-0 right-0 w-8 bg-gradient-to-l from-[#F2F2EF] to-transparent pointer-events-none" aria-hidden />
    </div>
  )
}
