import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The opt-in "shot on a $7,000 camera" modulation. These two passes run only
/// when a `CaptureSettings` is supplied and it is not at the loaded camera's
/// home — so the default develop path (and every golden-fixture parity test)
/// is byte-for-byte unchanged.
///
/// Stage 1 (pre-core) re-lights the *input* to the LUT/adaptive color core, so
/// the exposure and white-balance dials genuinely change how the film renders,
/// not merely brighten the finished frame. Stage 2 (post-core) adds the
/// physical consequences of the exposure triangle — depth-of-field from a wide
/// aperture, motion from a slow shutter, sensor grain from high ISO, flash.
extension FilmEngine {
  /// Stage 1 — the light the film sees. Inserted before the color core.
  func applyCaptureLight(_ image: CIImage, capture: CaptureSettings, recipe: CameraRecipe) -> CIImage {
    var out = image

    // white balance: warm dial pushes red up / blue down
    let w = capture.warmthWB
    if abs(w) > 0.001 {
      out = out.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 1 + w * 0.22, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 1 - w * 0.22, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ]).cropped(to: image.extent)
    }

    // exposure: the dialed EV the sensor didn't already realize
    let ev = min(4, max(-4, capture.appliedEV))
    if abs(ev) > 0.001 {
      out = out.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
      // re-shoulder so a LUT stock doesn't clip when pushed
      out = out.applyingFilter("CIHighlightShadowAdjust", parameters: [
        "inputHighlightAmount": 1 - min(0.35, max(0, ev) * 0.12),
        "inputShadowAmount": min(0.30, max(0, -ev) * 0.12),
      ]).cropped(to: image.extent)
    }
    return out
  }

  /// Scene-aware auto studio lighting — the "adjusts the lighting when you take
  /// the photo" pass. Balances the scene toward a well-lit target, recovers
  /// shadows, tames highlights, and lifts the detected subject like a key light,
  /// per capture mode. Runs before the color core so the film develops the
  /// relit scene. Computational (Vision + Core Image), not a neural relighter.
  func applyStudioRelight(
    _ image: CIImage,
    capture: CaptureSettings,
    scene: SceneProfile,
    subject: SubjectAnalysis
  ) -> CIImage {
    let mode = capture.captureMode
    let extent = image.extent
    var out = image

    // 1 — nudge global exposure toward the mode's target brightness
    let median = max(0.04, scene.medianLuminance)
    let ev = min(1.2, max(-0.8, log2(mode.exposureTarget / median))) * 0.7
    if abs(ev) > 0.01 {
      out = out.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
    }

    // 2 — recover shadows, hold highlights
    out = out.applyingFilter("CIHighlightShadowAdjust", parameters: [
      "inputShadowAmount": mode.shadowLift,
      "inputHighlightAmount": 0.86,
    ]).cropped(to: extent)

    // 3 — key light on the detected subject
    if let person = subject.personMask, mode.subjectKeyEV > 0.01 {
      let sx = extent.width / max(1, person.extent.width)
      let sy = extent.height / max(1, person.extent.height)
      let mask = person.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).cropped(to: extent)
      let lit = out.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: mode.subjectKeyEV])
      out = lit.applyingFilter("CIBlendWithMask", parameters: [
        "inputBackgroundImage": out,
        kCIInputMaskImageKey: mask,
      ]).cropped(to: extent)
    }

    // 4 — night: soften sensor noise
    if mode == .night {
      out = out.applyingFilter("CINoiseReduction", parameters: [
        "inputNoiseLevel": 0.03,
        "inputSharpness": 0.4,
      ]).cropped(to: extent)
    }

    return out.cropped(to: extent)
  }

  /// Stage 2 — the physical look of the settings. Inserted after grain and
  /// before the monochrome invariant / instant-frame passes.
  func applyCaptureLook(
    _ image: CIImage,
    capture: CaptureSettings,
    scene: SceneProfile,
    subject: SubjectAnalysis,
    recipe: CameraRecipe,
    seed: Double
  ) -> CIImage {
    var out = image
    let extent = image.extent
    let refScale = max(extent.width, extent.height) / 1000

    // 2a — aperture → depth of field (never blurs the subject / faces)
    if capture.bokehStrength > 0.05 {
      out = applyDepthOfField(out, strength: capture.bokehStrength, focus: capture.focusPoint,
                              subject: subject, refScale: refScale)
    }

    // 2b — shutter → motion blur
    if capture.motionStrength > 0.05 {
      let radius = min(6, capture.motionStrength) * 3 * refScale
      out = out.applyingFilter("CIMotionBlur", parameters: [
        kCIInputRadiusKey: radius,
        kCIInputAngleKey: 0,
      ]).cropped(to: extent)
    }

    // deep-focus / fast-shutter bite (acutance)
    let acutance = capture.deepFocusAcutance + capture.slowShutterAcutance
    if acutance > 0.001 {
      out = out.applyingFilter("CISharpenLuminance", parameters: [
        kCIInputSharpnessKey: acutance,
      ]).cropped(to: extent)
    }

    // 2c — ISO → sensor noise (shadow-weighted, deterministic)
    if capture.isoNoiseAmplitude > 0.001, let kernel = captureNoiseKernel {
      let chroma: Double = capture.isoStops > 3 ? 1 : 0
      let mono: Double = recipe.monochrome ? 1 : 0
      let noised = kernel.apply(extent: extent, arguments: [
        out, capture.isoNoiseAmplitude, seed + 7,
        max(0.5, 1 + max(0, capture.isoStops) * 0.05), chroma, mono,
      ]) ?? out
      out = noised.cropped(to: extent)
      if capture.isoSaturationMultiplier < 0.999 {
        out = out.applyingFilter("CIColorControls", parameters: [
          kCIInputSaturationKey: capture.isoSaturationMultiplier,
        ]).cropped(to: extent)
      }
    }

    // 2d — flash (when fired)
    if capture.flashMode != .off {
      let affinity = Self.flashAffinity(recipe.id)
      out = out.applyingFilter("CIExposureAdjust", parameters: [
        kCIInputEVKey: 0.10 * affinity,
      ])
      out = applyBloom(out, amount: recipe.bloom + 0.05 * affinity)
    }

    // 2e — wide-open veiling glow
    if capture.extraWideOpenGlow > 0.001 {
      out = applyBloom(out, amount: capture.extraWideOpenGlow)
    }

    return out.cropped(to: extent)
  }

  private func applyDepthOfField(
    _ image: CIImage,
    strength: Double,
    focus: CGPoint,
    subject: SubjectAnalysis,
    refScale: CGFloat
  ) -> CIImage {
    let extent = image.extent
    let blurR = strength * 16 * refScale

    // build a blur-amount mask: white = blur (background), black = keep sharp
    let mask: CIImage
    if let person = subject.personMask {
      // scale the segmentation to the working extent, then invert so the
      // background is what blurs and the person stays sharp
      let scaleX = extent.width / max(1, person.extent.width)
      let scaleY = extent.height / max(1, person.extent.height)
      let scaled = person
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        .cropped(to: extent)
      mask = scaled.applyingFilter("CIColorInvert")
    } else {
      // radial: sharp at the focus point, blurred toward the edges
      let cx = extent.minX + focus.x * extent.width
      let cy = extent.minY + (1 - focus.y) * extent.height
      let inner = min(extent.width, extent.height) * 0.28
      let outer = max(extent.width, extent.height) * 0.72
      mask = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": CIVector(x: cx, y: cy),
        "inputRadius0": inner,
        "inputRadius1": outer,
        "inputColor0": CIColor.black,
        "inputColor1": CIColor.white,
      ])?.outputImage?.cropped(to: extent) ?? CIImage(color: .white).cropped(to: extent)
    }

    let blurred = image.applyingFilter("CIMaskedVariableBlur", parameters: [
      "inputMask": mask,
      kCIInputRadiusKey: blurR,
    ])
    return blurred.cropped(to: extent)
  }

  /// how strongly a camera personality reacts to firing the flash
  static func flashAffinity(_ id: String) -> Double {
    switch id {
    case "disposable", "iphone-flash", "y2k-digicam", "photobooth", "point-shoot": return 1.0
    case "tokyo-neon", "super-8", "polaroid": return 0.6
    case "leica-street", "a24-still", "kodachrome", "film-noir": return 0.3
    default: return 0.5
    }
  }
}
