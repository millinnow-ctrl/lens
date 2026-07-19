import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// R78 lens fix-wave — owner-approval evidence. Each fix that changes a render
/// publishes a before/after pair to `ui-artifacts/lens-fixes/` (force-pushed to
/// the ci-captures branch by CI) so the owner rules on the look. Assertions
/// beyond existence are the numeric regression pins for each fix; the final
/// judgement is by eye, per the directive ("done means visually approved").
final class LensFixEvidenceTests: XCTestCase {

  /// Same working/output space as FilmEngine's production context (sRGB) so the
  /// kernels' luma thresholds read the same values they do in the app.
  private let context: CIContext = {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    return CIContext(options: [
      .workingColorSpace: sRGB,
      .outputColorSpace: sRGB,
      .useSoftwareRenderer: false,
    ])
  }()

  private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  private static let repoRoot = testsDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private func outDir() throws -> URL {
    let dir = Self.testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/lens-fixes")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func source(_ name: String) -> UIImage? {
    UIImage(contentsOfFile: Self.repoRoot.appendingPathComponent("reference/photos/\(name)").path)
  }

  private func writePNG(_ image: CIImage, to url: URL) throws {
    let extent = image.extent.integral
    guard let cg = context.createCGImage(image, from: extent) else {
      throw XCTSkip("could not rasterize \(url.lastPathComponent)")
    }
    try XCTUnwrap(UIImage(cgImage: cg).pngData()).write(to: url)
  }

  private func scaled(_ image: CIImage, maxPixelSize: CGFloat) -> CIImage {
    let largest = max(image.extent.width, image.extent.height)
    guard largest > maxPixelSize, largest > 0 else { return image }
    return image.applyingFilter("CILanczosScaleTransform", parameters: [
      kCIInputScaleKey: maxPixelSize / largest,
      kCIInputAspectRatioKey: 1,
    ])
  }

  // MARK: - Super-8 night reciprocity emissive carve-out (§10.1)

  /// Isolates the exact stage that changed: the −2 EV night starve, WITHOUT the
  /// carve-out (before) vs WITH it (after), on the real night-street fixture.
  /// The full-develop look lives in night-evidence/night-super-8.png; this pair
  /// shows the carve-out doing its one job — letting the lit neon survive.
  func testSuper8NightReciprocityEvidence() throws {
    guard let source = source("sample-night.jpg") else {
      throw XCTSkip("missing sample-night.jpg")
    }
    let engine = FilmEngine()
    let scene = try engine.read(source, analyzeSubjects: false).scene
    XCTAssertFalse(FilmEngine.emissiveLights(in: scene).isEmpty,
                   "sample-night must meter as an emissive (neon) scene for the carve-out")
    guard let ci = CIImage(image: source, options: [.applyOrientationProperty: true]) else {
      throw XCTSkip("unreadable source")
    }
    let base = scaled(ci.orientedForDisplay, maxPixelSize: 560)

    let before = engine.applyNightReciprocity(base, scene: scene, amount: 1.0, protectEmissive: false)
    let after = engine.applyNightReciprocity(base, scene: scene, amount: 1.0, protectEmissive: true)

    let dir = try outDir()
    try writePNG(base, to: dir.appendingPathComponent("super-8-source.png"))
    try writePNG(before, to: dir.appendingPathComponent("super-8-before.png"))
    try writePNG(after, to: dir.appendingPathComponent("super-8-after.png"))

    // Numeric guard: the carve-out must add highlight energy back (the neon)
    // without materially lifting the frame's mean (the street must still die).
    guard let beforeR = ImageMetrics.raster(cgImage(before)),
          let afterR = ImageMetrics.raster(cgImage(after)) else {
      return XCTFail("raster failed")
    }
    let beforeHi = ImageMetrics.highlightClipRate(beforeR, threshold: 140)
    let afterHi = ImageMetrics.highlightClipRate(afterR, threshold: 140)
    XCTAssertGreaterThan(afterHi, beforeHi,
                         "the carve-out must let bright emissive highlights survive the starve")
    let meanDelta = meanLuma(afterR) - meanLuma(beforeR)
    XCTAssertLessThan(meanDelta, 12,
                      "only the neon returns — the starve must not become a global lift")
  }

  // MARK: - Photobooth flashed-face blowout (§17.1)

