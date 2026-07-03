import type { SVGProps } from 'react'

/**
 * LensMood icon set — 24 viewBox, 1.5 stroke, square caps.
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
    strokeWidth: 1.5,
    strokeLinecap: 'square' as const,
    strokeLinejoin: 'miter' as const,
    className,
    'aria-hidden': true,
    ...rest,
  }
}

export const IconCamera = (p: P) => (
  <svg {...base(p)}>
    <rect x="3" y="6.5" width="18" height="13" />
    <circle cx="12" cy="13" r="3.75" />
    <path d="M8.5 6.5L10 4h4l1.5 2.5M17.75 9.75h.5" />
  </svg>
)

export const IconUpload = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 15V4m0 0L7.5 8.5M12 4l4.5 4.5M4 15v5h16v-5" />
  </svg>
)

export const IconDownload = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 4v11m0 0l-4.5-4.5M12 15l4.5-4.5M4 15v5h16v-5" />
  </svg>
)

export const IconShare = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 14V3.5m0 0L8 7.5M12 3.5L16 7.5" />
    <path d="M6 11H4v9h16v-9h-2" />
  </svg>
)

export const IconPlay = (p: P) => (
  <svg {...base(p)} fill="currentColor" stroke="none">
    <path d="M8 5.5v13l11-6.5Z" />
  </svg>
)

export const IconPause = (p: P) => (
  <svg {...base(p)} fill="currentColor" stroke="none">
    <rect x="6.5" y="5" width="3.5" height="14" />
    <rect x="14" y="5" width="3.5" height="14" />
  </svg>
)

export const IconHeart = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 20s-7.2-4.7-9.3-8.6a5.2 5.2 0 0 1 9.3-4.6 5.2 5.2 0 0 1 9.3 4.6C19.2 15.3 12 20 12 20Z" />
  </svg>
)

export const IconClose = (p: P) => (
  <svg {...base(p)}>
    <path d="M5.5 5.5l13 13m0-13l-13 13" />
  </svg>
)

export const IconCheck = (p: P) => (
  <svg {...base(p)}>
    <path d="M4.5 12.5l5 5L19.5 6.5" />
  </svg>
)

export const IconArrowRight = (p: P) => (
  <svg {...base(p)}>
    <path d="M4 12h16m0 0l-6-6m6 6l-6 6" />
  </svg>
)

export const IconCompare = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 3v18M8 8l-4 4 4 4M16 8l4 4-4 4" />
  </svg>
)

export const IconFilm = (p: P) => (
  <svg {...base(p)}>
    <rect x="4" y="3.5" width="16" height="17" />
    <path d="M8 3.5v17M16 3.5v17M4 8h4M4 12h4M4 16h4M16 8h4M16 12h4M16 16h4" />
  </svg>
)

export const IconGrid = (p: P) => (
  <svg {...base(p)}>
    <rect x="4" y="4" width="7" height="7" />
    <rect x="13" y="4" width="7" height="7" />
    <rect x="4" y="13" width="7" height="7" />
    <rect x="13" y="13" width="7" height="7" />
  </svg>
)

export const IconHome = (p: P) => (
  <svg {...base(p)}>
    <path d="M4 11l8-7 8 7v9h-5.5v-6h-5v6H4Z" />
  </svg>
)

export const IconTag = (p: P) => (
  <svg {...base(p)}>
    <path d="M4 4h7l9 9-7 7-9-9Z" />
    <circle cx="8.5" cy="8.5" r="1" fill="currentColor" stroke="none" />
  </svg>
)

export const IconTrash = (p: P) => (
  <svg {...base(p)}>
    <path d="M5 7h14M9.5 7V4.5h5V7M7 7l1 13h8l1-13M10.5 10.5v6M13.5 10.5v6" />
  </svg>
)

export const IconDot = (p: P) => (
  <svg {...base(p)} fill="currentColor" stroke="none">
    <circle cx="12" cy="12" r="5" />
  </svg>
)

export const IconAperture = (p: P) => (
  <svg {...base(p)}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 3.5l3.5 8.5M20 8.5l-8.5 3.5M20.5 15.5H11.5M15.5 20.5L12 12M8 20l4-8M3.5 15l8.5-3M4 8.5h8" />
  </svg>
)

export const IconBell = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 4a5.5 5.5 0 0 1 5.5 5.5c0 3 .8 4.6 1.7 5.7H4.8c.9-1.1 1.7-2.7 1.7-5.7A5.5 5.5 0 0 1 12 4Z" />
    <path d="M10 18.5a2 2 0 0 0 4 0" />
  </svg>
)

export const IconSearch = (p: P) => (
  <svg {...base(p)}>
    <circle cx="11" cy="11" r="6.5" />
    <path d="M15.8 15.8L20.5 20.5" />
  </svg>
)

export const IconChevronDown = (p: P) => (
  <svg {...base(p)}>
    <path d="M6 9.5l6 6 6-6" />
  </svg>
)

export const IconChevronRight = (p: P) => (
  <svg {...base(p)}>
    <path d="M9.5 6l6 6-6 6" />
  </svg>
)

export const IconSparkle = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 3.5l1.8 5.2 5.2 1.8-5.2 1.8L12 17.5l-1.8-5.2L5 10.5l5.2-1.8Z" />
    <path d="M18.5 15.5l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9Z" />
  </svg>
)

export const IconStack = (p: P) => (
  <svg {...base(p)}>
    <path d="M12 3.5L21 8l-9 4.5L3 8Z" />
    <path d="M3 12.5l9 4.5 9-4.5M3 17l9 4.5L21 17" />
  </svg>
)

export const IconUser = (p: P) => (
  <svg {...base(p)}>
    <circle cx="12" cy="8.5" r="4" />
    <path d="M4.5 20.5a7.5 7.5 0 0 1 15 0" />
  </svg>
)

export const IconImage = (p: P) => (
  <svg {...base(p)}>
    <rect x="3.5" y="4.5" width="17" height="15" />
    <circle cx="9" cy="10" r="1.75" />
    <path d="M3.5 17l5-5 4 4 3-3 5 5" />
  </svg>
)

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
