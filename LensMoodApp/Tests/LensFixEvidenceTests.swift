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
    XCTAssertGreaterThan(meanLuma(afterR, in: CGRect(x: 0, y: 0, width: 1, height: 1)), 105,
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
      // black-point commitment: the floating shadow point is reclaimed toward
      // black. The lift puts it at a grey ~0.40, so the target is a strong
      // commitment (≥35% down, into the dark), not a literal 0 the tone pass's
      // shadow lift never allows.
      XCTAssertLessThan(afterShadow, beforeShadow * 0.65, "\(id): the daylight guard must reclaim the floating black")
      XCTAssertLessThan(afterShadow, 65, "\(id): daylight blacks must commit toward true black")
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

  /// R84 item-2 DIAGNOSTIC (kept as honest documentation, no assertions — it
  /// only measures). Two prior toe reshapes left the daylight shadow floating at
  /// ~101 then ~107. Instead of guessing a third toe blind, this stages the SAME
  /// wash scene through recipe variants that isolate the three questions the CI
  /// log must answer in ONE run:
  ///  (a) does applyDaylightBlackPoint execute AND change the output? BP_OFF is
  ///      the id swapped out of `daylightBlackPointStocks` (so the toe gate's
  ///      `contains(recipe.id)` is false) with the median-chase cap re-supplied
  ///      via `flashHighlightHeadroom` (adaptiveExposure's dayRestraint also
  ///      gates on the set, so headroom keeps the cap identical). BP_OFF vs FULL
  ///      differs ONLY by the black-point pass → their shadow gap IS the toe's
  ///      net effect on the final render.
  ///  (b) what value does the COLOR CORE hand the toe — is it even in the toe's
  ///      pull zone (the toe is identity from 0.66)? CORE_NOBP strips every
  ///      downstream pass (bloom/grain/vignette/flash/skin/sky/ccd) AND the
  ///      black-point → the shadow ENTERING the toe. CORE_BP is the same strip
  ///      with the black-point ON → the shadow LEAVING the toe. Their delta is
  ///      the toe's true reduction at the value it actually sees.
  ///  (c) does any downstream pass re-lift the committed black? NOBLOOM/NOGRAIN/
  ///      NOVIGNETTE/NOFLASH zero one suspect each; whichever equals CORE_BP is
  ///      the eraser. (Structurally skin/sky are no-ops here — no masks.)
  func testFlashWashDaylightGuardDiagnostic() throws {
    let engine = FilmEngine()
    let bright = washProneImage()
    let scene = washProneScene()
    let reading = SceneReading(scene: scene, subject: SubjectAnalysis(faces: [], personMask: nil))
    let weight = FilmEngine.brightGuardWeight(scene)
    let shadow = CGRect(x: 0.1, y: 0.80, width: 0.8, height: 0.17)
    let highlight = CGRect(x: 0, y: 0.02, width: 1, height: 0.33)
    print("DIAG guard weight \(weight)")

    func measure(_ r: CameraRecipe) throws -> (shadow: Double, hi: Double) {
      let out = try engine.develop(bright, with: r, seed: 1, reading: reading)
      guard let raster = ImageMetrics.raster(out.image) else { return (-1, -1) }
      return (meanLuma(raster, in: shadow), meanLuma(raster, in: highlight))
    }

    for id in ["iphone-flash", "point-shoot"] {
      let base = CameraRecipe.recipe(for: id)
      // the effective median-chase restraint the set-gated dayRestraint applies
      // on FULL; re-supplied via headroom on the BP-off variants so ONLY the
      // black-point pass differs between the paired renders.
      let H = base.daylightHighlightGuard * weight
      let bpOffID = id + "-diagProbe"

      let full       = base
      let guardOff   = variant(base, dayGuard: 0)
      let bpOff      = variant(base, id: bpOffID, headroom: H)
      let coreNoBP   = variant(base, id: bpOffID, headroom: H,
                               bloom: 0, grain: 0, vignette: 0, flash: 0, skin: 0, sky: 0, ccd: 0)
      let coreBP     = variant(base, headroom: H,
                               bloom: 0, grain: 0, vignette: 0, flash: 0, skin: 0, sky: 0, ccd: 0)
      let noBloom    = variant(base, bloom: 0)
      let noGrain    = variant(base, grain: 0)
      let noVignette = variant(base, vignette: 0)
      let noFlash    = variant(base, flash: 0)

      let f = try measure(full)
      let go = try measure(guardOff)
      let bo = try measure(bpOff)
      let cnb = try measure(coreNoBP)
      let cb = try measure(coreBP)
      let nb = try measure(noBloom)
      let ng = try measure(noGrain)
      let nv = try measure(noVignette)
      let nf = try measure(noFlash)

      print("DIAG \(id): FULL shadow \(f.shadow) hi \(f.hi) | GUARD_OFF shadow \(go.shadow)")
      print("DIAG \(id): CORE_NOBP(enter toe) \(cnb.shadow) -> CORE_BP(leave toe) \(cb.shadow)  [toe reduces by \(cnb.shadow - cb.shadow)]")
      print("DIAG \(id): BP_OFF(cap kept, full downstream) \(bo.shadow)  [black-point net on FULL = \(bo.shadow - f.shadow)]")
      print("DIAG \(id): downstream — NOBLOOM \(nb.shadow) NOGRAIN \(ng.shadow) NOVIGNETTE \(nv.shadow) NOFLASH \(nf.shadow)  (vs FULL \(f.shadow))")
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

  // MARK: - Tokyo Neon daylight cast (R84 item 3)

  /// Tokyo-neon's neon-night grade smears a magenta/lavender cast onto a bright
  /// daylight sky (critic A #2). It is a Class-A GOLDEN stock (daylight key 0.366,
  /// guard weight ≈0.55 there) so a GLOBAL de-cast would move the golden — the
  /// fix is SKY-MASK scoped (a no-op on the analyzeSubjects:false golden) and
  /// scene-keyed (a no-op at night, its GOOD home). Simulator Vision has no mask,
  /// so this injects a synthetic blue sky and lets the real sky-mask builder run;
  /// the key-swap isolates the neutralization (tokyo is otherwise key-independent
  /// with no emissive lights). Pin: daylight sky magenta drops; golden + night
  /// unchanged. (The non-sky global cast is golden-locked — see the report.)
  func testTokyoNeonDaylightSkyEvidence() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "tokyo-neon")
    XCTAssertGreaterThan(recipe.skyResponse, 0, "tokyo-neon must carry the sky response")
    let dir = try outDir()
    let skyUI = blueSkyImage()
    guard let skyCI = CIImage(image: skyUI) else { return XCTFail("synthetic sky build failed") }
    let subject = engine.attachLightMasks(
      to: SubjectAnalysis(faces: [], personMask: nil), image: skyCI.orientedForDisplay
    )
    XCTAssertNotNil(subject.skyMask, "the synthetic blue sky must produce a sky mask to exercise the pass")

    func develop(key: Double) throws -> UIImage {
      try engine.develop(skyUI, with: recipe, seed: 1,
        reading: SceneReading(scene: skyOnlyScene(key: key), subject: subject)).image
    }
    let after = try develop(key: 0.55)    // daylight → neutralization engages
    let before = try develop(key: 0.20)   // weight 0 → cast left (pre-fix)
    let night = try develop(key: 0.13)    // night → left exactly alone
    try XCTUnwrap(before.pngData()).write(to: dir.appendingPathComponent("tokyo-neon-daylight-before.png"))
    try XCTUnwrap(after.pngData()).write(to: dir.appendingPathComponent("tokyo-neon-daylight-after.png"))

    guard let beforeR = ImageMetrics.raster(before), let afterR = ImageMetrics.raster(after)
    else { return XCTFail("raster failed") }
    let patch = CGRect(x: 0.2, y: 0.10, width: 0.6, height: 0.25)
    let beforeC = try XCTUnwrap(ImageMetrics.meanColor(beforeR, in: patch))
    let afterC = try XCTUnwrap(ImageMetrics.meanColor(afterR, in: patch))
    let beforeMagenta = beforeC.r - beforeC.b
    let afterMagenta = afterC.r - afterC.b
    print("tokyo-neon sky: red before \(beforeC.r) after \(afterC.r); magenta (R-B) before \(beforeMagenta) after \(afterMagenta)")
    // the magenta IS the excess red — pin the red channel pulled down (direct,
    // robust to the LUT's absolute sky color) and the sky moved toward cool.
    XCTAssertLessThan(afterC.r, beforeC.r * 0.85, "daylight sky red (the magenta channel) must be pulled down")
    XCTAssertLessThan(afterMagenta, beforeMagenta - 3, "daylight sky must move toward cool, never toward magenta")

    // night byte-identity: at key 0.13 the neutralization weight is 0 → identical
    // to the (also weight-0) key-0.20 before (tokyo is otherwise key-independent
    // here — LUT stock, no emissive lights).
    XCTAssertEqual(
      try XCTUnwrap(before.pngData()), try XCTUnwrap(night.pngData()),
      "tokyo-neon night must be byte-identical — the sky neutralization is a no-op in the dark"
    )

    // golden safety: without a sky mask (the analyzeSubjects:false golden path)
    // the pass no-ops regardless of scene key → byte-identical.
    let maskless = SubjectAnalysis(faces: [], personMask: nil)
    let goldenDay = try engine.develop(skyUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skyOnlyScene(key: 0.55), subject: maskless)).image
    let goldenDim = try engine.develop(skyUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skyOnlyScene(key: 0.20), subject: maskless)).image
    XCTAssertEqual(
      try XCTUnwrap(goldenDay.pngData()), try XCTUnwrap(goldenDim.pngData()),
      "no sky mask (the golden path) → sky neutralization is a structural no-op, byte-identical"
    )
  }

  /// A daylight raster with a flat blue sky filling the top 55% (blue-dominant,
  /// hue ≈216°, low texture — passes the sky-mask gate) over neutral ground.
  private func blueSkyImage(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      let g = ctx.cgContext
      g.setFillColor(UIColor(white: 0.40, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side))
      g.setFillColor(UIColor(red: 100 / 255, green: 140 / 255, blue: 200 / 255, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side * 0.55))
    }
  }

  /// A daylight scene at a chosen key for the tokyo sky pin — LUT stock (ignores
  /// exposure), no lights (so sourceBloom's emissive gate is empty at every key),
  /// so only brightGuardWeight(key) matters and the key-swap isolates the sky pass.
  private func skyOnlyScene(key: Double) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.15, p50: 0.48, p99: 0.82,
      illum: [1, 1, 1], sat: 0.35, lights: [], auxLights: [], faceLum: nil,
      meanLuminance: 0.50, medianLuminance: 0.48, shadowFraction: 0.12,
      highlightFraction: 0.20, dynamicRange: 0.65, averageRed: 0.45,
      averageGreen: 0.50, averageBlue: 0.60, saturation: 0.35, warmth: -0.05,
      isLowKey: false, isHighKey: false, isBacklit: false
    )
  }

  // MARK: - Kodachrome daylight skin jaundice (R84 item 6)

  /// Kodachrome's warm bias overshoots into an amber daylight wash that pushes
  /// skin toward jaundice (critic A #8). Its NIGHT is EXCELLENT and must stay
  /// byte-identical, and it is a Class-A GOLDEN stock — so the de-amber is scoped
  /// to the skin mask (a no-op on the analyzeSubjects:false golden path) and
  /// scene-keyed (a no-op in the dark). CI's simulator Vision returns no mask, so
  /// this injects a synthetic skin patch + matte to exercise the real pass; the
  /// key-swap isolates the de-amber (kodachrome is otherwise key-independent with
  /// no sky mask). Pin: daylight skin amber drops; golden path + night unchanged.
  func testKodachromeDaylightSkinDeamberEvidence() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "kodachrome")
    let dir = try outDir()
    let skinUI = skinPatchImage()
    guard let skinCI = CIImage(image: skinUI),
          let matteCI = CIImage(image: skinPatchMatte()) else { return XCTFail("synthetic image build failed") }
    let subject = engine.attachLightMasks(
      to: SubjectAnalysis(faces: [], personMask: matteCI), image: skinCI.orientedForDisplay
    )
    XCTAssertNotNil(subject.skinMask, "the synthetic skin patch must produce a skin mask to exercise the pass")

    func develop(key: Double) throws -> UIImage {
      try engine.develop(skinUI, with: recipe, seed: 1,
        reading: SceneReading(scene: skinScene(key: key), subject: subject)).image
    }
    let after = try develop(key: 0.55)    // daylight → de-amber engages (weight 1)
    let before = try develop(key: 0.20)   // weight 0 → de-amber off (pre-fix)
    let night = try develop(key: 0.13)    // night → de-amber off
    try XCTUnwrap(before.pngData()).write(to: dir.appendingPathComponent("kodachrome-daylight-before.png"))
    try XCTUnwrap(after.pngData()).write(to: dir.appendingPathComponent("kodachrome-daylight-after.png"))

    guard let beforeR = ImageMetrics.raster(before), let afterR = ImageMetrics.raster(after)
    else { return XCTFail("raster failed") }
    // skin-patch core (well inside the feathered mask).
    let patch = CGRect(x: 0.40, y: 0.42, width: 0.20, height: 0.16)
    let beforeC = try XCTUnwrap(ImageMetrics.meanColor(beforeR, in: patch))
    let afterC = try XCTUnwrap(ImageMetrics.meanColor(afterR, in: patch))
    let beforeAmber = beforeC.r - beforeC.b
    let afterAmber = afterC.r - afterC.b
    print("kodachrome skin amber (R-B): before \(beforeAmber) after \(afterAmber)")
    // the amber that reads as jaundice is graded down; skin stays warm, not cold.
    XCTAssertLessThan(afterAmber, beforeAmber - 5, "daylight skin must lose the amber/jaundice cast")
    XCTAssertGreaterThan(afterAmber, 0, "kodachrome skin must stay warm — de-amber, not neutralize")

    // night byte-identity: at key 0.13 the de-amber weight is 0, so the render is
    // identical to the (also weight-0) key-0.20 before — kodachrome is otherwise
    // key-independent here (LUT stock, no sky mask on the synthetic).
    XCTAssertEqual(
      try XCTUnwrap(before.pngData()), try XCTUnwrap(night.pngData()),
      "kodachrome night must be byte-identical — the de-amber is a no-op in the dark"
    )

    // golden safety: without a skin mask (the analyzeSubjects:false golden path)
    // the pass no-ops regardless of scene key → byte-identical.
    let maskless = SubjectAnalysis(faces: [], personMask: nil)
    let goldenDay = try engine.develop(skinUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skinScene(key: 0.55), subject: maskless)).image
    let goldenDim = try engine.develop(skinUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skinScene(key: 0.20), subject: maskless)).image
    XCTAssertEqual(
      try XCTUnwrap(goldenDay.pngData()), try XCTUnwrap(goldenDim.pngData()),
      "no skin mask (the golden path) → de-amber is a structural no-op, byte-identical"
    )
  }

  /// A daylight raster with a skin-tone patch (≈220,170,130 — passes the skin-
  /// chroma gate) over a neutral surround, for the injected-mask kodachrome pin.
  private func skinPatchImage(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      let g = ctx.cgContext
      g.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side))
      g.setFillColor(UIColor(red: 220 / 255, green: 170 / 255, blue: 130 / 255, alpha: 1).cgColor)
      g.fill(CGRect(x: side * 0.30, y: side * 0.34, width: side * 0.40, height: side * 0.32))
    }
  }

  /// A person matte (white over the skin patch, black elsewhere) so the real
  /// mask builders run on CI's simulator, where Vision returns nothing.
  private func skinPatchMatte(side: CGFloat = 160) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      let g = ctx.cgContext
      g.setFillColor(UIColor.black.cgColor)
      g.fill(CGRect(x: 0, y: 0, width: side, height: side))
      g.setFillColor(UIColor.white.cgColor)
      g.fill(CGRect(x: side * 0.26, y: side * 0.30, width: side * 0.48, height: side * 0.40))
    }
  }

  /// A daylight scene at a chosen key for the kodachrome skin pin — the LUT stock
  /// ignores exposure, so only brightGuardWeight(key) matters (plus there is no
  /// sky mask, so skyResponse is inert and the key-swap isolates the de-amber).
  private func skinScene(key: Double) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.18, p50: 0.50, p99: 0.80,
      illum: [1, 1, 1], sat: 0.30, lights: [], auxLights: [], faceLum: 0.60,
      meanLuminance: 0.50, medianLuminance: 0.50, shadowFraction: 0.10,
      highlightFraction: 0.15, dynamicRange: 0.6, averageRed: 0.55,
      averageGreen: 0.50, averageBlue: 0.45, saturation: 0.30, warmth: 0.10,
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
    // Maskless reading (analyzeSubjects:false) so the key-swap isolates grain —
    // disposable's flash falloff is key-dependent but needs a person matte, so a
    // maskless reading disables it and the only difference is the grain amplitude.
    if let street = source("sample-street.jpg") {
      let real = try engine.read(street, analyzeSubjects: false)
      let after = try engine.develop(street, with: recipe, maxPixelSize: 1024, seed: 1, reading: real)
      let before = try engine.develop(
        street, with: recipe, maxPixelSize: 1024, seed: 1,
        reading: SceneReading(scene: sceneWithKey(real.scene, key: 0.20), subject: real.subject)
      )
      try XCTUnwrap(before.image.pngData()).write(to: dir.appendingPathComponent("disposable-daylight-before.png"))
      try XCTUnwrap(after.image.pngData()).write(to: dir.appendingPathComponent("disposable-daylight-after.png"))
    }

    // --- night byte-identity: the softening is grainAmount *= (1 − 0.5·weight).
    // At friends' metered key (0.166, below the 0.27 guard-ramp onset) the weight
    // is EXACTLY 0, so the factor is exactly 1.0 — the grain amount, and thus the
    // whole render, is byte-identical to the pre-softening code. (A render-vs-
    // render key-swap can't prove this: forcing a different key also moves
    // disposable's key-dependent flash falloff, which is unrelated to the grain.)
    if let friends = source("sample-friends.jpg") {
      let nightReading = try engine.read(friends)
      XCTAssertEqual(
        FilmEngine.brightGuardWeight(nightReading.scene), 0,
        "friends must meter below the softening onset → grain factor exactly 1.0 → night byte-identical"
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

  /// A recipe clone with arbitrary fields overridden for the R84 item-2
  /// diagnostic (nil = keep the source's value). Lets the staged probe swap the
  /// `id` (to toggle the black-point set membership without touching product
  /// code) and zero individual downstream passes to bisect the shadow re-lift.
  private func variant(
    _ r: CameraRecipe,
    id: String? = nil,
    headroom: Double? = nil,
    dayGuard: Double? = nil,
    bloom: Double? = nil,
    grain: Double? = nil,
    vignette: Double? = nil,
    flash: Double? = nil,
    skin: Double? = nil,
    sky: Double? = nil,
    rim: Double? = nil,
    ccd: Double? = nil,
    contrast: Double? = nil,
    shadowLift: Double? = nil,
    adaptive: Double? = nil,
    exposure: Double? = nil
  ) -> CameraRecipe {
    CameraRecipe(
      id: id ?? r.id, engineClass: r.engineClass, lutName: r.lutName,
      postLUTExposure: r.postLUTExposure, postLUTSaturation: r.postLUTSaturation,
      postLUTContrast: r.postLUTContrast, postLUTMatrix: r.postLUTMatrix,
      referenceSpatial: r.referenceSpatial, exposureBias: exposure ?? r.exposureBias,
      adaptiveExposure: adaptive ?? r.adaptiveExposure, warmth: r.warmth, saturation: r.saturation,
      contrast: contrast ?? r.contrast, shadowLift: shadowLift ?? r.shadowLift,
      highlightCompression: r.highlightCompression, vignette: vignette ?? r.vignette,
      bloom: bloom ?? r.bloom, grain: grain ?? r.grain, grainSize: r.grainSize,
      monochrome: r.monochrome, protectsFaces: r.protectsFaces,
      preservesWarmCast: r.preservesWarmCast, decisionVocabulary: r.decisionVocabulary,
      flashPhysics: flash ?? r.flashPhysics, sourceBloom: r.sourceBloom, keyShadow: r.keyShadow,
      gainDrivenGrain: r.gainDrivenGrain, nightReciprocity: r.nightReciprocity,
      ccdClip: ccd ?? r.ccdClip, highlightSmear: r.highlightSmear,
      highlightSmearDarkOnly: r.highlightSmearDarkOnly,
      rimLight: rim ?? r.rimLight, skinProtect: skin ?? r.skinProtect, skyResponse: sky ?? r.skyResponse,
      flashHighlightHeadroom: headroom ?? r.flashHighlightHeadroom,
      daylightHighlightGuard: dayGuard ?? r.daylightHighlightGuard
    )
  }

  // MARK: - Flash trio daylight identity split (R84 Wave 2 item 1)

  /// The three flash-family digitals collapsed into one bright warm-punchy
  /// cluster on daylight (critic B: iphone-flash ~ point-shoot at 5.06, the
  /// tightest near-duplicate in the whole set). This splits their DAYLIGHT
  /// identity — Direct Flash clinical-cold, Pocket Compact warm, Pocket 2002
  /// cyan-CCD — scene-keyed so night (already distinct) is byte-identical.
  /// The direct pin runs the identity pass on a flat mid-gray at full daylight
  /// weight: each stock must read its own tint AND every pair must stay apart;
  /// the full develop is exported on the street fixture for the owner's eye.
  func testFlashTrioDaylightIdentitySplit() throws {
    let engine = FilmEngine()
    let dir = try outDir()
    guard let grayCI = CIImage(image: flatGrayImage()) else { return XCTFail("gray build failed") }
    let base = grayCI.orientedForDisplay
    let day = ownerLikeBrightScene()   // key 0.55 → full daylight weight
    XCTAssertGreaterThan(FilmEngine.brightGuardWeight(day), 0.99, "the split must fully engage on daylight")

    func splitColor(_ id: String) throws -> (r: Double, g: Double, b: Double) {
      let out = engine.applyFlashDaylightIdentity(base, scene: day, recipe: .recipe(for: id))
      let raster = try XCTUnwrap(ImageMetrics.raster(cgImage(out)))
      return try XCTUnwrap(ImageMetrics.meanColor(raster, in: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)))
    }
    let iphone = try splitColor("iphone-flash")
    let pocket = try splitColor("point-shoot")
    let y2k = try splitColor("y2k-digicam")
    print("flash split gray RGB — Direct Flash \(iphone) Pocket Compact \(pocket) Pocket 2002 \(y2k)")

    // each stock reads its dossier identity on daylight:
    XCTAssertLessThan(iphone.r - iphone.b, -3, "Direct Flash daylight must read cold (R < B)")
    XCTAssertGreaterThan(pocket.r - pocket.b, 5, "Pocket Compact daylight must read warm (R > B)")
    XCTAssertGreaterThan(y2k.g - y2k.r, 2, "Pocket 2002 daylight must lean cyan (G > R)")
    XCTAssertGreaterThan(y2k.b - y2k.r, 0, "Pocket 2002 daylight must lean cyan (B > R)")

    // no pair collapses (critic B's near-duplicate measured 5.06 in Lab-ish crop
    // units; this RGB-mean proxy floors every pair well clear of a collapse).
    let dIP = ImageMetrics.colorDelta(iphone, pocket)
    let dIY = ImageMetrics.colorDelta(iphone, y2k)
    let dPY = ImageMetrics.colorDelta(pocket, y2k)
    print("flash split pairwise RGB dist — DF|PC \(dIP) DF|P2 \(dIY) PC|P2 \(dPY)")
    XCTAssertGreaterThan(dIP, 6, "Direct Flash vs Pocket Compact must be distinct on daylight")
    XCTAssertGreaterThan(dIY, 6, "Direct Flash vs Pocket 2002 must be distinct on daylight")
    XCTAssertGreaterThan(dPY, 6, "Pocket Compact vs Pocket 2002 must be distinct on daylight")

    // night byte-identity: the pass guards on brightGuardWeight, exactly 0 in the
    // dark, so it returns its input bit-for-bit (structural no-op).
    let night = flatGrayScene(key: 0.166)
    XCTAssertEqual(FilmEngine.brightGuardWeight(night), 0, "night weight 0 → flash split is a structural no-op")
    for id in ["iphone-flash", "point-shoot", "y2k-digicam"] {
      let out = engine.applyFlashDaylightIdentity(base, scene: night, recipe: .recipe(for: id))
      XCTAssertEqual(try pngOf(out), try pngOf(base), "\(id): the flash split must be a night no-op")
    }

    // owner evidence + whole-develop separation on the real street fixture.
    if let street = source("sample-street.jpg") {
      let reading = try engine.read(street)
      var whole: [String: (r: Double, g: Double, b: Double)] = [:]
      for id in ["iphone-flash", "point-shoot", "y2k-digicam"] {
        let img = try engine.develop(street, with: .recipe(for: id), maxPixelSize: 1024, seed: 1, reading: reading).image
        try XCTUnwrap(img.pngData()).write(to: dir.appendingPathComponent("flash-split-\(id).png"))
        let raster = try XCTUnwrap(ImageMetrics.raster(img))
        whole[id] = try XCTUnwrap(ImageMetrics.meanColor(raster, in: CGRect(x: 0, y: 0, width: 1, height: 1)))
      }
      print("flash split whole-develop street dist — DF|PC \(ImageMetrics.colorDelta(whole["iphone-flash"]!, whole["point-shoot"]!)) DF|P2 \(ImageMetrics.colorDelta(whole["iphone-flash"]!, whole["y2k-digicam"]!)) PC|P2 \(ImageMetrics.colorDelta(whole["point-shoot"]!, whole["y2k-digicam"]!))")
    }
  }

  // MARK: - A24 light-intelligence engagement (R84 Wave 2 item 2)

  /// A24-still engaged ZERO light passes and collapsed into leica (critic B
  /// cluster B, 8.56). It now carries a soft rim (0.30) + a high skin protection
  /// (0.60), scene-keyed to daylight and mask-scoped. CI's simulator Vision
  /// returns no mask, so this injects a skin patch + matte and runs the real
  /// passes; the pin proves the intelligence ENGAGES on daylight, is OFF at night
  /// (scene-keyed), and is byte-identical on the analyzeSubjects:false golden path.
  func testA24LightIntelligenceEngagement() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "a24-still")
    XCTAssertGreaterThan(recipe.rimLight, 0, "a24 must carry the soft rim row")
    XCTAssertGreaterThan(recipe.skinProtect, 0, "a24 must carry the high skin row")
    let dir = try outDir()
    let stripped = variant(recipe, skin: 0, rim: 0)   // the pre-Wave-2 a24 (no intelligence)

    let skinUI = skinPatchImage()
    guard let skinCI = CIImage(image: skinUI),
          let matteCI = CIImage(image: skinPatchMatte()) else { return XCTFail("synthetic build failed") }
    let subject = engine.attachLightMasks(
      to: SubjectAnalysis(faces: [], personMask: matteCI), image: skinCI.orientedForDisplay)
    XCTAssertNotNil(subject.skinMask, "injected skin patch must produce a skin mask")

    func develop(_ r: CameraRecipe, key: Double) throws -> UIImage {
      try engine.develop(skinUI, with: r, seed: 1,
        reading: SceneReading(scene: skinScene(key: key), subject: subject)).image
    }
    XCTAssertGreaterThan(FilmEngine.brightGuardWeight(skinScene(key: 0.55)), 0.99, "engagement at the daylight key")
    let fullDay = try develop(recipe, key: 0.55)
    let strippedDay = try develop(stripped, key: 0.55)
    try XCTUnwrap(fullDay.pngData()).write(to: dir.appendingPathComponent("a24-intelligence-after.png"))
    try XCTUnwrap(strippedDay.pngData()).write(to: dir.appendingPathComponent("a24-intelligence-before.png"))

    // ENGAGED on daylight: the skin patch moves under the new intelligence.
    let patch = CGRect(x: 0.40, y: 0.42, width: 0.20, height: 0.16)
    let fullC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(fullDay)), in: patch))
    let stripC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(strippedDay)), in: patch))
    print("a24 skin patch — with intelligence \(fullC) vs pre-Wave-2 \(stripC); delta \(ImageMetrics.colorDelta(fullC, stripC))")
    XCTAssertGreaterThan(ImageMetrics.colorDelta(fullC, stripC), 1.5, "a24 intelligence must engage on daylight skin")
    XCTAssertNotEqual(try XCTUnwrap(fullDay.pngData()), try XCTUnwrap(strippedDay.pngData()))

    // night byte-identity: at key 0.13 the scene-key weight is 0, so the full
    // recipe and the stripped recipe render identically (the passes are skipped).
    XCTAssertEqual(FilmEngine.brightGuardWeight(skinScene(key: 0.13)), 0, "night weight 0 → a24 intelligence skipped")
    XCTAssertEqual(try XCTUnwrap(try develop(recipe, key: 0.13).pngData()),
                   try XCTUnwrap(try develop(stripped, key: 0.13).pngData()),
                   "a24 night must be byte-identical — the intelligence is scene-keyed off")

    // golden safety: without masks (the analyzeSubjects:false golden path) the
    // passes structurally no-op regardless of key → byte-identical.
    let maskless = SubjectAnalysis(faces: [], personMask: nil)
    let gDay = try engine.develop(skinUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skinScene(key: 0.55), subject: maskless)).image
    let gDim = try engine.develop(skinUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skinScene(key: 0.20), subject: maskless)).image
    XCTAssertEqual(try XCTUnwrap(gDay.pngData()), try XCTUnwrap(gDim.pngData()),
                   "no mask (golden path) → a24 intelligence is a structural no-op, byte-identical")
  }

  // MARK: - Pastel Cinema subject palette (R84 Wave 2 item 3)

  /// Pastel Cinema read as a plain neutral render — its powdery palette never
  /// engaged (critic A #7 / cluster B). The global umbrella/powder map is baked
  /// into the Class-A golden LUT (owner regen). This wakes the palette on the
  /// SUBJECT (mask-scoped, daylight-scene-keyed): the subject must desaturate on
  /// daylight, with the golden path + night byte-identical.
  func testPastelSubjectPaletteAwakens() throws {
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "pastel-cinema")
    let dir = try outDir()
    let skinUI = skinPatchImage()  // a saturated patch over neutral ground stands in for a costumed subject
    guard let skinCI = CIImage(image: skinUI),
          let matteCI = CIImage(image: skinPatchMatte()) else { return XCTFail("synthetic build failed") }
    let subject = engine.attachLightMasks(
      to: SubjectAnalysis(faces: [], personMask: matteCI), image: skinCI.orientedForDisplay)
    XCTAssertNotNil(subject.subjectMatte, "injected matte must produce a subject matte")

    func develop(key: Double) throws -> UIImage {
      try engine.develop(skinUI, with: recipe, seed: 1,
        reading: SceneReading(scene: skinScene(key: key), subject: subject)).image
    }
    let after = try develop(key: 0.55)   // daylight → palette wakes
    let before = try develop(key: 0.20)  // weight 0 → inert (pre-fix)
    let night = try develop(key: 0.13)   // night → inert
    try XCTUnwrap(before.pngData()).write(to: dir.appendingPathComponent("pastel-subject-before.png"))
    try XCTUnwrap(after.pngData()).write(to: dir.appendingPathComponent("pastel-subject-after.png"))

    let patch = CGRect(x: 0.40, y: 0.42, width: 0.20, height: 0.16)
    let afterC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(after)), in: patch))
    let beforeC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(before)), in: patch))
    let afterSat = max(afterC.r, max(afterC.g, afterC.b)) - min(afterC.r, min(afterC.g, afterC.b))
    let beforeSat = max(beforeC.r, max(beforeC.g, beforeC.b)) - min(beforeC.r, min(beforeC.g, beforeC.b))
    print("pastel subject chroma (max-min): daylight \(afterSat) vs inert \(beforeSat)")
    XCTAssertLessThan(afterSat, beforeSat - 3, "the pastel palette must desaturate the subject on daylight (powdery)")

    // night byte-identity: weight 0 at both sub-onset keys → identical, inert.
    XCTAssertEqual(try XCTUnwrap(before.pngData()), try XCTUnwrap(night.pngData()),
                   "pastel night must be byte-identical — the subject palette is a no-op in the dark")

    // golden safety: no matte on the analyzeSubjects:false path → no-op regardless of key.
    let maskless = SubjectAnalysis(faces: [], personMask: nil)
    let gDay = try engine.develop(skinUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skinScene(key: 0.55), subject: maskless)).image
    let gDim = try engine.develop(skinUI, with: recipe, seed: 1,
      reading: SceneReading(scene: skinScene(key: 0.20), subject: maskless)).image
    XCTAssertEqual(try XCTUnwrap(gDay.pngData()), try XCTUnwrap(gDim.pngData()),
                   "no matte (golden path) → pastel subject palette is a structural no-op, byte-identical")
  }

  // MARK: - Lomo cross-process shadows (R84 Wave 2 item 4)

  /// After Wave 1 de-ambered Kodachrome's skin, Lomo still overlapped it (critic
  /// B cluster D). The cleanest separator is Lomo's cross-process shadow shift —
  /// shadows cross toward CYAN-GREEN, highlights stay warm. Scene-keyed to
  /// daylight (Lomo's warm-orange night is byte-identical). The image and scene
  /// change ONLY in key across the pair, so the shadow shift is isolated.
  func testLomoCrossProcessShadows() throws {
    let engine = FilmEngine()
    let dir = try outDir()
    let img = washProneImage()   // has a 0.15 shadow band (bottom 22%) + bright top
    let maskless = SubjectAnalysis(faces: [], personMask: nil)
    let shadow = CGRect(x: 0.1, y: 0.80, width: 0.8, height: 0.17)

    func develop(key: Double) throws -> UIImage {
      try engine.develop(img, with: .recipe(for: "lomo"), seed: 1,
        reading: SceneReading(scene: lomoCrossScene(key: key), subject: maskless)).image
    }
    XCTAssertGreaterThan(FilmEngine.brightGuardWeight(lomoCrossScene(key: 0.55)), 0.99, "cross-process engages on daylight")
    let day = try develop(key: 0.55)
    let night = try develop(key: 0.13)
    try XCTUnwrap(night.pngData()).write(to: dir.appendingPathComponent("lomo-crossprocess-before.png"))
    try XCTUnwrap(day.pngData()).write(to: dir.appendingPathComponent("lomo-crossprocess-after.png"))

    let dayC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(day)), in: shadow))
    let nightC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(night)), in: shadow))
    print("lomo shadow — daylight R,G,B \(dayC) B-R \(dayC.b - dayC.r) G-R \(dayC.g - dayC.r); night \(nightC) B-R \(nightC.b - nightC.r)")
    // daylight shadows cross cyan-green, and clearly more so than the warm night.
    XCTAssertGreaterThan(dayC.b - dayC.r, 0, "Lomo daylight shadows must cross toward cyan (B > R)")
    XCTAssertGreaterThan(dayC.g - dayC.r, 0, "Lomo daylight shadows must cross toward green (G > R)")
    XCTAssertGreaterThan((dayC.b - dayC.r) - (nightC.b - nightC.r), 8, "the cross-process must shift the shadows cool vs the warm night")

    // night byte-identity: both sub-onset keys carry weight 0 → identical, no cross.
    let nightB = try develop(key: 0.20)
    XCTAssertEqual(try XCTUnwrap(night.pngData()), try XCTUnwrap(nightB.pngData()),
                   "Lomo night must be byte-identical — the cross-process is a no-op in the dark")

    // separation evidence vs Kodachrome on the real street fixture.
    if let street = source("sample-street.jpg") {
      let reading = try engine.read(street)
      let lomoImg = try engine.develop(street, with: .recipe(for: "lomo"), maxPixelSize: 1024, seed: 1, reading: reading).image
      let kodaImg = try engine.develop(street, with: .recipe(for: "kodachrome"), maxPixelSize: 1024, seed: 1, reading: reading).image
      let lC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(lomoImg)), in: CGRect(x: 0, y: 0, width: 1, height: 1)))
      let kC = try XCTUnwrap(ImageMetrics.meanColor(try XCTUnwrap(ImageMetrics.raster(kodaImg)), in: CGRect(x: 0, y: 0, width: 1, height: 1)))
      print("Lomo vs Kodachrome whole-develop street dist: \(ImageMetrics.colorDelta(lC, kC))")
    }
  }

  // MARK: - Tokyo-neon halation parity widening (R84 Wave 2 item 6)

  /// PARITY CORRECTION: the port under-rendered CineStill 800T's backlit halation
  /// — the per-source glow was radius-capped at 0.15·maxEdge (a dim point) where
  /// the reference blooms a broad red-dominant disc. The widening (cap → 0.24,
  /// wider multiplier, stronger broad bloom) is pinned here: the glow must now
  /// reach a ring the old cap excluded, carry the source's hue, and stay local
  /// (not a full-frame wash). Golden safety: at the daylight golden key the
  /// emissive gate is EMPTY, so the widened per-source code is never reached.
  func testTokyoNeonHalationWidening() throws {
    let engine = FilmEngine()
    let dir = try outDir()
    let dark = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
      ctx.cgContext.setFillColor(UIColor(white: 0.10, alpha: 1).cgColor)
      ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    }
    guard let darkCI = CIImage(image: dark) else { return XCTFail("dark build failed") }
    let base = darkCI.orientedForDisplay
    // one magenta neon at frame center.
    let neon = LightSource(x: 0.5, y: 0.5, r: 0.04, intensity: 0.9, tint: [1.0, 0.25, 0.9])
    let scene = neonNightScene(key: 0.10, light: neon)
    XCTAssertFalse(FilmEngine.emissiveLights(in: scene).isEmpty, "the neon scene must meter as emissive")
    let out = engine.applySourceBloom(base, scene: scene, baseBloom: 0.18, amount: 1.0)
    try pngOf(out).write(to: dir.appendingPathComponent("tokyo-halation-widened.png"))

    let raster = try XCTUnwrap(ImageMetrics.raster(cgImage(out)))
    func L(_ rect: CGRect) throws -> (rgb: (r: Double, g: Double, b: Double), lum: Double) {
      let c = try XCTUnwrap(ImageMetrics.meanColor(raster, in: rect))
      return (c, c.r * 0.299 + c.g * 0.587 + c.b * 0.114)
    }
    // inner ring ≈ 0.12·maxEdge — well inside the new sprite: a strong broad glow.
    let inner = try L(CGRect(x: 0.585, y: 0.45, width: 0.07, height: 0.10))
    // outer ring ≈ 0.19·maxEdge — BEYOND the old 0.15·maxEdge cap (where the old
    // per-source glow had died) but inside the new one: this is the widening.
    let outer = try L(CGRect(x: 0.655, y: 0.45, width: 0.07, height: 0.10))
    // far corner: the untouched surround (locality control).
    let corner = try L(CGRect(x: 0.02, y: 0.02, width: 0.10, height: 0.10))
    print("tokyo halation — inner L \(inner.lum) outer L \(outer.lum) corner L \(corner.lum); inner RGB \(inner.rgb)")
    XCTAssertGreaterThan(inner.lum, corner.lum + 6, "the source must bloom a strong broad halo")
    XCTAssertGreaterThan(inner.rgb.r, inner.rgb.g + 2, "the halo must carry the source's red-dominant (magenta) hue")
    XCTAssertGreaterThan(outer.lum, corner.lum + 2, "the widened halo must reach past the old 0.15·maxEdge cap")
    XCTAssertGreaterThan(inner.lum, outer.lum, "the halo must stay local — it falls off with radius, not a flat wash")

    // golden safety: at the daylight golden key the emissive gate is empty, so the
    // widened per-source glow code is never reached → tokyo golden byte-identical.
    XCTAssertTrue(FilmEngine.emissiveLights(in: neonNightScene(key: 0.366, light: neon)).isEmpty,
                  "at the golden daylight key neon refuses → the per-source glow code is unreachable")
  }

  /// A dark emissive scene carrying one colored light, for the halation pin.
  private func neonNightScene(key: Double, light: LightSource) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.02, p50: 0.10, p99: 0.95,
      illum: [1, 1, 1], sat: 0.5, lights: [light], auxLights: [], faceLum: nil,
      meanLuminance: 0.12, medianLuminance: 0.10, shadowFraction: 0.7,
      highlightFraction: 0.05, dynamicRange: 0.9, averageRed: 0.12,
      averageGreen: 0.10, averageBlue: 0.12, saturation: 0.5, warmth: 0,
      isLowKey: true, isHighKey: false, isBacklit: false
    )
  }

  /// A Lomo scene at a chosen key with a FIXED median / low-key flag, so the
  /// adaptive exposure is identical across keys and only the daylight-keyed
  /// cross-process differs (no sky mask on the wash raster → skyResponse inert).
  private func lomoCrossScene(key: Double) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.05, p50: 0.42, p99: 0.90,
      illum: [1, 1, 1], sat: 0.30, lights: [], auxLights: [], faceLum: nil,
      meanLuminance: 0.46, medianLuminance: 0.42, shadowFraction: 0.22,
      highlightFraction: 0.40, dynamicRange: 0.7, averageRed: 0.46,
      averageGreen: 0.46, averageBlue: 0.46, saturation: 0.30, warmth: 0,
      isLowKey: false, isHighKey: false, isBacklit: false
    )
  }

  /// PNG bytes of a rendered CIImage, in the tests' own context.
  private func pngOf(_ image: CIImage) throws -> Data {
    let cg = try XCTUnwrap(context.createCGImage(image, from: image.extent.integral))
    return try XCTUnwrap(UIImage(cgImage: cg).pngData())
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
