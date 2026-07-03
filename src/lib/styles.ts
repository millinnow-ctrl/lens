export interface StyleParams {
  /** 0–100, scales the whole look toward/away from the original */
  intensity: number
  grain: number
  /** 0–100, 50 = neutral */
  contrast: number
  /** 0–100, 50 = neutral. Below = cooler, above = warmer */
  warmth: number
  flash: number
  /** shadow depth / vignette */
  shadows: number
  smoothing: number
}

export interface StyleCharacter {
  bw?: boolean
  sepia?: number // 0..1
  hue?: number // degrees
  saturate?: number // multiplier, 1 = neutral
  brightness?: number // multiplier, 1 = neutral
  blur?: number // px at 1000px reference width
  fade?: number // 0..1 lifted blacks
  halation?: number // 0..1 highlight bloom
  scanlines?: boolean
  timestamp?: boolean
  polaroidFrame?: boolean
  tint?: { color: string; alpha: number; blend: GlobalCompositeOperation }
}

export interface CameraStyle {
  id: string
  name: string
  tagline: string
  description: string
  tier: 'free' | 'premium'
  badge?: 'trending' | 'featured' | 'new'
  defaults: StyleParams
  character: StyleCharacter
  /** cheap CSS approximation for card thumbnails */
  cardFilter: string
  /** small accent gradient used on chips / selected glow */
  gradient: string
}

const P = (p: Partial<StyleParams>): StyleParams => ({
  intensity: 80,
  grain: 20,
  contrast: 50,
  warmth: 50,
  flash: 0,
  shadows: 30,
  smoothing: 0,
  ...p,
})

export const CAMERA_STYLES: CameraStyle[] = [
  {
    id: 'disposable',
    name: 'Disposable Camera',
    tagline: 'Warm flash. Zero regrets.',
    description: 'Warm flash, soft blur, imperfect exposure and that unmistakable nostalgic grain.',
    tier: 'free',
    badge: 'trending',
    defaults: P({ grain: 62, contrast: 57, warmth: 66, flash: 48, shadows: 34 }),
    character: {
      sepia: 0.18,
      saturate: 1.06,
      brightness: 1.04,
      blur: 0.7,
      fade: 0.28,
      halation: 0.22,
      tint: { color: '#ff9a3c', alpha: 0.08, blend: 'overlay' },
    },
    cardFilter: 'sepia(0.25) saturate(1.15) contrast(1.06) brightness(1.06)',
    gradient: 'linear-gradient(135deg,#ffb84d,#ff7a59)',
  },
  {
    id: 'iphone-flash',
    name: 'iPhone Flash',
    tagline: 'Nightlife, documented.',
    description: 'Bright direct flash, sharp subject, background falling into darkness. Social-night energy.',
    tier: 'free',
    defaults: P({ grain: 16, contrast: 62, warmth: 46, flash: 82, shadows: 62 }),
    character: {
      saturate: 1.03,
      brightness: 1.06,
      halation: 0.12,
    },
    cardFilter: 'contrast(1.18) brightness(1.12) saturate(1.05)',
    gradient: 'linear-gradient(135deg,#e8e8f2,#9aa0b4)',
  },
  {
    id: 'camcorder-90s',
    name: "90s Camcorder",
    tagline: 'REC ● 00:00:01',
    description: 'Lo-fi video softness, timestamp, scanlines, muted color and a hiss of analog noise.',
    tier: 'premium',
    defaults: P({ grain: 46, contrast: 47, warmth: 52, flash: 8, shadows: 28 }),
    character: {
      saturate: 0.78,
      brightness: 1.02,
      blur: 0.9,
      fade: 0.22,
      scanlines: true,
      timestamp: true,
      tint: { color: '#5a8f7b', alpha: 0.07, blend: 'overlay' },
    },
    cardFilter: 'saturate(0.75) contrast(0.95) brightness(1.04) blur(0.4px)',
    gradient: 'linear-gradient(135deg,#7de0b8,#3d8f9f)',
  },
  {
    id: 'leica-street',
    name: 'Leica Street',
    tagline: 'The decisive moment.',
    description: 'Clean contrast, honest skin tones, a whisper of film grain. Pure editorial street.',
    tier: 'free',
    defaults: P({ grain: 26, contrast: 60, warmth: 48, flash: 0, shadows: 44 }),
    character: {
      saturate: 0.94,
      brightness: 1.0,
      fade: 0.08,
    },
    cardFilter: 'contrast(1.14) saturate(0.92)',
    gradient: 'linear-gradient(135deg,#3c3c46,#c8c8d2)',
  },
  {
    id: 'gq-editorial',
    name: 'GQ Editorial',
    tagline: 'Cover-shoot energy.',
    description: 'Luxury magazine lighting, crisp shadows, polished skin. You, but on a newsstand.',
    tier: 'premium',
    badge: 'featured',
    defaults: P({ grain: 8, contrast: 64, warmth: 54, flash: 18, shadows: 52, smoothing: 38 }),
    character: {
      saturate: 1.08,
      brightness: 1.03,
      halation: 0.1,
      tint: { color: '#c9a24b', alpha: 0.05, blend: 'overlay' },
    },
    cardFilter: 'contrast(1.16) saturate(1.1) brightness(1.05)',
    gradient: 'linear-gradient(135deg,#e8c877,#9a6b2f)',
  },
  {
    id: 'a24-still',
    name: 'A24 Movie Still',
    tagline: 'Frame from a film that broke you.',
    description: 'Cinematic shadows, muted palette, soft highlights. Quiet, moody, devastating.',
    tier: 'free',
    badge: 'featured',
    defaults: P({ grain: 30, contrast: 55, warmth: 46, flash: 0, shadows: 58 }),
    character: {
      saturate: 0.8,
      brightness: 0.99,
      fade: 0.3,
      halation: 0.16,
      tint: { color: '#2a4a52', alpha: 0.12, blend: 'overlay' },
    },
    cardFilter: 'saturate(0.72) contrast(1.05) brightness(0.98)',
    gradient: 'linear-gradient(135deg,#3f6f78,#1d2a33)',
  },
  {
    id: 'film-noir',
    name: 'Film Noir',
    tagline: 'Trust no one.',
    description: 'Black and white, hard shadows, dramatic contrast. Vintage mystery in every frame.',
    tier: 'premium',
    defaults: P({ grain: 40, contrast: 76, warmth: 50, flash: 6, shadows: 72 }),
    character: {
      bw: true,
      brightness: 0.99,
      halation: 0.1,
      fade: 0.06,
    },
    cardFilter: 'grayscale(1) contrast(1.35)',
    gradient: 'linear-gradient(135deg,#f2f2f2,#101014)',
  },
  {
    id: 'y2k-digicam',
    name: 'Y2K Digicam',
    tagline: 'It’s 2003 and life is good.',
    description: 'Harsh flash, glossy highlights, slight overexposure. Early-2000s party immortality.',
    tier: 'premium',
    badge: 'trending',
    defaults: P({ grain: 20, contrast: 58, warmth: 45, flash: 72, shadows: 30 }),
    character: {
      saturate: 1.24,
      brightness: 1.1,
      blur: 0.3,
      fade: 0.1,
      halation: 0.3,
    },
    cardFilter: 'saturate(1.3) brightness(1.14) contrast(1.08)',
    gradient: 'linear-gradient(135deg,#7ad7ff,#c65cff)',
  },
  {
    id: 'polaroid',
    name: 'Polaroid',
    tagline: 'Shake it like a—you know.',
    description: 'Creamy highlights, soft faded color, instant-film frame. Warmth you can hold.',
    tier: 'free',
    defaults: P({ grain: 30, contrast: 43, warmth: 60, flash: 22, shadows: 24 }),
    character: {
      saturate: 0.85,
      brightness: 1.06,
      blur: 0.4,
      fade: 0.34,
      polaroidFrame: true,
      tint: { color: '#ffd9a0', alpha: 0.08, blend: 'overlay' },
    },
    cardFilter: 'saturate(0.85) brightness(1.08) contrast(0.92) sepia(0.12)',
    gradient: 'linear-gradient(135deg,#fff2dc,#f0b8a0)',
  },
]

