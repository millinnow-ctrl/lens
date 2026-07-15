import CoreImage
import UIKit

/// R61 light-intelligence passes — the light is READ from the photograph, not
/// painted over it. Validated first as a local prototype tournament on real
/// photos (flash falloff/speculars, source-hued bloom, directional noir), then
/// ported here against the physics critique:
///  · flash backgrounds fall toward ambient, they never lift;
///  · colored glow only ever emanates from detected emissive sources;
///  · noir gains an actual key-light direction instead of a global curve;
///  · video "sensor noise" follows scene darkness like real AGC gain.
/// All passes are deterministic (no randomness) and gated per-recipe, so every
/// other stock renders byte-identically to before.
///
/// Label: intentional camera refinement (owner-directed light physics).
extension FilmEngine {

  // MARK: - Flash physics (iphone-flash, photobooth, y2k-digicam, point-shoot, disposable)

  /// Specular pop on reflective surfaces + subject-anchored falloff.
  /// The specular map is scene-relative (top-percentile luminance, desaturated
  /// pixels — glass, screens, metal, eyes) so daylight scenes aren't fogged.
  /// Falloff pulls the background DOWN toward ambient — scaled by scene
  /// darkness so a bright-day photo keeps its world and a night shot plunges.
  func applyFlashPhysics(
    _ image: CIImage,
    scene: SceneProfile,
    subject: SubjectAnalysis,
    amount: Double
  ) -> CIImage {
    guard amount > 0.001 else { return image }
    let extent = image.extent
    var out = image

    // 1 — near/far falloff (before speculars so they ride on top).
    let darkness = max(0, min(1, (0.5 - scene.key) / 0.5))
    let fall = amount * (0.10 + 0.48 * pow(darkness, 1.2))
    if fall > 0.02, let nearMask = flashNearMask(for: image, subject: subject) {
      let lift = 0.08 * amount
      if let kernel = flashFalloffKernel {
        let shaded = kernel.apply(
          extent: extent,
          arguments: [out, nearMask, fall, lift]
        )
        if let shaded { out = shaded.cropped(to: extent) }
      }
    }

    // 2 — speculars: bright + desaturated pixels catch the flash and bloom.
    if let kernel = flashSpecularKernel {
      let lo = scene.p50 + (scene.p99 - scene.p50) * 0.55
      let hi = max(scene.p99, lo + 0.04) + 0.02
      let push = 0.5 * amount
      if let specced = kernel.apply(extent: extent, arguments: [out, lo, hi, push]) {
        out = specced.cropped(to: extent)
      }
    }
    return out
  }

