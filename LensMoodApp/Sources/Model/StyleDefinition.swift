import Foundation

/// A structured, human-readable identity for each of LensMood's 18 film "stocks".
///
/// This is intentionally a pure-value description layer — no dependency on
/// `CameraRecipe`, `Stock`, or any engine type. It answers *why a look exists*
/// and *what it should and should not do*, so a user understands the intent and
/// engine work has a spec to grade against. Numeric behavior still lives in
/// `CameraRecipe`; this is the prose/contract that recipe is meant to satisfy.
///
/// Every field is a concise concrete phrase (String / [String] / Bool), so the
/// file compiles with zero external types.
struct StyleDefinition: Identifiable, Equatable {
  /// Stable engine id — matches `Stock.id` / `CameraRecipe.id` exactly.
  let id: String
  /// Display name.
  let name: String

  /// One-line palette / color-signature description.
  let palette: String
  /// True for looks that resolve to black & white (or near-mono metal).
  let isMonochrome: Bool
  /// How the B&W mix behaves (spectral response, toning). Empty for color stocks.
  let bwBehavior: String

  let whiteBalance: String
  let exposure: String
  let contrastCurve: String
  let highlightRolloff: String
  let shadowTreatment: String
  let saturation: String
  let grain: String
  let halation: String
  let bloom: String
  let vignette: String
  let sharpness: String
  let lensSoftness: String
  /// Hue/channel shifts, split-tone, and colour-science moves.
  let colorShifts: String
  /// How aggressively skin tones are protected from the look.
  let skinToneProtection: String

  let era: String
  /// The real camera / film / medium this look references.
  let cameraInspiration: String
  let emotionalTone: String
  /// What this style is for.
  let suitableSubjects: [String]
  /// Visual elements this style must NOT produce (guard rails).
  let avoid: [String]
}

