import { Link } from 'react-router-dom'
import { ApertureMark } from '../Logo'
import { useApp } from '../../lib/store'

interface Props {
  onAccount: () => void
}

export default function Header({ onAccount }: Props) {
  const { isPaid, plan } = useApp()

  return (
    <header className="flex items-center justify-between gap-2 px-5 pt-3 pb-1">
      <button onClick={onAccount} className="hm-press inline-flex items-center gap-2.5" aria-label="LensMood account">
        <ApertureMark className="w-16 h-16" tile={false} />
        <span className="brand-word text-[31px] leading-none text-ink">
          Lens
          <span className="grad-text">Mood</span>
        </span>
      </button>

      <div className="relative">
        {isPaid ? (
          <span className="h-9 inline-flex items-center gap-1.5 rounded-full glass px-4 text-[14px] font-semibold text-ink">
            <span className="capitalize">{plan}</span>
          </span>
        ) : (
          <Link
            to="/pricing"
            className="hm-press h-9 inline-flex items-center gap-1.5 rounded-full glass px-4 text-[14px] font-semibold text-ink"
          >
            Pro
          </Link>
        )}
      </div>
    </header>
  )
}
