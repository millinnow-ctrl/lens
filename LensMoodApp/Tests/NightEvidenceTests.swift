import UIKit
import XCTest
@testable import LensMood

/// Renders the light-intelligence stocks on the dark fixtures and publishes the
/// results to `ui-artifacts/night-evidence/` (force-pushed to the ci-captures
/// branch by CI) — the visual-verification loop for night behavior that the
/// daylight parity golden cannot exercise. Assertions are existence/size only;
/// the LOOK is judged by eye from the published images, per the directive
/// ("done means visually approved, never merely compiles").
final class NightEvidenceTests: XCTestCase {

  func testRenderNightEvidence() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let outDir = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/night-evidence")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let scenes = [
      ("night", "reference/photos/sample-night.jpg"),
      ("friends", "reference/photos/sample-friends.jpg"),
      // R64: bright-day stress scene — verifies the photobooth highlight
      // protection and the security-cam day mode (no green wash in sun)
      ("day", "reference/photos/sample-brunch.jpg"),
    ]
    let stocks = [
      "super-8", "y2k-digicam", "camcorder-90s", "security-cam",
      "tokyo-neon", "film-noir", "iphone-flash", "photobooth",
    ]

    for (sceneName, path) in scenes {
      let sourceURL = repoRoot.appendingPathComponent(path)
      guard let source = UIImage(contentsOfFile: sourceURL.path) else {
        // Fixture photos live outside the app bundle; absence (e.g. a future
        // repo layout change) shouldn't fail the suite — evidence just skips.
        continue
      }
      for stock in stocks {
        let rendered = try FilmEngine().develop(
          source,
          with: CameraRecipe.recipe(for: stock),
          maxPixelSize: 560,
          seed: 1,
          analyzeSubjects: false
        ).image
        let url = outDir.appendingPathComponent("\(sceneName)-\(stock).png")
        try XCTUnwrap(rendered.pngData()).write(to: url)
        XCTAssertGreaterThan(rendered.size.width, 0, "\(sceneName)/\(stock)")
      }
      // the untouched source for side-by-side comparison in review
      let srcOut = outDir.appendingPathComponent("\(sceneName)-original.png")
      if let png = source.preparingThumbnail(of: CGSize(
        width: source.size.width * 560 / max(source.size.width, source.size.height),
        height: source.size.height * 560 / max(source.size.width, source.size.height)
      ))?.pngData() {
        try png.write(to: srcOut)
      }
    }
  }

  /// Owner-photo evidence: when an owner-supplied test photo is present, render
  /// it through ALL 18 lenses with the full Vision path (faces + person mask)
  /// and publish to ui-artifacts. The photo is only ever committed temporarily
  /// on owner request; this test skips silently when it is absent, so the
  /// harness survives the photo's removal.
  func testRenderOwnerEvidenceIfPresent() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sourceURL = repoRoot.appendingPathComponent("reference/photos/owner-busstop.jpg")
    guard let source = UIImage(contentsOfFile: sourceURL.path) else { return } // absent = skip
    let outDir = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/owner-evidence")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let engine = FilmEngine()
    for recipe in CameraRecipe.all {
      let rendered = try engine.develop(
        source,
        with: recipe,
        maxPixelSize: 900,
        seed: 1,
        analyzeSubjects: true // the real hardware path: faces + person mask
      ).image
      let url = outDir.appendingPathComponent("busstop-\(recipe.id).png")
      try XCTUnwrap(rendered.pngData()).write(to: url)
    }
    if let png = source.preparingThumbnail(of: CGSize(
      width: source.size.width * 900 / max(source.size.width, source.size.height),
      height: source.size.height * 900 / max(source.size.width, source.size.height)
    ))?.pngData() {
      try png.write(to: outDir.appendingPathComponent("busstop-original.png"))
    }
  }
}
