import Foundation

enum CameraEngineClass: String, Codable {
  case staticLUT
  case adaptive
}

struct ReferenceSpatialProfile: Equatable {
  let intensity: Double
  let acutance: Double
  let chromaticAberration: Double
  let distortion: Double
  let cornerSoftness: Double
  let shadowVignette: Double
  let grainLevel: Double
  let grainAmplitude: Double
  let grainChroma: Double
  let grainSize: Double
}

struct CameraRecipe: Identifiable, Equatable {
  let id: String
  let engineClass: CameraEngineClass
  let lutName: String?
  let postLUTExposure: Double
  let postLUTSaturation: Double
  let postLUTContrast: Double
  let postLUTMatrix: [Double]?
  let referenceSpatial: ReferenceSpatialProfile?
  let exposureBias: Double
  let adaptiveExposure: Double
  let warmth: Double
  let saturation: Double
  let contrast: Double
  let shadowLift: Double
  let highlightCompression: Double
  let vignette: Double
  let bloom: Double
  let grain: Double
  let grainSize: Double
  let monochrome: Bool
  let protectsFaces: Bool
  let preservesWarmCast: Bool
  let decisionVocabulary: [String]

  // MARK: Light-intelligence passes (R61 — the light is read, not painted)
  /// On-camera-flash physics for the develop path: specular pop on reflective
  /// surfaces + near/far falloff from the subject mask (background falls toward
  /// ambient, never lifts). 0 = off.
  let flashPhysics: Double
  /// Bloom emanates from detected light sources in the SOURCE's own hue;
  /// refuses to add colored glow when the scene has no emissive sources. 0 = off.
  let sourceBloom: Double
  /// Directional key-light shading: shadows deepen with distance from the
  /// detected key light (faces partially preserved). 0 = off.
  let keyShadow: Double
  /// Video AGC behavior: grain amplitude follows scene darkness (night = noisy,
  /// daylight = near-clean) instead of a fixed overlay.
  let gainDrivenGrain: Bool

  static func recipe(for stockID: String) -> CameraRecipe {
    all.first(where: { $0.id == stockID }) ?? all[0]
  }

