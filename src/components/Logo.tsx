/**
 * LensMood mark — dark rounded app tile, white aperture blades,
 * violet→pink glow ring, a pink sparkle catching the lens.
 */

const TAU = Math.PI * 2
/** blade separation: a twisted seam from the lens opening out to the rim —
 *  cut into a solid white annulus these read as shutter blades, not a star */
const bladeSeam = (i: number, rOut: number, rIn: number, cx: number, cy: number) => {
  const aIn = (i / 6) * TAU - Math.PI / 2
  const aOut = aIn - (38 / 360) * TAU
  return `M${(cx + rIn * Math.cos(aIn)).toFixed(2)} ${(cy + rIn * Math.sin(aIn)).toFixed(2)} L${(
    cx + rOut * Math.cos(aOut)
  ).toFixed(2)} ${(cy + rOut * Math.sin(aOut)).toFixed(2)}`
}

export function ApertureMark({
  className = 'w-7 h-7',
  tile = true,
}: {
  className?: string
  /** draw the dark rounded-square tile behind the lens */
  tile?: boolean
}) {
  const seams = Array.from({ length: 6 }, (_, i) => bladeSeam(i, 14.2, 5.6, 24, 24))
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden>
      <defs>
        <linearGradient id="lmRing" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stopColor="#b0512e" />
          <stop offset="0.55" stopColor="#f26a2e" />
          <stop offset="1" stopColor="#f2a03a" />
        </linearGradient>
        <radialGradient id="lmLens" cx="0.38" cy="0.34" r="0.9">
          <stop offset="0" stopColor="#f4bd6a" />
          <stop offset="0.45" stopColor="#c56a24" />
          <stop offset="1" stopColor="#3a2410" />
        </radialGradient>
      </defs>
      {tile && <rect x="0.5" y="0.5" width="47" height="47" rx="13" fill="#241c12" />}
      <circle cx="24" cy="24" r="17.6" fill="none" stroke="url(#lmRing)" strokeWidth="2.8" />
      {/* solid blade annulus with twisted seams cut through it */}
      <circle cx="24" cy="24" r="9.9" fill="none" stroke={tile ? '#f3ecd9' : '#e6ddc8'} strokeWidth="8.6" />
      {seams.map((d) => (
        <path key={d} d={d} stroke="#241c12" strokeWidth="1.7" strokeLinecap="round" />
      ))}
      <circle cx="24" cy="24" r="6" fill="url(#lmLens)" />
      <circle cx="22" cy="22" r="1.7" fill="#fff6e6" opacity="0.9" />
      {/* sparkle */}
      <path
        d="M38.5 6.5 L39.6 9.4 L42.5 10.5 L39.6 11.6 L38.5 14.5 L37.4 11.6 L34.5 10.5 L37.4 9.4 Z"
        fill="#f7d59a"
      />
    </svg>
  )
}

export default function Logo({ dark = false }: { dark?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <ApertureMark className="w-8 h-8" />
      <span className={`brand-word text-[19px] leading-none ${dark ? 'text-white' : 'text-ink'}`}>
        Lens
        <span className="grad-text">Mood</span>
      </span>
    </span>
  )
}
