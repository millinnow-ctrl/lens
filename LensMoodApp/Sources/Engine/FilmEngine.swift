import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum FilmEngineError: LocalizedError {
  case unreadableImage
  case renderFailed

  var errorDescription: String? {
    switch self {
    case .unreadableImage: return "This photograph could not be opened."
    case .renderFailed: return "LensMood could not develop this photograph."
    }
  }
}

struct FilmRenderResult {
  let image: UIImage
  let scene: SceneProfile
  let decisions: [String]
  let faces: [FaceProfile]
}

/// One photograph's complete read — the scene meter plus the subject pass —
/// computed once and reusable across every develop of that photograph.
/// Produced by `FilmEngine.read`; cached and handed back to
/// `develop(reading:)` by the Conductor, so switching cameras never re-runs
/// the meter or the subject pass on the same photo.
struct SceneReading {
  let scene: SceneProfile
  let subject: SubjectAnalysis
}

final class FilmEngine {
  static let shared = FilmEngine()

  private let context: CIContext
  private let analyzer: SceneAnalyzer
  private let lutLoader = LUTLoader()
  private let grainKernel: CIColorKernel?
  private let referenceGeometryKernel: CIWarpKernel?
  private let referenceChannelMergeKernel: CIColorKernel?
  private let referenceAcutanceKernel: CIColorKernel?
  private let referenceCornerSoftnessKernel: CIColorKernel?
  private let referenceVignetteKernel: CIColorKernel?
  private let referenceGrainKernel: CIColorKernel?
  // internal so the opt-in capture-look extension (a separate file) can use it
  let captureNoiseKernel: CIColorKernel?
  // R61 light-intelligence kernels (used by FilmEngine+LightIntelligence)
  let flashSpecularKernel: CIColorKernel?
  let flashFalloffKernel: CIColorKernel?
  let keyShadowKernel: CIColorKernel?
  let clipMaskKernel: CIColorKernel?

