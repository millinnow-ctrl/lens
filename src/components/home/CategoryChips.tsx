import { motion } from 'framer-motion'
import { springSoft } from '../../lib/motion'

export const CATEGORIES = [
  { id: 'all', label: 'All' },
  { id: 'film', label: 'Film' },
  { id: 'flash', label: 'Flash' },
  { id: 'video', label: 'Video' },
  { id: 'editorial', label: 'Editorial' },
  { id: 'bw', label: 'B&W' },
] as const

export type CategoryId = (typeof CATEGORIES)[number]['id']

/** which looks belong to which shelf */
export const CATEGORY_STYLES: Record<CategoryId, string[]> = {
  all: [],
  film: ['disposable', 'leica-street', 'a24-still', 'film-noir', 'polaroid', 'super-8', 'lomo', 'kodachrome', 'tintype'],
  flash: ['iphone-flash', 'y2k-digicam', 'disposable', 'photobooth', 'tokyo-neon'],
  video: ['camcorder-90s', 'y2k-digicam', 'security-cam', 'super-8'],
  editorial: ['gq-editorial', 'leica-street', 'a24-still', 'blockbuster', 'pastel-cinema'],
  bw: ['film-noir', 'tintype', 'photobooth', 'security-cam'],
}

interface Props {
  active: CategoryId
  onSelect: (id: CategoryId) => void
}

/** shelf selector — a glass rail with a gold glass puck that slides to sit
 *  over the active shelf (the affordance lives in the material) */
export default function CategoryChips({ active, onSelect }: Props) {
  return (
    <div className="px-5 pt-3 pb-1">
      {/* one rail, fully on screen — every shelf reachable without scrolling */}
      <div
        className="glass rounded-full p-1 flex items-center"
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
              className="relative flex-1 h-9 rounded-full min-w-0"
            >
              {on && (
                <motion.span
                  layoutId="lm-tab-puck"
                  transition={springSoft}
                  className="tab-puck absolute inset-0 rounded-full"
                  aria-hidden
                />
              )}
              <span
                className={`relative text-[12.5px] whitespace-nowrap transition-colors duration-150 ${
                  on ? 'text-[#3a2410] font-semibold' : 'text-ink-soft font-medium'
                }`}
              >
                {c.label}
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
