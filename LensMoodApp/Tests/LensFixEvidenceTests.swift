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

  /// photobooth with the R78 flash headroom disabled — reproduces the pre-fix
  /// (blown) render for the before pane and the reduction pin.
  private func withoutFlashHeadroom(_ r: CameraRecipe) -> CameraRecipe {
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
      flashHighlightHeadroom: 0
    )
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
}
