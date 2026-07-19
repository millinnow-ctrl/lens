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
    amount: Double,
    highlightHeadroom: Double = 0
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
      // R78: on a headroom stock whose flashed faces already sit near clip —
      // photobooth especially, whose mono conversion defeats the specular's
      // saturation guard so EVERY bright pixel reads as a mirror — lift the
      // threshold toward the very top and cut the push, so only genuine glints
      // (catchlights, glass) pop and the face body keeps its structure.
      let loFrac = 0.55 + 0.38 * highlightHeadroom
      let lo = scene.p50 + (scene.p99 - scene.p50) * loFrac
      let hi = max(scene.p99, lo + 0.04) + 0.02
      let push = 0.5 * amount * (1 - 0.6 * highlightHeadroom)
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
    let emissive = FilmEngine.emissiveLights(in: scene)
    guard amount > 0.001, scene.analyzed, !emissive.isEmpty else {
      return applyBloom(image, amount: baseBloom)
    }
    let extent = image.extent
    let maxEdge = max(extent.width, extent.height)

    // 1 — accumulate one tinted radial glow per source.
    // First night-evidence review: linear-ramp sprites at full radius read as
    // giant white discs. Fixes: square the ramp (gaussian-ish falloff like the
    // approved prototype), cap the radius, and treat near-white sources
    // (streetlamps) as tight warm glows at reduced strength — only strongly
    // colored sources (actual neon) throw wide halos.
    var accum = CIImage(color: .black).cropped(to: extent)
    for light in emissive {
      let center = CIVector(
        x: extent.minX + light.x * extent.width,
        y: extent.minY + (1 - light.y) * extent.height
      )
      let tint = saturatedTint(light.tint, boost: 1.8)
      let tintMax = tint.max() ?? 1
      let tintMin = tint.min() ?? 1
      let colorfulness = tintMax > 1e-4 ? (tintMax - tintMin) / tintMax : 0
      let whiteness = 1 - min(1, colorfulness / 0.5)  // 1 = white lamp, 0 = neon
      let core = max(light.r * maxEdge, 3)
      var outer = core * (2.2 + 1.8 * amount) * (1 - 0.45 * whiteness)
      outer = min(outer, maxEdge * 0.15)
      let strength = (0.35 + 0.65 * min(1, light.intensity)) * (1 - 0.5 * whiteness)
      guard let sprite = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center,
        "inputRadius0": core * 0.3,
        "inputRadius1": max(outer, core * 0.3 + 1),
        "inputColor0": CIColor(
          red: tint[0] * strength,
          green: tint[1] * strength,
          blue: tint[2] * strength
        ),
        "inputColor1": CIColor.black,
      ])?.outputImage?.cropped(to: extent) else { continue }
      // square the linear ramp → soft gaussian-like falloff, no hard disc edge
      let soft = sprite.applyingFilter("CIMultiplyBlendMode", parameters: [
        kCIInputBackgroundImageKey: sprite,
      ]).cropped(to: extent)
      accum = soft.applyingFilter("CIScreenBlendMode", parameters: [
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

  /// Sources that are genuinely emissive. Neon does not exist under the sun:
  /// bright scenes refuse outright (the daylight golden regressed when the
  /// sun's warm glow annulus slipped a tint-only gate). In the dark, any hot
  /// source glows (tungsten, LED, neon); in the dusk band, only clearly
  /// colored ones. Internal (and static — pure function of the scene) so
  /// decision notes AND the Conductor's rail ranking use the same gate.
  static func emissiveLights(in scene: SceneProfile) -> [LightSource] {
    guard scene.key < 0.35 else { return [] }
    // lights = the meter's specular-knee sources; auxLights = R63 chroma pass
    // (saturated colored emitters like blue neon that luma detection misses)
    return (scene.lights + scene.auxLights).filter { light in
      guard light.tint.count == 3 else { return false }
      let mx = light.tint.max() ?? 0
      let mn = light.tint.min() ?? 0
      let tintSaturation = mx > 1e-4 ? (mx - mn) / mx : 0
      if scene.key < 0.30 {
        return tintSaturation > 0.10 || light.intensity > 0.5
      }
      return tintSaturation > 0.30
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
    guard amount > 0.001, scene.analyzed,
          let key = scene.lights.first ?? scene.auxLights.first,
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

  // MARK: - Night reciprocity (super-8)

  /// Slow emulsion cannot see in the dark. ISO-40 movie film at night is
  /// starved: exposure collapses, shadows crush to color-starved black
  /// (reciprocity failure) — instead of shipping the phone's full shadow
  /// detail with a warm cast. Applied BEFORE the color core; strictly gated on
  /// scene darkness so daylight renders (and the golden) are byte-identical.
  /// `protectEmissive` is the R62.1 carve-out (parity correction to the
  /// ratified "only the neon survives" verdict). It is `true` on the shipping
  /// path; the evidence test renders `false` to reconstruct the pre-carve
  /// "before". When there are no emissive sources (e.g. the daylight parity
  /// golden, or any scene with no colored/hot lights) the carve-out is a
  /// structural no-op and the output is byte-identical to the uniform starve.
  func applyNightReciprocity(
    _ image: CIImage,
    scene: SceneProfile,
    amount: Double,
    protectEmissive: Bool = true
  ) -> CIImage {
    guard amount > 0.001, scene.analyzed else { return image }
    let darkness = max(0, min(1, (0.30 - scene.key) / 0.30))
    guard darkness > 0.05 else { return image }
    let extent = image.extent
    let starved = image
      .applyingFilter("CIExposureAdjust", parameters: [
        kCIInputEVKey: -2.0 * darkness * amount,
      ])
      .applyingFilter("CIGammaAdjust", parameters: [
        "inputPower": 1.0 + 0.85 * darkness * amount,
      ])
      .applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 1.0 - 0.35 * darkness * amount,
      ])
      .cropped(to: extent)

    // R62.1 carve-out: real ISO-40 movie film photographing a lit neon sign
    // still records the sign even as the street dies. Uniform −2 EV erased it
    // (the develop-screen review returned an essentially black frame). When
    // the meter found emissive sources, hold the brightest emissive highlights
    // back from the collapse so signs/lamps stay readable; the desaturated
    // shadows still crush. Gated on emissive presence, so daylight (and the
    // golden) render byte-identically to the uniform starve.
    guard protectEmissive,
          !FilmEngine.emissiveLights(in: scene).isEmpty,
          let maskKernel = nightEmissiveMaskKernel else { return starved }
    let t0 = min(0.90, max(0.55, scene.p99 - 0.10))
    let t1 = min(1.0, t0 + 0.14)
    // deeper night → stronger neon survival, with a floor so the sign is
    // clearly readable ("only the neon survives"); capped below 1 so it is
    // still touched by the pull (not a hole punched in the reciprocity)
    let strength = min(0.90, 0.45 + 0.55 * darkness)
    guard let mask = maskKernel.apply(
      extent: extent, arguments: [image, t0, t1, strength]
    ) else { return starved }
    return starved.applyingFilter("CIBlendWithMask", parameters: [
      kCIInputImageKey: image,               // the original neon survives here
      kCIInputBackgroundImageKey: starved,   // the starved street everywhere else
      kCIInputMaskImageKey: mask,
    ]).cropped(to: extent)
  }

  // MARK: - CCD sensor behavior (y2k-digicam, camcorder-90s)

  /// Early-CCD highlight response: no film shoulder — highlights race to full
  /// clip. The opposite of a milky lift. Curve tempered after the first
  /// night-evidence review: the harder shoulder posterized already-saturated
  /// night skies (per-channel clip exaggerating hue splits).
  func applyCCDClip(_ image: CIImage, amount: Double) -> CIImage {
    guard amount > 0.001 else { return image }
    return image.applyingFilter("CIToneCurve", parameters: [
      "inputPoint0": CIVector(x: 0, y: 0),
      "inputPoint1": CIVector(x: 0.25, y: 0.24),
      "inputPoint2": CIVector(x: 0.5, y: 0.51),
      "inputPoint3": CIVector(x: 0.78, y: 0.82),
      "inputPoint4": CIVector(x: 0.95, y: 1.0),
    ]).cropped(to: image.extent)
  }

  /// CCD charge-overflow blooming / tube comet-tails: clipped highlights smear
  /// VERTICALLY down the sensor column, carrying the highlight's own color.
  /// `onlyInDark` models tube cameras whose smear shows at night gain; CCD
  /// stills smear on hot speculars in any light (scaled up in darkness).
  func applyHighlightSmear(
    _ image: CIImage,
    scene: SceneProfile,
    amount: Double,
    onlyInDark: Bool
  ) -> CIImage {
    guard amount > 0.001, let kernel = clipMaskKernel else { return image }
    let darkness = max(0, min(1, (0.35 - scene.key) / 0.35))
    if onlyInDark, darkness <= 0.05 { return image }
    let strength = amount * (onlyInDark ? darkness : (0.45 + 0.55 * darkness))
    guard strength > 0.02 else { return image }
    let extent = image.extent
    guard let clipped = kernel.apply(extent: extent, arguments: [image, 0.90, 0.985]) else {
      return image
    }
    let radius = max(extent.width, extent.height) * 0.035 * strength
    let smear = clipped
      .clampedToExtent()
      .applyingFilter("CIMotionBlur", parameters: [
        kCIInputRadiusKey: radius,
        kCIInputAngleKey: Double.pi / 2, // vertical: down the sensor column
      ])
      .cropped(to: extent)
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.55 * strength, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0.55 * strength, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0.55 * strength, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ])
    return smear.applyingFilter("CIScreenBlendMode", parameters: [
      kCIInputBackgroundImageKey: image,
    ]).cropped(to: extent)
  }
}
