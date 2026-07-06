/**
 * LensMood mark — a real photograph: a machined brass lens mount with a
 * matcha-glass element, shot from above on cream linen. The brand mark IS
 * a camera part, not an icon of one. `ApertureMarkVector` keeps the old
 * engraved SVG around as a fallback for contexts that need vector.
 */

import mark from '../assets/mark.png'

export function ApertureMark({
  className = 'w-7 h-7',
}: {
  className?: string
  /** kept for call-site compatibility; the photographic mark has no tile */
  tile?: boolean
}) {
  return (
    <img
      src={mark}
      alt=""
      aria-hidden
      draggable={false}
      className={`${className} select-none object-contain`}
    />
  )
}

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

export function ApertureMarkVector({
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
      {tile && <rect x="0.5" y="0.5" width="47" height="47" rx="13" fill="#241c12" />}
      <circle cx="24" cy="24" r="17.6" fill="none" stroke="#5f7247" strokeWidth="2.4" />
      {/* solid blade annulus with twisted seams cut through it */}
      <circle cx="24" cy="24" r="9.9" fill="none" stroke={tile ? '#f3ecd9' : '#e6ddc8'} strokeWidth="8.6" />
      {seams.map((d) => (
        <path key={d} d={d} stroke="#241c12" strokeWidth="1.7" strokeLinecap="round" />
      ))}
      <circle cx="24" cy="24" r="6" fill="#57683f" />
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
