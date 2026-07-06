import { useId } from 'react'
import type { SVGProps } from 'react'

/**
 * LensMood icon set — hand-tuned on a 24pt grid, SF Symbols discipline.
 *
 * Rules of the set:
 *  - stroke 2.05 (matched to the heavyweight SF text), round caps + joins,
 *    no miters anywhere
 *  - every glyph fills ~17–19 units of the grid; pure circles are drawn
 *    ~4% smaller so they read the same optical size as squares
 *  - chevrons / small marks run slightly heavier (2.25–2.35) so they don't wisp
 *  - Fill variants (tab-bar active states) use fill="currentColor", no stroke,
 *    matched to the optical footprint of their outline twins
 *
 * The only iconography allowed in the app. No emoji, ever.
 */

type P = SVGProps<SVGSVGElement> & { size?: number }

const base = (props: P) => {
  const { size = 18, className = '', ...rest } = props
  return {
    viewBox: '0 0 24 24',
    width: size,
    height: size,
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 2.05,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    className,
    'aria-hidden': true,
    ...rest,
  }
}

/** filled twins: same grid, solid currentColor, no stroke */
const baseFill = (props: P) => {
  const { size = 18, className = '', ...rest } = props
  return {
    viewBox: '0 0 24 24',
    width: size,
    height: size,
    fill: 'currentColor',
    stroke: 'none',
    className,
    'aria-hidden': true,
    ...rest,
  }
}

/* ------------------------------------------------------------------ */
/* Capture                                                             */
/* ------------------------------------------------------------------ */

export const IconCamera = (p: P) => (
  <svg {...base(p)}>
    {/* prism top — trapezoid with softened shoulders, tangent into the body */}
    <path d="M8.35 6.9l.9-1.62c.32-.57.81-.88 1.47-.88h2.56c.66 0 1.15.31 1.47.88l.9 1.62" />
    {/* body */}
    <rect x="3" y="6.9" width="18" height="13" rx="3.4" />
    {/* lens — big, centered on the body */}
    <circle cx="12" cy="13.3" r="3.85" />
    {/* viewfinder detail dot, top right */}
    <path d="M17.55 10.15h.01" strokeWidth={2.35} />
  </svg>
)

export const IconAperture = (p: P) => (
  <svg {...base(p)}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M13.99 8.56l4.93 8.55M10.01 8.56h9.88M8.03 12l4.93-8.55M10.01 15.44L5.08 6.89M13.99 15.44H4.11M15.97 12l-4.93 8.55" />
  </svg>
)

export const IconImage = (p: P) => (
  <svg {...base(p)}>
    <rect x="3.2" y="4.7" width="17.6" height="14.6" rx="3.6" />
    <circle cx="8.7" cy="9.5" r="1.85" />
    <path d="M20.8 15.9l-4.63-4.63a1.85 1.85 0 0 0-2.62 0L5.2 19.6" />
  </svg>
)

export const IconImageFill = (p: P) => {
  const { size = 18, className = '', ...rest } = p
  const id = useId()
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="currentColor" className={className} aria-hidden {...rest}>
      <mask id={id} maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">
        <rect x="3.2" y="4.7" width="17.6" height="14.6" rx="3.6" fill="#fff" />
        <path
          d="M20.8 15.9l-4.63-4.63a1.85 1.85 0 0 0-2.62 0L5.2 19.6"
          fill="none"
          stroke="#000"
          strokeWidth="2.1"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <circle cx="8.7" cy="9.5" r="2.05" fill="#000" />
      </mask>
      <rect x="3.2" y="4.7" width="17.6" height="14.6" rx="3.6" mask={`url(#${id})`} />
    </svg>
  )
}

/** picture with a plus badge — the upload drop zone */
export const IconImagePlus = (p: P) => (
  <svg {...base(p)}>
    <path d="M20.8 11.4V8.3a3.6 3.6 0 0 0-3.6-3.6H6.8a3.6 3.6 0 0 0-3.6 3.6v7.4a3.6 3.6 0 0 0 3.6 3.6h6.2" />
    <circle cx="8.5" cy="9.3" r="1.7" />
    <path d="M3.3 16.4l4.14-4.14a1.85 1.85 0 0 1 2.62 0L14.2 16.4" />
    <path d="M17.9 15.1v5.6M15.1 17.9h5.6" />
  </svg>
)

