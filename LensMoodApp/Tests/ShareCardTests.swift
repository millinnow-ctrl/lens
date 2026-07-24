import UIKit
import XCTest
@testable import LensMood

/// Light Test card renders — the user-chosen share format (single) and the
/// "two lights, one camera" pair, published to ui-artifacts (ci-captures) for
/// screenshots and the press kit. Every frame is the real engine's output on
/// the fixture photographs; the bare photo export stays unmarked forever.
// Simulator note: person segmentation returns no usable matte on CI runners, so these renders run without the masked-light passes. They understate the device output; marketing pulls device-rendered replacements at the TestFlight pass.
final class ShareCardTests: XCTestCase {

  func testRenderShareCards() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    let outDir = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/share-cards")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let engine = FilmEngine()
    let stock = Stock.find("tokyo-neon")
    let scenes = [
      ("night", "reference/photos/sample-night.jpg"),
      ("friends", "reference/photos/sample-friends.jpg"),
    ]
    let edge: CGFloat = 1350

    // night left, friends right — collected for the pair export below
    var panels: [(photo: UIImage, decision: String?)] = []
    for (sceneName, path) in scenes {
      let sourceURL = repoRoot.appendingPathComponent(path)
      guard let source = UIImage(contentsOfFile: sourceURL.path) else { continue }
      let reading = try engine.read(source)
      let render = try engine.develop(
        source,
        with: CameraRecipe.recipe(for: stock.id),
        maxPixelSize: edge,
        seed: 1,
        analyzeSubjects: true,
        reading: reading
      )
      let card = LightTestCard.single(
        photo: render.image, stock: stock, decision: render.decisions.first
      )
      try XCTUnwrap(card.pngData())
        .write(to: outDir.appendingPathComponent("\(sceneName)-tokyo-neon-card.png"))
      panels.append((photo: render.image, decision: render.decisions.first))
    }

    if panels.count == 2 {
      let pairCard = LightTestCard.pair(left: panels[0], right: panels[1], stock: stock)
      try XCTUnwrap(pairCard.pngData())
        .write(to: outDir.appendingPathComponent("tokyo-neon-light-test-pair.png"))
    }
  }

  func testCardGeometryAndDeterminism() throws {
    let syntheticSize = CGSize(width: 1000, height: 1250)
    let synthetic = UIGraphicsImageRenderer(size: syntheticSize).image { ctx in
      UIColor(red: 0.35, green: 0.5, blue: 0.6, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: syntheticSize))
    }
    let stock = Stock.find("tokyo-neon")
    XCTAssertEqual(LightTestCard.lmIndex(of: stock), "LM·16")

    let first = LightTestCard.single(photo: synthetic, stock: stock, decision: "Neon held")
    let second = LightTestCard.single(photo: synthetic, stock: stock, decision: "Neon held")
    XCTAssertEqual(first.size, CGSize(width: 1080, height: 1920))
    XCTAssertEqual(first.scale, 1)
    XCTAssertEqual(try XCTUnwrap(first.pngData()), try XCTUnwrap(second.pngData()))

    let pairCard = LightTestCard.pair(
      left: (photo: synthetic, decision: "Neon held"),
      right: (photo: synthetic, decision: "Shadows kept deep"),
      stock: stock
    )
    XCTAssertEqual(pairCard.size, CGSize(width: 2160, height: 1350))
    XCTAssertEqual(pairCard.scale, 1)
  }
}
