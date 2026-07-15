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
}
