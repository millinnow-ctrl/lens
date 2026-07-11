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

final class FilmEngine {
  static let shared = FilmEngine()

  private let context: CIContext
  private let analyzer: SceneAnalyzer
  private let lutLoader = LUTLoader()
  private let grainKernel: CIColorKernel?

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
  }

  func develop(
    _ source: UIImage,
    with recipe: CameraRecipe,
    maxPixelSize: CGFloat? = nil,
    seed: Double = 1
  ) throws -> FilmRenderResult {
    guard var image = CIImage(
      image: source,
      options: [.applyOrientationProperty: true]
    ) else {
      throw FilmEngineError.unreadableImage
    }

    image = image.orientedForDisplay
    let scene = try analyzer.analyze(image)
    let subject = (try? VisionService.analyze(source)) ?? SubjectAnalysis(faces: [], personMask: nil)

    if let maxPixelSize {
      image = scaled(image, maxPixelSize: maxPixelSize)
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

    if recipe.protectsFaces, !subject.faces.isEmpty {
      image = applyFaceProtection(image, faces: subject.faces, amount: scene.isBacklit ? 0.22 : 0.10)
    }
    if recipe.monochrome {
      image = image.applyingFilter("CIPhotoEffectMono")
    }
    image = applyBloom(image, amount: recipe.bloom)
    image = applyVignette(image, amount: recipe.vignette)
    image = applyGrain(image, amount: recipe.grain, size: recipe.grainSize, seed: seed)
    if recipe.monochrome {
      // Enforce the invariant after every spatial and lighting pass.
      image = image.applyingFilter("CIColorMonochrome", parameters: [
        kCIInputColorKey: CIColor.white,
        kCIInputIntensityKey: 1,
      ])
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

  private func adaptiveExposure(for scene: SceneProfile, recipe: CameraRecipe) -> Double {
    guard recipe.engineClass == .adaptive else { return 0 }
    let target = scene.isLowKey ? 0.42 : 0.50
    let correction = log2(max(0.08, target) / max(0.08, scene.medianLuminance))
    return correction.clamped(to: -0.85...0.85) * recipe.adaptiveExposure
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
      return image
        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.22])
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 0.45, y: 0.18, z: 0.08, w: 0),
          "inputGVector": CIVector(x: 0.12, y: 0.88, z: 0.22, w: 0),
          "inputBVector": CIVector(x: 0.08, y: 0.22, z: 0.46, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: 0, y: 0.04, z: 0, w: 0),
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

  private func applyBloom(_ image: CIImage, amount: Double) -> CIImage {
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
    for note in recipe.decisionVocabulary where notes.count < 4 {
      if !notes.contains(note) { notes.append(note) }
    }
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