export const IconFilm = (p: P) => (
  <svg {...base(p)}>
    <rect x="3.3" y="4.1" width="17.4" height="15.8" rx="3" />
    <path d="M8 4.3v15.4M16 4.3v15.4" />
    <path d="M3.3 8.4h4.7M3.3 12h4.7M3.3 15.6h4.7M16 8.4h4.7M16 12h4.7M16 15.6h4.7" />
  </svg>
)

export const IconCompare = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 3.4v17.2" />
    <path d="M8.1 8.6L4.7 12l3.4 3.4M15.9 8.6l3.4 3.4-3.4 3.4" />
  </svg>
)

/* ------------------------------------------------------------------ */
/* Navigation / tab bar                                                */
/* ------------------------------------------------------------------ */

export const IconHome = (p: P) => (
  <svg {...base(p)}>
    <path d="M3.9 11.1l7.06-6.15a1.6 1.6 0 0 1 2.08 0L20.1 11.1" />
    <path d="M5.5 12.6v5.5c0 1 .81 1.8 1.8 1.8h9.4c.99 0 1.8-.8 1.8-1.8v-5.5" />
    <path d="M10.2 19.9v-3.85a1.8 1.8 0 0 1 3.6 0V19.9" />
  </svg>
)

export const IconHomeFill = (p: P) => (
  <svg {...baseFill(p)}>
    <path d="M11.47 3.73a.85.85 0 0 1 1.06 0l7.7 6.3c.49.4.77 1 .77 1.63v6.44a2.1 2.1 0 0 1-2.1 2.1H14.6v-4.55a2.6 2.6 0 0 0-5.2 0v4.55H5.1a2.1 2.1 0 0 1-2.1-2.1v-6.44c0-.63.28-1.23.77-1.63Z" />
  </svg>
)

/** contact sheet — four frames on the light table, the Styles tab */
export const IconStyles = (p: P) => (
  <svg {...base(p)}>
    <rect x="3.9" y="3.9" width="7" height="7" rx="2.2" />
    <rect x="13.1" y="3.9" width="7" height="7" rx="2.2" />
    <rect x="3.9" y="13.1" width="7" height="7" rx="2.2" />
    <rect x="13.1" y="13.1" width="7" height="7" rx="2.2" />
  </svg>
)

export const IconStylesFill = (p: P) => (
  <svg {...baseFill(p)}>
    <rect x="3.4" y="3.4" width="8" height="8" rx="2.5" />
    <rect x="12.6" y="3.4" width="8" height="8" rx="2.5" />
    <rect x="3.4" y="12.6" width="8" height="8" rx="2.5" />
    <rect x="12.6" y="12.6" width="8" height="8" rx="2.5" />
  </svg>
)

export const IconUser = (p: P) => (
  <svg {...base(p)}>
    <circle cx="12" cy="8.3" r="3.95" />
    <path d="M4.9 19.9a7.15 7.15 0 0 1 14.2 0" />
  </svg>
)

export const IconUserFill = (p: P) => (
  <svg {...baseFill(p)}>
    <circle cx="12" cy="8.1" r="4.5" />
    <path d="M12 14.3c-4.66 0-8.2 2.66-8.68 6.05-.09.63.43 1.15 1.06 1.15h15.24c.63 0 1.15-.52 1.06-1.15-.48-3.39-4.02-6.05-8.68-6.05Z" />
  </svg>
)

export const IconPlusCircle = (p: P) => (
  <svg {...base(p)}>
    <circle cx="12" cy="12" r="8.65" />
    <path d="M12 8.4v7.2M8.4 12h7.2" />
  </svg>
)

export const IconGrid = (p: P) => (
  <svg {...base(p)}>
    <rect x="3.9" y="3.9" width="7" height="7" rx="2.2" />
    <rect x="13.1" y="3.9" width="7" height="7" rx="2.2" />
    <rect x="3.9" y="13.1" width="7" height="7" rx="2.2" />
    <rect x="13.1" y="13.1" width="7" height="7" rx="2.2" />
  </svg>
)

