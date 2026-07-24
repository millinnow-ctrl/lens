import UIKit
import XCTest
@testable import LensMood

/// Marketing material renders — published to ui-artifacts (ci-captures) for
/// the ad edit. Every frame is the real engine's output on the fixture
/// photographs; the subject matte export powers the ad's depth-parallax shot
/// with the engine's own mask (the staging is the edit, never the photography).
final class AdMaterialTests: XCTestCase {

  func testRenderAdMaterial() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    let outDir = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/ad-material")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let engine = FilmEngine()
    let scenes = [
      ("night", "reference/photos/sample-night.jpg"),
      ("friends", "reference/photos/sample-friends.jpg"),
    ]
    // the ad's three-slam stocks + the depth-shot hero
    let stocks = ["disposable", "tokyo-neon", "film-noir"]

    for (sceneName, path) in scenes {
      let sourceURL = repoRoot.appendingPathComponent(path)
      guard let source = UIImage(contentsOfFile: sourceURL.path) else { continue }
      let reading = try engine.read(source)

      // the untouched original at edit resolution
      let edge: CGFloat = 1350
      let scale = edge / max(source.size.width, source.size.height)
      if let thumb = source.preparingThumbnail(of: CGSize(
        width: source.size.width * scale, height: source.size.height * scale
      )), let png = thumb.pngData() {
        try png.write(to: outDir.appendingPathComponent("\(sceneName)-original.png"))
      }

      for stock in stocks {
        let rendered = try engine.develop(
          source,
          with: CameraRecipe.recipe(for: stock),
          maxPixelSize: edge,
          seed: 1,
          analyzeSubjects: true,
          reading: reading
        ).image
        try XCTUnwrap(rendered.pngData())
          .write(to: outDir.appendingPathComponent("\(sceneName)-\(stock).png"))
      }

      // the engine's own subject matte (L8, analysis resolution) — the ad's
      // depth-parallax layer separation comes from the product's real read
      if let matte = reading.subject.subjectMatte ?? reading.subject.personMask,
         let cgMatte = engine.context.createCGImage(matte, from: matte.extent) {
        let matteImage = UIImage(cgImage: cgMatte)
        try XCTUnwrap(matteImage.pngData())
          .write(to: outDir.appendingPathComponent("\(sceneName)-matte.png"))
      }
    }
  }
}
