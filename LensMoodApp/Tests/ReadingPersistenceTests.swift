import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// Persisting the reading with the develop: a photograph's develop record
/// carries the SceneReading it was developed with, so a later re-develop
/// replays that exact reading instead of a drifted re-read (Vision output is
/// not bit-stable across separate runs or OS updates). These pin the three
/// guarantees that make that safe — the serialization round-trips masks and
/// scene exactly (byte-identical develop), the LibraryStore sidecar survives
/// the disk round-trip, and an engine-schema mismatch falls back to a fresh
/// read rather than half-applying a stale reading.
final class ReadingPersistenceTests: XCTestCase {

  // MARK: - Fixtures (same committed matte path as MaskedLightRenderTests)

  private static let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
  private static let repoRoot = testsDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private func matteURL(_ name: String) -> URL {
    Self.testsDirectory.appendingPathComponent("Fixtures/mattes/\(name)")
  }

  private func sourceImage(_ name: String) throws -> UIImage {
    let url = Self.repoRoot.appendingPathComponent("reference/photos/\(name)")
    return try XCTUnwrap(UIImage(contentsOfFile: url.path), "missing fixture photo \(name)")
  }

  /// A reading whose subject pass ran on a committed fixture matte (the
  /// simulator's Vision segmentation is degenerate) — so subjectMatte / skin /
  /// sky are real, materialized masks with committed raw bytes to serialize.
  private func maskedReading(engine: FilmEngine) throws -> (UIImage, SceneReading) {
    let source = try sourceImage("sample-friends.jpg")
    let reading = try MatteInjection.reading(
      source: source, mattePNG: matteURL("friends-person.png"), engine: engine
    )
    return (source, reading)
  }

  // MARK: - Determinism: a deserialized reading develops byte-identically

  /// The core law: freezing a reading to `PersistedReading`, sending it through
  /// JSON (as the sidecar does), and rebuilding it yields a reading that
  /// develops the photograph byte-for-byte the same as the original in-memory
  /// reading. The masks and scene round-trip exactly.
  func testDeserializedReadingDevelopsByteIdentically() throws {
    let engine = FilmEngine()
    let (source, original) = try maskedReading(engine: engine)

    // the fixture must actually carry masks, or this proves nothing
    XCTAssertNotNil(original.subject.subjectMatte, "fixture reading must have a subject matte")
    XCTAssertNotNil(original.subject.skinMask, "fixture reading must have a skin mask")

    let record = PersistedReading(original, osBuild: "test")
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(PersistedReading.self, from: data)
    let replayed = try XCTUnwrap(decoded.makeReading(), "current-schema reading must rebuild")

    // scene scalars survive JSON exactly (a 1-ULP drift would split the render)
    XCTAssertEqual(original.scene, replayed.scene, "scene meter must round-trip exactly")
    // the derived masks came back (not both-nil, which would pass vacuously)
    XCTAssertNotNil(replayed.subject.subjectMatte)
    XCTAssertNotNil(replayed.subject.skinMask)

    // stocks that consume the derived masks (rim / skin / sky) but never the
    // person matte — so the dropped person matte cannot explain any match
    for stockID in ["kodachrome", "leica-street"] {
      let recipe = CameraRecipe.recipe(for: stockID)
      let fromOriginal = try engine.develop(source, with: recipe, seed: 7, reading: original).image
      let fromReplayed = try engine.develop(source, with: recipe, seed: 7, reading: replayed).image
      XCTAssertEqual(
        fromOriginal.pngData(), fromReplayed.pngData(),
        "\(stockID): a develop from the deserialized reading must be byte-identical"
      )
    }
  }

  // MARK: - LibraryStore sidecar round-trip

  func testLibraryStoreReadingSidecarRoundTrips() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-reading-tests-\(UUID().uuidString)", isDirectory: true)
    LibraryStore.directoryOverride = tempDir
    defer {
      LibraryStore.directoryOverride = nil
      try? FileManager.default.removeItem(at: tempDir)
    }

    let engine = FilmEngine()
    let (source, original) = try maskedReading(engine: engine)
    let id = UUID()

    XCTAssertNil(LibraryStore.loadReading(for: id), "no sidecar yet")
    LibraryStore.persistReading(original, for: id)
    LibraryStore.waitForWrites()

