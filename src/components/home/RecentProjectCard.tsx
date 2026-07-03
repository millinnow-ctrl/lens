import { Link } from 'react-router-dom'

interface Props {
  to: string
  image: string
  label: string
  sublabel?: string
  /** apply a CSS filter fallback while an engine render is pending */
  filter?: string
}

export default function RecentProjectCard({ to, image, label, sublabel, filter }: Props) {
  return (
    <Link to={to} className="hm-tile hm-press block w-[148px] shrink-0 snap-start p-1.5 pb-2">
      <div className="rounded-[11px] overflow-hidden aspect-square bg-hairline">
        <img
          src={image}
          alt=""
          loading="lazy"
          draggable={false}
          className="w-full h-full object-cover"
          style={filter ? { filter } : undefined}
        />
      </div>
      <p className="mt-2 px-1.5 text-[13px] font-semibold leading-tight truncate">{label}</p>
      {sublabel && <p className="px-1.5 text-[11px] text-ink-soft truncate">{sublabel}</p>}
    </Link>
  )
}
