import CoreImage
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

  func testGlossyCCDNotPromotedOnBrightDaylight() {
    // R81 rank honesty: the CCD "glossy clip" gate used to promote y2k on
    // daylight (score += 0.06 * daylight) — the exact scenes it bleached. The
    // engine now grades that gloss DOWN on bright frames, so the rail must
    // mirror it: y2k no longer leads a bright, well-exposed daylight rail, and
    // the daylight emulsion characters (kodachrome) outrank it.
    let ranked = Conductor.rank(scene: scene(key: 0.55, sat: 0.4), faces: oneFace)
    let position = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.stockID, $0) })
    XCTAssertGreaterThanOrEqual(position["y2k-digicam"]!, 3,
      "glossy CCD must not lead a bright daylight rail: \(ranked.map(\.stockID))")
    XCTAssertLessThan(position["kodachrome"]!, position["y2k-digicam"]!,
      "a daylight color emulsion must outrank the glossy night stock in daylight")
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

  // MARK: - R84 Wave 2: ranking-gate honesty (a gate may only claim what renders)

  /// Same sRGB working/output space as FilmEngine's production context — the
  /// key-shadow kernel's luma term is defined on sRGB-encoded values.
  private let renderContext: CIContext = {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    return CIContext(options: [
      .workingColorSpace: sRGB,
      .outputColorSpace: sRGB,
      .useSoftwareRenderer: false,
    ])
  }()

  private func uniformCanvas(_ white: CGFloat, side: CGFloat = 96) -> CIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // the simulator's 3× scale would break the geometric probes
    let ui = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      UIColor(white: white, alpha: 1).setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    return CIImage(image: ui)!
  }

  private func meanLuma(_ image: CIImage, region: CGRect) -> Double {
    let e = image.extent
    let rect = CGRect(
      x: e.minX + region.minX * e.width, y: e.minY + region.minY * e.height,
      width: region.width * e.width, height: region.height * e.height
    ).integral
    guard let cg = renderContext.createCGImage(image, from: rect),
          let raster = ImageMetrics.raster(cg) else { return -1 }
    var sum = 0.0
    for i in stride(from: 0, to: raster.px.count, by: 4) {
      sum += Double(raster.px[i]) * 0.299 + Double(raster.px[i + 1]) * 0.587 + Double(raster.px[i + 2]) * 0.114
    }
    return sum / Double(max(raster.count, 1))
  }

  /// The left/right luma split the noir key-shadow render carves into a uniform
  /// field lit from the left, with the SAME key light — only the field's own
  /// brightness varies. The render's gain is weighted by (1 − luma), so this is
  /// the magnitude of chiaroscuro the pass actually produces: large on a dark
  /// fill, collapsing toward zero as the fill brightens (nothing left to cut).
  private func keyShadowCarve(onWhite white: CGFloat) -> Double {
    let img = uniformCanvas(white)
    let keyLeft = LightSource(x: 0.08, y: 0.5, r: 0.04, intensity: 1, tint: [1, 1, 0.9])
    let out = FilmEngine.shared.applyKeyShadow(
      img, scene: scene(key: 0.2, lights: [keyLeft]),
      subject: SubjectAnalysis(faces: [], personMask: nil), amount: 0.7
    )
    let left = meanLuma(out, region: CGRect(x: 0.04, y: 0.33, width: 0.20, height: 0.34))
    let right = meanLuma(out, region: CGRect(x: 0.76, y: 0.33, width: 0.20, height: 0.34))
    return left - right
  }

  /// (a) keyShadow — "A key light to carve shadows from" must gate on measured
  /// directionality (a real key over a dark fill), not on mere light presence.
  /// On bright daylight the render's (1 − luma) carve budget collapses, so the
  /// noir pass sculpts no shadow; the rail must not narrate chiaroscuro there.
  func testKeyShadowClaimGatesOnDirectionalityNotLightPresence() {
    // Defect precondition: a bright daylight frame in which the meter DID find a
    // light — so the old mere-light-presence gate (`if let keyLight`) fired.
    let brightSpot = LightSource(x: 0.5, y: 0.3, r: 0.05, intensity: 0.7, tint: [1, 0.98, 0.95])
    let brightDay = scene(key: 0.62, lights: [brightSpot], dynamicRange: 0.5)
    XCTAssertNotNil(brightDay.lights.first ?? brightDay.auxLights.first,
                    "defect precondition: a light IS present, so the old mere-presence gate fired here")

    // Fix: the directional gate refuses — no chiaroscuro claim on the flat frame.
    let day = Conductor.rank(scene: brightDay, faces: [])
    let noirDay = day.first { $0.stockID == "film-noir" }!
    XCTAssertNil(noirDay.reason,
                 "fix: no 'key light to carve shadows from' claim on a flat bright frame")

    // Render inert there: with the SAME key light, the directional carve on a
    // bright fill is a small fraction of the carve on a dark one — the (1 − luma)
    // budget has collapsed, so the noir pass sculpts effectively nothing.
    let darkCarve = keyShadowCarve(onWhite: 0.45)
    let brightCarve = keyShadowCarve(onWhite: 0.90)
    XCTAssertGreaterThan(darkCarve, 12, "sanity: the pass carves real chiaroscuro on a dark fill")
    XCTAssertLessThan(brightCarve, darkCarve * 0.5,
                      "the noir carve collapses on the bright fill — the render is inert there")

    // Liveness (no dead gate): a hot key over a dark fill still earns the claim.
    let night = scene(key: 0.15, lights: [LightSource(x: 0.08, y: 0.5, r: 0.05, intensity: 1.0, tint: [1, 1, 0.9])])
    let noirNight = Conductor.rank(scene: night, faces: []).first { $0.stockID == "film-noir" }!
    XCTAssertEqual(noirNight.reason, "A key light to carve shadows from",
                   "liveness: a hot key over a dark fill still narrates the chiaroscuro")
  }

  /// (b) sourceBloom — "Found light sources to bloom" must gate on the bloom
  /// pass actually engaging, which the render decides via emissiveLights():
  /// neon does not exist under the sun, so a bright frame renders plain bloom
  /// instead of the colored source bloom. The rail mirrors that exact gate.
  func testSourceBloomClaimGatesOnEmissiveEngagementNotLightPresence() {
    // Defect precondition: daylight with a colored light present — the old
    // mere-light-presence gate would fire "Found light sources to bloom".
    let sign = LightSource(x: 0.3, y: 0.3, r: 0.06, intensity: 0.9, tint: [1.0, 0.2, 0.9])
    let brightDay = scene(key: 0.55, auxLights: [sign], sat: 0.4)
    XCTAssertFalse((brightDay.lights + brightDay.auxLights).isEmpty,
                   "defect precondition: a colored light IS present, so the old mere-presence gate fired here")

    // Render inert there: emissiveLights() — the render's own refusal gate in
    // applySourceBloom — returns empty in daylight, so only plain bloom renders.
    XCTAssertTrue(FilmEngine.emissiveLights(in: brightDay).isEmpty,
                  "render inert: neon does not exist under the sun — the colored bloom pass refuses")

    // Fix: no bloom claim, and the refused pass demotes tokyo-neon honestly.
    let day = Conductor.rank(scene: brightDay, faces: [])
    let neonDay = day.first { $0.stockID == "tokyo-neon" }!
    XCTAssertNil(neonDay.reason, "fix: no bloom claim on daylight where the pass renders plain bloom")
    let position = Dictionary(uniqueKeysWithValues: day.enumerated().map { ($1.stockID, $0) })
    XCTAssertGreaterThan(position["tokyo-neon"]!, day.count - 4,
                         "the refused bloom pass demotes tokyo-neon on daylight")
    XCTAssertGreaterThan(position["tokyo-neon"]!, position["kodachrome"]!,
                         "a daylight emulsion outranks the refused neon look")

    // Liveness (no dead gate): a colored emitter in the dark still blooms.
    let night = scene(key: 0.12, auxLights: [sign], sat: 0.45)
    XCTAssertFalse(FilmEngine.emissiveLights(in: night).isEmpty, "the emitter is emissive in the dark")
    let neonNight = Conductor.rank(scene: night, faces: []).first { $0.stockID == "tokyo-neon" }!
    XCTAssertEqual(neonNight.reason, "Found light sources to bloom",
                   "liveness: a colored source in the dark still narrates the bloom")
  }

  /// Hero-path routing is pure: the same ranking and the same gate always
  /// pick the same first-develop camera.
  func testFirstDevelopStockIDIsDeterministic() {
    let ranked = Conductor.rank(
      scene: scene(key: 0.15, auxLights: [neon]), faces: oneFace
    ).map(\.stockID)
    let unlocked: (String) -> Bool = { PlusCatalog.freeForeverStockIDs.contains($0) }
    let first = Conductor.firstDevelopStockID(ranked: ranked, isUnlocked: unlocked)
    let second = Conductor.firstDevelopStockID(ranked: ranked, isUnlocked: unlocked)
    XCTAssertEqual(first, second, "same input must always route the same camera")
    XCTAssertTrue(unlocked(first), "the pick must be a camera the user can open")
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