export const IconStack = (p: P) => (
  <svg {...base(p)}>
    <path d="M11.32 3.8a1.6 1.6 0 0 1 1.36 0l7.25 3.35c.9.42.9 1.7 0 2.11l-7.25 3.35a1.6 1.6 0 0 1-1.36 0L4.07 9.26c-.9-.42-.9-1.7 0-2.11Z" />
    <path d="M20.7 13.3l-8 3.68a1.7 1.7 0 0 1-1.4 0l-8-3.68" />
    <path d="M20.7 17.1l-8 3.68a1.7 1.7 0 0 1-1.4 0l-8-3.68" />
  </svg>
)

/* ------------------------------------------------------------------ */
/* Actions                                                             */
/* ------------------------------------------------------------------ */

export const IconUpload = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 14.5V3.9" />
    <path d="M7.9 7.8L12 3.7l4.1 4.1" />
    <path d="M4.4 14.9v2.7a2.6 2.6 0 0 0 2.6 2.6h10a2.6 2.6 0 0 0 2.6-2.6v-2.7" />
  </svg>
)

export const IconDownload = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 3.9v10.6" />
    <path d="M7.9 10.6l4.1 4.1 4.1-4.1" />
    <path d="M4.4 14.9v2.7a2.6 2.6 0 0 0 2.6 2.6h10a2.6 2.6 0 0 0 2.6-2.6v-2.7" />
  </svg>
)

export const IconShare = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 13.9V3.6" />
    <path d="M8.3 7.2L12 3.5l3.7 3.7" />
    <path d="M8.75 9.4H7.1a2.6 2.6 0 0 0-2.6 2.6v6a2.6 2.6 0 0 0 2.6 2.6h9.8a2.6 2.6 0 0 0 2.6-2.6v-6a2.6 2.6 0 0 0-2.6-2.6h-1.65" />
  </svg>
)

export const IconPlay = (p: P) => (
  // fill + self-stroke fattens the triangle and rounds its corners
  <svg {...base(p)} fill="currentColor" strokeWidth={2.05}>
    <path d="M8.7 6.9v10.2L17.7 12Z" />
  </svg>
)

export const IconPause = (p: P) => (
  <svg {...baseFill(p)}>
    <rect x="6.7" y="4.9" width="3.6" height="14.2" rx="1.8" />
    <rect x="13.7" y="4.9" width="3.6" height="14.2" rx="1.8" />
  </svg>
)

export const IconHeart = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 20.1c-.2 0-.4-.06-.57-.18C9.5 18.6 3.1 14 3.1 9.1c0-2.9 2.3-5.2 5.1-5.2 1.5 0 2.9.68 3.8 1.8.9-1.12 2.3-1.8 3.8-1.8 2.8 0 5.1 2.3 5.1 5.2 0 4.9-6.4 9.5-8.33 10.82-.17.12-.37.18-.57.18Z" />
  </svg>
)

export const IconTrash = (p: P) => (
  <svg {...base(p)}>
    <path d="M4.3 6.6h15.4" />
    <path d="M9.3 6.5V5.35c0-.66.54-1.2 1.2-1.2h3c.66 0 1.2.54 1.2 1.2V6.5" />
    <path d="M6.3 6.7l.72 11.6a2 2 0 0 0 2 1.9h5.96a2 2 0 0 0 2-1.9l.72-11.6" />
    <path d="M10.1 10.4l.2 6M13.9 10.4l-.2 6" />
  </svg>
)

export const IconTag = (p: P) => (
  <svg {...base(p)}>
    <path d="M4.15 6.1c0-1.08.87-1.95 1.95-1.95h4.22c.52 0 1.01.2 1.38.57l7.7 7.7a1.95 1.95 0 0 1 0 2.76l-4.27 4.27a1.95 1.95 0 0 1-2.76 0l-7.7-7.7a1.95 1.95 0 0 1-.52-1.33Z" />
    <circle cx="8.55" cy="8.55" r="1.15" />
  </svg>
)

/* ------------------------------------------------------------------ */
/* Marks / small glyphs (drawn slightly heavier)                       */
/* ------------------------------------------------------------------ */

export const IconClose = (p: P) => (
  <svg {...base(p)} strokeWidth={2.25}>
    <path d="M6.2 6.2l11.6 11.6M17.8 6.2L6.2 17.8" />
  </svg>
)

export const IconCheck = (p: P) => (
  <svg {...base(p)} strokeWidth={2.25}>
    <path d="M4.9 12.9l4.6 4.6L19.1 7.1" />
  </svg>
)