  static let all: [CameraRecipe] = [
    .adaptive("disposable", exposure: 0.10, adaptive: 0.45, warmth: 0.12, saturation: 1.04, contrast: 1.10, shadows: 0.05, highlights: 0.20, vignette: 0.28, bloom: 0.10, grain: 0.15, grainSize: 1.1, faces: true, warmCast: true, flash: 0.45, decisions: ["Uneven flash retained", "Faces lifted gently", "Highlights allowed to bloom"]),
    .adaptive("iphone-flash", exposure: 0.18, adaptive: 0.60, warmth: -0.08, saturation: 1.08, contrast: 1.20, shadows: -0.08, highlights: 0.08, vignette: 0.05, bloom: 0.06, grain: 0.04, grainSize: 0.7, faces: true, warmCast: false, flash: 1.0, decisions: ["Face exposure prioritized", "Flash kept cool", "Background shadows held deep"]),
    .adaptive("camcorder-90s", exposure: 0.08, adaptive: 0.55, warmth: 0.02, saturation: 0.78, contrast: 0.92, shadows: 0.08, highlights: 0.24, vignette: 0.18, bloom: 0.10, grain: 0.20, grainSize: 1.5, faces: false, warmCast: true, gainNoise: true, decisions: ["Auto gain followed the scene", "Color softened toward tape", "Shadow noise left visible"]),
    .lut("leica-street", exposure: -0.05, warmth: 0, saturation: 0.98, contrast: 1.12, shadows: -0.02, highlights: 0.10, vignette: 0.12, bloom: 0.02, grain: 0.07, grainSize: 0.75, postExposure: 0.19, postMatrix: [0.885, 0, 0, 0, 1.033, 0, 0, 0, 1.132, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.8, acutance: 0.22, chromaticAberration: 0.02, distortion: 0.01, cornerSoftness: 0.05, shadowVignette: 0.32, grainLevel: 0.26, grainAmplitude: 0.75, grainChroma: 0.12, grainSize: 0.8), faces: true, warmCast: true, decisions: ["Texture preserved", "Highlights protected", "Contrast kept restrained"]),
    .lut("gq-editorial", exposure: 0.10, warmth: 0.02, saturation: 0.96, contrast: 1.14, shadows: 0.02, highlights: 0.12, vignette: 0.04, bloom: 0.03, grain: 0.03, grainSize: 0.65, postExposure: 0.35, postMatrix: [0.874, 0, 0, 0, 1.036, 0, 0, 0, 1.144, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.82, acutance: 0.22, chromaticAberration: 0.03, distortion: 0.0, cornerSoftness: 0.04, shadowVignette: 0.48, grainLevel: 0.05, grainAmplitude: 0.45, grainChroma: 0.05, grainSize: 0.6), faces: true, warmCast: false, decisions: ["Face structure protected", "Strobe contrast shaped", "Color kept editorial"]),
    .lut("a24-still", exposure: -0.06, warmth: 0.02, saturation: 0.90, contrast: 0.96, shadows: 0.06, highlights: 0.26, vignette: 0.08, bloom: 0.08, grain: 0.09, grainSize: 0.9, postExposure: 0.16, postMatrix: [0.923, 0, 0, 0, 1.022, 0, 0, 0, 1.088, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.8, acutance: 0.22, chromaticAberration: 0.06, distortion: 0.02, cornerSoftness: 0.15, shadowVignette: 0.42, grainLevel: 0.3, grainAmplitude: 1.0, grainChroma: 0.25, grainSize: 1.05), faces: true, warmCast: true, decisions: ["Highlight rolloff softened", "Ambient cast retained", "Shadows opened selectively"]),
    // noir carries a restrained cool silver-gelatin tone (blue-black shadows) via
    // the post-LUT matrix — the moodier cinematic noir the reference renders,
    // rather than a flat neutral B&W. Subtle so it reads as toned, not tinted.
    .lut("film-noir", exposure: -0.10, warmth: 0, saturation: 0, contrast: 1.34, shadows: -0.10, highlights: 0.08, vignette: 0.22, bloom: 0.02, grain: 0.12, grainSize: 0.8, mono: true, postExposure: 0.0, postMatrix: [0.96, 0, 0, 0, 0.99, 0, 0, 0, 1.05, -0.004, 0, 0.006], referenceSpatial: ReferenceSpatialProfile(intensity: 0.88, acutance: 0.22, chromaticAberration: 0.0, distortion: 0.04, cornerSoftness: 0.45, shadowVignette: 0.68, grainLevel: 0.42, grainAmplitude: 1.05, grainChroma: 0.0, grainSize: 1.1), faces: true, warmCast: false, keyShadow: 0.7, decisions: ["Color removed completely", "Cool silver tone held", "Blacks allowed to fall"]),
    .adaptive("y2k-digicam", exposure: 0.20, adaptive: 0.70, warmth: -0.03, saturation: 1.22, contrast: 1.18, shadows: -0.02, highlights: 0.02, vignette: 0.04, bloom: 0.04, grain: 0.05, grainSize: 0.55, faces: true, warmCast: false, flash: 0.65, decisions: ["Flash exposure favored", "Color pushed glossy", "Highlights allowed to clip"]),
    .lut("polaroid", exposure: 0.08, warmth: 0.08, saturation: 0.86, contrast: 0.90, shadows: 0.10, highlights: 0.30, vignette: 0.10, bloom: 0.10, grain: 0.08, grainSize: 0.9, postExposure: 0.35, postMatrix: [0.935, 0, 0, 0, 1.019, 0, 0, 0, 1.075, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.85, acutance: 0.22, chromaticAberration: 0.18, distortion: 0.08, cornerSoftness: 0.55, shadowVignette: 0.2, grainLevel: 0.18, grainAmplitude: 0.6, grainChroma: 0.15, grainSize: 0.85), faces: true, warmCast: true, decisions: ["Dynamic range compressed", "Cream warmth retained", "Edges softened chemically"]),
    .lut("super-8", exposure: 0.02, warmth: 0.10, saturation: 0.94, contrast: 1.05, shadows: 0.02, highlights: 0.18, vignette: 0.20, bloom: 0.12, grain: 0.18, grainSize: 1.2, postExposure: 0.11, postMatrix: [0.984, 0, 0, 0, 1.005, 0, 0, 0, 1.015, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.85, acutance: 0.22, chromaticAberration: 0.45, distortion: 0.2, cornerSoftness: 0.95, shadowVignette: 0.68, grainLevel: 0.7, grainAmplitude: 1.5, grainChroma: 0.3, grainSize: 1.6), faces: false, warmCast: true, decisions: ["Warm stock response retained", "Gate edges darkened", "Grain allowed to lead"]),
    .adaptive("lomo", exposure: -0.02, adaptive: 0.32, warmth: 0.02, saturation: 1.28, contrast: 1.20, shadows: -0.08, highlights: 0.06, vignette: 0.42, bloom: 0.04, grain: 0.12, grainSize: 1.15, faces: false, warmCast: true, decisions: ["Color exaggerated", "Corners sacrificed", "Exposure kept unpredictable"]),
    .lut("kodachrome", exposure: -0.04, warmth: 0.06, saturation: 1.10, contrast: 1.13, shadows: -0.03, highlights: 0.14, vignette: 0.06, bloom: 0.02, grain: 0.035, grainSize: 0.7, postExposure: 0.12, postSaturation: 0.92, postContrast: 0.96, postMatrix: [1.242303, -0.216002, -0.130785, 0.070520, 1.107397, 0.010722, -0.073353, 0.111281, 1.324162, -0.031531, -0.038719, -0.027803], referenceSpatial: ReferenceSpatialProfile(intensity: 0.80, acutance: 0.22, chromaticAberration: 0.12, distortion: 0.06, cornerSoftness: 0.20, shadowVignette: 0.46, grainLevel: 0.18, grainAmplitude: 1, grainChroma: 0.25, grainSize: 0.7), faces: true, warmCast: true, decisions: ["Reds held dense", "Shadow color preserved", "Slide highlights protected"]),
    .adaptive("security-cam", exposure: 0.12, adaptive: 0.90, warmth: -0.14, saturation: 0.28, contrast: 1.02, shadows: 0.14, highlights: 0.02, vignette: 0.24, bloom: 0, grain: 0.28, grainSize: 1.5, faces: false, warmCast: false, gainNoise: true, decisions: ["Auto gain raised the scene", "Color collapsed toward surveillance green", "Noise left as evidence"]),
    .adaptive("point-shoot", exposure: 0.14, adaptive: 0.72, warmth: -0.02, saturation: 1.14, contrast: 1.14, shadows: 0.02, highlights: 0.08, vignette: 0.08, bloom: 0.05, grain: 0.03, grainSize: 0.65, faces: true, warmCast: false, flash: 0.5, decisions: ["Face exposure favored", "Small-sensor clarity retained", "Flash color kept clean"]),
    .lut("pastel-cinema", exposure: 0.10, warmth: 0.04, saturation: 0.84, contrast: 0.86, shadows: 0.14, highlights: 0.34, vignette: 0.02, bloom: 0.07, grain: 0.04, grainSize: 0.75, postExposure: 0.34, postMatrix: [0.886, 0, 0, 0, 1.033, 0, 0, 0, 1.131, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.85, acutance: 0.22, chromaticAberration: 0.05, distortion: 0.0, cornerSoftness: 0.22, shadowVignette: 0.14, grainLevel: 0.1, grainAmplitude: 0.5, grainChroma: 0.1, grainSize: 0.7), faces: true, warmCast: true, decisions: ["Contrast flattened", "Pastels protected", "Highlights spread softly"]),
    .lut("tokyo-neon", exposure: -0.12, warmth: -0.08, saturation: 1.20, contrast: 1.18, shadows: -0.10, highlights: 0.24, vignette: 0.16, bloom: 0.18, grain: 0.08, grainSize: 0.85, postExposure: -0.1, postMatrix: [0.983, 0, 0, 0, 1.005, 0, 0, 0, 1.014, 0, 0, 0], referenceSpatial: ReferenceSpatialProfile(intensity: 0.9, acutance: 0.22, chromaticAberration: 0.75, distortion: 0.06, cornerSoftness: 0.18, shadowVignette: 0.62, grainLevel: 0.26, grainAmplitude: 1.05, grainChroma: 0.5, grainSize: 1.05), faces: true, warmCast: true, sourceBloom: 1.0, decisions: ["Colored light preserved", "Black levels held low", "Neon allowed to bloom"]),
    .adaptive("photobooth", exposure: 0.18, adaptive: 0.55, warmth: 0, saturation: 0, contrast: 1.30, shadows: -0.06, highlights: 0.06, vignette: 0.16, bloom: 0.04, grain: 0.10, grainSize: 0.8, mono: true, faces: true, warmCast: false, flash: 0.75, decisions: ["Face exposure centered", "Color removed completely", "Flash contrast kept hard"]),
    // tintype is a COOL orthochromatic wet-plate (owner-directed): the postLUT
    // matrix mixes channels so reds render dark and blues render pale, over a
    // slightly cool silver tint — a real collodion plate, not warm sepia. This
    // intentionally diverges from the warm reference fixture (see the raised
    // parity ceiling in FilmEngineTests).
    .lut("tintype", exposure: -0.08, warmth: -0.05, saturation: 0.15, contrast: 1.12, shadows: -0.06, highlights: 0.20, vignette: 0.48, bloom: 0.06, grain: 0.20, grainSize: 1.7, postExposure: 0.30, postMatrix: [0.06, 0.34, 0.60, 0.05, 0.35, 0.60, 0.05, 0.33, 0.62, -0.02, -0.01, 0.01], referenceSpatial: ReferenceSpatialProfile(intensity: 0.9, acutance: 0.22, chromaticAberration: 0.05, distortion: 0.02, cornerSoftness: 0.95, shadowVignette: 0.8, grainLevel: 0.35, grainAmplitude: 0.9, grainChroma: 0.0, grainSize: 1.3), faces: true, warmCast: false, decisions: ["Portrait tones translated to plate", "Edges allowed to fail", "Cool silver plate — reds run dark"]),
  ]