    let loaded = try XCTUnwrap(LibraryStore.loadReading(for: id), "sidecar must load back")
    XCTAssertEqual(original.scene, loaded.scene)

    let recipe = CameraRecipe.recipe(for: "kodachrome")
    let fromOriginal = try engine.develop(source, with: recipe, seed: 7, reading: original).image
    let fromDisk = try engine.develop(source, with: recipe, seed: 7, reading: loaded).image
    XCTAssertEqual(
      fromOriginal.pngData(), fromDisk.pngData(),
      "a reading recovered from the sidecar must develop byte-identically"
    )

    // the sidecar follows its frame out on delete
    LibraryStore.delete(id: id)
    LibraryStore.waitForWrites()
    XCTAssertNil(LibraryStore.loadReading(for: id), "delete must remove the reading sidecar")
  }

  // MARK: - Schema mismatch falls back to a fresh read (never a half-apply)

  func testSchemaMismatchYieldsNilReading() throws {
    let engine = FilmEngine()
    let (_, original) = try maskedReading(engine: engine)
    let record = PersistedReading(original, osBuild: "test")
    let data = try JSONEncoder().encode(record)

    // bump the stamp to a schema this build does not recognize
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    object["schema"] = ReadingSchema.version + 1
    let tampered = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(PersistedReading.self, from: tampered)
    XCTAssertNil(
      decoded.makeReading(),
      "a reading from a foreign engine schema must refuse to rebuild"
    )
  }

  func testLibraryStoreIgnoresForeignSchemaSidecar() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-reading-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    LibraryStore.directoryOverride = tempDir
    defer {
      LibraryStore.directoryOverride = nil
      try? FileManager.default.removeItem(at: tempDir)
    }

    let engine = FilmEngine()
    let (_, original) = try maskedReading(engine: engine)
    let record = PersistedReading(original, osBuild: "test")
    let data = try JSONEncoder().encode(record)
    var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["schema"] = ReadingSchema.version + 1
    let tampered = try JSONSerialization.data(withJSONObject: object)

    let id = UUID()
    // write straight to the sidecar path the store uses
    let url = tempDir.appendingPathComponent("\(id.uuidString).reading")
    try tampered.write(to: url)

    XCTAssertNil(
      LibraryStore.loadReading(for: id),
      "a stale-schema sidecar must load as nil so the caller reads fresh"
    )
  }

  // MARK: - Conductor adoption respects the live cache + LRU

  private func scene(key: Double) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.02, p50: key, p99: 0.98, illum: [1, 1, 1],
      sat: 0.35, lights: [], auxLights: [], faceLum: nil,
      meanLuminance: key, medianLuminance: key,
      shadowFraction: 0.1, highlightFraction: 0.1, dynamicRange: 0.5,
      averageRed: 0.5, averageGreen: 0.5, averageBlue: 0.5, saturation: 0.35,
      warmth: 0, isLowKey: false, isHighKey: false, isBacklit: false
    )
  }

  private func reading(key: Double) -> SceneReading {
    SceneReading(scene: scene(key: key), subject: SubjectAnalysis(faces: [], personMask: nil))
  }

  @MainActor
  func testAdoptSeedsAnEmptyKeyButNeverClobbersALiveReading() async {
    let conductor = Conductor()
    let key = UUID()
    XCTAssertNil(conductor.cachedReading(for: key))

    conductor.adopt(reading(key: 0.20), key: key)
    XCTAssertEqual(conductor.cachedReading(for: key)?.scene.key, 0.20, "adopt seeds an empty key")

    // a second adopt must not overwrite the reading the active session holds
    conductor.adopt(reading(key: 0.80), key: key)
    XCTAssertEqual(
      conductor.cachedReading(for: key)?.scene.key, 0.20,
      "adopt must never clobber a reading already in the cache"
    )
  }

  @MainActor
  func testAdoptedReadingsParticipateInTheLRUCap() async {
    let conductor = Conductor()
    var keys: [UUID] = []
    for i in 0..<5 {
      let key = UUID()
      keys.append(key)
      conductor.adopt(reading(key: Double(i) / 10 + 0.1), key: key)
    }
    XCTAssertNil(conductor.cachedReading(for: keys[0]), "oldest adopted reading evicted at the cap")
    XCTAssertNotNil(conductor.cachedReading(for: keys[4]))
  }
}
