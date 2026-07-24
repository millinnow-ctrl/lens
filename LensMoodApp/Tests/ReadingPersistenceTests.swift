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

  // MARK: - Original persistence (the live re-develop replay source)

  /// A flat solid image at an exact pixel size — used to prove the stored
  /// original is bounded (an oversized source must come back downscaled).
  private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(
      size: CGSize(width: width, height: height), format: format
    ).image { ctx in
      UIColor.systemTeal.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  private func withTempStore(_ body: () throws -> Void) rethrows {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-original-tests-\(UUID().uuidString)", isDirectory: true)
    LibraryStore.directoryOverride = tempDir
    defer {
      LibraryStore.directoryOverride = nil
      try? FileManager.default.removeItem(at: tempDir)
    }
    try body()
  }

  /// The stored original round-trips and is bounded: an oversized source is
  /// written back downscaled (≤ 2048 px long edge), decoded on demand.
  func testPersistedOriginalRoundTripsBounded() throws {
    try withTempStore {
      let oversized = solidImage(width: 3000, height: 2000)   // > 2048 long edge
      let asset = DevelopedAsset(
        image: oversized, source: oversized,
        stock: Stock.find("kodachrome"), decisions: []
      )
      LibraryStore.persist(asset)
      LibraryStore.waitForWrites()

      let url = LibraryStore.originalURL(for: asset.id)
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "original must be written")

      let reloaded = try XCTUnwrap(UIImage(contentsOfFile: url.path), "original must decode back")
      let longest = max(reloaded.size.width * reloaded.scale, reloaded.size.height * reloaded.scale)
      XCTAssertLessThanOrEqual(longest, 2048, "the stored original must be bounded ≤ 2048 px")
      XCTAssertLessThan(longest, 3000, "an oversized source must actually be downscaled")
    }
  }

  /// The live replay guarantee: after a disk round-trip, the SAME persisted
  /// original developed with the SAME persisted reading reproduces the develop
  /// byte-for-byte — and matches the reading held in memory (proving the
  /// reading half did not drift). This is the R80 proof extended to include
  /// the source pixels, so a re-develop of a kept frame after relaunch is
  /// byte-stable end to end.
  func testReDevelopFromPersistedOriginalAndReadingIsByteStable() throws {
    try withTempStore {
      let engine = FilmEngine()
      let (source, original) = try maskedReading(engine: engine)
      let asset = DevelopedAsset(
        image: source, source: source,
        stock: Stock.find("kodachrome"), decisions: []
      )
      LibraryStore.persist(asset)
      LibraryStore.persistReading(original, for: asset.id)
      LibraryStore.waitForWrites()

      let originalURL = LibraryStore.originalURL(for: asset.id)
      let originalFromDisk = try XCTUnwrap(
        UIImage(contentsOfFile: originalURL.path), "persisted original must decode"
      )
      let readingFromDisk = try XCTUnwrap(
        LibraryStore.loadReading(for: asset.id), "persisted reading must load"
      )

      let recipe = CameraRecipe.recipe(for: "kodachrome")
      // develop the disk original with the disk reading, and with the in-memory
      // reading — same source pixels, so any difference would be reading drift
      let replayDiskReading = try engine.develop(
        originalFromDisk, with: recipe, seed: 7, reading: readingFromDisk
      ).image
      let replayMemoryReading = try engine.develop(
        originalFromDisk, with: recipe, seed: 7, reading: original
      ).image
      XCTAssertEqual(
        replayDiskReading.pngData(), replayMemoryReading.pngData(),
        "the persisted reading must replay byte-identically over the persisted original"
      )

      // and an independent second reload of the original develops identically —
      // the source pixels themselves round-trip deterministically
      let originalReloaded = try XCTUnwrap(UIImage(contentsOfFile: originalURL.path))
      let replaySecondLoad = try engine.develop(
        originalReloaded, with: recipe, seed: 7, reading: readingFromDisk
      ).image
      XCTAssertEqual(
        replayDiskReading.pngData(), replaySecondLoad.pngData(),
        "the persisted original must decode to the same pixels every relaunch"
      )
    }
  }

  /// Missing-sidecar fallback: a keep with no stored original (old keep, or a
  /// schema-gated reading) decodes to nil rather than crashing — the caller
  /// (shoot-this-film-again) then falls back to picking a photograph.
  func testMissingOriginalSidecarFallsBackToNil() throws {
    try withTempStore {
      let id = UUID()
      // a disk-restored asset whose original file was never written
      let asset = DevelopedAsset(
        id: id,
        thumbnail: solidImage(width: 100, height: 125),
        imageURL: LibraryStore.frameURL(for: id),
        originalURL: LibraryStore.originalURL(for: id),
        stock: Stock.find("kodachrome"),
        decisions: [], createdAt: Date(), favorite: false
      )
      XCTAssertNil(asset.loadOriginalImage(), "no stored original ⇒ nil, never a crash")
      XCTAssertNil(LibraryStore.loadReading(for: id), "no reading sidecar either")
    }
  }

  /// Delete removes the stored original along with the frame + reading.
  func testDeleteRemovesStoredOriginal() throws {
    try withTempStore {
      let image = solidImage(width: 800, height: 1000)
      let asset = DevelopedAsset(
        image: image, source: image, stock: Stock.find("kodachrome"), decisions: []
      )
      LibraryStore.persist(asset)
      LibraryStore.waitForWrites()
      let url = LibraryStore.originalURL(for: asset.id)
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

      LibraryStore.delete(id: asset.id)
      LibraryStore.waitForWrites()
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: url.path),
        "delete must remove the stored original"
      )
    }
  }

  /// Prune (the 48-frame cap) removes the original of any frame that fell off
  /// the roll, and keeps the originals of frames that survive.
  func testPruneRemovesDroppedOriginalsAndKeepsSurvivors() throws {
    try withTempStore {
      let keptImage = solidImage(width: 600, height: 750)
      let droppedImage = solidImage(width: 600, height: 750)
      let kept = DevelopedAsset(
        image: keptImage, source: keptImage, stock: Stock.find("kodachrome"), decisions: []
      )
      let dropped = DevelopedAsset(
        image: droppedImage, source: droppedImage, stock: Stock.find("kodachrome"), decisions: []
      )
      LibraryStore.persist(kept)
      LibraryStore.persist(dropped)
      LibraryStore.waitForWrites()

      LibraryStore.prune(keeping: [kept.id])
      LibraryStore.waitForWrites()

      XCTAssertTrue(
        FileManager.default.fileExists(atPath: LibraryStore.originalURL(for: kept.id).path),
        "a surviving frame keeps its original"
      )
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: LibraryStore.originalURL(for: dropped.id).path),
        "a pruned frame's original is removed"
      )
    }
  }

  /// Two-tier memory law: a session asset carries its original in memory, but
  /// once demoted it holds no resident bitmaps — the original is decoded from
  /// disk on demand instead (its `originalURL` points at the stored JPEG).
  func testDemotedAssetHoldsNoResidentOriginal() throws {
    let image = solidImage(width: 400, height: 500)
    let session = DevelopedAsset(
      image: image, source: image, stock: Stock.find("kodachrome"), decisions: []
    )
    XCTAssertNotNil(session.source, "a live session asset holds its original in memory")

    let demoted = session.demotedToStored()
    XCTAssertNil(demoted.source, "a demoted frame must not keep the original resident")
    XCTAssertNil(demoted.image, "a demoted frame must not keep the full frame resident")
    XCTAssertNotNil(demoted.originalURL, "a demoted frame's original is on disk, decoded on demand")
    XCTAssertEqual(demoted.originalURL, LibraryStore.originalURL(for: session.id))
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
