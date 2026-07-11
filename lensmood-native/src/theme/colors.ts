/**
 * Ocean darkroom palette — ported from the web app's src/index.css @theme.
 * Cool gray-white paper, deep teal feature blocks, one calm ocean accent.
 * The photograph stays the loudest color in the room.
 */
export const colors = {
  paper: '#eef2f5', // app canvas — cool gray-white (not pure white)
  surface: '#ffffff', // raised cards / sheets — crisp white
  clay: '#0c5568', // deep ocean teal — hero / feature blocks
  clayDeep: '#083c4a', // pressed / darker teal
  deepTeal: '#0c5568', // alias of clay — secondary buttons / badge text
  ink: '#17242d', // primary text — cool navy-ink (not pure black)
  inkSoft: '#586974', // secondary text — cool slate
  fog: '#6e7c86', // tertiary / captions — cool grey (>=3:1 on paper)
  hairline: '#e1e7ec', // dividers, borders — cool hairline
  accent: '#0e7487', // THE accent — ocean teal, 4.6:1 on paper
  accentMid: '#1c8397', // mid teal (eyebrows / logo mid-stop)
  accentLight: '#39a6bb', // lighter teal — favorites / hearts
  viewfinder: '#141a1f', // deepest well — viewfinder / contact sheet
  vfChrome: '#8a96a0',
  white: '#ffffff',
  black: '#000000',
} as const

/** brand gradient stops ("Mood" wordmark, glossy CTA fills) */
export const gradients = {
  /** deep teal → ocean → bright teal */
  brandText: ['#0c6376', '#0f7d92', '#2ea0b3'] as const,
  /** glossy ocean fill — the primary action */
  brandFill: ['#128aa0', '#0c5e70'] as const,
  /** ocean ring around a pill / focal card */
  ring: ['#2ea0b3', '#0f7d92', '#0c6376'] as const,
} as const

export type ColorToken = keyof typeof colors
