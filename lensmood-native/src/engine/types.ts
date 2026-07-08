/**
 * LensMood shared types — the single source of truth imported as
 * `@/engine/types` by the styles data, the scene meter, the Skia develop
 * engine, and every screen. Ported 1:1 from the web app's src/lib/{styles,
 * scene,engine,focal}.ts, with the browser-only types adapted for React
 * Native + Skia (see CompositeOperation and RenderOptions below).
 *
 * Keep this module dependency-free (types + plain consts only). styles.ts is
 * pure data and scene.ts is pure pixel math; neither should be forced to
 * import Skia just to name a type.
 */

/* ------------------------------------------------------------ blend modes */

/**
 * The subset of canvas composite operations the stock palettes actually use.
 * On the web this was the DOM `GlobalCompositeOperation`; here it is a closed
 * string union so the ported styles.ts data (`blend: 'overlay'`) stays
 * byte-for-byte identical. The Skia engine maps each value to an SkBlendMode:
 *   source-over -> SrcOver, multiply -> Multiply, screen -> Screen,
 *   overlay -> Overlay, lighten -> Lighten, darken -> Darken,
 *   destination-out -> DstOut.
 */
export type CompositeOperation =
  | 'source-over'
  | 'multiply'
  | 'screen'
  | 'overlay'
  | 'soft-light'
  | 'lighten'
  | 'darken'
  | 'destination-out'

/* --------------------------------------------------------------- sliders */

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

/* --------------------------------------------------------- stock character */

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
  tint?: { color: string; alpha: number; blend: CompositeOperation }
  /** 0..1 filmic S-curve — crushes blacks, rolls highlights */
  curve?: number
  /** color the shadows one way, the highlights another */
  splitTone?: { shadows: string; highlights: string; amount: number }
  /** chromatic fringe in px at 1000px reference width */
  fringe?: number
  /** lens physics — how this stock's GLASS misbehaves (all 0..1, 0 = off).
   *  Color science is the film; this is the lens bolted in front of it. */
  optics?: {
    /** lateral chromatic aberration: fringes growing toward the corners */
    ca?: number
    /** field curvature: corners drift soft while the center stays crisp */
    cornerSoft?: number
    /** barrel distortion: cheap wide glass bows straight lines outward */
    distortion?: number
    /** flare anisotropy: per-light halation streaks outward from center */
    flareAniso?: number
  }
  /** 0..1 warm light leak bleeding in from one edge */
  leak?: number
  /** grain clump size multiplier — wet plate 1.8, slide film 0.7 */
  grainSize?: number
  /** 3×3 channel-crosstalk matrix (row-major, on 0–255) — the signature
   *  colour science of a stock: how its dye layers contaminate each other */
  colorMatrix?: number[]
  /** per-stock colour science: six hue bands (R/Y/G/C/B/M), each with its
   *  own saturation and luminance delta (-1..1), interpolated per-pixel. */
  bands?: { sat: number[]; lum: number[] }
  /** grain amplitude multiplier (default 1) */
  grainAmp?: number
  /** grain chroma / per-channel decorrelation, 0 = monochrome (default 0.4) */
  grainChroma?: number
  /** how this camera's metering/AWB electronics respond to the scene */
  lens?: LensResponse
  /** per-channel film dye transfer — each channel's [shadowShift, highlightShift]
   *  in ~-0.3..0.3. Cross-process casts, teal-shadow dyes, a highlight channel
   *  that clips before the others: a per-channel transfer no slider produces. */
  channelCurves?: { r: [number, number]; g: [number, number]; b: [number, number] }
  /** low print DMax (0..0.25): blacks clamp up to this floor — instant film and
   *  cheap processes never reach true black. A chemistry limit, not a fade fill. */
  dmax?: number
  /** analog-video signal artifacts — a signal-domain look no slider produces.
   *  bleed: horizontal chroma smear (VHS color bandwidth, color drags sideways
   *  past edges while luma stays sharp). dropout: bright tape-dropout streaks.
   *  interlace: even/odd field comb offset (CCTV / interlaced video). */
  video?: { bleed?: number; dropout?: number; interlace?: number }
  /** palette / motivated colour — a colourist move, not a slider. anchors+snap
   *  steers every hue toward a coordinated set (pastel); keepHue+keepWidth+crush
   *  protects one hue at full chroma and drains the rest. Skin is always exempt. */
  palette?: { anchors?: number[]; snap?: number; keepHue?: number; keepWidth?: number; crush?: number }
  /** spectral black & white — channel weights [wr,wg,wb] for the mono mix, so a
   *  red-blind (orthochromatic/silver-gelatin) response can render reds dark and
   *  separate skin/lips tonally. Overrides the flat luma grayscale. */
  bwMix?: [number, number, number]
  /** subject chiaroscuro — synthesize a directional key across the subject mask
   *  using the low-freq luma: deepen the shadow side, hold the key side, and
   *  crush true blacks only OFF-subject. Models the figure by light (0..~0.7). */
  chiaroscuro?: number
  /** edge-local chromatic fringing — bloom violet/green into the dark side of
   *  high-gradient edges (CCD colour crosstalk), independent of image radius,
   *  plus light block quantisation. { fringe, block } each 0..1. */
  edgeFringe?: { fringe?: number; block?: number }
  /** highlight shoulder — film rolloff on the brightest zones so flash/halation
   *  don't clip to blinding white; compresses the top end and tints the
   *  recovered headroom toward this stock's highlight tone. Defaults ~0.62;
   *  set 0 to opt a stock out (e.g. a stark surveillance blowout). 0..1. */
  highlightGuard?: number
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
  /** 0..1 — flash-on-skin relighting: with a face locked and the flash up,
   *  existing facial highlights catch the light and a soft catchlight
   *  blooms — light interacting with skin, not a white overlay. */
  skinGlow?: number
  /** 0..1 — RELIGHT: how hard the on-camera flash lifts the subject along its
   *  real silhouette (not a disc). Driven together with the flash dial. */
  flashStrength?: number
  /** 0..1 — how fast the background falls to black by distance from the
   *  subject (inverse-square-ish); the depth the flash carves. Runs at low
   *  level for available-light stocks so the subject still reads. */
  flashFalloff?: number
  /** 0..1 — reflective specular pop on the lit subject: skin, jewelry and
   *  oily highlights catch the flash the way real reflectance does. */
  flashSpecular?: number
  /** 0..1 — flash white balance: how much the lit subject is pulled toward
   *  neutral-cool (~5500K) while the background keeps its ambient cast. */
  flashCool?: number
  /** capsule spread — how wide the subject mask reaches past the face over the
   *  torso (≈0.8 tight head-and-shoulders … ≈2.4 loose). Default 1.4. */
  flashSpread?: number
}