extension StyleDefinition {
  static let all: [StyleDefinition] = [

    // 1 ────────────────────────────────────────────────────── disposable
    StyleDefinition(
      id: "disposable",
      name: "Disposable",
      palette: "Warm Gold-800 party palette — vivid reds and yellows, punchy but never sepia-washed",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Warm flash, only lightly neutralized; keeps the amber room cast",
      exposure: "Modest face lift over inconsistent, uneven background falloff",
      contrastCurve: "Punchy consumer-negative S-curve; lively midtones",
      highlightRolloff: "Hot flash cores allowed to bloom rather than clip harshly",
      shadowTreatment: "Distant subjects stay dark; shadows kept but slightly lifted",
      saturation: "Elevated, cheerful color; reds and yellows lead",
      grain: "Soft, visible chunky grain (ISO-800 consumer stock)",
      halation: "Mild warm halation around flash highlights",
      bloom: "Gentle bloom on bright flash areas",
      vignette: "Plastic-lens corner falloff",
      sharpness: "Casual center sharpness, not clinical",
      lensSoftness: "Soft plastic-lens corners with mild CA and distortion",
      colorShifts: "Split-tone: warm-brown shadows, golden highlights; subtle amber tint; light warm edge leak",
      skinToneProtection: "High — faces lifted and kept warm and recognisable",
      era: "1990s–2000s single-use party camera",
      cameraInspiration: "Kodak FunSaver / Fujifilm QuickSnap single-use flash camera on Gold 800",
      emotionalTone: "Nostalgic, spontaneous, affectionate",
      suitableSubjects: ["Friends after dark", "Candid close groups", "House parties", "Nights out"],
      avoid: ["Sepia/monochrome wash", "Clean even studio light", "Perfect corners", "Muted or desaturated color"]
    ),

    // 2 ────────────────────────────────────────────────────── iphone-flash
    StyleDefinition(
      id: "iphone-flash",
      name: "Direct Flash",
      palette: "Neutral-cool True Tone color, clean and glossy",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Strong AWB, cool-neutral white flash (~5500K), background barely warm",
      exposure: "Aggressive subject priority with deliberately fast background falloff",
      contrastCurve: "Hard microcontrast, crisp digital response",
      highlightRolloff: "Reflective skin/objects may clip before background opens",
      shadowTreatment: "Backgrounds fall into deep darkness; mild HDR shadow recovery on subject",
      saturation: "Slightly boosted, clean modern color",
      grain: "Almost none (low-ISO computational capture)",
      halation: "Minimal",
      bloom: "Very slight",
      vignette: "Essentially none",
      sharpness: "Clinically crisp",
      lensSoftness: "None — corners stay sharp",
      colorShifts: "Cool split-tone: blue-grey shadows, warm-white highlights; faint warm skin tint",
      skinToneProtection: "Very high — nearest face is the exposure anchor",
      era: "2015–present smartphone night flash",
      cameraInspiration: "iPhone LED True Tone flash / computational night portrait",
      emotionalTone: "Immediate, unfiltered, social-night energy",
      suitableSubjects: ["Night portraits", "Bar and club close-ups", "One clear subject in the dark"],
      avoid: ["Warm nostalgic cast", "Heavy grain", "Lifted milky shadows", "Vintage softness"]
    ),

    // 3 ────────────────────────────────────────────────────── camcorder-90s
    StyleDefinition(
      id: "camcorder-90s",
      name: "Tape 94",
      palette: "Muted tube color with green-grey drift and chroma-bled edges",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Loose auto white balance, slight green tube contamination",
      exposure: "Slow auto-gain breathing; never hard black cutouts",
      contrastCurve: "Low, soft video gamma",
      highlightRolloff: "Blooming, smeary tube highlights",
      shadowTreatment: "Smoky-but-dark shadows carrying crawling luminance noise",
      saturation: "Reduced, washed tape color",
      grain: "Coarse crawling video noise",
      halation: "Soft tube glow around brights",
      bloom: "Smeary highlight bloom",
      vignette: "Restrained soft corners",
      sharpness: "Low apparent resolution, soft edges",
      lensSoftness: "Soft, with visible chroma-bleed fringing",
      colorShifts: "VHS signature: horizontal chroma bleed, tape dropout, burned-in timestamp, scanline character even as a still",
      skinToneProtection: "Low-moderate — the tape look outranks flattery",
      era: "Early-to-mid 1990s home video",
      cameraInspiration: "VHS-C / Hi8 consumer camcorder recording to tape",
      emotionalTone: "Domestic, wistful, recorded-time memory",
      suitableSubjects: ["Moving memories", "Domestic interiors", "Home-video moments"],
      avoid: ["Clean sharp HD detail", "Vivid saturated color", "Stable clinical exposure", "Absence of tape artifacts"]
    ),

    // 4 ────────────────────────────────────────────────────── leica-street
    StyleDefinition(
      id: "leica-street",
      name: "Street 35",
      palette: "Honest neutrals — Portra-like skin over Tri-X tonal bones",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Accurate AWB, honest neutrals",
      exposure: "Restrained metering biased to protect highlights, gentle face awareness",
      contrastCurve: "Restrained editorial S-curve, true blacks",
      highlightRolloff: "Protected highlight structure, no blow-out",
      shadowTreatment: "True blacks held; difficult light stays difficult",
      saturation: "Quiet, slightly reduced — no exaggeration",
      grain: "Fine, quiet 35mm grain",
      halation: "Almost none",
      bloom: "None to negligible",
      vignette: "Subtle corner falloff",
      sharpness: "Crisp micro-contrast, biting detail",
      lensSoftness: "Sharp fast-prime rendering, minimal aberration",
      colorShifts: "Neutral split-tone: warm-black shadows, cream highlights; no hue push",
      skinToneProtection: "High — honest, natural skin",
      era: "Timeless mid-century-to-now reportage",
      cameraInspiration: "Leica M with 35mm summicron, available light, Portra/Tri-X sensibility",
      emotionalTone: "Quiet, observational, dignified",
      suitableSubjects: ["Candid street work", "Window light", "Available-light portraits", "Documentary frames"],
      avoid: ["Cosmetic smoothing", "Oversaturation", "Glossy Instagram punch", "Heavy vignette or fringe"]
    ),

    // 5 ────────────────────────────────────────────────────── gq-editorial
    StyleDefinition(
      id: "gq-editorial",
      name: "Editorial Strobe",
      palette: "Bronze-gold skin with luminous warmth over espresso shadows",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Controlled warm-neutral, polished but not plastic",
      exposure: "Shaped strobe contrast with held facial highlights",
      contrastCurve: "Crisp editorial contrast, deep controlled shadows",
      highlightRolloff: "Clean specular control on skin and fabric",
      shadowTreatment: "Espresso shadows that stay deep and shaped, not muddy",
      saturation: "Restrained, disciplined color",
      grain: "Very fine to none — glossy",
      halation: "Slight, controlled",
      bloom: "Minimal",
      vignette: "Very slight, clean",
      sharpness: "High, retouched clarity",
      lensSoftness: "Clean optics, negligible aberration",
      colorShifts: "Warm gold split-tone; subtle bronze skin tint; strong directional key from upper-left",
      skinToneProtection: "Very high — face structure and fabric detail protected",
      era: "Contemporary magazine studio",
      cameraInspiration: "Medium-format studio digital with profoto strobe, GQ/fashion newsstand grade",
      emotionalTone: "Polished, aspirational, composed",
      suitableSubjects: ["Structured portraits", "Fashion-like scenes", "Composed studio frames"],
      avoid: ["Flat ambient snapshot look", "Heavy grain", "Muddy shadows", "Casual softness"]
    ),

    // 6 ────────────────────────────────────────────────────── a24-still
    StyleDefinition(
      id: "a24-still",
      name: "Independent Still",
      palette: "Muted teal-leaning palette with living skin — quiet melancholia",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Partial neutralization; scene cast respected, gently warm when the light asks",
      exposure: "Slight underexposure with open narrative shadows",
      contrastCurve: "Low, matte contrast — a gentle matte, not milk",
      highlightRolloff: "Soft rolloff on highlights, no clinical recovery",
      shadowTreatment: "Teal-leaning shadows that stay shadows; blacks lifted to a low matte floor",
      saturation: "Intentionally muted, scene-respectful",
      grain: "Moderate fine grain",
      halation: "Soft halation on brights",
      bloom: "Gentle bloom",
      vignette: "Light corner falloff",
      sharpness: "Softly detailed, unshowy",
      lensSoftness: "Mild corner drift and anamorphic-ish flare",
      colorShifts: "Real teal-and-orange grade via per-channel curves: teal shadows, warm highlights; hue-protected sky band",
      skinToneProtection: "High — skin stays alive inside the muted grade",
      era: "2010s–present independent cinema",
      cameraInspiration: "A24-style ARRI Alexa narrative still, muted colourist grade",
      emotionalTone: "Melancholic, quiet, devastating",
      suitableSubjects: ["Quiet narrative frames", "Mixed available light", "Atmospheric environments"],
      avoid: ["Punchy social-media brightness", "Vivid saturation", "Milky lifted-black wash", "Warm nostalgia clichés"]
    ),

    // 7 ────────────────────────────────────────────────────── film-noir
    StyleDefinition(
      id: "film-noir",
      name: "Noir",
      palette: "Monochrome only — inky blacks and sculpted hot highlights",
      isMonochrome: true,
      bwBehavior: "Chiaroscuro silver-gelatin mix (weighted to green/blue) that keeps faces modeled with a rich silver midband; strictly mono after every stage",
      whiteBalance: "N/A — color removed completely",
      exposure: "Meters for highlights; lets blacks fall while keeping meaningful highlights",
      contrastCurve: "Dramatic high contrast, deep filmic S-curve",
      highlightRolloff: "Sculpted hot highlights, controlled not clipped",
      shadowTreatment: "Deep crushed blacks; directional shadow side on the subject",
      saturation: "Zero — full monochrome",
      grain: "Visible fine silver grain",
      halation: "Modest halation on hot practicals",
      bloom: "Slight on key highlights",
      vignette: "Deliberate heavy edge falloff",
      sharpness: "Sharp on the modeled face",
      lensSoftness: "Soft, failing corners framing the subject",
      colorShifts: "None (mono); faint cool-black / warm-white split toning only",
      skinToneProtection: "High — facial geometry separated and modeled, never crushed flat",
      era: "1940s–50s film-noir cinema",
      cameraInspiration: "Classic Hollywood noir — hard directional key, silver-gelatin B&W",
      emotionalTone: "Dramatic, mysterious, tense",
      suitableSubjects: ["Graphic directional light", "Expressive faces", "High-contrast scenes"],
      avoid: ["Flat gray decorative look", "Muddy midtones", "Any color cast", "Even frontal lighting"]
    ),

    // 8 ────────────────────────────────────────────────────── y2k-digicam
    StyleDefinition(
      id: "y2k-digicam",
      name: "Pocket 2002",
      palette: "Glossy saturated color with cyan-drifting clipped whites",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Weak early-CCD AWB; whites clip fast and drift cyan",
      exposure: "Eager auto exposure plus hard close flash; slight overexposure",
      contrastCurve: "Moderate, slightly synthetic digital curve",
      highlightRolloff: "Highlights clip hard; skin can look over-flashed",
      shadowTreatment: "Shallow shadows with a low DMax floor; noise rising in the dark",
      saturation: "High, glossy, slightly synthetic",
      grain: "Crisp small-sensor noise, low film grain, banded JPEG chroma",
      halation: "Mild",
      bloom: "Mild on clipped whites",
      vignette: "Slight",
      sharpness: "Crisp small-sensor detail with over-sharpen bite",
      lensSoftness: "Cheap-zoom distortion and corner softness",
      colorShifts: "Purple/violet edge fringing on the dark side of interior edges (demosaic crosstalk, NOT radial CA); cyan highlight drift; -4° hue",
      skinToneProtection: "Moderate — face visible but flash-flattened",
      era: "Early 2000s (Y2K)",
      cameraInspiration: "Early-2000s CCD point-and-shoot digicam with on-camera flash",
      emotionalTone: "Chaotic, glossy, party immortality",
      suitableSubjects: ["Chaotic nights", "Close social frames", "Flash-lit party candids"],
      avoid: ["Smooth clean modern rendering", "Radial-lens-style CA (must be edge/demosaic fringe)", "Muted film palette", "Deep true blacks"]
    ),

    // 9 ────────────────────────────────────────────────────── polaroid
    StyleDefinition(
      id: "polaroid",
      name: "Instant 600",
      palette: "Warm-neutral color with a gentle teal drift in the shadows",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Partial neutralization; overall warm, teal-shadow drift",
      exposure: "Compresses extremes into the printable middle; face-priority lift",
      contrastCurve: "Medium-low instant-film contrast",
      highlightRolloff: "Creamy highlights that hold, never harsh",
      shadowTreatment: "Lifted shadows with a raised DMax floor (never true black), teal-tinged",
      saturation: "Gently faded chroma",
      grain: "Restrained soft grain",
      halation: "Soft warm halation",
      bloom: "Soft flash glow",
      vignette: "Mild",
      sharpness: "Soft, gentle",
      lensSoftness: "Soft chemical edge, plastic-lens corner softness with mild CA",
      colorShifts: "Per-channel curves: warm highlights, teal shadows; warm cream tint; instant-film paper frame",
      skinToneProtection: "High — midtone faces carried warm",
      era: "Instant film, 1970s–present revival",
      cameraInspiration: "Polaroid 600 / SX-70 instant integral film",
      emotionalTone: "Tender, warm, keepsake",
      suitableSubjects: ["Tender daylight", "Simple portraits", "Intimate everyday moments"],
      avoid: ["Deep clinical blacks", "High contrast punch", "Cold neutral color", "Sharp modern clarity"]
    ),

    // 10 ───────────────────────────────────────────────────── super-8
    StyleDefinition(
      id: "super-8",
      name: "8mm Home Movie",
      palette: "Dense warm amber with saturated reds and oranges",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Barely neutralized; strong warm amber cast retained",
      exposure: "Favors the bright lived moment over shadow recovery",
      contrastCurve: "Warm reversal-stock S-curve over deep shadows",
      highlightRolloff: "Memory-like glowing highlights, halation off hot cores",
      shadowTreatment: "Deep, dense shadows that go grain-forward when underexposed",
      saturation: "Elevated warm saturation",
      grain: "Thick, leading 8mm grain",
      halation: "Strong halation bloom off hot cores",
      bloom: "Warm projector-glow bloom",
      vignette: "Dark projector-gate corners",
      sharpness: "Resolved center (a real lens is sharp on-axis)",
      lensSoftness: "Softness ONLY in projector-gate corners + halation — never a flat gaussian over the whole frame",
      colorShifts: "Warm amber split-tone, orange tint (multiply), warm edge leak; softened blues",
      skinToneProtection: "Low-moderate — the warm stock look leads over flattery",
      era: "1960s–70s home movies",
      cameraInspiration: "Super 8 cartridge on Kodachrome 40, projector-gate playback",
      emotionalTone: "Warm, sunlit, endless-summer memory",
      suitableSubjects: ["Sunlit family scenes", "Summers", "Warm daylight movement"],
      avoid: ["Flat all-over gaussian blur", "Cool neutral color", "Clean digital sharpness", "Soft center focus"]
    ),

    // 11 ───────────────────────────────────────────────────── lomo
    StyleDefinition(
      id: "lomo",
      name: "Toy Color",
      palette: "Toxic-but-gorgeous cross-processed color: hot reds and magentas, crushed cyan-green shadows",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Barely corrected; cross-process casts left intact",
      exposure: "Lightly adaptive but intentionally imperfect and unpredictable",
      contrastCurve: "High, crunchy cross-processed contrast",
      highlightRolloff: "Hard, bold highlights",
      shadowTreatment: "Crushed cyan-green shadows, heavy black vignette corners",
      saturation: "Oversaturated, exaggerated chroma with strong hue separation",
      grain: "Visible grain with color chroma noise",
      halation: "Moderate",
      bloom: "Slight",
      vignette: "Heavy black crushed corners (signature)",
      sharpness: "Center-only; corners fail",
      lensSoftness: "Plastic-lens softness, strong CA and barrel distortion",
      colorShifts: "Cross-process channel curves, -10° hue, green shadow tint (overlay), magenta highlight split",
      skinToneProtection: "Low — color is exaggerated over everything",
      era: "1990s–2000s Lomography movement",
      cameraInspiration: "Lomo LC-A toy camera, cross-processed (E-6 in C-41) slide film",
      emotionalTone: "Playful, unpredictable, happy accident",
      suitableSubjects: ["Playful daylight", "Graphic subjects", "Unpredictable color scenes"],
      avoid: ["Neutral accurate color", "Clean corners", "Predictable even exposure", "Subtle muted palette"]
    ),

    // 12 ───────────────────────────────────────────────────── kodachrome
    StyleDefinition(
      id: "kodachrome",
      name: "Slide 64",
      palette: "K64 slide density — wine-dark reds, cyan skies, inky clean shadows",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Conservative; daylight color relationships preserved",
      exposure: "Careful, slightly conservative slide-film bias (protects highlights)",
      contrastCurve: "High slide-film contrast, biting micro-contrast",
      highlightRolloff: "Limited latitude in extreme highlights (sacrifices there)",
      shadowTreatment: "Inky, clean, dense shadows that hold color",
      saturation: "Rich and dense without broad inflation — never pastel, never bright",
      grain: "Fine slide-film grain",
      halation: "Minimal",
      bloom: "Negligible",
      vignette: "Slight",
      sharpness: "Crisp, biting",
      lensSoftness: "Clean optics",
      colorShifts: "Dense-red colour matrix, warm-red multiply tint, warm-shadow / warm-highlight split; reds held dense",
      skinToneProtection: "Moderate-high — dense but honest skin",
      era: "1950s–2000s (the film that shot the sixties)",
      cameraInspiration: "Kodachrome 64 slide film (K-14 process)",
      emotionalTone: "Rich, timeless, documentary-golden",
      suitableSubjects: ["Color in daylight", "Travel frames", "Saturated outdoor scenes"],
      avoid: ["Pastel or washed color", "Bright high-key look", "Muddy lifted shadows", "Blown highlights"]
    ),

    // 13 ───────────────────────────────────────────────────── security-cam
    StyleDefinition(
      id: "security-cam",
      name: "Monitor 02",
      palette: "Collapsed surveillance green-grey near-monochrome",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Strong auto-gain AWB collapsing toward fluorescent green",
      exposure: "Aggressive whole-frame auto gain; hot brights, dead shadows",
      contrastCurve: "Hard utilitarian gamma",
      highlightRolloff: "Bright sources contaminate/blow out (highlight guard low — stark blowout allowed)",
      shadowTreatment: "Dead electronic shadows with heavy luminance noise",
      saturation: "Near-zero, weak chroma",
      grain: "Coarse, heavy luminance noise (high gain)",
      halation: "Slight bloom on hot sources",
      bloom: "Utilitarian glow on brights",
      vignette: "Cheap-glass vignette",
      sharpness: "Low apparent resolution",
      lensSoftness: "Cheap wide vignetted glass with barrel distortion",
      colorShifts: "Heavy green colour matrix; interlace/field comb + tape dropout; scanlines; burned-in CAM 02 timestamp",
      skinToneProtection: "None — surveillance evidence, not flattery",
      era: "1990s–2000s CCTV / analog surveillance",
      cameraInspiration: "Interlaced CCTV security camera to VHS timelapse recorder",
      emotionalTone: "Detached, eerie, observed",
      suitableSubjects: ["Detached observation", "Empty spaces", "Eerie static scenes"],
      avoid: ["Flattering color", "Smooth clean noise-free image", "Cinematic composition", "Absent timestamp/scanlines"]
    ),

    // 14 ───────────────────────────────────────────────────── point-shoot
    StyleDefinition(
      id: "point-shoot",
      name: "Pocket Compact",
      palette: "Clean, honest natural color — disciplined, not glossy-synthetic",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Good AWB, cool-neutral whites",
      exposure: "Confident auto-everything with open shadows (not crushed)",
      contrastCurve: "Moderate natural contrast",
      highlightRolloff: "Guarded highlights (highlight guard on), only a soft fill of flash",
      shadowTreatment: "Open, honest shadows — not crushed",
      saturation: "Natural, lightly boosted — more disciplined than Y2K digicam",
      grain: "Clean modern digital noise, low",
      halation: "Slight",
      bloom: "Slight",
      vignette: "Modest corner weakness",
      sharpness: "Crisp micro-contrast, clean bite",
      lensSoftness: "Modest corner softness, mild CA",
      colorShifts: "Cool split-tone (blue-grey shadows, cool-white highlights), faint cool tint; only a small fringe",
      skinToneProtection: "Very high — face exposure favored, clean flash color",
      era: "2010s premium large-sensor compact",
      cameraInspiration: "Sony RX100 / large-sensor 1-inch premium compact",
      emotionalTone: "Effortless, everyday, honest",
      suitableSubjects: ["Everyday immediacy", "Travel", "Clean well-lit candids"],
      avoid: ["Crushed oversaturated Y2K look", "Purple demosaic fringing", "Heavy grain", "Synthetic clipped whites"]
    ),

    // 15 ───────────────────────────────────────────────────── pastel-cinema
    StyleDefinition(
      id: "pastel-cinema",
      name: "Pastel Cinema",
      palette: "Powder pink / mint / cream storybook pastels",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Strong AWB toward clean, with a persistent powder-pink signature cast",
      exposure: "High-key friendly with softly opened shadows",
      contrastCurve: "Gentle-but-real low contrast",
      highlightRolloff: "Airy, softly spreading highlights",
      shadowTreatment: "Soft mauve blacks that still exist (very low DMax, never true black)",
      saturation: "Reduced overall with selective pastel-band preservation",
      grain: "Fine grain",
      halation: "Soft halation",
      bloom: "Mild airy bloom",
      vignette: "Almost none",
      sharpness: "Soft, creamy",
      lensSoftness: "Gentle corner softness",
      colorShifts: "Palette snap toward pink/mint/amber anchors; creamy-skin curves; powder-pink tint so it keeps its signature even in low light",
      skinToneProtection: "High — creamy protected skin",
      era: "Contemporary stylized cinema",
      cameraInspiration: "Wes Anderson symmetrical pastel palette",
      emotionalTone: "Whimsical, storybook, arranged",
      suitableSubjects: ["Soft symmetrical compositions", "Arranged scenes", "Soft daylight"],
      avoid: ["Deep true blacks", "Hard local contrast", "Vivid saturated color", "Cool moody grade"]
    ),

    // 16 ───────────────────────────────────────────────────── tokyo-neon
    StyleDefinition(
      id: "tokyo-neon",
      name: "Neon Night",
      palette: "Tungsten-teal ambient with pink/cyan/red neon where the light lives",
      isMonochrome: false,
      bwBehavior: "",
      whiteBalance: "Deliberately NOT neutralized — preserves cyan/magenta/mixed illuminants",
      exposure: "Meters low so signs and practicals keep their color",
      contrastCurve: "High night contrast",
      highlightRolloff: "Red halation blooms off every lamp; cores glow",
      shadowTreatment: "Deep blacks that swallow non-lit areas",
      saturation: "Saturated where the colored light lives, inky elsewhere",
      grain: "Moderate high-ISO grain with chroma",
      halation: "Strong red/colored halation (CineStill 800T signature)",
      bloom: "Colored neon bloom",
      vignette: "Dark corners",
      sharpness: "Sharp on lit subject",
      lensSoftness: "Modest fringe, night-lens CA",
      colorShifts: "Tungsten-teal shadow split, warm highlight; -6° hue; blue-black multiply tint; neon hue bands preserved",
      skinToneProtection: "Moderate — subject reads when inside colored light",
      era: "Contemporary night city",
      cameraInspiration: "CineStill 800T (tungsten, halation-rich) at 2 a.m. in Tokyo",
      emotionalTone: "Moody, cinematic, nocturnal",
      suitableSubjects: ["Wet streets", "Neon signage", "Nightlife", "Colored city light"],
      avoid: ["Neutralized white balance", "Bright even lighting", "Flat daytime look", "Broadly lifted shadows"]
    ),

    // 17 ───────────────────────────────────────────────────── photobooth
    StyleDefinition(
      id: "photobooth",
      name: "Photobooth",
      palette: "Warm silver-gelatin B&W — selenium-warm, never neutral or milky",
      isMonochrome: true,
      bwBehavior: "Warm-toned true B&W (green-weighted mix) with skin separation: flash-bright face, medium-grey curtain, punchy true blacks in hair and clothes",
      whiteBalance: "N/A — monochrome, but toned warm (selenium/sepia)",
      exposure: "Hard frontal flash centered on faces; high-key face",
      contrastCurve: "Punchy strip contrast",
      highlightRolloff: "Flash-bright faces held, gentle uncoloured halation",
      shadowTreatment: "Punchy true blacks in hair/clothes; very low DMax lets blacks reach deep",
      saturation: "Zero (mono)",
      grain: "Moderate strip grain",
      halation: "Gentle and uncoloured — must NOT bloom warm speckles",
      bloom: "Slight",
      vignette: "Close-focus corner softness",
      sharpness: "Crisp on the near face",
      lensSoftness: "Close-focus softness, mild CA",
      colorShifts: "Warm selenium toner: sepia-selenium highlights over warm-black shadows (the chemical-strip warmth, not cold digital B&W)",
      skinToneProtection: "Very high — face placement and graphic skin tone are the whole point",
      era: "20th-century analog photo booth",
      cameraInspiration: "Chemical dip-and-dunk 4-frame photo-strip booth",
      emotionalTone: "Playful, intimate, keepsake",
      suitableSubjects: ["One or two close faces", "Couples", "Curtain close-ups"],
      avoid: ["Flat neutral/cold B&W", "Milky low-contrast gray", "Warm coloured halation speckles", "Distant groups / big backgrounds"]
    ),

    // 18 ───────────────────────────────────────────────────── tintype
    StyleDefinition(
      id: "tintype",
      name: "Wet Plate",
      palette: "Cool silvery-grey metal — orthochromatic, luminous pale skin, reds dropping toward black",
      isMonochrome: true,
      bwBehavior: "Orthochromatic (red-blind) wet-plate response: reds/lips render DARK, blues/skin render pale and luminous — a cool silver plate, NOT warm sepia",
      whiteBalance: "N/A — cool metallic near-monochrome (blue-weighted plate)",
      exposure: "Conservative slow plate-like response (long exposure), deep edge loss",
      contrastCurve: "High plate contrast",
      highlightRolloff: "Luminous pale highlights on skin and metal",
      shadowTreatment: "Deep dark plate edges; reds fall to near-black",
      saturation: "Near-monochrome, minimal residual color",
      grain: "Coarse plate texture / collodion mottle",
      halation: "Soft plate halation",
      bloom: "Slight",
      vignette: "Strong deep candlelight vignette (signature)",
      sharpness: "Sharp on the broad facial plane",
      lensSoftness: "Shallow portrait focus, failing uneven edges (cornerSoft high)",
      colorShifts: "Orthochromatic colour matrix (weights blue/green, drops red); cool blue-grey split-tone and cool metal tint (multiply)",
      skinToneProtection: "High for facial planes — pale luminous skin, but reds/lips deliberately darkened",
      era: "1860s–1880s wet-plate collodion",
      cameraInspiration: "Wet-plate collodion tintype / ambrotype on blackened metal",
      emotionalTone: "Solemn, timeless, ancestral",
      suitableSubjects: ["Still portraits", "Simple backgrounds", "Held, static poses"],
      avoid: ["Warm sepia / brown toning", "Modern saturation", "Bright reds rendered light", "Motion or busy scenes"]
    ),
  ]

  /// Lookup by stable engine id. Falls back to the first entry (disposable),
  /// mirroring `Stock.find` / `CameraRecipe.recipe(for:)`.
  static func forStock(id: String) -> StyleDefinition {
    all.first(where: { $0.id == id }) ?? all[0]
  }
}
