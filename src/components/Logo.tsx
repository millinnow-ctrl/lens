/**
 * LensMood mark — a lens element drawn as a precision instrument:
 * ink outer ring, aperture blades, record-red signal dot.
 */
export function ApertureMark({ className = 'w-6 h-6', dark = false }: { className?: string; dark?: boolean }) {
  const ink = dark ? '#F6F5F1' : '#171614'
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden>
      <circle cx="24" cy="24" r="20" fill="none" stroke={ink} strokeWidth="3" />
      <circle cx="24" cy="24" r="9.5" fill="none" stroke={ink} strokeWidth="2.5" />
      <path d="M24 4v7M44 24h-7M24 44v-7M4 24h7" stroke={ink} strokeWidth="2" />
      <circle cx="35" cy="13" r="3.5" fill="#E1251B" />
    </svg>
  )
}

export default function Logo({ dark = false }: { dark?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <ApertureMark dark={dark} />
      <span
        className={`font-sans text-[17px] font-bold tracking-[-0.01em] ${dark ? 'text-paper' : 'text-ink'}`}
        style={{ fontStretch: '110%' }}
      >
        LensMood
      </span>
    </span>
  )
}
