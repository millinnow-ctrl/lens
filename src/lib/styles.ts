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
  /** 0..1 filmic S-curve — crushes blacks, rolls highlights */
  curve?: number
  /** color the shadows one way, the highlights another */
  splitTone?: { shadows: string; highlights: string; amount: number }
  /** chromatic fringe in px at 1000px reference width */
  fringe?: number
  /** 0..1 warm light leak bleeding in from one edge */
  leak?: number
  /** grain clump size multiplier — wet plate 1.8, slide film 0.7 */
  grainSize?: number
  /** 3×3 channel-crosstalk matrix (row-major, on 0–255) — the signature
   *  colour science of a stock: how its dye layers contaminate each other */
  colorMatrix?: number[]
  /** grain amplitude multiplier (default 1) */
  grainAmp?: number
  /** grain chroma / per-channel decorrelation, 0 = monochrome (default 0.4) */
  grainChroma?: number
  /** how this camera's metering/AWB electronics respond to the scene */
  lens?: LensResponse
}

/**
 * The camera behind the stock — how its meter and color electronics react
 * to the actual scene. Engine defaults cover every stock; a stock only
 * overrides what makes it *itself* (a disposable overexposes, noir meters
 * for highlights, a phone normalizes everything away).
 */
export interface LensResponse {
  /** EV offset from the mid target; + overexposes, − protects highlights */
  meterBias?: number
  /** 0..1 — how strongly the meter corrects (0 = fixed-exposure box camera) */
  meterStrength?: number
  /** 0..1 — face-priority metering weight when a face is present */
  faceWeight?: number
  /** 0..1 — fraction of the scene's color cast neutralized before the stock's palette */
  awb?: number
  /** max per-channel white-balance gain deviation (default 0.30) */
  awbClamp?: number
  /** 0..1 — how much halation concentrates onto detected light sources */
  lightHalation?: number
  /** 0..1 — adaptive dynamic-range recovery (smart-HDR shadow lift) */
  toneMap?: number
  /** 0..1 — face-aware subject separation; the lens's background falloff */
  dof?: number
  /** 0..1 — auto-ISO: how much grain rises as the scene darkens (real
   *  cameras push ISO in the dark; texture follows) */
  autoIso?: number
  /** 0..1 — local-contrast clarity; the "detail that bites" of digital
   *  compacts and editorial glass. 0 for soft dreamy stocks. */
  clarity?: number
  /** 0..1 — smart saturation recovery: muted scenes get their color back,
   *  vivid scenes are left alone, skin tones are guarded. 0 for stocks
   *  whose charm IS the mutedness. */
  vibrance?: number
  /** 0..1 — high-ISO shadow chroma suppression: in low light, deep shadows
   *  desaturate toward neutral the way a real sensor kills color noise */
  shadowDenoise?: number
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
  /** plausible viewfinder readout for this camera */
  exif: string
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
    exif: 'F/11 · 400 FILM · FLASH',
    name: 'Disposable Camera',
    tagline: 'Warm flash, soft grain',
    description: 'Warm flash, soft blur, imperfect exposure and that unmistakable nostalgic grain.',
    tier: 'free',
    badge: 'trending',
    defaults: P({ grain: 62, contrast: 57, warmth: 66, flash: 48, shadows: 34 }),
    character: {
      lens: { meterBias: 0.35, meterStrength: 0.7, awb: 0.3, lightHalation: 0.85, dof: 0.28 },
      grainSize: 1.3,
      colorMatrix: [1.06, -0.02, -0.02, -0.02, 1.0, 0.0, -0.03, 0.02, 1.0],
      grainChroma: 0.5,
      curve: 0.2,
      leak: 0.3,
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
    exif: 'F/1.8 · ISO 640 · FLASH',
    name: 'iPhone Flash',
    tagline: 'Hard flash, deep shadows',
    description: 'Bright direct flash, sharp subject, background falling into darkness. Social-night energy.',
    tier: 'free',
    defaults: P({ grain: 16, contrast: 62, warmth: 46, flash: 82, shadows: 62 }),
    character: {
      lens: { meterStrength: 0.85, faceWeight: 0.8, awb: 0.8, awbClamp: 0.45, dof: 0.32, toneMap: 0.7, clarity: 0.15, vibrance: 0.6, shadowDenoise: 0.75 },
      curve: 0.15,
      saturate: 1.03,
      brightness: 1.06,
      halation: 0.12,
    },
    cardFilter: 'contrast(1.18) brightness(1.12) saturate(1.05)',
    gradient: 'linear-gradient(135deg,#e8e8f2,#9aa0b4)',
  },
  {
    id: 'camcorder-90s',
    exif: 'REC · 30FPS · AUTO',
    name: "90s Camcorder",
    tagline: 'Soft tape, muted color',
    description: 'Lo-fi video softness, timestamp, scanlines, muted color and a hiss of analog noise.',
    tier: 'premium',
    defaults: P({ grain: 46, contrast: 47, warmth: 52, flash: 8, shadows: 28 }),
    character: {
      grainSize: 1.4,
      curve: 0.15,
      fringe: 1.4,
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
    exif: 'F/2 · ISO 400 · 35MM',
    name: 'Leica Street',
    tagline: 'Clean contrast, quiet grain',
    description: 'Clean contrast, honest skin tones, a whisper of film grain. Pure editorial street.',
    tier: 'free',
    defaults: P({ grain: 26, contrast: 60, warmth: 48, flash: 0, shadows: 44 }),
    character: {
      lens: { faceWeight: 0.7, dof: 0.55, toneMap: 0.6, clarity: 0.2, vibrance: 0.5 },
      curve: 0.3,
      saturate: 0.94,
      brightness: 1.0,
      fade: 0.08,
    },
    cardFilter: 'contrast(1.14) saturate(0.92)',
    gradient: 'linear-gradient(135deg,#3c3c46,#c8c8d2)',
  },
  {
    id: 'gq-editorial',
    exif: 'F/8 · ISO 100 · STROBE',
    name: 'GQ Editorial',
    tagline: 'Polished light, crisp shadows',
    description: 'Luxury magazine lighting, crisp shadows, polished skin. You, but on a newsstand.',
    tier: 'premium',
    defaults: P({ grain: 8, contrast: 64, warmth: 54, flash: 18, shadows: 52, smoothing: 38 }),
    character: {
      lens: { meterStrength: 0.9, faceWeight: 0.85, awb: 0.85, dof: 0.85, toneMap: 0.4, clarity: 0.2, autoIso: 0.15, vibrance: 0.55, shadowDenoise: 0.5 },
      grainSize: 0.6,
      colorMatrix: [1.05, 0.0, -0.03, -0.01, 1.0, 0.0, -0.02, -0.02, 1.03],
      curve: 0.25,
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
    exif: 'F/2.8 · ISO 800 · 1/48',
    name: 'A24 Movie Still',
    tagline: 'Muted color, soft highlights',
    description: 'Cinematic shadows, muted palette, soft highlights. Quiet, moody, devastating.',
    tier: 'free',
    badge: 'featured',
    defaults: P({ grain: 30, contrast: 55, warmth: 46, flash: 0, shadows: 58 }),
    character: {
      lens: { meterBias: -0.1, faceWeight: 0.7, awb: 0.5, dof: 0.7, toneMap: 0.7, vibrance: 0.2 },
      curve: 0.25,
      colorMatrix: [0.92, 0.06, 0.02, 0.03, 0.94, 0.03, 0.03, 0.05, 0.94],
      splitTone: { shadows: '#164e63', highlights: '#fcd34d', amount: 0.4 },
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
    exif: 'F/5.6 · ISO 400 · B&W',
    name: 'Film Noir',
    tagline: 'Hard light, deep blacks',
    description: 'Black and white, hard shadows, dramatic contrast. Vintage mystery in every frame.',
    tier: 'premium',
    defaults: P({ grain: 40, contrast: 76, warmth: 50, flash: 6, shadows: 72 }),
    character: {
      lens: { meterBias: -0.45, meterStrength: 0.75, faceWeight: 0.7, dof: 0.5, toneMap: 0 },
      grainSize: 1.15,
      curve: 0.55,
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
    exif: 'F/2.6 · ISO 200 · FLASH',
    name: 'Y2K Digicam',
    tagline: 'Glossy flash, bright color',
    description: 'Harsh flash, glossy highlights, slight overexposure. Early-2000s party immortality.',
    tier: 'premium',
    badge: 'trending',
    defaults: P({ grain: 20, contrast: 58, warmth: 45, flash: 72, shadows: 30 }),
    character: {
      curve: 0.2,
      fringe: 1.8,
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
    exif: 'F/8 · 600 FILM · INSTANT',
    name: 'Polaroid',
    tagline: 'Creamy light, faded color',
    description: 'Creamy highlights, soft faded color, instant-film frame. Warmth you can hold.',
    tier: 'free',
    defaults: P({ grain: 30, contrast: 43, warmth: 60, flash: 22, shadows: 24 }),
    character: {
      lens: { meterBias: 0.2, meterStrength: 0.6, awb: 0.4, dof: 0.3, vibrance: 0.1 },
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
  {
    id: 'super-8',
    exif: 'REC · 18FPS · 8MM',
    name: 'Super 8',
    tagline: 'Warm grain, home-movie glow',
    description: 'Faded warmth, thick grain and a soft flicker of light. Summers that never ended.',
    tier: 'premium',
    defaults: P({ grain: 58, contrast: 52, warmth: 68, flash: 0, shadows: 40 }),
    character: {
      grainSize: 1.5,
      curve: 0.25,
      leak: 0.55,
      saturate: 0.9,
      brightness: 1.03,
      blur: 0.8,
      fade: 0.3,
      halation: 0.24,
      tint: { color: '#ff8c42', alpha: 0.1, blend: 'overlay' },
      lens: { vibrance: 0.1 },
    },
    cardFilter: 'sepia(0.22) saturate(1.02) contrast(0.97) brightness(1.05) blur(0.3px)',
    gradient: 'linear-gradient(135deg,#ffc46b,#d96f32)',
  },
  {
    id: 'lomo',
    exif: 'F/2.8 · 400 FILM · ZONE',
    name: 'Lomo',
    tagline: 'Punchy color, dark corners',
    description: 'Oversaturated color, crushed vignette corners and happy accidents. Toy-camera magic.',
    tier: 'free',
    badge: 'new',
    defaults: P({ grain: 36, contrast: 66, warmth: 52, flash: 0, shadows: 78 }),
    character: {
      grainSize: 1.2,
      curve: 0.45,
      fringe: 2.2,
      leak: 0.5,
      splitTone: { shadows: '#14532d', highlights: '#fef08a', amount: 0.55 },
      saturate: 1.35,
      hue: -8,
      brightness: 1.02,
      fade: 0.06,
      tint: { color: '#1f6f5b', alpha: 0.16, blend: 'overlay' },
    },
    cardFilter: 'saturate(1.45) contrast(1.18) hue-rotate(-8deg)',
    gradient: 'linear-gradient(135deg,#37c978,#0e5a46)',
  },
  {
    id: 'kodachrome',
    exif: 'F/5.6 · K64 SLIDE · 1/125',
    name: 'Kodachrome',
    tagline: 'Rich color, clean shadows',
    description: 'The slide film that shot the sixties — dense reds, honest light, shadows that hold.',
    tier: 'premium',
    defaults: P({ grain: 18, contrast: 62, warmth: 58, flash: 0, shadows: 46 }),
    character: {
      lens: { meterBias: -0.15, awb: 0.45, dof: 0.55, toneMap: 0.6, vibrance: 0.7 },
      grainSize: 0.7,
      colorMatrix: [1.14, -0.06, -0.05, -0.06, 1.07, -0.03, -0.04, -0.09, 1.08],
      grainChroma: 0.25,
      curve: 0.4,
      splitTone: { shadows: '#7f1d1d', highlights: '#fde68a', amount: 0.45 },
      saturate: 1.22,
      brightness: 1.0,
      fade: 0.04,
      halation: 0.06,
      tint: { color: '#d9a441', alpha: 0.06, blend: 'overlay' },
    },
    cardFilter: 'saturate(1.28) contrast(1.12) sepia(0.08)',
    gradient: 'linear-gradient(135deg,#e8534a,#8f2d1e)',
  },
  {
    id: 'security-cam',
    exif: 'CAM 02 · 12FPS · IR',
    name: 'Security Cam',
    tagline: 'Grainy green, timestamped',
    description: 'Fluorescent wash, analog noise and a running timestamp. Caught on tape, forever.',
    tier: 'premium',
    defaults: P({ grain: 70, contrast: 58, warmth: 40, flash: 0, shadows: 36 }),
    character: {
      lens: { meterStrength: 0.9, awb: 0.9, awbClamp: 0.45, dof: 0, toneMap: 0.2, clarity: 0.25, autoIso: 0.9, vibrance: 0, shadowDenoise: 0.9 },
      grainSize: 1.5,
      curve: 0.35,
      saturate: 0.35,
      brightness: 1.05,
      blur: 1.1,
      fade: 0.18,
      scanlines: true,
      timestamp: true,
      tint: { color: '#3fae6a', alpha: 0.12, blend: 'overlay' },
    },
    cardFilter: 'saturate(0.4) brightness(1.08) contrast(1.05) blur(0.5px)',
    gradient: 'linear-gradient(135deg,#7de8a9,#2e4d3a)',
  },
  {
    id: 'point-shoot',
    exif: 'F/1.8 · 1.0″ CMOS · 24MM',
    name: 'Point & Shoot',
    tagline: 'Crisp flash, glossy color',
    description:
      'The pocket vlogger’s compact — hard little flash, glossy color, detail that bites. Every night out looks like a press event.',
    tier: 'premium',
    badge: 'new',
    defaults: P({ grain: 10, contrast: 60, warmth: 48, flash: 55, shadows: 50 }),
    character: {
      // the "model": a computational little camera — strong auto-everything,
      // deep focus (tiny sensor), cool-white flash, clean noise not film grain
      lens: {
        meterStrength: 0.85,
        faceWeight: 0.8,
        awb: 0.7,
        awbClamp: 0.45,
        toneMap: 0.5,
        dof: 0.2,
        lightHalation: 0.5,
        clarity: 0.35,
        autoIso: 0.4,
        vibrance: 0.75,
        shadowDenoise: 0.7,
      },
      curve: 0.2,
      colorMatrix: [1.08, -0.04, -0.04, -0.03, 1.06, -0.03, -0.04, -0.02, 1.06],
      saturate: 1.14,
      brightness: 1.05,
      grainSize: 0.7,
      grainChroma: 0.2,
      halation: 0.1,
      tint: { color: '#dbe9ff', alpha: 0.06, blend: 'overlay' },
    },
    cardFilter: 'saturate(1.16) contrast(1.12) brightness(1.06)',
    gradient: 'linear-gradient(135deg,#d8dee8,#2a2e36)',
  },
  {
    id: 'pastel-cinema',
    exif: 'F/4 · ISO 100 · SYM',
    name: 'Pastel Cinema',
    tagline: 'Powdery color, flat light',
    description: 'Flat storybook light and powdery pastels. Every frame arranged just so.',
    tier: 'free',
    defaults: P({ grain: 12, contrast: 40, warmth: 55, flash: 0, shadows: 16, smoothing: 20 }),
    character: {
      grainSize: 0.75,
      saturate: 0.88,
      brightness: 1.08,
      fade: 0.34,
      halation: 0.08,
      blur: 0.2,
      tint: { color: '#ffd7e0', alpha: 0.1, blend: 'overlay' },
      lens: { vibrance: 0.1 },
    },
    cardFilter: 'saturate(0.85) brightness(1.1) contrast(0.88)',
    gradient: 'linear-gradient(135deg,#ffd7e0,#b8e6d9)',
  },
  {
    id: 'tokyo-neon',
    exif: 'F/1.4 · ISO 1600 · NIGHT',
    name: 'Tokyo Neon',
    tagline: 'Neon bloom, wet streets',
    description: 'Pink and cyan bloom on wet pavement, blacks that swallow the rest. 2 a.m. forever.',
    tier: 'premium',
    badge: 'trending',
    defaults: P({ grain: 26, contrast: 66, warmth: 38, flash: 0, shadows: 62 }),
    character: {
      lens: { meterBias: -0.3, awb: 0.15, lightHalation: 1.0, dof: 0.55, toneMap: 0.15, autoIso: 0.8, vibrance: 0.8, shadowDenoise: 0.25 },
      curve: 0.35,
      colorMatrix: [1.04, -0.02, 0.02, -0.03, 1.0, 0.02, 0.03, 0.02, 1.05],
      splitTone: { shadows: '#312e81', highlights: '#f0abfc', amount: 0.8 },
      fringe: 1.6,
      saturate: 1.3,
      hue: -10,
      brightness: 0.98,
      halation: 0.4,
      fade: 0.05,
      blur: 0.2,
      tint: { color: '#4338ca', alpha: 0.12, blend: 'overlay' },
    },
    cardFilter: 'saturate(1.35) contrast(1.2) hue-rotate(-10deg) brightness(0.96)',
    gradient: 'linear-gradient(135deg,#22d3ee,#e879f9)',
  },
  {
    id: 'photobooth',
    exif: 'STRIP · 4 FRAMES · B&W',
    name: 'Photobooth',
    tagline: 'Hard flash, true black & white',
    description: 'Curtain, flash, four frames. High-key black and white that flatters everyone.',
    tier: 'free',
    badge: 'new',
    defaults: P({ grain: 34, contrast: 70, warmth: 50, flash: 66, shadows: 44, smoothing: 12 }),
    character: {
      curve: 0.45,
      bw: true,
      brightness: 1.08,
      halation: 0.12,
      fade: 0.04,
    },
    cardFilter: 'grayscale(1) contrast(1.25) brightness(1.1)',
    gradient: 'linear-gradient(135deg,#ffffff,#3a3a42)',
  },
  {
    id: 'tintype',
    exif: 'WET PLATE · 5S EXP',
    name: 'Tintype 1900',
    tagline: 'Sepia plate, deep vignette',
    description: 'Wet-plate sepia, scratched edges, a vignette like candlelight. Portraits that outlive you.',
    tier: 'premium',
    defaults: P({ grain: 64, contrast: 60, warmth: 60, flash: 0, shadows: 84 }),
    character: {
      // a box camera has no electronics: weak fixed meter, no AWB, no HDR
      lens: { meterStrength: 0.35, awb: 0.15, toneMap: 0, lightHalation: 0.3 },
      grainSize: 1.8,
      curve: 0.5,
      sepia: 0.85,
      saturate: 0.6,
      brightness: 0.98,
      blur: 0.5,
      fade: 0.12,
      halation: 0.08,
    },
    cardFilter: 'sepia(0.85) contrast(1.1) brightness(0.97)',
    gradient: 'linear-gradient(135deg,#c9a05c,#4a321b)',
  },
]

export const getStyle = (id: string | null | undefined): CameraStyle | undefined =>
  CAMERA_STYLES.find((s) => s.id === id)

export interface QuickPreset {
  id: string
  name: string
  apply: (d: StyleParams) => StyleParams
}

const clamp = (v: number) => Math.max(0, Math.min(100, Math.round(v)))

export const QUICK_PRESETS: QuickPreset[] = [
  {
    id: 'natural',
    name: 'Natural',
    apply: (d) => ({
      ...d,
      intensity: 52,
      grain: clamp(d.grain * 0.55),
      smoothing: clamp(d.smoothing + 8),
    }),
  },
  {
    id: 'strong',
    name: 'Push',
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
    name: 'Punch',
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

/** compact param encoding for shareable transformation links */
const PARAM_ORDER: (keyof StyleParams)[] = [
  'intensity',
  'grain',
  'contrast',
  'warmth',
  'flash',
  'shadows',
  'smoothing',
]

export const encodeParams = (p: StyleParams): string => PARAM_ORDER.map((k) => p[k]).join('.')

export function decodeParams(raw: string | null): StyleParams | null {
  if (!raw) return null
  const parts = raw.split('.').map(Number)
  if (parts.length !== PARAM_ORDER.length || parts.some((n) => !Number.isFinite(n))) return null
  const p = {} as StyleParams
  PARAM_ORDER.forEach((k, i) => {
    p[k] = Math.max(0, Math.min(100, Math.round(parts[i])))
  })
  return p
}

export const GENERATION_STEPS = [
  'Reading lighting…',
  'Rebuilding color profile…',
  'Matching camera mood…',
  'Adding grain…',
  'Developing…',
]
