import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// Parity gate for the ported scene meter (SceneAnalyzer.swift) against the
/// frozen reference meter (lensmood-native/src/engine/scene.ts).
///
/// Golden numbers come from Tests/Fixtures/scene-metrics.json, produced by
/// `reference/scenemeter-dump.cjs` running the compiled reference meter over
/// the 10 photos in reference/fixtures/manifest.json — each analyzed once
/// with no focal and once with the committed focal probe (pass 3).
///
/// Tolerances: scalar fields must land within +-0.02 absolute or +-3%
/// relative — the two sides run identical math but resample the thumbnail
/// with different libraries (node-canvas/Skia vs CoreGraphics), so byte
/// equality is impossible while the statistics stay close. Any field with a
/// wider tolerance carries a comment explaining exactly why; nothing is
/// silently skipped.
final class SceneAnalyzerParityTests: XCTestCase {
  // MARK: - Fixture decoding

  private struct SceneMetrics: Decodable {
    let thumb: Int
    let focalProbe: FocalProbe
    let photos: [String: PhotoEntry]
  }

  private struct FocalProbe: Decodable {
    let x: Double
    let y: Double
    let r: Double
  }

  private struct PhotoEntry: Decodable {
    let file: String
    let width: Int
    let height: Int
    let noFocal: ReferenceProfile
    let withFocal: ReferenceProfile
  }

  private struct ReferenceProfile: Decodable {
    let analyzed: Bool
    let key: Double
    let p01: Double
    let p50: Double
    let p99: Double
    let illum: [Double]
    let sat: Double
    let faceLum: Double?
    let lights: [ReferenceLight]
    let label: String
    let notes: [String]
  }

  private struct ReferenceLight: Decodable {
    let x: Double
    let y: Double
    let r: Double
    let intensity: Double
    let tint: [Double]
  }

  // MARK: - Tests

  func testPortedMeterMatchesReferenceMeterOnAllFixturePhotos() throws {
    let metrics = try loadMetrics()
    XCTAssertEqual(metrics.thumb, 96)
    XCTAssertEqual(metrics.photos.count, 10, "all manifest photos must be dumped")
    let analyzer = SceneAnalyzer(context: makeContext())
    let focal = Focal(x: metrics.focalProbe.x, y: metrics.focalProbe.y, r: metrics.focalProbe.r)

    for (photo, entry) in metrics.photos.sorted(by: { $0.key < $1.key }) {
      let image = try loadPhoto(entry.file)
      let noFocal = try analyzer.analyze(image)
      assertProfile(noFocal, matches: entry.noFocal, context: "\(photo)/noFocal")
      XCTAssertNil(noFocal.faceLum, "\(photo)/noFocal must not meter a face")

      let withFocal = try analyzer.analyze(image, focal: focal)
      assertProfile(withFocal, matches: entry.withFocal, context: "\(photo)/withFocal")
    }
  }

  func testPureBlackFrameFallsBackToNeutral() throws {
    // mirrors the reference guard: key < 0.004 && p99 < 0.02 -> NEUTRAL_SCENE
    let black = CIImage(color: CIColor.black).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    let profile = try SceneAnalyzer(context: makeContext()).analyze(black)
    XCTAssertEqual(profile, SceneProfile.neutral)
    XCTAssertFalse(profile.analyzed)
    XCTAssertEqual(sceneLabel(profile), "READING")
    XCTAssertEqual(sceneNotes(profile), [])
  }

  // MARK: - Profile comparison

