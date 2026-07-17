import UIKit
import XCTest
@testable import LensMood

/// The Conductor (Master Prompt §II): one read per photo, deterministic
/// "For this photo" ranking that mirrors the engine's real physics gates,
/// honest narration, and byte-identical develops when the cached reading is
/// handed back to the engine.
final class ConductorTests: XCTestCase {

  // MARK: - Scene builders

  private func scene(
    key: Double,
    lights: [LightSource] = [],
    auxLights: [LightSource] = [],
    sat: Double = 0.35,
    warmth: Double = 0,
    dynamicRange: Double = 0.5
  ) -> SceneProfile {
    SceneProfile(
      analyzed: true,
      key: key,
      p01: 0.02,
      p50: key,
      p99: 0.98,
      illum: [1, 1, 1],
      sat: sat,
      lights: lights,
      auxLights: auxLights,
      faceLum: nil,
      meanLuminance: key,
      medianLuminance: key,
      shadowFraction: key < 0.3 ? 0.5 : 0.1,
      highlightFraction: key > 0.6 ? 0.3 : 0.05,
      dynamicRange: dynamicRange,
      averageRed: 0.5,
      averageGreen: 0.5,
      averageBlue: 0.5,
      saturation: sat,
      warmth: warmth,
      isLowKey: key < 0.3,
      isHighKey: key > 0.7,
      isBacklit: false
    )
  }