/* ------------------------------------------------------------- the stock */

export type StyleTier = 'free' | 'premium'
export type StyleBadge = 'trending' | 'featured' | 'new'

export interface CameraStyle {
  id: string
  name: string
  tagline: string
  description: string
  tier: StyleTier
  badge?: StyleBadge
  defaults: StyleParams
  character: StyleCharacter
  /** cheap CSS approximation for card thumbnails (web legacy; unused on native
   *  render but kept so the ported data stays identical) */
  cardFilter: string
  /** plausible viewfinder readout for this camera */
  exif: string
  /** small accent gradient used on chips / selected glow (CSS gradient string) */
  gradient: string
}

/* -------------------------------------------------------------- the meter */

export interface Focal {
  /** face center, normalized 0..1 */
  x: number
  y: number
  /** face radius as a fraction of the longest edge */
  r: number
}

export interface LightSource {
  /** normalized center, 0..1 of frame */
  x: number
  y: number
  /** blob radius as a fraction of the longest edge */
  r: number
  /** 0..1 — how hot the blob's peak burns above the specular threshold */
  intensity: number
  /** the light's true color, sampled on the glow annulus around the clipped
   *  core (the core itself is blown white) — [r,g,b] 0..1 */
  tint: [number, number, number]
}

export interface SceneProfile {
  /** false for the neutral fallback — adaptive passes that would otherwise
   *  misread the placeholder percentiles must check this */
  analyzed: boolean
  /** log-average luminance, 0..1 — the meter's reading of the scene key */
  key: number
  p01: number
  p50: number
  p99: number
  /** white-balance gains [r, g, b], luma-preserving (never change exposure) */
  illum: [number, number, number]
  /** mean pixel saturation 0..1 — how much color the scene actually has;
   *  drives vibrance recovery on muted uploads */
  sat: number
  /** up to 5 detected light sources, largest energy first */
  lights: LightSource[]
  /** mean luminance under the face ellipse, when a face was found */
  faceLum: number | null
}

/** neutral profile — what `scene: null` and failed analysis fall back to */
export const NEUTRAL_SCENE: SceneProfile = {
  analyzed: false,
  key: 0.4,
  p01: 0,
  p50: 0.4,
  p99: 1,
  illum: [1, 1, 1],
  sat: 0.35,
  lights: [],
  faceLum: null,
}

/* ------------------------------------------------------------ render I/O */

export interface RenderOptions {
  /** longest edge of the output; source is downscaled to fit */
  maxSize?: number
  watermark?: boolean
  /** jitter the grain pattern per call so video grain flickers like film
   *  (M1: stills only; kept for parity with the web engine's video path) */
  animateGrain?: boolean
  /** face lock (normalized) — flash centers here, smoothing stays on skin */
  focal?: Focal | null
  /** precomputed scene profile; omit to analyze (cached), null to disable
   *  the adaptive lens entirely */
  scene?: SceneProfile | null
  /** draw the instant-film paper frame (default true); the compare view
   *  renders a frameless companion so the wipe stays pixel-aligned */
  frame?: boolean
  /** per-shot dial overrides from the Pro Camera (ƒ→dof, EV→meterBias,
   *  ISO→autoIso, WB→awb) — merged over the stock's lens response */
  lensOverride?: Partial<LensResponse>
  /** seconds into a tape — when set, timestamped stocks burn a counting
   *  REC timecode instead of a static clock (parity field; video is web) */
  time?: number

  // NOTE — web-only field intentionally dropped in the native port:
  //   target?: HTMLCanvasElement  → the Skia engine allocates its own
  //   offscreen surface per develop (Skia.Surface.MakeOffscreen), so there is
  //   no reusable DOM canvas to thread through.
}

/**
 * The develop pipeline's output contract — Skia-agnostic on purpose so the
 * develop screen and the export/share flow can consume it without importing
 * @shopify/react-native-skia. The engine renders to an offscreen Skia surface,
 * encodes a JPEG, writes it to the cache directory, and returns this.
 */
export interface DevelopResult {
  /** local file:// URI of the encoded JPEG in cache (feed to <Image>, Sharing,
   *  and MediaLibrary.saveToLibraryAsync) */
  uri: string
  /** pixel dimensions of the developed frame (after downscale / any frame) */
  width: number
  height: number
}
