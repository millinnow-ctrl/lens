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
