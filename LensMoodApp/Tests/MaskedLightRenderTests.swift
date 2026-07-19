import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// End-to-end renders of the R66 masked-light passes on the fixture
/// photographs, driven by the committed fixture mattes (see MatteInjection).
/// Until now no CI render ever fired rim/skin/sky — the simulator's person
/// segmentation is degenerate and `buildSubjectMatte` correctly refuses it.
/// These tests prove the passes fire, differ materially from the control,
/// stay deterministic, and that the control path is structurally untouched.
///
/// Fixture mattes: hand-authored L8 PNGs in Tests/Fixtures/mattes/.
/// Placeholder silhouettes: hand-authored geometry standing in until
/// device-captured mattes replace them at the TestFlight pass. Committed so
/// CI can render the masked-light passes end-to-end.
final class MaskedLightRenderTests: XCTestCase {

  private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  private static let repoRoot = testsDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  /// The masked-light decision notes, verbatim from FilmEngine.decisions.
  private static let maskedLightNotes = [
    "Rim light traced behind your subject",
    "Skin held natural under the look",
    "Sky rendered the way this film sees it",
  ]

  private func matteURL(_ name: String) -> URL {
    Self.testsDirectory.appendingPathComponent("Fixtures/mattes/\(name)")
  }

  private func sourceImage(_ name: String) throws -> UIImage {
    let url = Self.repoRoot.appendingPathComponent("reference/photos/\(name)")
    return try XCTUnwrap(UIImage(contentsOfFile: url.path), "missing fixture photo \(name)")
  }

  // MARK: mask materialization

  func testInjectedMatteProducesMasks() throws {
    let engine = FilmEngine()
    let source = try sourceImage("sample-friends.jpg")
    let injected = try MatteInjection.reading(
      source: source, mattePNG: matteURL("friends-person.png"), engine: engine
    )
    XCTAssertNotNil(
      injected.subject.subjectMatte,
      "the fixture silhouettes must survive coverage + cleanup into a subject matte"
    )
    XCTAssertNotNil(
      injected.subject.skinMask,
      "real skin chroma exists inside the silhouettes on this photo — the skin mask must materialize"
    )

    // the night fixture matte must clear coverage too (it drives future
    // dim-scene render evidence)
    let night = try MatteInjection.reading(
      source: try sourceImage("sample-night.jpg"),
      mattePNG: matteURL("night-person.png"),
      engine: engine
    )
    XCTAssertNotNil(night.subject.subjectMatte)

    // nil-injection control: the exact reading the golden suites render with
    let control = try engine.read(source, analyzeSubjects: false)
    XCTAssertNil(control.subject.subjectMatte, "no injection → no subject matte")
    XCTAssertNil(control.subject.skinMask)
    XCTAssertNil(control.subject.skyMask)
  }

  // MARK: end-to-end develop — the passes fire, differ, and stay deterministic

  func testMaskedPassesFireEndToEnd() throws {
    let engine = FilmEngine()
    let source = try sourceImage("sample-friends.jpg")
    let injected = try MatteInjection.reading(
      source: source, mattePNG: matteURL("friends-person.png"), engine: engine
    )
    let control = try engine.read(source, analyzeSubjects: false)
    // gq-editorial: rimLight 0.35 + skinProtect 0.70 — both masked passes
    // engage on this flash-lit pair (the meter finds real lights here, pinned
    // by SceneAnalyzerParityTests).
    let recipe = CameraRecipe.recipe(for: "gq-editorial")

    let injectedResult = try engine.develop(
      source, with: recipe, maxPixelSize: 1024, seed: 1, reading: injected
    )
    let controlResult = try engine.develop(
      source, with: recipe, maxPixelSize: 1024, seed: 1, reading: control
    )

    // (a) the two renders differ materially
    let a = try XCTUnwrap(ImageMetrics.raster(injectedResult.image))
    let b = try XCTUnwrap(ImageMetrics.raster(controlResult.image))
    let mae = try XCTUnwrap(ImageMetrics.meanAbsoluteError(a, b))
    XCTAssertGreaterThan(mae, 0.05, "the masked passes must move the render measurably (MAE)")
    XCTAssertNotEqual(injectedResult.image.pngData(), controlResult.image.pngData())

    // (b) the injected render carries the masked-light notes the control lacks
    XCTAssertTrue(injectedResult.decisions.contains("Skin held natural under the look"))
    XCTAssertTrue(injectedResult.decisions.contains("Rim light traced behind your subject"))
    XCTAssertFalse(controlResult.decisions.contains("Skin held natural under the look"))
    XCTAssertFalse(controlResult.decisions.contains("Rim light traced behind your subject"))

    // (c) determinism — the injected develop rendered twice is byte-identical
    let again = try engine.develop(
      source, with: recipe, maxPixelSize: 1024, seed: 1, reading: injected
    )
    XCTAssertEqual(
      try XCTUnwrap(injectedResult.image.pngData()),
      try XCTUnwrap(again.image.pngData()),
      "the same injected reading must always render the same bytes"
    )

    // export both renders so ci-captures holds a frame where a rim fires
    let outDir = Self.testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/masked-light")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try XCTUnwrap(injectedResult.image.pngData())
      .write(to: outDir.appendingPathComponent("friends-gq-editorial-injected.png"))
    try XCTUnwrap(controlResult.image.pngData())
      .write(to: outDir.appendingPathComponent("friends-gq-editorial-control.png"))
  }

  // MARK: the control path is pinned untouched

  func testControlPathUnchanged() throws {
    let engine = FilmEngine()
    let source = try sourceImage("sample-friends.jpg")
    let control = try engine.read(source, analyzeSubjects: false)
    let recipe = CameraRecipe.recipe(for: "gq-editorial")
    let first = try engine.develop(
      source, with: recipe, maxPixelSize: 1024, seed: 1, reading: control
    )
    let second = try engine.develop(
      source, with: recipe, maxPixelSize: 1024, seed: 1, reading: control
    )
    XCTAssertEqual(
      try XCTUnwrap(first.image.pngData()),
      try XCTUnwrap(second.image.pngData()),
      "the control develop must be byte-identical across runs"
    )
    for note in Self.maskedLightNotes {
      XCTAssertFalse(
        first.decisions.contains(note),
        "no mask → no masked-light note (structural no-op pinned): \(note)"
      )
    }
  }
}
