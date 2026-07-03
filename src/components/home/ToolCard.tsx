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
}

export default function ToolCard({ to, title, sub, image, tag }: Props) {
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
      className={`hm-tile hm-press w-full text-left p-2 flex items-start gap-2.5 transition-shadow ${
        active ? 'ring-2 ring-ink' : ''
      }`}
    >
      <div className="flex-1 min-w-0 pl-1.5 pt-1.5">
        <p className="text-[15px] font-semibold leading-[1.25] min-h-[2.5em]">{title}</p>
        <p className="text-[11px] text-ink-soft leading-snug truncate">{sub}</p>
      </div>
      <div className="relative w-16 h-16 rounded-[11px] overflow-hidden bg-hairline shrink-0">
        <img src={image} alt="" loading="lazy" draggable={false} className="w-full h-full object-cover" />
        {tag && (
          <span className="absolute top-1 right-1 rounded-full bg-vf/75 text-white font-semibold text-[8.5px] tracking-[0.06em] uppercase px-1.5 py-0.5">
            {tag}
          </span>
        )}
      </div>
    </button>
  )
}