  private func assertProfile(
    _ actual: SceneProfile,
    matches expected: ReferenceProfile,
    context ctx: String
  ) {
    XCTAssertEqual(actual.analyzed, expected.analyzed, "\(ctx) analyzed")
    assertClose(actual.key, expected.key, "\(ctx) key")
    assertClose(actual.p01, expected.p01, "\(ctx) p01")
    assertClose(actual.p50, expected.p50, "\(ctx) p50")
    assertClose(actual.p99, expected.p99, "\(ctx) p99")
    XCTAssertEqual(actual.illum.count, 3, "\(ctx) illum arity")
    for channel in 0..<3 {
      assertClose(actual.illum[channel], expected.illum[channel], "\(ctx) illum[\(channel)]")
    }
    assertClose(actual.sat, expected.sat, "\(ctx) sat")

    switch (actual.faceLum, expected.faceLum) {
    case (nil, nil):
      break
    case let (actualFace?, expectedFace?):
      assertClose(actualFace, expectedFace, "\(ctx) faceLum")
    default:
      XCTFail("\(ctx) faceLum presence mismatch: \(String(describing: actual.faceLum)) vs \(String(describing: expected.faceLum))")
    }

    XCTAssertEqual(sceneLabel(actual), expected.label, "\(ctx) label")
    assertLights(actual.lights, expected.lights, ctx)
    assertNotes(sceneNotes(actual), reference: expected, actualProfile: actual, ctx)
  }

  /// scalar tolerance: +-0.02 absolute or +-3% relative (whichever is looser)
  private func assertClose(
    _ actual: Double,
    _ expected: Double,
    absolute: Double = 0.02,
    relative: Double = 0.03,
    _ message: String
  ) {
    let diff = abs(actual - expected)
    let relativeLimit = relative * max(abs(actual), abs(expected))
    XCTAssertTrue(
      diff <= absolute || diff <= relativeLimit,
      "\(message): \(actual) vs reference \(expected) (diff \(diff))"
    )
  }

  /// Light-source blobs are the one genuinely resampling-sensitive pass:
  /// blob membership flips pixel by pixel at the specular threshold T, so a
  /// different downscale filter legitimately merges, splits, or drops
  /// marginal blobs. Measured on these exact 10 photos, swapping only the
  /// canvas sampler (Skia default vs Skia high) already moved: count by 1,
  /// centroid x by 0.04, r by 0.006, intensity by 0.19 (it divides by
  /// max(0.02, 1-T), amplifying tiny peak shifts), and tint by 0.31 (the
  /// annulus census can drop to <= 3 pixels and snap to the warm default).
  /// Tolerances below sit just above those observed deltas — widened per
  /// field with this justification, never skipped.
  private func assertLights(_ actual: [LightSource], _ expected: [ReferenceLight], _ ctx: String) {
    XCTAssertLessThanOrEqual(
      abs(actual.count - expected.count), 1,
      "\(ctx) lights count \(actual.count) vs reference \(expected.count)"
    )
    var matched = 0
    for (index, ref) in expected.enumerated() {
      guard let best = actual.min(by: {
        centroidDistance($0, ref) < centroidDistance($1, ref)
      }), centroidDistance(best, ref) <= 0.08 else { continue }
      matched += 1
      let lightCtx = "\(ctx) light[\(index)]"
      assertClose(best.x, ref.x, absolute: 0.05, "\(lightCtx).x") // widened: centroid, see above
      assertClose(best.y, ref.y, absolute: 0.05, "\(lightCtx).y") // widened: centroid, see above
      assertClose(best.r, ref.r, absolute: 0.02, "\(lightCtx).r")
      assertClose(best.intensity, ref.intensity, absolute: 0.25, "\(lightCtx).intensity") // widened: /max(0.02, 1-T)
      XCTAssertEqual(best.tint.count, 3, "\(lightCtx).tint arity")
      for channel in 0..<3 {
        // widened: warm-default fallback when the annulus census is <= 3 px
        assertClose(best.tint[channel], ref.tint[channel], absolute: 0.35, "\(lightCtx).tint[\(channel)]")
      }
    }
    XCTAssertGreaterThanOrEqual(
      matched, min(actual.count, expected.count),
      "\(ctx) every mutually-present light must have a positional match"
    )
  }

  private func centroidDistance(_ light: LightSource, _ ref: ReferenceLight) -> Double {
    let dx = light.x - ref.x
    let dy = light.y - ref.y
    return (dx * dx + dy * dy).squareRoot()
  }

