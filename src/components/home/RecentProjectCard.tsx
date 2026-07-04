import { Link } from 'react-router-dom'
import { IconDots } from '../icons'

interface Props {
  to: string
  image: string
  label: string
  sublabel?: string
  /** apply a CSS filter fallback while an engine render is pending */
  filter?: string
  /** small neutral chip in the top-right, e.g. Example */
  chip?: string
}

/** big rounded photo card — the "Recent edits" tile from the reference */
export default function RecentProjectCard({ to, image, label, sublabel, filter, chip }: Props) {
  return (
    <Link to={to} className="hm-press relative block rounded-[20px] overflow-hidden aspect-[4/4.6] bg-vf">
      <img
        src={image}
        alt=""
        loading="lazy"
        draggable={false}
        className="absolute inset-0 w-full h-full object-cover"
        style={filter ? { filter } : undefined}
      />
      <div className="absolute inset-x-0 bottom-0 h-[46%] bg-gradient-to-t from-black/70 via-black/25 to-transparent" />
      {chip && (
        <span className="absolute top-2.5 right-2.5 rounded-full bg-black/45 backdrop-blur-sm text-white/90 text-[9.5px] font-semibold tracking-[0.04em] uppercase px-2 py-0.5">
          {chip}
        </span>
      )}
      <div className="absolute inset-x-0 bottom-0 flex items-end justify-between gap-2 p-3">
        <div className="min-w-0">
          <p className="text-white font-semibold text-[14.5px] leading-tight truncate">{label}</p>
          {sublabel && <p className="text-white/70 text-[11.5px] leading-tight mt-0.5 truncate">{sublabel}</p>}
        </div>
        <span
          className="shrink-0 w-8 h-8 rounded-full bg-black/40 backdrop-blur-sm flex items-center justify-center text-white"
          aria-hidden
        >
          <IconDots size={15} />
        </span>
      </div>
    </Link>
  )
}