  private static func lut(_ id: String, exposure: Double, warmth: Double, saturation: Double, contrast: Double, shadows: Double, highlights: Double, vignette: Double, bloom: Double, grain: Double, grainSize: Double, mono: Bool = false, postExposure: Double = 0, postSaturation: Double = 1, postContrast: Double = 1, postMatrix: [Double]? = nil, referenceSpatial: ReferenceSpatialProfile? = nil, faces: Bool, warmCast: Bool, sourceBloom: Double = 0, keyShadow: Double = 0, decisions: [String]) -> CameraRecipe {
    CameraRecipe(id: id, engineClass: .staticLUT, lutName: id, postLUTExposure: postExposure, postLUTSaturation: postSaturation, postLUTContrast: postContrast, postLUTMatrix: postMatrix, referenceSpatial: referenceSpatial, exposureBias: exposure, adaptiveExposure: 0, warmth: warmth, saturation: saturation, contrast: contrast, shadowLift: shadows, highlightCompression: highlights, vignette: vignette, bloom: bloom, grain: grain, grainSize: grainSize, monochrome: mono, protectsFaces: faces, preservesWarmCast: warmCast, decisionVocabulary: decisions, flashPhysics: 0, sourceBloom: sourceBloom, keyShadow: keyShadow, gainDrivenGrain: false)
  }

  private static func adaptive(_ id: String, exposure: Double, adaptive: Double, warmth: Double, saturation: Double, contrast: Double, shadows: Double, highlights: Double, vignette: Double, bloom: Double, grain: Double, grainSize: Double, mono: Bool = false, faces: Bool, warmCast: Bool, flash: Double = 0, gainNoise: Bool = false, decisions: [String]) -> CameraRecipe {
    CameraRecipe(id: id, engineClass: .adaptive, lutName: nil, postLUTExposure: 0, postLUTSaturation: 1, postLUTContrast: 1, postLUTMatrix: nil, referenceSpatial: nil, exposureBias: exposure, adaptiveExposure: adaptive, warmth: warmth, saturation: saturation, contrast: contrast, shadowLift: shadows, highlightCompression: highlights, vignette: vignette, bloom: bloom, grain: grain, grainSize: grainSize, monochrome: mono, protectsFaces: faces, preservesWarmCast: warmCast, decisionVocabulary: decisions, flashPhysics: flash, sourceBloom: 0, keyShadow: 0, gainDrivenGrain: gainNoise)
  }
}



