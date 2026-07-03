import { Link } from 'react-router-dom'
import { ApertureMark } from '../Logo'
import { IconBell, IconChevronDown } from '../icons'
import { FREE_CREDITS, useApp } from '../../lib/store'

interface Props {
  onAccount: () => void
}

export default function Header({ onAccount }: Props) {
  const { isPaid, plan, creditsLeft } = useApp()

  return (
    <header className="flex items-center justify-between gap-3 px-4 pt-3.5 pb-1">
      {/* workspace pill */}
      <button
        onClick={onAccount}
        className="hm-pill hm-press inline-flex items-center gap-2 pl-1.5 pr-3 h-11"
        aria-label="LensMood Studio workspace"
      >
        <span className="w-8 h-8 rounded-full bg-ink flex items-center justify-center">
          <ApertureMark className="w-5 h-5" dark />
        </span>
        <span className="text-[13px] font-semibold tracking-[-0.01em]">LensMood Studio</span>
        <IconChevronDown size={13} className="text-fog -ml-0.5" />
      </button>

      <div className="flex items-center gap-2">
        <button
          className="hm-pill hm-press w-11 h-11 flex items-center justify-center text-ink"
          aria-label="Notifications"
        >
          <span className="relative">
            <IconBell size={17} />
            <span className="absolute -top-0.5 -right-0.5 w-1.5 h-1.5 rounded-full bg-signal" />
          </span>
        </button>
        {isPaid ? (
          <span className="h-11 rounded-full bg-ink text-white inline-flex items-center gap-1.5 px-4 text-[13px] font-bold">
            <span className="capitalize">{plan}</span>
            <svg viewBox="0 0 12 12" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="square" aria-hidden>
              <path d="M2.5 6.5l2.5 2.5 4.5-5" />
            </svg>
          </span>
        ) : (
          <Link
            to="/pricing"
            className="hm-press h-11 rounded-full bg-ink text-white inline-flex items-center px-4 text-[13px] font-bold"
          >
            Pro
          </Link>
        )}
      </div>
      {!isPaid && (
        <span className="sr-only">
          {creditsLeft} of {FREE_CREDITS} free shots left
        </span>
      )}
    </header>
  )
}