export const IconArrowRight = (p: P) => (
  <svg {...base(p)} strokeWidth={2.25}>
    <path d="M4.6 12h14.8M13.5 6.1l5.9 5.9-5.9 5.9" />
  </svg>
)

export const IconChevronDown = (p: P) => (
  <svg {...base(p)} strokeWidth={2.35}>
    <path d="M6.6 9.3l5.4 5.5 5.4-5.5" />
  </svg>
)

export const IconChevronRight = (p: P) => (
  <svg {...base(p)} strokeWidth={2.35}>
    <path d="M9.3 6.6l5.5 5.4-5.5 5.4" />
  </svg>
)

export const IconDot = (p: P) => (
  <svg {...baseFill(p)}>
    <circle cx="12" cy="12" r="4.6" />
  </svg>
)

export const IconDots = (p: P) => (
  <svg {...baseFill(p)}>
    <circle cx="5.6" cy="12" r="1.15" />
    <circle cx="12" cy="12" r="1.15" />
    <circle cx="18.4" cy="12" r="1.15" />
  </svg>
)

/* ------------------------------------------------------------------ */
/* Ambient                                                             */
/* ------------------------------------------------------------------ */

export const IconBell = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 4.2a5.9 5.9 0 0 1 5.9 5.9c0 2.7.55 4.3 1.14 5.3.36.6-.04 1.4-.74 1.4H5.7c-.7 0-1.1-.8-.74-1.4.59-1 1.14-2.6 1.14-5.3A5.9 5.9 0 0 1 12 4.2Z" />
    <path d="M9.95 17.1a2.05 2.05 0 0 0 4.1 0" />
  </svg>
)

export const IconSearch = (p: P) => (
  <svg {...base(p)}>
    <circle cx="10.9" cy="10.9" r="6.7" />
    <path d="M15.75 15.75l4.6 4.6" />
  </svg>
)

/* ------------------------------------------------------------------ */
/* Brand marks (fixed colors, not part of the stroke system)           */
/* ------------------------------------------------------------------ */

export const IconApple = (p: P) => {
  const { size = 18, className = '' } = p
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} className={className} fill="currentColor" aria-hidden>
      <path d="M17.05 12.98c-.03-2.62 2.14-3.88 2.24-3.94-1.22-1.79-3.12-2.03-3.8-2.06-1.61-.16-3.15.95-3.97.95-.82 0-2.09-.93-3.44-.9-1.77.03-3.4 1.03-4.31 2.61-1.84 3.19-.47 7.9 1.32 10.49.88 1.27 1.92 2.69 3.29 2.64 1.32-.05 1.82-.85 3.42-.85 1.6 0 2.05.85 3.44.82 1.42-.02 2.32-1.29 3.19-2.56.7-1 1.14-2.06 1.4-2.66-3.06-1.17-3.53-4.06-2.78-4.54ZM14.44 5.01c.73-.88 1.22-2.1 1.08-3.32-1.05.04-2.32.7-3.07 1.58-.67.78-1.26 2.02-1.1 3.21 1.17.09 2.36-.59 3.09-1.47Z" />
    </svg>
  )
}

export const IconGoogle = (p: P) => {
  const { size = 18, className = '' } = p
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} className={className} aria-hidden>
      <path fill="#4285F4" d="M23.5 12.3c0-.9-.1-1.5-.3-2.2H12v4.1h6.5c-.1 1.1-.8 2.7-2.4 3.8l3.7 2.9c2.2-2 3.7-5 3.7-8.6z" />
      <path fill="#34A853" d="M12 24c3.2 0 5.9-1.1 7.9-2.9l-3.7-2.9c-1 .7-2.4 1.2-4.2 1.2-3.2 0-5.9-2.1-6.8-5l-3.9 3C3.2 21.3 7.3 24 12 24z" />
      <path fill="#FBBC05" d="M5.2 14.4c-.2-.7-.4-1.5-.4-2.4s.1-1.7.4-2.4l-3.9-3C.5 8.2 0 10 0 12s.5 3.8 1.3 5.4l3.9-3z" />
      <path fill="#EA4335" d="M12 4.7c1.8 0 3 .8 3.7 1.4l3.3-3.2C17.9 1.1 15.2 0 12 0 7.3 0 3.2 2.7 1.3 6.6l3.9 3c.9-2.9 3.6-4.9 6.8-4.9z" />
    </svg>
  )
}