export const getStyle = (id: string | null | undefined): CameraStyle | undefined =>
  CAMERA_STYLES.find((s) => s.id === id)

export interface QuickPreset {
  id: string
  name: string
  emoji: string
  apply: (d: StyleParams) => StyleParams
}

const clamp = (v: number) => Math.max(0, Math.min(100, Math.round(v)))

export const QUICK_PRESETS: QuickPreset[] = [
  {
    id: 'natural',
    name: 'Natural',
    emoji: '🌿',
    apply: (d) => ({
      ...d,
      intensity: 52,
      grain: clamp(d.grain * 0.55),
      smoothing: clamp(d.smoothing + 8),
    }),
  },
  {
    id: 'strong',
    name: 'Strong',
    emoji: '⚡',
    apply: (d) => ({
      ...d,
      intensity: 100,
      grain: clamp(d.grain + 14),
      contrast: clamp(d.contrast + 10),
      shadows: clamp(d.shadows + 10),
    }),
  },
  {
    id: 'viral',
    name: 'Viral',
    emoji: '🔥',
    apply: (d) => ({
      ...d,
      intensity: 92,
      flash: clamp(d.flash + 24),
      grain: clamp(d.grain + 8),
      warmth: clamp(d.warmth + 5),
      contrast: clamp(d.contrast + 8),
    }),
  },
  {
    id: 'cinematic',
    name: 'Cinematic',
    emoji: '🎬',
    apply: (d) => ({
      ...d,
      intensity: 86,
      shadows: clamp(d.shadows + 20),
      contrast: clamp(d.contrast + 5),
      warmth: clamp(d.warmth - 6),
      grain: clamp(d.grain + 6),
    }),
  },
  {
    id: 'editorial',
    name: 'Editorial',
    emoji: '🗞️',
    apply: (d) => ({
      ...d,
      intensity: 74,
      smoothing: clamp(d.smoothing + 26),
      contrast: clamp(d.contrast + 10),
      grain: clamp(d.grain * 0.4),
      shadows: clamp(d.shadows + 8),
    }),
  },
]

export const GENERATION_STEPS = [
  'Reading lighting…',
  'Rebuilding color profile…',
  'Matching camera mood…',
  'Adding grain…',
  'Developing…',
]