  init() {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    context = CIContext(options: [
      .workingColorSpace: sRGB,
      .outputColorSpace: sRGB,
      .cacheIntermediates: true,
      .useSoftwareRenderer: false,
    ])
    analyzer = SceneAnalyzer(context: context)
    grainKernel = CIColorKernel(source: """
      kernel vec4 lensMoodGrain(__sample pixel, float amount, float seed, float grainSize) {
        vec2 cell = floor(destCoord() / max(grainSize, 0.5));
        float random = fract(sin(dot(cell, vec2(12.9898, 78.233)) + seed) * 43758.5453);
        float noise = (random - 0.5) * amount;
        return vec4(clamp(pixel.rgb + vec3(noise), 0.0, 1.0), pixel.a);
      }
      """)
    referenceGeometryKernel = CIWarpKernel(source: """
      kernel vec2 lensMoodReferenceGeometry(
        float centerX,
        float centerY,
        float radialScale,
        float chromaticScale
      ) {
        vec2 center = vec2(centerX, centerY);
        vec2 delta = destCoord() - center;
        float d2 = dot(delta, delta) / max(radialScale * radialScale, 0.001);
        float barrel = 1.0 + radialScale * 0.0 + chromaticScale * d2;
        return center + delta * barrel;
      }
      """)
    referenceChannelMergeKernel = CIColorKernel(source: """
      kernel vec4 lensMoodReferenceChannelMerge(__sample red, __sample green, __sample blue) {
        return vec4(red.r, green.g, blue.b, green.a);
      }
      """)
    referenceAcutanceKernel = CIColorKernel(source: """
      kernel vec4 lensMoodReferenceAcutance(__sample pixel, __sample blurred, float amount) {
        float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float weight = amount * (4.0 * luminance * (1.0 - luminance));
        vec3 result = pixel.rgb + (pixel.rgb - blurred.rgb) * weight;
        return vec4(clamp(result, 0.0, 1.0), pixel.a);
      }
      """)
    referenceCornerSoftnessKernel = CIColorKernel(source: """
      kernel vec4 lensMoodReferenceCornerSoftness(
        __sample sharp,
        __sample blurred,
        float centerX,
        float centerY,
        float radialScale,
        float clearStop,
        float opacity
      ) {
        float radius = distance(destCoord(), vec2(centerX, centerY)) / max(radialScale, 0.001);
        float mask = clamp((radius - clearStop) / max(1.0 - clearStop, 0.001), 0.0, 1.0);
        return mix(sharp, blurred, mask * opacity);
      }
      """)
    referenceVignetteKernel = CIColorKernel(source: """
      kernel vec4 lensMoodReferenceVignette(
        __sample pixel,
        float centerX,
        float centerY,
        float innerRadius,
        float outerRadius,
        float outerAlpha
      ) {
        float distanceFromCenter = distance(destCoord(), vec2(centerX, centerY));
        float ramp = clamp(
          (distanceFromCenter - innerRadius) / max(outerRadius - innerRadius, 0.001),
          0.0,
          1.0
        );
        float alpha = ramp * outerAlpha;
        vec3 vignetteColor = vec3(8.0 / 255.0, 8.0 / 255.0, 12.0 / 255.0);
        return vec4(mix(pixel.rgb, vignetteColor, alpha), pixel.a);
      }
      """)
    referenceGrainKernel = CIColorKernel(source: """
      kernel vec4 lensMoodReferenceGrain(__sample pixel, __sample noise, float amplitude) {
        float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float weight = 0.25 + 0.75 * (4.0 * luminance * (1.0 - luminance));
        vec3 result = pixel.rgb + noise.rgb * (amplitude / 255.0) * weight;
        return vec4(clamp(result, 0.0, 1.0), pixel.a);
      }
      """)
    // ISO sensor noise for the in-app camera — shadow-weighted, deterministic
    captureNoiseKernel = CIColorKernel(source: """
      kernel vec4 lensMoodSensorNoise(__sample pixel, float amount, float seed, float sizeMul, float chroma, float mono) {
        vec2 cell = floor(destCoord() / max(sizeMul, 0.5));
        float lum = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float shadowWeight = 0.35 + 0.65 * (1.0 - lum);
        float r = fract(sin(dot(cell, vec2(12.9898, 78.233)) + seed) * 43758.5453);
        vec3 result = pixel.rgb + vec3((r - 0.5) * amount * shadowWeight);
        if (chroma > 0.5 && mono < 0.5) {
          float rc = fract(sin(dot(cell, vec2(39.3468, 11.135)) + seed) * 24634.6345);
          float bc = fract(sin(dot(cell, vec2(93.9898, 67.345)) + seed) * 13221.1234);
          result += vec3((rc - 0.5), 0.0, (bc - 0.5)) * amount * 0.5;
        }
        return vec4(clamp(result, 0.0, 1.0), pixel.a);
      }
      """)
    // R61 — flash speculars: bright, desaturated pixels (glass, screens, metal,
    // eyes) catch the flash with a screen-blend white push toward clip.
    flashSpecularKernel = CIColorKernel(source: """
      kernel vec4 lensMoodFlashSpecular(__sample pixel, float lo, float hi, float push) {
        float lum = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float mx = max(pixel.r, max(pixel.g, pixel.b));
        float mn = min(pixel.r, min(pixel.g, pixel.b));
        float sat = mx > 1e-4 ? (mx - mn) / mx : 0.0;
        float t = clamp((lum - lo) / max(hi - lo, 1e-4), 0.0, 1.0);
        t = t * t * (3.0 - 2.0 * t);
        float spec = t * (1.0 - sat * 0.85) * push;
        vec3 screened = 1.0 - (1.0 - pixel.rgb) * (1.0 - vec3(spec, spec * 0.99, spec * 0.97));
        return vec4(clamp(screened, 0.0, 1.0), pixel.a);
      }
      """)
    // R61 — flash falloff: gain = (1-fall) + (fall+lift)*near. Background falls
    // toward ambient; the subject holds (and lifts a touch). Never lifts the far
    // field — the physics the critique demanded.
    flashFalloffKernel = CIColorKernel(source: """
      kernel vec4 lensMoodFlashFalloff(__sample pixel, __sample near, float fall, float lift) {
        float gain = (1.0 - fall) + (fall + lift) * clamp(near.r, 0.0, 1.0);
        return vec4(clamp(pixel.rgb * gain, 0.0, 1.0), pixel.a);
      }
      """)
    // R61 — noir key shadow: shadows deepen with distance from the key light;
    // highlights hold (1-lum term); the face circle is partially preserved.
    // Multiplies channels uniformly so the stock's split-tone survives.
    keyShadowKernel = CIColorKernel(source: """
      kernel vec4 lensMoodKeyShadow(
        __sample pixel,
        float keyX, float keyY, float invDiag, float amount,
        float faceX, float faceY, float faceR
      ) {
        float lum = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float d = clamp(distance(destCoord(), vec2(keyX, keyY)) * invDiag, 0.0, 1.0);
        float faceD = distance(destCoord(), vec2(faceX, faceY));
        float facePreserve = 1.0 - 0.55 * clamp(1.0 - faceD / max(faceR, 1.0), 0.0, 1.0);
        float gain = 1.0 - amount * d * facePreserve * (1.0 - lum);
        return vec4(clamp(pixel.rgb * gain, 0.0, 1.0), pixel.a);
      }
      """)
    // R62 — clipped-highlight extract (colored): feeds the vertical CCD/tube
    // smear so blown highlights bleed down the sensor column in their own hue.
    clipMaskKernel = CIColorKernel(source: """
      kernel vec4 lensMoodClipMask(__sample pixel, float t0, float t1) {
        float lum = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float t = clamp((lum - t0) / max(t1 - t0, 1e-4), 0.0, 1.0);
        t = t * t * (3.0 - 2.0 * t);
        return vec4(pixel.rgb * t, 1.0);
      }
      """)
  }

