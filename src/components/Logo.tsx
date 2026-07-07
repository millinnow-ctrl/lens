/**
 * LensMood mark — the launch icon: a glossy violet lens in a dark barrel,
 * wrapped by a matcha-green focus ring that opens toward a four-point
 * glint. Drawn as vector so it stays crisp from favicon to hero.
 * `ApertureMarkVector` keeps the older engraved SVG around as a fallback.
 */

import { useId } from 'react'

const TAU = Math.PI * 2

/** open focus ring — an arc with its gap aimed at the top-right glint */
const ringArc = (cx: number, cy: number, r: number) => {
  const a0 = (-14 / 360) * TAU // gap edge, upper right
  const a1 = (-76 / 360) * TAU + TAU // sweep the long way around
  const p = (a: number) => `${(cx + r * Math.cos(a)).toFixed(2)} ${(cy + r * Math.sin(a)).toFixed(2)}`
  return `M${p(a0)} A${r} ${r} 0 1 1 ${p(a1)}`
}

export function ApertureMark({
  className = 'w-7 h-7',
  tile = true,
}: {
  className?: string
  /** draw the white rounded-square tile behind the lens */
  tile?: boolean
}) {
  // gradient/clip ids must be unique per instance — with several marks on a
  // page, url(#...) refs all resolve to the FIRST id in the document, and if
  // that instance sits in a hidden container the paint silently drops out
  const uid = useId()
  const ring = `lmRing${uid}`
  const glass = `lmGlass${uid}`
  const core = `lmCore${uid}`
  const clip = `lmClip${uid}`
  return (
    <svg viewBox="0 0 48 48" className={`${className} select-none`} aria-hidden>
      <defs>
        <linearGradient id={ring} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#8fc31f" />
          <stop offset="1" stopColor="#5a8f00" />
        </linearGradient>
        <radialGradient id={glass} cx="0.38" cy="0.3" r="0.85">
          <stop offset="0" stopColor="#b06cf0" />
          <stop offset="0.55" stopColor="#7a1fd0" />
          <stop offset="1" stopColor="#3c0a70" />
        </radialGradient>
        <radialGradient id={core} cx="0.4" cy="0.35" r="0.9">
          <stop offset="0" stopColor="#c084fc" />
          <stop offset="1" stopColor="#6b21a8" />
        </radialGradient>
        <clipPath id={clip}>
          <circle cx="23" cy="26" r="10.2" />
        </clipPath>
      </defs>

      {tile && <rect x="0.5" y="0.5" width="47" height="47" rx="12" fill="#ffffff" stroke="#000000" strokeOpacity="0.06" />}

      {/* focus ring, open toward the glint */}
      <path d={ringArc(23, 26, 17.6)} fill="none" stroke={`url(#${ring})`} strokeWidth="3.3" strokeLinecap="round" />

      {/* four-point glint sitting in the ring's opening */}
      <path
        d="M39.5 4.5 C40.2 7.8 41.9 9.4 45 10 C41.9 10.6 40.2 12.2 39.5 15.5 C38.8 12.2 37.1 10.6 34 10 C37.1 9.4 38.8 7.8 39.5 4.5 Z"
        fill={`url(#${ring})`}
      />

      {/* lens barrel with an inscribed matcha ring */}
      <circle cx="23" cy="26" r="13.2" fill="#170e2c" />
      <circle cx="23" cy="26" r="11.4" fill="none" stroke="#74a80e" strokeWidth="1.5" />

      {/* violet glass, stepped elements, glossy sweep */}
      <circle cx="23" cy="26" r="10.2" fill={`url(#${glass})`} />
      <circle cx="23" cy="26" r="6.6" fill="none" stroke="#2a0850" strokeWidth="1.4" strokeOpacity="0.75" />
      <circle cx="23" cy="26" r="3.7" fill={`url(#${core})`} />
      <g clipPath={`url(#${clip})`}>
        <ellipse cx="28" cy="19.5" rx="9.5" ry="5.2" transform="rotate(-32 28 19.5)" fill="#ffffff" opacity="0.26" />
      </g>
    </svg>
  )
}

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
      <ApertureMark className="w-10 h-10" tile={false} />
      <span className={`brand-word text-[23px] leading-none ${dark ? 'text-white' : 'text-ink'}`}>
        Lens
        <span className="grad-text">Mood</span>
      </span>
    </span>
  )
}
