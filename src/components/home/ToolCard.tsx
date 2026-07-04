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
      className={`hm-tile hm-press w-full text-left p-2 flex items-center gap-2 ${
        active ? 'border-ink' : ''
      }`}
    >
      <div className="flex-1 min-w-0 pl-1">
        <p className="text-[14px] font-semibold leading-tight truncate">{title}</p>
        <p className="text-[11px] text-fog leading-tight mt-0.5 truncate">{sub}</p>
      </div>
      <div className="relative w-[52px] h-[52px] rounded-[10px] overflow-hidden bg-hairline shrink-0">
        <img src={image} alt="" loading="lazy" draggable={false} className="w-full h-full object-cover" />
        {tag && (
          <span className="absolute bottom-1 right-1 rounded bg-black/55 text-white font-semibold text-[8px] tracking-[0.04em] uppercase px-1 py-px">
            {tag}
          </span>
        )}
      </div>
    </button>
  )
}