  /// The "near the flash" mask: the Vision person cut-out when available,
  /// else a radial field around the detected faces. `nil` skips falloff
  /// (speculars still apply) — never a fabricated subject.
  private func flashNearMask(for image: CIImage, subject: SubjectAnalysis) -> CIImage? {
    let extent = image.extent
    if let person = subject.personMask {
      let scaleX = extent.width / max(1, person.extent.width)
      let scaleY = extent.height / max(1, person.extent.height)
      let scaled = person
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        .cropped(to: extent)
      // soften the cut edge so the falloff reads as light, not a sticker
      return scaled
        .applyingFilter("CIGaussianBlur", parameters: [
          kCIInputRadiusKey: max(extent.width, extent.height) * 0.015,
        ])
        .cropped(to: extent)
    }
    guard !subject.faces.isEmpty else { return nil }
    var mask = CIImage(color: .black).cropped(to: extent)
    for face in subject.faces {
      let center = CIVector(
        x: extent.minX + face.bounds.midX * extent.width,
        y: extent.minY + (1 - face.bounds.midY) * extent.height
      )
      let radius = max(
        face.bounds.width * extent.width,
        face.bounds.height * extent.height
      ) * 2.4 // flash reaches the torso, not just the face
      guard radius > 1 else { continue }
      guard let blob = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center,
        "inputRadius0": radius * 0.35,
        "inputRadius1": radius,
        "inputColor0": CIColor.white,
        "inputColor1": CIColor.black,
      ])?.outputImage?.cropped(to: extent) else { continue }
      mask = blob.applyingFilter("CILightenBlendMode", parameters: [
        kCIInputBackgroundImageKey: mask,
      ]).cropped(to: extent)
    }
    return mask
  }

  // MARK: - Source-aware bloom (tokyo-neon)

  /// Bloom that emanates from the meter's detected light sources in each
  /// source's OWN hue — an amber lamp glows amber, a pink sign glows pink —
  /// with unlit areas sinking slightly so the glow reads as illumination.
  /// Refusal rule (physics critique): when the scene has no emissive sources
  /// (no colored lights, not a dark scene), no colored glow is added — the
  /// stock's plain bloom applies instead, so daylight never turns magenta.
  func applySourceBloom(
    _ image: CIImage,
    scene: SceneProfile,
    baseBloom: Double,
    amount: Double
  ) -> CIImage {
    let emissive = emissiveLights(in: scene)
    guard amount > 0.001, scene.analyzed, !emissive.isEmpty else {
      return applyBloom(image, amount: baseBloom)
    }
    let extent = image.extent
    let maxEdge = max(extent.width, extent.height)

    // 1 — accumulate one tinted radial glow per source.
    var accum = CIImage(color: .black).cropped(to: extent)
    for light in emissive {
      let center = CIVector(
        x: extent.minX + light.x * extent.width,
        y: extent.minY + (1 - light.y) * extent.height
      )
      let core = max(light.r * maxEdge, 3)
      let outer = core * (3.5 + 3.0 * amount)
      let strength = 0.35 + 0.65 * min(1, light.intensity)
      let tint = saturatedTint(light.tint, boost: 1.8)
      guard let sprite = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center,
        "inputRadius0": core * 0.4,
        "inputRadius1": outer,
        "inputColor0": CIColor(
          red: tint[0] * strength,
          green: tint[1] * strength,
          blue: tint[2] * strength
        ),
        "inputColor1": CIColor.black,
      ])?.outputImage?.cropped(to: extent) else { continue }
      accum = sprite.applyingFilter("CIScreenBlendMode", parameters: [
        kCIInputBackgroundImageKey: accum,
      ]).cropped(to: extent)
    }

    // 2 — screen the glow over the image (strength-scaled).
    let glow = accum.applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: 0.75 * amount, y: 0, z: 0, w: 0),
      "inputGVector": CIVector(x: 0, y: 0.75 * amount, z: 0, w: 0),
      "inputBVector": CIVector(x: 0, y: 0, z: 0.75 * amount, w: 0),
      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
    ])
    var out = glow.applyingFilter("CIScreenBlendMode", parameters: [
      kCIInputBackgroundImageKey: image,
    ]).cropped(to: extent)

    // 3 — unlit areas sink a touch: gain = (1-s) + s*glowLuma, s = 0.16*amount.
    let sink = 0.16 * amount
    let gain = accum
      .applyingFilter("CIColorMonochrome", parameters: [
        kCIInputColorKey: CIColor.white,
        kCIInputIntensityKey: 1,
      ])
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: sink, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: sink, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: sink, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 1 - sink, y: 1 - sink, z: 1 - sink, w: 0),
      ])
    out = out.applyingFilter("CIMultiplyBlendMode", parameters: [
      kCIInputBackgroundImageKey: gain,
    ]).cropped(to: extent)

    // 4 — the stock's own halation, reduced: sources carry the glow now.
    return applyBloom(out, amount: baseBloom * 0.4)
  }

  /// Sources that are genuinely emissive: visibly colored (tint saturation)
  /// or any hot source in a dark scene. A white sky patch on an overcast day
  /// is NOT an emissive source. Internal so decision notes use the same gate.
  func emissiveLights(in scene: SceneProfile) -> [LightSource] {
    scene.lights.filter { light in
      guard light.tint.count == 3 else { return false }
      let mx = light.tint.max() ?? 0
      let mn = light.tint.min() ?? 0
      let tintSaturation = mx > 1e-4 ? (mx - mn) / mx : 0
      return tintSaturation > 0.18 || scene.key < 0.30
    }
  }

  private func saturatedTint(_ tint: [Double], boost: Double) -> [Double] {
    guard tint.count == 3 else { return [1, 1, 1] }
    let mean = (tint[0] + tint[1] + tint[2]) / 3
    return tint.map { max(0, min(1, mean + ($0 - mean) * boost)) }
  }

  // MARK: - Directional key shadow (film-noir)

  /// Shadows deepen with distance from the detected key light, so the frame
  /// gains an actual light direction — highlights hold, the far side falls.
  /// The largest face is partially preserved so the subject keeps reading.
  /// Skips honestly when the meter found no light source to key from.
  func applyKeyShadow(
    _ image: CIImage,
    scene: SceneProfile,
    subject: SubjectAnalysis,
    amount: Double
  ) -> CIImage {
    guard amount > 0.001, scene.analyzed, let key = scene.lights.first,
          let kernel = keyShadowKernel else { return image }
    let extent = image.extent
    let keyX = extent.minX + key.x * extent.width
    let keyY = extent.minY + (1 - key.y) * extent.height
    let diag = sqrt(extent.width * extent.width + extent.height * extent.height)

    // largest face → partial preservation inside its radius
    var faceX = -10_000.0, faceY = -10_000.0, faceR = 1.0
    if let face = subject.faces.max(by: {
      $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
    }) {
      faceX = extent.minX + face.bounds.midX * extent.width
      faceY = extent.minY + (1 - face.bounds.midY) * extent.height
      faceR = max(
        face.bounds.width * extent.width,
        face.bounds.height * extent.height
      ) * 1.1
    }

    let shaded = kernel.apply(extent: extent, arguments: [
      image, keyX, keyY, 1.0 / max(diag * 0.85, 1), 0.55 * amount,
      faceX, faceY, faceR,
    ])
    return shaded?.cropped(to: extent) ?? image
  }

  // MARK: - Video gain (security-cam, camcorder-90s)

  /// AGC behavior: grain amplitude follows scene darkness. A night street runs
  /// the gain flat-out (noise explodes); a daylight scene is near-clean and
  /// only the look's structural character remains.
  static func gainGrainFactor(key: Double) -> Double {
    let darkness = max(0, min(1, (0.45 - key) / 0.45))
    return 0.4 + 1.3 * pow(darkness, 1.1)
  }
}