  /// Run the intelligence passes alone — the meter and (optionally) the
  /// subject pass — without developing. The Conductor calls this once per
  /// photograph and hands the result to every subsequent `develop(reading:)`.
  /// Same analyzer, same oriented input as `develop`: the meter side is
  /// byte-identical to a self-reading develop, and because ALL of a photo's
  /// renders share this one reading, the subject pass (whose separate runs
  /// are not guaranteed bit-stable) can never split preview from export.
  func read(_ source: UIImage, analyzeSubjects: Bool = true) throws -> SceneReading {
    guard let image = CIImage(
      image: source,
      options: [.applyOrientationProperty: true]
    ) else {
      throw FilmEngineError.unreadableImage
    }
    let scene = try analyzer.analyze(image.orientedForDisplay)
    let subject = analyzeSubjects
      ? ((try? VisionService.analyze(source, includePersonMask: true)) ?? SubjectAnalysis(faces: [], personMask: nil))
      : SubjectAnalysis(faces: [], personMask: nil)
    return SceneReading(scene: scene, subject: subject)
  }

  func develop(
    _ source: UIImage,
    with recipe: CameraRecipe,
    maxPixelSize: CGFloat? = nil,
    seed: Double = 1,
    analyzeSubjects: Bool = true,
    capture: CaptureSettings? = nil,
    reading: SceneReading? = nil
  ) throws -> FilmRenderResult {
    guard var image = CIImage(
      image: source,
      options: [.applyOrientationProperty: true]
    ) else {
      throw FilmEngineError.unreadableImage
    }

    // opt-in: subject cut-out for depth of field, the auto studio relight, or
    // (R61) flash-physics falloff in the develop path
    let wantsMask = capture?.wantsDepthOfField == true || capture?.autoRelight == true
      || (recipe.flashPhysics > 0.001 && analyzeSubjects)
    image = image.orientedForDisplay
    let scene: SceneProfile
    let subject: SubjectAnalysis
    if let reading {
      // A cached read for THIS photo, produced by `read` above. The mask is
      // always present in a cached read; passes that don't want it are gated
      // off by the recipe, so unused extras never change the render.
      scene = reading.scene
      subject = analyzeSubjects ? reading.subject : SubjectAnalysis(faces: [], personMask: nil)
    } else {
      scene = try analyzer.analyze(image)
      subject = analyzeSubjects
        ? ((try? VisionService.analyze(source, includePersonMask: wantsMask)) ?? SubjectAnalysis(faces: [], personMask: nil))
        : SubjectAnalysis(faces: [], personMask: nil)
    }

    if let maxPixelSize {
      image = scaled(image, maxPixelSize: maxPixelSize)
    }

    if let profile = recipe.referenceSpatial {
      image = applyReferenceGeometry(image, profile: profile)
    }

    // The in-app camera's pre-core passes (all opt-in via `capture`; the
    // default develop path with capture==nil is untouched):
    //  · auto studio relight — balances lighting when you take the photo
    //  · dial re-light — exposure/WB dials change how the film renders
    if let capture {
      if capture.autoRelight {
        image = applyStudioRelight(image, capture: capture, scene: scene, subject: subject)
      }
      if !capture.isNeutral {
        image = applyCaptureLight(image, capture: capture, recipe: recipe)
      }
    }

    // R62: slow film starves in the dark — reciprocity failure hits the light
    // BEFORE it reaches the emulsion (color core). Gated on scene darkness, so
    // daylight scenes render byte-identically.
    if recipe.nightReciprocity > 0.001 {
      image = applyNightReciprocity(image, scene: scene, amount: recipe.nightReciprocity)
    }

    let adaptiveEV = adaptiveExposure(for: scene, recipe: recipe)
    if recipe.engineClass == .staticLUT, let lutName = recipe.lutName {
      // The baked cube is the complete per-pixel color core. Applying the
      // recipe's exposure, white balance, and tone again would double-develop it.
      image = try lutLoader.apply(named: lutName, to: image)
      if recipe.postLUTExposure != 0 {
        image = applyExposure(image, ev: recipe.postLUTExposure)
      }
      if recipe.postLUTSaturation != 1 || recipe.postLUTContrast != 1 {
        image = image.applyingFilter("CIColorControls", parameters: [
          kCIInputSaturationKey: recipe.postLUTSaturation,
          kCIInputContrastKey: recipe.postLUTContrast,
        ])
      }
      if let matrix = recipe.postLUTMatrix, matrix.count == 12 {
        image = image.applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: matrix[0], y: matrix[1], z: matrix[2], w: 0),
          "inputGVector": CIVector(x: matrix[3], y: matrix[4], z: matrix[5], w: 0),
          "inputBVector": CIVector(x: matrix[6], y: matrix[7], z: matrix[8], w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: matrix[9], y: matrix[10], z: matrix[11], w: 0),
        ])
      }
    } else {
      image = applyExposure(image, ev: recipe.exposureBias + adaptiveEV)
      image = applyWhiteBalance(image, scene: scene, recipe: recipe)
      image = applyTone(image, recipe: recipe)
      image = applyAdaptiveColor(image, scene: scene, recipe: recipe)
    }
    // R62: early-CCD sensors have no film shoulder — highlights race to clip.
    if recipe.ccdClip > 0.001 {
      image = applyCCDClip(image, amount: recipe.ccdClip)
    }

    if let profile = recipe.referenceSpatial {
      image = applyReferenceAcutance(image, profile: profile)
      image = applyReferenceCornerSoftness(image, profile: profile)
    }

    if recipe.protectsFaces, !subject.faces.isEmpty {
      image = applyFaceProtection(image, faces: subject.faces, amount: scene.isBacklit ? 0.22 : 0.10)
    }
    // R61 light-intelligence: flash physics (speculars + subject falloff) and
    // the noir key-light direction — both read the scene, both recipe-gated.
    if recipe.flashPhysics > 0.001 {
      image = applyFlashPhysics(image, scene: scene, subject: subject, amount: recipe.flashPhysics)
    }
    if recipe.keyShadow > 0.001 {
      image = applyKeyShadow(image, scene: scene, subject: subject, amount: recipe.keyShadow)
    }
    if recipe.monochrome, recipe.engineClass != .staticLUT {
      // LUT stocks (noir) bake their own B&W + split-tone; a second mono pass
      // strips the baked tint and double-applies the S-curve
      image = image.applyingFilter("CIPhotoEffectMono")
    }
    if recipe.sourceBloom > 0.001 {
      // R61: bloom emanates from detected sources in their own hue (with an
      // honest refusal when the scene has no emissive sources).
      image = applySourceBloom(image, scene: scene, baseBloom: recipe.bloom, amount: recipe.sourceBloom)
    } else {
      image = applyBloom(image, amount: recipe.bloom)
    }
    // R62: clipped highlights bleed down the sensor column (CCD blooming /
    // tube comet-tails), riding on top of the bloomed highlights.
    if recipe.highlightSmear > 0.001 {
      image = applyHighlightSmear(
        image, scene: scene,
        amount: recipe.highlightSmear,
        onlyInDark: recipe.highlightSmearDarkOnly
      )
    }
    if let profile = recipe.referenceSpatial {
      image = applyReferenceVignette(image, profile: profile)
      image = applyReferenceGrain(image, recipeID: recipe.id, profile: profile)
    } else {
      image = applyVignette(image, amount: recipe.vignette)
      // R61: video stocks run real AGC — noise follows scene darkness instead
      // of shipping one fixed overlay for night and daylight alike.
      let grainAmount = recipe.gainDrivenGrain
        ? recipe.grain * FilmEngine.gainGrainFactor(key: scene.key)
        : recipe.grain
      image = applyGrain(image, amount: grainAmount, size: recipe.grainSize, seed: seed)
    }
    // Stage 2 of the in-app camera: the physical look of the exposure triangle
    // (depth of field, motion, sensor grain, flash). Before mono-enforce and
    // the instant frame, so those invariants are re-applied on top.
    if let capture, !capture.isNeutral {
      image = applyCaptureLook(image, capture: capture, scene: scene,
                               subject: subject, recipe: recipe, seed: seed)
    }
    if recipe.monochrome, recipe.engineClass != .staticLUT {
      // Enforce the invariant after every spatial and lighting pass.
      // (LUT stocks keep their baked split-tone — see the gate above.)
      image = image.applyingFilter("CIColorMonochrome", parameters: [
        kCIInputColorKey: CIColor.white,
        kCIInputIntensityKey: 1,
      ])
    }
    if recipe.id == "polaroid" {
      image = applyInstantFrame(to: image)
    }

    let extent = image.extent.integral
    guard let cgImage = context.createCGImage(
      image,
      from: extent,
      format: .RGBA8,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    ) else {
      throw FilmEngineError.renderFailed
    }
    return FilmRenderResult(
      image: UIImage(cgImage: cgImage, scale: source.scale, orientation: .up),
      scene: scene,
      decisions: decisions(for: scene, recipe: recipe, adaptiveEV: adaptiveEV, faces: subject.faces),
      faces: subject.faces
    )
  }

  private func scaled(_ image: CIImage, maxPixelSize: CGFloat) -> CIImage {
    let largest = max(image.extent.width, image.extent.height)
    guard largest > maxPixelSize, largest > 0 else { return image }
    let scale = maxPixelSize / largest
    return image.applyingFilter("CILanczosScaleTransform", parameters: [
      kCIInputScaleKey: scale,
      kCIInputAspectRatioKey: 1,
    ])
  }

  // internal for direct unit testing of the R63 night-lift rule
  func adaptiveExposure(for scene: SceneProfile, recipe: CameraRecipe) -> Double {
    guard recipe.engineClass == .adaptive else { return 0 }
    let target = scene.isLowKey ? 0.42 : 0.50
    var correction = log2(max(0.08, target) / max(0.08, scene.medianLuminance))
      .clamped(to: -0.85...0.85)
    // R63: a flash camera exposes for the SUBJECT — it cannot lift a night sky
    // it never reached. The night-evidence review showed flash stocks fogging
    // dark skies toward the midtone target; cap the upward pull (AFTER the
    // clamp, or deep-night corrections saturate the clamp and the cap
    // vanishes) so the far field stays dark and the flash-falloff physics
    // reads true. Face protection + the falloff's subject lift still expose
    // the people.
    if recipe.flashPhysics > 0.001, scene.key < 0.30, correction > 0 {
      correction *= 0.35
    }
    return correction * recipe.adaptiveExposure
  }

  private func applyExposure(_ image: CIImage, ev: Double) -> CIImage {
    image.applyingFilter("CIExposureAdjust", parameters: [
      kCIInputEVKey: ev,
    ])
  }

  private func applyWhiteBalance(
    _ image: CIImage,
    scene: SceneProfile,
    recipe: CameraRecipe
  ) -> CIImage {
    let retainedSceneWarmth = recipe.preservesWarmCast ? scene.warmth * 0.35 : -scene.warmth * 0.45
    let warmth = (recipe.warmth + retainedSceneWarmth).clamped(to: -0.30...0.30)
    return image.applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: 1 + warmth * 0.22, y: 0, z: 0, w: 0),
      "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
      "inputBVector": CIVector(x: 0, y: 0, z: 1 - warmth * 0.22, w: 0),
      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
    ])
  }

  private func applyTone(_ image: CIImage, recipe: CameraRecipe) -> CIImage {
    let highlights = (1 - recipe.highlightCompression * 0.72).clamped(to: 0.25...1)
    let shadows = (1 + recipe.shadowLift * 1.5).clamped(to: 0...2)
    let adjusted = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
      "inputHighlightAmount": highlights,
      "inputShadowAmount": shadows,
    ])
    return adjusted.applyingFilter("CIColorControls", parameters: [
      kCIInputSaturationKey: recipe.monochrome ? 0 : recipe.saturation,
      kCIInputContrastKey: recipe.contrast,
      kCIInputBrightnessKey: 0,
    ])
  }

  private func applyAdaptiveColor(
    _ image: CIImage,
    scene: SceneProfile,
    recipe: CameraRecipe
  ) -> CIImage {
    switch recipe.id {
    case "security-cam":
      // R64: green IR is a NIGHT mode. A daylight CCTV frame is washed,
      // slightly lifeless color — not a green wash (daylight-evidence review).
      // The IR matrix fades in with scene darkness for dusk continuity.
      let darkness = max(0, min(1, (0.35 - scene.key) / 0.35))
      let washed = image.applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0.22 + 0.28 * (1 - darkness),
      ])
      guard darkness > 0.05 else { return washed }
      func ir(_ day: Double, _ night: Double) -> CGFloat {
        CGFloat(day + (night - day) * darkness)
      }
      return washed.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: ir(1, 0.45), y: ir(0, 0.18), z: ir(0, 0.08), w: 0),
        "inputGVector": CIVector(x: ir(0, 0.12), y: ir(1, 0.88), z: ir(0, 0.22), w: 0),
        "inputBVector": CIVector(x: ir(0, 0.08), y: ir(0, 0.22), z: ir(1, 0.46), w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 0, y: ir(0, 0.04), z: 0, w: 0),
      ])
    case "camcorder-90s":
      return image.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.92, y: 0.05, z: 0.03, w: 0),
        "inputGVector": CIVector(x: 0.04, y: 0.91, z: 0.05, w: 0),
        "inputBVector": CIVector(x: 0.07, y: 0.08, z: 0.85, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ])
    case "lomo":
      return image.applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: recipe.saturation + scene.saturation * 0.12,
        kCIInputContrastKey: recipe.contrast,
      ])
    case "photobooth":
      return image.applyingFilter("CIPhotoEffectMono")
    default:
      let saturation = recipe.saturation + (scene.isLowKey ? 0.05 : 0)
      return image.applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: saturation,
        kCIInputContrastKey: recipe.contrast,
      ])
    }
  }

  private func applyFaceProtection(
    _ image: CIImage,
    faces: [FaceProfile],
    amount: Double
  ) -> CIImage {
    var protected = image
    for face in faces {
      let center = CIVector(
        x: image.extent.minX + face.bounds.midX * image.extent.width,
        y: image.extent.minY + (1 - face.bounds.midY) * image.extent.height
      )
      let radius = max(
        face.bounds.width * image.extent.width,
        face.bounds.height * image.extent.height
      ) * 0.85
      guard radius > 1 else { continue }
      let lifted = protected.applyingFilter("CIExposureAdjust", parameters: [
        kCIInputEVKey: amount,
      ])
      let mask = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center,
        "inputRadius0": radius * 0.22,
        "inputRadius1": radius,
        "inputColor0": CIColor.white,
        "inputColor1": CIColor.black,
      ])?.outputImage?.cropped(to: image.extent)
      if let mask {
        protected = lifted.applyingFilter("CIBlendWithMask", parameters: [
          kCIInputBackgroundImageKey: protected,
          kCIInputMaskImageKey: mask,
        ])
      }
    }
    return protected
  }

  func applyBloom(_ image: CIImage, amount: Double) -> CIImage {
    guard amount > 0.001 else { return image }
    return image.applyingFilter("CIBloom", parameters: [
      kCIInputRadiusKey: 3 + amount * 18,
      kCIInputIntensityKey: amount,
    ]).cropped(to: image.extent)
  }

  private func applyVignette(_ image: CIImage, amount: Double) -> CIImage {
    guard amount > 0.001 else { return image }
    return image.applyingFilter("CIVignette", parameters: [
      kCIInputIntensityKey: amount * 1.7,
      kCIInputRadiusKey: min(image.extent.width, image.extent.height) * 0.72,
    ]).cropped(to: image.extent)
  }

  private func applyInstantFrame(to image: CIImage) -> CIImage {
    // reference geometry (engine.ts polaroid frame): margins are proportions
    // of the LONGEST side, not the width — 0.055 border, 0.16 bottom lip.
    // The previous width-based constants only matched 3:4 portraits.
    let longest = max(image.extent.width, image.extent.height)
    let horizontal = round(longest * 0.055)
    let top = horizontal
    let bottom = round(longest * 0.16)
    let canvas = CGRect(
      x: image.extent.minX - horizontal,
      y: image.extent.minY - bottom,
      width: image.extent.width + horizontal * 2,
      height: image.extent.height + top + bottom
    )
    let paper = CIImage(color: CIColor(
      red: 0.965,
      green: 0.952,
      blue: 0.905,
      alpha: 1
    )).cropped(to: canvas)
    return image.composited(over: paper)
  }

  private func applyGrain(
    _ image: CIImage,
    amount: Double,
    size: Double,
    seed: Double
  ) -> CIImage {
    guard amount > 0.001, let grainKernel else { return image }
    return grainKernel.apply(
      extent: image.extent,
      arguments: [image, amount, seed, size]
    ) ?? image
  }

  private func applyReferenceAcutance(
    _ image: CIImage,
    profile: ReferenceSpatialProfile
  ) -> CIImage {
    guard let referenceAcutanceKernel else { return image }
    let referenceScale = max(image.extent.width, image.extent.height) / 1000
    let radius = 2.2 * referenceScale
    let blurred = image
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
      .cropped(to: image.extent)
    return referenceAcutanceKernel.apply(
      extent: image.extent,
      arguments: [image, blurred, profile.acutance * profile.intensity]
    ) ?? image
  }

  private func applyReferenceGeometry(
    _ image: CIImage,
    profile: ReferenceSpatialProfile
  ) -> CIImage {
    guard let referenceGeometryKernel, let referenceChannelMergeKernel else { return image }
    let extent = image.extent
    let referenceScale = max(extent.width, extent.height) / 1000
    let radialScale = hypot(extent.width / 2, extent.height / 2)
    let distortion = profile.distortion * 0.09 * profile.intensity
    let caPixels = profile.chromaticAberration * 3 * profile.intensity * referenceScale
    let chromatic = caPixels / radialScale
    guard distortion > 0.0015 || caPixels >= 0.5 else { return image }

    let source = image.clampedToExtent()
    let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -2, dy: -2) }
    func warped(_ coefficient: Double) -> CIImage {
      referenceGeometryKernel.apply(
        extent: extent,
        roiCallback: roi,
        image: source,
        arguments: [extent.midX, extent.midY, radialScale, coefficient]
      )?.cropped(to: extent) ?? image
    }

    let red = warped(distortion - chromatic)
    let green = warped(distortion)
    let blue = warped(distortion + chromatic)
    return referenceChannelMergeKernel.apply(
      extent: extent,
      arguments: [red, green, blue]
    ) ?? image
  }

  private func applyReferenceCornerSoftness(
    _ image: CIImage,
    profile: ReferenceSpatialProfile
  ) -> CIImage {
    guard let referenceCornerSoftnessKernel, profile.cornerSoftness > 0.02 else { return image }
    let extent = image.extent
    let referenceScale = max(extent.width, extent.height) / 1000
    let softness = profile.cornerSoftness * profile.intensity
    let radius = 2.6 * softness * referenceScale + 0.8
    let blurred = image
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
      .cropped(to: extent)
    let radialScale = hypot(extent.width, extent.height) / 2
    let clearStop = max(0.05, 0.62 - softness * 0.2)
    let opacity = min(1, 0.9 * softness)
    return referenceCornerSoftnessKernel.apply(
      extent: extent,
      arguments: [image, blurred, extent.midX, extent.midY, radialScale, clearStop, opacity]
    ) ?? image
  }

  private func applyReferenceVignette(
    _ image: CIImage,
    profile: ReferenceSpatialProfile
  ) -> CIImage {
    guard let referenceVignetteKernel else { return image }
    let extent = image.extent
    let innerRadius = min(extent.width, extent.height) * 0.35
    let outerRadius = max(extent.width, extent.height) * 0.78
    let outerAlpha = profile.shadowVignette * profile.intensity * 0.55
    return referenceVignetteKernel.apply(
      extent: extent,
      arguments: [
        image,
        extent.midX,
        extent.midY,
        innerRadius,
        outerRadius,
        outerAlpha,
      ]
    ) ?? image
  }

  private func applyReferenceGrain(
    _ image: CIImage,
    recipeID: String,
    profile: ReferenceSpatialProfile
  ) -> CIImage {
    guard let referenceGrainKernel else { return image }
    let extent = image.extent.integral
    let width = max(1, Int(extent.width))
    let height = max(1, Int(extent.height))
    let referenceScale = Double(max(width, height)) / 1000
    let clumpSize = max(1, Int((profile.grainSize * referenceScale).rounded()))
    let seed = referenceHash(recipeID) & 0xffff
    var pixels = [Float32](repeating: 0, count: width * height * 4)

    for y in 0..<height {
      let grainY = clumpSize > 1 ? y / clumpSize : y
      for x in 0..<width {
        let grainX = clumpSize > 1 ? x / clumpSize : x
        let mono = referenceGrainSample(x: grainX, y: grainY, seed: seed)
        let index = (y * width + x) * 4
        pixels[index] = Float32(
          mono + referenceGrainSample(x: grainX, y: grainY, seed: seed &+ 13) * profile.grainChroma
        )
        pixels[index + 1] = Float32(
          mono + referenceGrainSample(x: grainX, y: grainY, seed: seed &+ 37) * profile.grainChroma
        )
        pixels[index + 2] = Float32(
          mono + referenceGrainSample(x: grainX, y: grainY, seed: seed &+ 61) * profile.grainChroma
        )
        pixels[index + 3] = 1
      }
    }

    let data = pixels.withUnsafeBytes { Data($0) }
    let noise = CIImage(
      bitmapData: data,
      bytesPerRow: width * 4 * MemoryLayout<Float32>.size,
      size: CGSize(width: width, height: height),
      format: .RGBAf,
      colorSpace: nil
    ).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    let amplitude = profile.grainLevel * 34 * profile.grainAmplitude
      * min(1, profile.intensity * 1.25)
    return referenceGrainKernel.apply(
      extent: extent,
      arguments: [image, noise, amplitude]
    ) ?? image
  }

  private func referenceHash(_ string: String) -> UInt32 {
    var hash: UInt32 = 0x811c9dc5
    for codeUnit in string.utf16 {
      hash ^= UInt32(codeUnit)
      hash = hash &* 0x01000193
    }
    return hash
  }

  private func referenceNoiseHash(x: Int, y: Int, seed: UInt32) -> Double {
    var hash = UInt32(truncatingIfNeeded: x) &* 374_761_393
    hash = hash &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
    hash = hash &+ seed &* 2_246_822_519
    hash = (hash ^ (hash >> 13)) &* 1_274_126_177
    hash ^= hash >> 16
    return Double(hash) / 4_294_967_296
  }

  private func referenceGrainSample(x: Int, y: Int, seed: UInt32) -> Double {
    (
      referenceNoiseHash(x: x, y: y, seed: seed)
        + referenceNoiseHash(x: x, y: y, seed: seed &+ 9_173)
        + referenceNoiseHash(x: x, y: y, seed: seed &+ 51_287)
    ) / 3 - 0.5
  }

  private func decisions(
    for scene: SceneProfile,
    recipe: CameraRecipe,
    adaptiveEV: Double,
    faces: [FaceProfile]
  ) -> [String] {
    var notes: [String] = []
    if !faces.isEmpty, recipe.protectsFaces {
      notes.append(faces.count == 1 ? "Face exposure protected" : "Group exposure balanced")
    }
    if adaptiveEV > 0.08 { notes.append("Low light raised \(formattedStops(adaptiveEV))") }
    if adaptiveEV < -0.08 { notes.append("Highlights held \(formattedStops(abs(adaptiveEV)))") }
    if scene.isBacklit, recipe.protectsFaces, !faces.isEmpty { notes.append("Backlit subject lifted") }
    if abs(scene.warmth) > 0.06 {
      notes.append(recipe.preservesWarmCast ? "Ambient color retained" : "Color cast restrained")
    }
    // R61 light-intelligence notes — only when the pass actually engaged.
    if recipe.flashPhysics > 0.001 {
      notes.append(scene.key < 0.35 ? "Flash falloff shaped to the subject" : "Flash read off the bright surfaces")
    }
    if recipe.sourceBloom > 0.001, !emissiveLights(in: scene).isEmpty {
      notes.append("Glow followed the light sources")
    }
    if recipe.keyShadow > 0.001, !scene.lights.isEmpty {
      notes.append("Key light held to one side")
    }
    if recipe.gainDrivenGrain {
      notes.append(scene.key < 0.25 ? "Gain noise rose with the dark" : "Gain kept low in the light")
    }
    if recipe.nightReciprocity > 0.001, scene.key < 0.30 {
      notes.append("Slow film starved in the dark")
    }
    if recipe.highlightSmear > 0.001, scene.key < 0.30 {
      notes.append("Hot highlights smeared down the frame")
    }
    // Directive §8: decision notes come from real analysis only. The static
    // per-camera vocabulary is intentionally NOT used as filler — an empty or
    // short list is the honest result for a scene the camera left alone.
    return Array(notes.prefix(4))
  }

  private func formattedStops(_ value: Double) -> String {
    String(format: "%.1f stops", value)
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, self))
  }
}




