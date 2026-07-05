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

/** shelf tabs in the camera-spec voice — typographic, not another row of
 *  pills. The active tab carries a short film-red tick, rhyming with the
 *  frame counter under the deck. */
export default function CategoryChips({ active, onSelect }: Props) {
  return (
    <div className="relative">
      <div
        className="flex gap-6 overflow-x-auto no-scrollbar px-5 pt-3 pb-1"
        role="tablist"
        aria-label="Look categories"
      >
        {CATEGORIES.map((c) => {
          const on = active === c.id
          return (
            <button
              key={c.id}
              role="tab"
              aria-selected={on}
              onClick={() => onSelect(c.id)}
              className="hit shrink-0 flex flex-col items-start gap-1 pt-1 pb-0.5"
            >
              <span
                className={`font-mono text-[12px] tracking-[0.14em] uppercase transition-colors duration-150 ${
                  on ? 'text-ink font-medium' : 'text-fog'
                }`}
              >
                {c.label}
              </span>
              <span
                aria-hidden
                className="block h-[2px] w-4 rounded-full transition-all duration-200"
                style={{ background: on ? '#e0392b' : 'transparent' }}
              />
            </button>
          )
        })}
        <span className="shrink-0 w-3" aria-hidden />
      </div>
      <div className="absolute inset-y-0 right-0 w-6 bg-gradient-to-l from-paper to-transparent pointer-events-none" aria-hidden />
    </div>
  )
}