  /// sceneNotes is a fixed set of threshold rules over numbers this test has
  /// already pinned to +-0.02 (percentiles quantized to 1/64 bins). A note
  /// whose reference metric sits closer to its rule threshold than that
  /// tolerance cannot be asserted across resamplers — the number is allowed
  /// to land on the other side of the cut — so each rule is enforced only
  /// when the reference clears its threshold by the field's own tolerance.
  /// The underlying numbers are still asserted above in every case, so
  /// nothing is silently skipped; only the derived string is exempted, and
  /// only within the numeric tolerance band.
  private func assertNotes(
    _ actual: [String],
    reference: ReferenceProfile,
    actualProfile: SceneProfile,
    _ ctx: String
  ) {
    let expected = reference.notes

    func assertRule(_ note: String, margin: Double, minimum: Double = 0.02) {
      guard margin >= minimum else { return }
      XCTAssertEqual(
        actual.contains(note), expected.contains(note),
        "\(ctx) note '\(note)' (reference margin \(margin))"
      )
    }

    // deterministic: presence tracks the focal argument, not the pixels
    XCTAssertEqual(
      actual.contains("metered for the face"),
      expected.contains("metered for the face"),
      "\(ctx) note 'metered for the face'"
    )

    assertRule("exposure recovered, ISO pushed", margin: abs(reference.key - 0.1))
    assertRule(
      "low light — exposure lifted",
      margin: min(abs(reference.key - 0.1), abs(reference.key - 0.26))
    )
    if let refFace = reference.faceLum {
      // two +-0.02 fields feed this rule, so it needs double the clearance
      assertRule(
        "backlight — shadows opened",
        margin: abs((reference.key - refFace) - 0.15),
        minimum: 0.04
      )
    } else {
      XCTAssertFalse(actual.contains("backlight — shadows opened"), "\(ctx) backlight without a face")
    }
    assertRule(
      "color cast neutralized",
      margin: abs(max(reference.illum[2], reference.illum[0]) - 1.12)
    )
    assertRule("muted scene — color recovered", margin: abs(reference.sat - 0.14))
    // p99 and p01 are 1/64-quantized; one-bin flips on each side move the
    // range by up to 2/64 = 0.03125, so this rule needs that much clearance
    assertRule(
      "high contrast — highlights guarded",
      margin: abs((reference.p99 - reference.p01) - 0.85),
      minimum: 0.032
    )

    // the lights note tracks the blob count, which is tolerant to +-1 (see
    // assertLights); presence can only be asserted when the count cannot
    // legitimately cross zero under that allowance
    let referenceHasLightsNote = !reference.lights.isEmpty
    let actualHasLightsNote = !actualProfile.lights.isEmpty
    if reference.lights.count > 1 || reference.lights.count == actualProfile.lights.count {
      XCTAssertEqual(actualHasLightsNote, referenceHasLightsNote, "\(ctx) lights-mapped note")
    }
  }

  // MARK: - Loading

  private func makeContext() -> CIContext {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    return CIContext(options: [
      .workingColorSpace: sRGB,
      .outputColorSpace: sRGB,
      .useSoftwareRenderer: false,
    ])
  }

  private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // LensMoodApp
      .deletingLastPathComponent() // repo root
  }

  /// resources are copied flat into the test bundle (see project.yml); fall
  /// back to the repo checkout so `swift`-less environments and local runs
  /// both work
  private func locate(bundleName: String, extension ext: String, repoRelative: String) throws -> URL {
    if let url = Bundle(for: Self.self).url(forResource: bundleName, withExtension: ext) {
      return url
    }
    let fallback = repoRoot.appendingPathComponent(repoRelative)
    guard FileManager.default.fileExists(atPath: fallback.path) else {
      throw XCTSkip("missing fixture \(repoRelative); run reference/scenemeter-dump.cjs")
    }
    return fallback
  }

  private func loadMetrics() throws -> SceneMetrics {
    let url = try locate(
      bundleName: "scene-metrics",
      extension: "json",
      repoRelative: "LensMoodApp/Tests/Fixtures/scene-metrics.json"
    )
    return try JSONDecoder().decode(SceneMetrics.self, from: Data(contentsOf: url))
  }

  private func loadPhoto(_ file: String) throws -> CIImage {
    let name = (file as NSString).lastPathComponent
    let url = try locate(
      bundleName: (name as NSString).deletingPathExtension,
      extension: (name as NSString).pathExtension,
      repoRelative: "reference/\(file)"
    )
    return try XCTUnwrap(CIImage(contentsOf: url), "unreadable photo \(file)")
  }
}
