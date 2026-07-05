import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { haptic } from '../../lib/native'

interface Props {
  to: string
  title: string
  sub?: string
  image: string
  /** small neutral tag over the image, e.g. PRO */
  tag?: string
  /** tailwind aspect class — lets the grid vary tile shapes */
  ratio?: string
}

/** image-led tool tile — the photo is the surface, text sits on a scrim */
export default function ToolCard({ to, title, sub, image, tag, ratio = 'aspect-[16/10]' }: Props) {
  const navigate = useNavigate()
  const [active, setActive] = useState(false)

  const go = () => {
    setActive(true)
    haptic('light')
    // let the selected state read before the route change
    setTimeout(() => navigate(to), 140)
  }

  return (
    <button
      onClick={go}
      aria-pressed={active}
      className={`hm-press lift shadow-[var(--shadow-e2)] relative block w-full text-left ${ratio} rounded-[18px] overflow-hidden bg-vf ${
        active ? 'ring-2 ring-ink/70 ring-offset-2 ring-offset-paper' : ''
      }`}
    >
      <img
        src={image}
        alt=""
        loading="lazy"
        draggable={false}
        className="absolute inset-0 w-full h-full object-cover"
      />
      <div className="absolute inset-x-0 bottom-0 h-[68%] bg-gradient-to-t from-black/85 via-black/42 to-transparent" />
      {tag && (
        <span className="absolute top-2 right-2 rounded-full bg-black/45 backdrop-blur-sm text-white/90 text-[9px] font-semibold tracking-[0.06em] uppercase px-2 py-0.5">
          {tag}
        </span>
      )}
      <div className="absolute inset-x-0 bottom-0 p-2.5">
        <p className="text-white font-semibold text-[14px] leading-tight truncate">{title}</p>
        {sub && <p className="text-white/80 text-[11px] leading-tight mt-0.5 truncate">{sub}</p>}
      </div>
    </button>
  )
}