  /// The identity-breaking fix: the face-first stock erased faces on its own
  /// scene class (measured 68% / 49% of face-crop pixels ≥ 250 luma). Renders
  /// photobooth on the friends fixture with the flash headroom OFF (before) and
  /// ON (after), publishes the pair, and pins the reduction. CI's simulator
  /// Vision returns no faces, so the primary pin measures the fixed flashed-
  /// subject region (around the meter's focal probe); a best-effort per-face
  /// pin runs too when faces are detected (device / future matte harness).
  func testPhotoboothFaceHeadroomEvidence() throws {
    guard let source = source("sample-friends.jpg") else {
      throw XCTSkip("missing sample-friends.jpg")
    }
    let engine = FilmEngine()
    let reading = try engine.read(source)
    let recipe = CameraRecipe.recipe(for: "photobooth")
    XCTAssertGreaterThan(recipe.flashHighlightHeadroom, 0, "photobooth must carry the headroom")

    // grid-resolution render (matches the audit measurement condition)
    let after = try engine.develop(source, with: recipe, maxPixelSize: 1024, seed: 1, reading: reading)
    let before = try engine.develop(
      source, with: withoutFlashHeadroom(recipe), maxPixelSize: 1024, seed: 1, reading: reading
    )

    let dir = try outDir()
    try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("photobooth-before.png"))
    try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("photobooth-after.png"))

    guard let beforeR = ImageMetrics.raster(before.image),
          let afterR = ImageMetrics.raster(after.image) else {
      return XCTFail("raster failed")
    }

    // Primary (Vision-independent): the flashed-subject region the meter's
    // default focal probe points at (0.5, 0.42) — the faces that blew out.
    let subject = CGRect(x: 0.25, y: 0.20, width: 0.50, height: 0.45)
    let beforeClip = ImageMetrics.highlightClipRate(beforeR, in: subject, threshold: 250)
    let afterClip = ImageMetrics.highlightClipRate(afterR, in: subject, threshold: 250)
    print("photobooth flashed-subject clip ≥250: before \(beforeClip) after \(afterClip)")
    // The headroom removes the subject over-lifts, so the fused-white bulk drops
    // below clip. Require a real reduction (>=30%) and a low absolute floor.
    XCTAssertLessThan(afterClip, beforeClip * 0.7,
                      "flash headroom must materially reduce the flashed-subject blowout")
    XCTAssertLessThan(afterClip, 0.10,
                      "the flashed subject must keep structure — not fuse to paper-white")

    // Best-effort per-face (runs when Vision detected faces).
    for face in after.faces {
      let b = ImageMetrics.highlightClipRate(beforeR, in: face.bounds, threshold: 250)
      let a = ImageMetrics.highlightClipRate(afterR, in: face.bounds, threshold: 250)
      print("photobooth face clip ≥250: before \(b) after \(a)")
      if b > 0.12 {
        XCTAssertLessThan(a, b * 0.7, "a blown face must recover structure (>=30% less clip)")
        XCTAssertLessThan(a, 0.20, "a recovered face must not stay mostly paper-white")
      }
    }
  }

  // MARK: - y2k-digicam daylight blowout (owner report, R81)

  /// The glossy "Pocket 2002" was tuned on dark party scenes; on a bright, well-
  /// exposed daylight frame its CCD clip + double contrast + flash gloss stacked
  /// past clip and bleached whites and faces. The defect reproduces at the
  /// owner's key (~0.55): NO committed fixture is that bright (brightest is
  /// street at 0.404, whose pre-fix y2k pixels top out just under 250, so a ≥250
  /// metric reads 0 there — the guard still engages, weight 0.837, but there is
  /// nothing crossing clip to reduce). So the authoritative pin runs the real
  /// develop path on a deterministic owner-like bright raster + scene (key 0.55,
  /// whites at 0.90, mid faces at 0.70); street is rendered too, as real-photo
  /// before/after context. The guard weight is asserted > 0.9 so a silently
  /// disengaged guard can never pass.
  func testY2KDaylightGuardEvidence() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "y2k-digicam")
    XCTAssertGreaterThan(recipe.daylightHighlightGuard, 0, "y2k must carry the daylight guard")
    let dir = try outDir()

    // --- Authoritative: an owner-like bright daylight scene.
    let bright = brightDaylightImage()
    let scene = ownerLikeBrightScene()   // key 0.55
    let weight = FilmEngine.brightGuardWeight(scene)
    XCTAssertGreaterThan(weight, 0.9, "the guard must fully engage at the owner's daylight key")
    let reading = SceneReading(scene: scene, subject: SubjectAnalysis(faces: [], personMask: nil))

    let after = try engine.develop(bright, with: recipe, seed: 1, reading: reading)
    let before = try engine.develop(bright, with: withoutDaylightGuard(recipe), seed: 1, reading: reading)
    try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("y2k-daylight-before.png"))
    try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("y2k-daylight-after.png"))

    guard let beforeR = ImageMetrics.raster(before.image),
          let afterR = ImageMetrics.raster(after.image) else { return XCTFail("raster failed") }
    let beforeClip = ImageMetrics.highlightClipRate(beforeR, threshold: 250)
    let afterClip = ImageMetrics.highlightClipRate(afterR, threshold: 250)
    // disposable is the owner-ratified "good" reference for how much is right
    let dispo = try engine.develop(bright, with: .recipe(for: "disposable"), seed: 1, reading: reading)
    let dispoClip = ImageMetrics.raster(dispo.image).map { ImageMetrics.highlightClipRate($0, threshold: 250) } ?? -1
    print("y2k owner-like daylight clip ≥250: before \(beforeClip) after \(afterClip) (disposable \(dispoClip))")
    // non-degenerate: the pre-fix bleach must visibly exist, the guard must cut
    // it materially, and the fixed render must hold highlights off clip.
    XCTAssertGreaterThan(beforeClip, 0.30, "the pre-fix bleach must reproduce on the owner-like scene")
    XCTAssertLessThan(afterClip, beforeClip * 0.7, "the daylight guard must materially reduce the bleaching")
    XCTAssertLessThan(afterClip, 0.10, "y2k must stop bleaching daylight — highlights held off clip")

    // --- Real-photo context: the brightest committed fixture (street). Its pre-
    // fix y2k does not cross 250 (too dim for the owner's key) — reported, not
    // asserted — but the guard still pulls its highlights down; the pair is the
    // photograph the owner can review.
    guard let street = source("sample-street.jpg") else { return }
    let sreading = try engine.read(street)
    print("street metered key \(sreading.scene.key) → guard weight \(FilmEngine.brightGuardWeight(sreading.scene))")
    let sAfter = try engine.develop(street, with: recipe, maxPixelSize: 1024, seed: 1, reading: sreading)
    let sBefore = try engine.develop(street, with: withoutDaylightGuard(recipe), maxPixelSize: 1024, seed: 1, reading: sreading)
    try XCTUnwrap(sBefore.image.pngData()).write(to: dir.appendingPathComponent("y2k-street-before.png"))
    try XCTUnwrap(sAfter.image.pngData()).write(to: dir.appendingPathComponent("y2k-street-after.png"))
    for id in ["y2k-digicam", "point-shoot", "iphone-flash", "disposable"] {
      let r = try engine.develop(street, with: .recipe(for: id), maxPixelSize: 1024, seed: 1, reading: sreading)
      let clip = ImageMetrics.raster(r.image).map { ImageMetrics.highlightClipRate($0, threshold: 250) } ?? -1
      let clip240 = ImageMetrics.raster(r.image).map { ImageMetrics.highlightClipRate($0, threshold: 240) } ?? -1
      print("street clip: \(id) ≥250 \(clip) ≥240 \(clip240)")
    }
  }

  // MARK: - Photobooth daylight blowout (R84 item 1)

  /// Photobooth's unconditional flashHeadroom fixed NIGHT flashed faces; on a
  /// bright daylight frame the mono conversion + hard contrast still fused a
  /// large fraction of the frame to paper-white (critic B measured 21.7% pure
  /// white on the owner café frame). The daylightHighlightGuard adds the scene-
  /// keyed highlight rolloff (output capped ≈0.86 on full daylight) and raises
  /// the subject restraint to full, so the high-key B&W stays bright but OFF
  /// clip. Pinned on an owner-like bright raster where the blowout reproduces;
  /// night byte-identity is pinned on the friends fixture (guard weight 0).
  func testPhotoboothDaylightGuardEvidence() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "photobooth")
    XCTAssertGreaterThan(recipe.daylightHighlightGuard, 0, "photobooth must carry the daylight guard")
    let dir = try outDir()

    let bright = photoboothBrightImage()
    let scene = photoboothBrightScene()   // key 0.58, whites near clip
    let weight = FilmEngine.brightGuardWeight(scene)
    XCTAssertGreaterThan(weight, 0.9, "the guard must fully engage at the owner's daylight key")
    let reading = SceneReading(scene: scene, subject: SubjectAnalysis(faces: [], personMask: nil))

    let after = try engine.develop(bright, with: recipe, seed: 1, reading: reading)
    let before = try engine.develop(bright, with: withoutDaylightGuard(recipe), seed: 1, reading: reading)
    try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("photobooth-daylight-before.png"))
    try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("photobooth-daylight-after.png"))

    guard let beforeR = ImageMetrics.raster(before.image),
          let afterR = ImageMetrics.raster(after.image) else { return XCTFail("raster failed") }
    let beforeClip = ImageMetrics.highlightClipRate(beforeR, threshold: 250)
    let afterClip = ImageMetrics.highlightClipRate(afterR, threshold: 250)
    // the bright band (top 45% of the frame) — the shirts/background that blew.
    let hiBand = CGRect(x: 0, y: 0, width: 1, height: 0.45)
    let beforeHi = meanLuma(beforeR, in: hiBand)
    let afterHi = meanLuma(afterR, in: hiBand)
    print("photobooth daylight clip ≥250: before \(beforeClip) after \(afterClip); hi-band mean before \(beforeHi) after \(afterHi)")
    // Target (item 1): daylight clip < 5%. The rolloff caps highlight output, so
    // the after render holds off clip regardless of how hard the input clipped.
    XCTAssertLessThan(afterClip, 0.05, "photobooth must stop blowing daylight to paper-white")
    // Non-degenerate: the guard measurably pulls the blown band down (robust to
    // the exact clip fraction — the rolloff always lowers the highlight mean).
    XCTAssertGreaterThan(beforeHi - afterHi, 6, "the daylight guard must visibly hold the highlights back")
    // ...while it stays the brightest B&W — bright, not blown.
    XCTAssertGreaterThan(meanLuma(afterR, in: CGRect(x: 0, y: 0, width: 1, height: 1)), 120,
                         "photobooth must stay high-key (bright), not be darkened into a grey B&W")

    // Night byte-identity: on the dark party scene the guard weight is 0, so the
    // full recipe and the guard-off clone must render bit-for-bit identically.
    if let friends = source("sample-friends.jpg") {
      let nightReading = try engine.read(friends)
      XCTAssertEqual(FilmEngine.brightGuardWeight(nightReading.scene), 0, "friends must meter below the guard ramp")
      let nAfter = try engine.develop(friends, with: recipe, maxPixelSize: 512, seed: 1, reading: nightReading)
      let nBefore = try engine.develop(friends, with: withoutDaylightGuard(recipe), maxPixelSize: 512, seed: 1, reading: nightReading)
      XCTAssertEqual(
        try XCTUnwrap(nAfter.image.pngData()), try XCTUnwrap(nBefore.image.pngData()),
        "photobooth night must be byte-identical — the daylight guard is a no-op in the dark"
      )
    }
  }

  // MARK: - Direct Flash / Pocket Compact daylight wash (R84 item 2)

  /// The hard-flash family (iphone-flash, point-shoot) was tuned on dark party
  /// frames; on a bright daylight café the same face-lift + median chase just
  /// over-exposes — the whole frame lifts, the blacks never reach black (grey
  /// tabletop), skin goes waxy, the background verges on blown (critic A #4/#5).
  /// The scene-keyed guard rolls the highlights off and (as black-point stocks)
  /// commits the blacks + caps the adaptive lift. Pinned on a wash-prone bright
  /// scene (median below the exposure target, so the lift engages) where the
  /// defect reproduces: the guard must reclaim the shadow point and hold the
  /// highlights. Night byte-identity pinned on friends (guard weight 0).
  func testFlashWashDaylightGuardEvidence() throws {
    let engine = FilmEngine()
    let dir = try outDir()
    let bright = washProneImage()
    let scene = washProneScene()
    let weight = FilmEngine.brightGuardWeight(scene)
    XCTAssertGreaterThan(weight, 0.9, "the guard must fully engage on the bright wash scene")
    let reading = SceneReading(scene: scene, subject: SubjectAnalysis(faces: [], personMask: nil))
    // the shadow surface that floats grey (the "tabletop") and the bright band.
    let shadow = CGRect(x: 0.1, y: 0.80, width: 0.8, height: 0.17)
    let highlight = CGRect(x: 0, y: 0.02, width: 1, height: 0.33)

    for id in ["iphone-flash", "point-shoot"] {
      let recipe = CameraRecipe.recipe(for: id)
      XCTAssertGreaterThan(recipe.daylightHighlightGuard, 0, "\(id) must carry the daylight guard")
      XCTAssertTrue(FilmEngine.daylightBlackPointStocks.contains(id), "\(id) must be a black-point stock")

      let after = try engine.develop(bright, with: recipe, seed: 1, reading: reading)
      let before = try engine.develop(bright, with: withoutDaylightGuard(recipe), seed: 1, reading: reading)
      try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("\(id)-daylight-before.png"))
      try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("\(id)-daylight-after.png"))

      guard let beforeR = ImageMetrics.raster(before.image),
            let afterR = ImageMetrics.raster(after.image) else { return XCTFail("raster failed \(id)") }
      let beforeShadow = meanLuma(beforeR, in: shadow)
      let afterShadow = meanLuma(afterR, in: shadow)
      let beforeHi = meanLuma(beforeR, in: highlight)
      let afterHi = meanLuma(afterR, in: highlight)
      print("\(id) daylight: shadow before \(beforeShadow) after \(afterShadow); hi before \(beforeHi) after \(afterHi)")
      // black-point commitment: the floating shadow point is reclaimed to black.
      XCTAssertLessThan(afterShadow, beforeShadow - 5, "\(id): the daylight guard must reclaim the floating black")
      XCTAssertLessThan(afterShadow, 22, "\(id): daylight blacks must reach near-true-black")
      // and the near-blown background is held back.
      XCTAssertLessThan(afterHi, beforeHi, "\(id): the daylight guard must hold the highlights back")

      // Night byte-identity: guard weight 0 on the dark party frame.
      if let friends = source("sample-friends.jpg") {
        let nightReading = try engine.read(friends)
        let nAfter = try engine.develop(friends, with: recipe, maxPixelSize: 512, seed: 1, reading: nightReading)
        let nBefore = try engine.develop(friends, with: withoutDaylightGuard(recipe), maxPixelSize: 512, seed: 1, reading: nightReading)
        XCTAssertEqual(
          try XCTUnwrap(nAfter.image.pngData()), try XCTUnwrap(nBefore.image.pngData()),
          "\(id) night must be byte-identical — the daylight guard is a no-op in the dark"
        )
      }
    }
  }

  /// A bright daylight raster that WASHES for a flash stock: a bright background
  /// (top 40%) at 0.88, a mid face band at 0.55, and a shadow surface (bottom
  /// 22%) at 0.15 — the "tabletop" that should reach black but floats grey.
  private func washProneImage(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      let g = ctx.cgContext
      g.setFillColor(UIColor(white: 0.35, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side))
      g.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)          // bright background
      g.fill(CGRect(x: 0, y: 0, width: side, height: side * 0.40))
      g.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)          // mid face band
      g.fill(CGRect(x: side * 0.2, y: side * 0.46, width: side * 0.6, height: side * 0.16))
      g.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)          // shadow "tabletop"
      g.fill(CGRect(x: 0, y: side * 0.78, width: side, height: side * 0.22))
    }
  }

  /// The scene a wash-prone bright café meters as: bright (key 0.44 → full guard
  /// weight) but with a median BELOW the exposure target (0.42 < 0.50), so the
  /// adaptive median chase lifts the whole frame — the exact wash condition.
  private func washProneScene() -> SceneProfile {
    SceneProfile(
      analyzed: true, key: 0.44, p01: 0.05, p50: 0.42, p99: 0.90,
      illum: [1, 1, 1], sat: 0.22, lights: [], auxLights: [], faceLum: 0.50,
      meanLuminance: 0.46, medianLuminance: 0.42, shadowFraction: 0.22,
      highlightFraction: 0.40, dynamicRange: 0.7, averageRed: 0.46,
      averageGreen: 0.46, averageBlue: 0.46, saturation: 0.22, warmth: 0,
      isLowKey: false, isHighKey: false, isBacklit: false
    )
  }

  // MARK: - Disposable daylight grain (R84 item 5 — the owner's loved lens)

  /// Disposable's daylight grain read as a grunge-texture overlay + HDR crunch,
  /// not film (critic A #6). This is the OWNER'S LOVED lens, so the fix is a
  /// conservative amplitude softening on bright scenes — a refinement, never a
  /// transform. Because the softening scales with brightGuardWeight and every
  /// other disposable pass is key-independent on a flat, faceless field, a
  /// key-swap isolates ONLY the grain: the low-key render is bit-equivalent to
  /// the pre-fix daylight render (un-softened), the daylight-key render is the
  /// softened one. Pin the amplitude ratio on a flat patch; export the real-photo
  /// pair (street) for the owner's eye. Night grain is byte-identical (weight 0).
  func testDisposableDaylightGrainEvidence() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "disposable")
    let dir = try outDir()

    // --- numeric pin: grain amplitude on a flat mid-gray patch.
    let flat = flatGrayImage()
    let subject = SubjectAnalysis(faces: [], personMask: nil)
    let softened = try engine.develop(flat, with: recipe, seed: 3,
      reading: SceneReading(scene: flatGrayScene(key: 0.55), subject: subject))   // daylight
    let full = try engine.develop(flat, with: recipe, seed: 3,
      reading: SceneReading(scene: flatGrayScene(key: 0.20), subject: subject))   // pre-fix
    guard let softR = ImageMetrics.raster(softened.image),
          let fullR = ImageMetrics.raster(full.image) else { return XCTFail("raster failed") }
    // central crop where the vignette is flat, so std ≈ grain amplitude.
    let center = CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25)
    let softStd = lumaStd(softR, in: center)
    let fullStd = lumaStd(fullR, in: center)
    print("disposable grain std: daylight(softened) \(softStd) vs pre-fix \(fullStd)")
    // grain is linear in amplitude and the softening halves it on full daylight
    // (weight 1 → ×0.5). Bound the ratio tight: real reduction, grain not killed.
    XCTAssertLessThan(softStd, fullStd * 0.7, "daylight grain must be softened (less grunge)")
    XCTAssertGreaterThan(softStd, fullStd * 0.3, "grain must remain — a refinement, not a transform")
    XCTAssertGreaterThan(softStd, 1.0, "grain must still be visible where film shows it")

    // --- owner evidence: the real flash-print look on a bright street photo.
    if let street = source("sample-street.jpg") {
      let real = try engine.read(street)
      let after = try engine.develop(street, with: recipe, maxPixelSize: 1024, seed: 1, reading: real)
      let before = try engine.develop(
        street, with: recipe, maxPixelSize: 1024, seed: 1,
        reading: SceneReading(scene: sceneWithKey(real.scene, key: 0.20), subject: real.subject)
      )
      try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("disposable-daylight-before.png"))
      try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("disposable-daylight-after.png"))
    }

    // --- night byte-identity: at friends' key the softening weight is 0.
    if let friends = source("sample-friends.jpg") {
      let nightReading = try engine.read(friends)
      XCTAssertEqual(FilmEngine.brightGuardWeight(nightReading.scene), 0, "friends must meter below the guard ramp")
      let a = try engine.develop(friends, with: recipe, maxPixelSize: 512, seed: 1, reading: nightReading)
      // a second develop at a forced low key must match — the softening is a
      // no-op in the dark, so the loved night grain is untouched.
      let b = try engine.develop(
        friends, with: recipe, maxPixelSize: 512, seed: 1,
        reading: SceneReading(scene: sceneWithKey(nightReading.scene, key: 0.10), subject: nightReading.subject)
      )
      XCTAssertEqual(
        try XCTUnwrap(a.image.pngData()), try XCTUnwrap(b.image.pngData()),
        "disposable night grain must be byte-identical — the daylight softening is a no-op in the dark"
      )
    }
  }

  /// A uniform mid-gray (0.55) field — grain is the only pixel-to-pixel variance
  /// in a flat central crop, so its std reads the grain amplitude directly.
  private func flatGrayImage(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      ctx.cgContext.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
      ctx.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
  }

  /// A flat-scene profile at a chosen key, everything else fixed — so two keys
  /// differ ONLY in the grain-softening weight (median 0.55 keeps the adaptive
  /// correction identical and negative in both, no faces → no key-dependent lift).
  private func flatGrayScene(key: Double) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.50, p50: 0.55, p99: 0.60,
      illum: [1, 1, 1], sat: 0.10, lights: [], auxLights: [], faceLum: nil,
      meanLuminance: 0.55, medianLuminance: 0.55, shadowFraction: 0,
      highlightFraction: 0, dynamicRange: 0.1, averageRed: 0.55,
      averageGreen: 0.55, averageBlue: 0.55, saturation: 0.10, warmth: 0,
      isLowKey: false, isHighKey: false, isBacklit: false
    )
  }

  /// A copy of `base` with only `key` changed (for the grain-isolation key-swap).
  private func sceneWithKey(_ base: SceneProfile, key: Double) -> SceneProfile {
    SceneProfile(
      analyzed: base.analyzed, key: key, p01: base.p01, p50: base.p50, p99: base.p99,
      illum: base.illum, sat: base.sat, lights: base.lights, auxLights: base.auxLights,
      faceLum: base.faceLum, meanLuminance: base.meanLuminance,
      medianLuminance: base.medianLuminance, shadowFraction: base.shadowFraction,
      highlightFraction: base.highlightFraction, dynamicRange: base.dynamicRange,
      averageRed: base.averageRed, averageGreen: base.averageGreen,
      averageBlue: base.averageBlue, saturation: base.saturation, warmth: base.warmth,
      isLowKey: base.isLowKey, isHighKey: base.isHighKey, isBacklit: base.isBacklit
    )
  }

  // MARK: - Camcorder / Security-cam daylight clip (R84 item 4)

  /// The two video stocks clip a bright daylight frame — camcorder 6.8%,
  /// security-cam 12.6% (critic B). Both are adaptive stocks (NOT in the Class-A
  /// golden list), so a measured daylightHighlightGuard rides the normal develop
  /// path and rolls those highlights back. Pinned on the near-clip bright raster;
  /// the guard must lower the highlight band and (security) cut the pure-white
  /// clip below the target. Night byte-identity pinned on friends (weight 0).
  func testVideoDaylightClipGuardEvidence() throws {
    let engine = FilmEngine()
    let dir = try outDir()
    let bright = photoboothBrightImage()
    let scene = photoboothBrightScene()
    XCTAssertGreaterThan(FilmEngine.brightGuardWeight(scene), 0.9, "the guard must fully engage")
    let reading = SceneReading(scene: scene, subject: SubjectAnalysis(faces: [], personMask: nil))
    let hiBand = CGRect(x: 0, y: 0, width: 1, height: 0.45)

    for (id, clipCeiling) in [("camcorder-90s", 1.0), ("security-cam", 0.06)] {
      let recipe = CameraRecipe.recipe(for: id)
      XCTAssertGreaterThan(recipe.daylightHighlightGuard, 0, "\(id) must carry the daylight guard")
      let after = try engine.develop(bright, with: recipe, seed: 1, reading: reading)
      let before = try engine.develop(bright, with: withoutDaylightGuard(recipe), seed: 1, reading: reading)
      try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("\(id)-daylight-before.png"))
      try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("\(id)-daylight-after.png"))

      guard let beforeR = ImageMetrics.raster(before.image),
            let afterR = ImageMetrics.raster(after.image) else { return XCTFail("raster failed \(id)") }
      let beforeHi = meanLuma(beforeR, in: hiBand)
      let afterHi = meanLuma(afterR, in: hiBand)
      let beforeClip = ImageMetrics.highlightClipRate(beforeR, threshold: 250)
      let afterClip = ImageMetrics.highlightClipRate(afterR, threshold: 250)
      print("\(id) daylight: hi before \(beforeHi) after \(afterHi); clip before \(beforeClip) after \(afterClip)")
      XCTAssertLessThan(afterHi, beforeHi - 2, "\(id): the guard must roll the daylight highlights back")
      XCTAssertLessThanOrEqual(afterClip, beforeClip, "\(id): the guard must not add clip")
      XCTAssertLessThan(afterClip, clipCeiling, "\(id): daylight clip must sit under the measured ceiling")

      if let friends = source("sample-friends.jpg") {
        let nightReading = try engine.read(friends)
        let nAfter = try engine.develop(friends, with: recipe, maxPixelSize: 512, seed: 1, reading: nightReading)
        let nBefore = try engine.develop(friends, with: withoutDaylightGuard(recipe), maxPixelSize: 512, seed: 1, reading: nightReading)
        XCTAssertEqual(
          try XCTUnwrap(nAfter.image.pngData()), try XCTUnwrap(nBefore.image.pngData()),
          "\(id) night must be byte-identical — the daylight guard is a no-op in the dark"
        )
      }
    }
  }

  /// Owner-like bright daylight raster whose highlights sit AT clip: the top 45%
  /// (shirts / background) at 0.98, a mid face band at 0.72, darker ground 0.40.
  private func photoboothBrightImage(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      let g = ctx.cgContext
      g.setFillColor(UIColor(white: 0.40, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side))
      g.setFillColor(UIColor(white: 0.98, alpha: 1).cgColor)          // near-clip whites
      g.fill(CGRect(x: 0, y: 0, width: side, height: side * 0.45))
      g.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)          // mid-tone faces
      g.fill(CGRect(x: side * 0.2, y: side * 0.50, width: side * 0.6, height: side * 0.18))
    }
  }

  /// The scene an owner-like bright daylight photo meters as for photobooth
  /// (key 0.58, whites near clip): the guard's smoothstep reaches full weight.
  private func photoboothBrightScene() -> SceneProfile {
    SceneProfile(
      analyzed: true, key: 0.58, p01: 0.12, p50: 0.55, p99: 0.97,
      illum: [1, 1, 1], sat: 0.05, lights: [], auxLights: [], faceLum: 0.72,
      meanLuminance: 0.58, medianLuminance: 0.55, shadowFraction: 0.08,
      highlightFraction: 0.45, dynamicRange: 0.7, averageRed: 0.58,
      averageGreen: 0.58, averageBlue: 0.58, saturation: 0.05, warmth: 0,
      isLowKey: false, isHighKey: true, isBacklit: false
    )
  }

  /// A deterministic bright daylight raster with owner-photo-like statistics:
  /// bright whites (sky / shirts / umbrella highlights) at 0.90, a mid-tone face
  /// band at 0.70, darker ground at 0.35.
  private func brightDaylightImage(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      let g = ctx.cgContext
      g.setFillColor(UIColor(white: 0.35, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side))
      g.setFillColor(UIColor(white: 0.90, alpha: 1).cgColor)          // bright highlights
      g.fill(CGRect(x: 0, y: 0, width: side, height: side * 0.50))
      g.setFillColor(UIColor(white: 0.70, alpha: 1).cgColor)          // mid-tone faces
      g.fill(CGRect(x: side * 0.2, y: side * 0.50, width: side * 0.6, height: side * 0.15))
    }
  }

  /// The scene an owner-like bright daylight photo meters as (key ~0.55): the
  /// guard's smoothstep (0.27→0.45) reaches full weight here.
  private func ownerLikeBrightScene() -> SceneProfile {
    SceneProfile(
      analyzed: true, key: 0.55, p01: 0.10, p50: 0.55, p99: 0.90,
      illum: [1, 1, 1], sat: 0.20, lights: [], auxLights: [], faceLum: 0.70,
      meanLuminance: 0.55, medianLuminance: 0.55, shadowFraction: 0.10,
      highlightFraction: 0.35, dynamicRange: 0.6, averageRed: 0.55,
      averageGreen: 0.55, averageBlue: 0.55, saturation: 0.20, warmth: 0,
      isLowKey: false, isHighKey: false, isBacklit: false
    )
  }

  /// A recipe clone with the R78/R81 headroom knobs overridden — reproduces the
  /// pre-fix (blown) render for the before pane and the reduction pins.
  private func clone(
    _ r: CameraRecipe, flashHeadroom: Double, dayGuard: Double
  ) -> CameraRecipe {
    CameraRecipe(
      id: r.id, engineClass: r.engineClass, lutName: r.lutName,
      postLUTExposure: r.postLUTExposure, postLUTSaturation: r.postLUTSaturation,
      postLUTContrast: r.postLUTContrast, postLUTMatrix: r.postLUTMatrix,
      referenceSpatial: r.referenceSpatial, exposureBias: r.exposureBias,
      adaptiveExposure: r.adaptiveExposure, warmth: r.warmth, saturation: r.saturation,
      contrast: r.contrast, shadowLift: r.shadowLift,
      highlightCompression: r.highlightCompression, vignette: r.vignette,
      bloom: r.bloom, grain: r.grain, grainSize: r.grainSize,
      monochrome: r.monochrome, protectsFaces: r.protectsFaces,
      preservesWarmCast: r.preservesWarmCast, decisionVocabulary: r.decisionVocabulary,
      flashPhysics: r.flashPhysics, sourceBloom: r.sourceBloom, keyShadow: r.keyShadow,
      gainDrivenGrain: r.gainDrivenGrain, nightReciprocity: r.nightReciprocity,
      ccdClip: r.ccdClip, highlightSmear: r.highlightSmear,
      highlightSmearDarkOnly: r.highlightSmearDarkOnly,
      rimLight: r.rimLight, skinProtect: r.skinProtect, skyResponse: r.skyResponse,
      flashHighlightHeadroom: flashHeadroom, daylightHighlightGuard: dayGuard
    )
  }

  private func withoutFlashHeadroom(_ r: CameraRecipe) -> CameraRecipe {
    clone(r, flashHeadroom: 0, dayGuard: r.daylightHighlightGuard)
  }

  private func withoutDaylightGuard(_ r: CameraRecipe) -> CameraRecipe {
    clone(r, flashHeadroom: r.flashHighlightHeadroom, dayGuard: 0)
  }

  // MARK: helpers

  private func cgImage(_ image: CIImage) -> CGImage {
    context.createCGImage(image, from: image.extent.integral)!
  }

  private func meanLuma(_ r: ImageMetrics.Raster) -> Double {
    guard r.count > 0 else { return 0 }
    var sum = 0.0
    for i in stride(from: 0, to: r.px.count, by: 4) {
      sum += Double(r.px[i]) * 0.299 + Double(r.px[i + 1]) * 0.587 + Double(r.px[i + 2]) * 0.114
    }
    return sum / Double(r.count)
  }

  /// Mean Rec.601 luma (0…255) inside a normalized, top-left-origin rect.
  private func meanLuma(_ r: ImageMetrics.Raster, in rect: CGRect) -> Double {
    guard let c = ImageMetrics.meanColor(r, in: rect) else { return 0 }
    return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
  }

  /// Std-dev of Rec.601 luma (0…255) inside a normalized rect — on a flat field
  /// this reads the grain amplitude, the rest of the develop being uniform.
  private func lumaStd(_ r: ImageMetrics.Raster, in rect: CGRect) -> Double {
    let x0 = max(0, Int(Double(rect.minX) * Double(r.w)))
    let x1 = min(r.w, Int(Double(rect.maxX) * Double(r.w)))
    let y0 = max(0, Int(Double(rect.minY) * Double(r.h)))
    let y1 = min(r.h, Int(Double(rect.maxY) * Double(r.h)))
    guard x1 > x0, y1 > y0 else { return 0 }
    var sum = 0.0, sumSq = 0.0, n = 0.0
    for y in y0..<y1 {
      for x in x0..<x1 {
        let i = (y * r.w + x) * 4
        let l = Double(r.px[i]) * 0.299 + Double(r.px[i + 1]) * 0.587 + Double(r.px[i + 2]) * 0.114
        sum += l; sumSq += l * l; n += 1
      }
    }
    guard n > 0 else { return 0 }
    let mean = sum / n
    return (sumSq / n - mean * mean).squareRoot()
  }
}
