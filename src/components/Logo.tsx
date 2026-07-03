export function ApertureMark({ className = 'w-7 h-7' }: { className?: string }) {
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden>
      <circle cx="24" cy="24" r="22" fill="#6c3bf4" />
      <circle cx="24" cy="24" r="11" fill="#fff" />
      <circle cx="24" cy="24" r="5" fill="#101014" />
      <path d="M24 2 A22 22 0 0 1 43 13 L28 20 A9 9 0 0 0 24 19 Z" fill="#8b63ff" opacity="0.9" />
    </svg>
  )
}

export default function Logo({ dark = false }: { dark?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2">
      <ApertureMark />
      <span
        className={`font-display text-xl font-semibold tracking-tight ${dark ? 'text-paper' : 'text-ink'}`}
      >
        LensMood
      </span>
    </span>
  )
}
