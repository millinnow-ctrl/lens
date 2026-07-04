export const CATEGORIES = [
  { id: 'all', label: 'All' },
  { id: 'film', label: 'Film' },
  { id: 'flash', label: 'Flash' },
  { id: 'video', label: 'Video' },
  { id: 'editorial', label: 'Editorial' },
] as const

export type CategoryId = (typeof CATEGORIES)[number]['id']

/** which looks belong to which shelf */
export const CATEGORY_STYLES: Record<CategoryId, string[]> = {
  all: [],
  film: ['disposable', 'leica-street', 'a24-still', 'film-noir', 'polaroid', 'super-8', 'lomo', 'kodachrome', 'tintype'],
  flash: ['iphone-flash', 'y2k-digicam', 'disposable', 'photobooth', 'tokyo-neon'],
  video: ['camcorder-90s', 'y2k-digicam', 'security-cam', 'super-8'],
  editorial: ['gq-editorial', 'leica-street', 'a24-still', 'blockbuster', 'pastel-cinema'],
}

interface Props {
  active: CategoryId
  onSelect: (id: CategoryId) => void
}

export default function CategoryChips({ active, onSelect }: Props) {
  return (
    <div className="relative">
      <div
        className="flex gap-2 overflow-x-auto no-scrollbar px-5 pt-3 pb-0.5"
        role="tablist"
        aria-label="Look categories"
      >
        {CATEGORIES.map((c) => (
          <button
            key={c.id}
            role="tab"
            aria-selected={active === c.id}
            data-active={active === c.id}
            onClick={() => onSelect(c.id)}
            className="hm-chip shrink-0"
          >
            {c.label}
          </button>
        ))}
        <span className="shrink-0 w-3" aria-hidden />
      </div>
      <div className="absolute inset-y-0 right-0 w-6 bg-gradient-to-l from-paper to-transparent pointer-events-none" aria-hidden />
    </div>
  )
}