  private let neon = LightSource(x: 0.3, y: 0.4, r: 0.06, intensity: 0.8, tint: [0.2, 0.4, 1.0])
  private let oneFace = [FaceProfile(id: 0, bounds: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.25), confidence: 1)]

  // MARK: - Ranking

  func testRankingIsCompleteAndDeterministic() {
    let night = scene(key: 0.15, auxLights: [neon])
    let first = Conductor.rank(scene: night, faces: oneFace)
    let second = Conductor.rank(scene: night, faces: oneFace)
    XCTAssertEqual(first, second, "same photo must rank the rail identically")
    XCTAssertEqual(first.count, CameraRecipe.all.count)
    XCTAssertEqual(Set(first.map(\.stockID)).count, CameraRecipe.all.count, "every camera exactly once")
  }

  func testNeonNightPromotesSourceBloomAndStarvesSlowFilm() {
    let ranked = Conductor.rank(scene: scene(key: 0.15, auxLights: [neon], sat: 0.45), faces: [])
    let position = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.stockID, $0) })
    XCTAssertLessThan(position["tokyo-neon"]!, 3, "neon look leads when sources glow: \(ranked.map(\.stockID))")
    XCTAssertGreaterThan(
      position["super-8"]!, ranked.count - 5,
      "slow film starves at night — the rail must not lead with it"
    )
    XCTAssertNotNil(ranked.first(where: { $0.stockID == "tokyo-neon" })?.reason)
  }

  func testDaylightDemotesNeonAndFeedsSlideFilm() {
    let ranked = Conductor.rank(scene: scene(key: 0.62, sat: 0.5, warmth: 0.1), faces: [])
    let position = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.stockID, $0) })
    XCTAssertGreaterThan(
      position["tokyo-neon"]!, ranked.count - 4,
      "the source-bloom pass refuses in daylight, so the rail demotes it honestly"
    )
    XCTAssertLessThan(position["kodachrome"]!, position["tokyo-neon"]!)
    XCTAssertLessThan(position["super-8"]!, position["tokyo-neon"]!)
  }

  func testDarkFacesPromoteFlashCameras() {
    let withFaces = Conductor.rank(scene: scene(key: 0.12), faces: oneFace)
    let withoutFaces = Conductor.rank(scene: scene(key: 0.12), faces: [])
    func score(_ id: String, in ranked: [LookMatch]) -> Double {
      ranked.first(where: { $0.stockID == id })!.score
    }
    for flashStock in ["iphone-flash", "photobooth"] {
      XCTAssertGreaterThan(
        score(flashStock, in: withFaces), score(flashStock, in: withoutFaces),
        "\(flashStock): flash physics loves a dark scene with a subject"
      )
    }
    let position = Dictionary(uniqueKeysWithValues: withFaces.enumerated().map { ($1.stockID, $0) })
    XCTAssertLessThan(position["iphone-flash"]!, 6, "\(withFaces.map(\.stockID))")
  }

  func testKeyLightPromotesNoir() {
    let lit = Conductor.rank(scene: scene(key: 0.25, lights: [neon]), faces: [])
    let flat = Conductor.rank(scene: scene(key: 0.25), faces: [])
    let litScore = lit.first(where: { $0.stockID == "film-noir" })!.score
    let flatScore = flat.first(where: { $0.stockID == "film-noir" })!.score
    XCTAssertGreaterThan(litScore, flatScore, "noir wants a key light to carve shadows from")
  }

  // MARK: - Narration honesty

  func testNarrationOnlyNamesStepsThatRun() {
    let quiet = SceneReading(
      scene: scene(key: 0.5),
      subject: SubjectAnalysis(faces: [], personMask: nil)
    )
    XCTAssertEqual(Conductor.narration(for: quiet), ["Reading the light", "Developing"])

    let busy = SceneReading(
      scene: scene(key: 0.2, auxLights: [neon]),
      subject: SubjectAnalysis(faces: oneFace, personMask: nil)
    )
    XCTAssertEqual(
      Conductor.narration(for: busy),
      ["Reading the light", "Finding your subject", "Tracing the light sources", "Developing"]
    )
  }

  // MARK: - Engine parity: a cached reading changes nothing in the pixels

  private func canvas() -> UIImage {
    let size = CGSize(width: 128, height: 96)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // pixel geometry must not inherit the simulator's 3× screen
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      UIColor(white: 0.18, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      UIColor(red: 0.95, green: 0.93, blue: 0.9, alpha: 1).setFill()
      ctx.cgContext.fillEllipse(in: CGRect(x: 88, y: 12, width: 24, height: 24))
      UIColor(red: 0.15, green: 0.25, blue: 0.85, alpha: 1).setFill()
      ctx.cgContext.fillEllipse(in: CGRect(x: 12, y: 56, width: 30, height: 30))
    }
  }

  /// Scene-meter plumbing is exact: with the subject pass off, a develop fed
  /// the cached reading is byte-identical to one that meters for itself.
  /// (The subject pass is excluded here deliberately — Vision segmentation is
  /// not guaranteed bit-stable across separate runs, which is exactly why the
  /// app routes every render through the Conductor's ONE reading; that path
  /// is locked by the reproducibility test below.)
  func testDevelopWithReadingIsByteIdenticalToSelfAnalysis() throws {
    let engine = FilmEngine()
    let photo = canvas()
    let reading = try engine.read(photo, analyzeSubjects: false)
    // one flash stock, one emulsion stock, one source-bloom stock
    for stockID in ["iphone-flash", "kodachrome", "tokyo-neon"] {
      let recipe = CameraRecipe.recipe(for: stockID)
      let direct = try engine.develop(photo, with: recipe, seed: 7, analyzeSubjects: false).image
      let conducted = try engine.develop(
        photo, with: recipe, seed: 7, analyzeSubjects: false, reading: reading
      ).image
      XCTAssertEqual(
        direct.pngData(), conducted.pngData(),
        "\(stockID): a develop fed the cached reading must be byte-identical"
      )
    }
  }

  /// The shipping path: every render of a photograph (first develop, lens
  /// switches, full-res save) shares the Conductor's single reading — and
  /// renders from that one reading are byte-reproducible, full subject pass
  /// included.
  func testDevelopFromOneReadingIsReproducible() throws {
    let engine = FilmEngine()
    let photo = canvas()
    let reading = try engine.read(photo)
    for stockID in ["iphone-flash", "photobooth"] {
      let recipe = CameraRecipe.recipe(for: stockID)
      let first = try engine.develop(photo, with: recipe, seed: 7, reading: reading).image
      let second = try engine.develop(photo, with: recipe, seed: 7, reading: reading).image
      XCTAssertEqual(
        first.pngData(), second.pngData(),
        "\(stockID): the same reading must always render the same bytes"
      )
    }
  }

  // MARK: - Evidence: rankings on the real fixture photographs

  /// Publishes the "For this photo" order for each fixture scene to
  /// ui-artifacts (ci-captures branch) so the ranking is reviewed by eye
  /// against the actual photographs, not only against synthetic scenes.
  func testPublishRankingEvidence() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    let outDir = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/conductor")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let engine = FilmEngine()
    var report = "For this photo — Conductor rankings on the fixture scenes\n"
    for (sceneName, path) in [
      ("night", "reference/photos/sample-night.jpg"),
      ("friends", "reference/photos/sample-friends.jpg"),
      ("day", "reference/photos/sample-brunch.jpg"),
    ] {
      let sourceURL = repoRoot.appendingPathComponent(path)
      guard let source = UIImage(contentsOfFile: sourceURL.path) else { continue }
      let reading = try engine.read(source)
      let ranked = Conductor.rank(scene: reading.scene, faces: reading.subject.faces)
      report += "\n[\(sceneName)]  key=\(String(format: "%.2f", reading.scene.key))"
      report += "  mean=\(String(format: "%.2f", reading.scene.meanLuminance))"
      report += "  lights=\(reading.scene.lights.count)+\(reading.scene.auxLights.count)"
      report += "  emissive=\(FilmEngine.emissiveLights(in: reading.scene).count)"
      report += "  faces=\(reading.subject.faces.count)\n"
      for (index, match) in ranked.enumerated() {
        report += String(format: "  %2d. %-14@ %.2f", index + 1, match.stockID as NSString, match.score)
        if let reason = match.reason { report += "  — \(reason)" }
        report += "\n"
      }
      report += "  narration: \(Conductor.narration(for: reading).joined(separator: " → "))\n"
    }
    try report.write(
      to: outDir.appendingPathComponent("rankings.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  // MARK: - Caching

  @MainActor
  func testConductorReadsEachPhotoOnce() async throws {
    let conductor = Conductor()
    let photo = canvas()
    let key = UUID()
    XCTAssertNil(conductor.cachedReading(for: key))
    let first = try await conductor.reading(for: photo, key: key)
    XCTAssertNotNil(conductor.cachedReading(for: key))
    let second = try await conductor.reading(for: photo, key: key)
    XCTAssertEqual(first.scene, second.scene, "second ask returns the cached read")
    conductor.forget(key: key)
    XCTAssertNil(conductor.cachedReading(for: key))
  }

  /// A reading retains a full-resolution person mask, so the cache is a
  /// small LRU: the oldest photo's reading falls out at the cap.
  @MainActor
  func testConductorCapsItsMemory() async throws {
    let conductor = Conductor()
    let photo = canvas()
    var keys: [UUID] = []
    for _ in 0..<5 {
      let key = UUID()
      keys.append(key)
      _ = try await conductor.reading(for: photo, key: key)
    }
    XCTAssertNil(conductor.cachedReading(for: keys[0]), "oldest reading evicted at the cap")
    XCTAssertNotNil(conductor.cachedReading(for: keys[4]))
  }
}
