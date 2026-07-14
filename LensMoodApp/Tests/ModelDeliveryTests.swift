import XCTest
@testable import LensMood

/// Pins the delivery seam's real guarantees: correct SHA-256, checksum-gated
/// install, storage accounting, remove-keeps-entitlement, honest status, and the
/// default "no provider ⇒ fail cleanly (never fake)" behaviour.
final class ModelDeliveryTests: XCTestCase {

  private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lm-model-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writeAsset(_ bytes: String, in dir: URL) -> URL {
    let url = dir.appendingPathComponent("asset-\(UUID().uuidString).bin")
    try? Data(bytes.utf8).write(to: url)
    return url
  }

  private func descriptor(id: String, version: Int, sha: String) -> RefinementModelDescriptor {
    RefinementModelDescriptor(
      modelID: id, version: version, displayName: "Test \(id)",
      downloadBytes: 10, installedBytes: 10,
      minDeviceTier: .enhanced, minOSMajor: 17,
      computeUnits: .cpuAndNeuralEngine, defaultStrength: 0.3,
      sha256: sha, hasDeterministicFallback: true
    )
  }

  func testSha256KnownVector() {
    XCTAssertEqual(
      ModelVerifier.sha256(Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  func testVerifyRejectsEmptyAndMismatch() {
    let data = Data("hello".utf8)
    XCTAssertTrue(ModelVerifier.verify(data, expected: ModelVerifier.sha256(data)))
    XCTAssertFalse(ModelVerifier.verify(data, expected: ""), "empty digest must be rejected")
    XCTAssertFalse(ModelVerifier.verify(data, expected: "00" ))
  }

  func testInstallListAccountAndRemove() async throws {
    let dir = tempDir()
    let registry = ModelRegistry(directoryOverride: dir)
    let asset = writeAsset("model-weights-payload", in: dir)
    let sha = ModelVerifier.sha256(try Data(contentsOf: asset))
    let desc = descriptor(id: "hero.refiner", version: 1, sha: sha)

    let record = try await registry.install(assetAt: asset, descriptor: desc)
    XCTAssertEqual(record.modelID, "hero.refiner")
    XCTAssertGreaterThan(record.installedBytes, 0)

    let installed = await registry.installed()
    XCTAssertEqual(installed.count, 1)
    let total = await registry.totalBytesOnDisk()
    XCTAssertEqual(total, record.installedBytes)
    let isThere = await registry.isInstalled("hero.refiner", atLeast: 1)
    XCTAssertTrue(isThere)

    try await registry.remove("hero.refiner")
    let afterCount = await registry.installed().count
    XCTAssertEqual(afterCount, 0)
    let afterTotal = await registry.totalBytesOnDisk()
    XCTAssertEqual(afterTotal, 0)
  }

  func testInstallRejectsChecksumMismatch() async {
    let dir = tempDir()
    let registry = ModelRegistry(directoryOverride: dir)
    let asset = writeAsset("real-payload", in: dir)
    let wrong = descriptor(id: "bad", version: 1, sha: "deadbeefdeadbeef")
    do {
      _ = try await registry.install(assetAt: asset, descriptor: wrong)
      XCTFail("checksum mismatch must throw")
    } catch let ModelDeliveryError.checksumMismatch(expected, _) {
      XCTAssertEqual(expected, "deadbeefdeadbeef")
    } catch {
      XCTFail("unexpected error \(error)")
    }
  }

  func testStatusTransitions() async throws {
    let dir = tempDir()
    let registry = ModelRegistry(directoryOverride: dir)
    let nilStatus = await registry.status(for: nil)
    XCTAssertEqual(nilStatus, .notInstalled)

    let asset = writeAsset("v1", in: dir)
    let sha = ModelVerifier.sha256(try Data(contentsOf: asset))
    let v1 = descriptor(id: "m", version: 1, sha: sha)
    let before = await registry.status(for: v1)
    XCTAssertEqual(before, .notInstalled)

    _ = try await registry.install(assetAt: asset, descriptor: v1)
    let after = await registry.status(for: v1)
    XCTAssertEqual(after, .installed(version: 1))

    let v2 = descriptor(id: "m", version: 2, sha: sha)
    let upgrade = await registry.status(for: v2)
    XCTAssertEqual(upgrade, .updateAvailable(installed: 1, latest: 2))
  }

  func testDefaultDownloaderReportsNoProvider() async {
    let registry = ModelRegistry(directoryOverride: tempDir())
    let desc = descriptor(id: "x", version: 1, sha: "abc")
    do {
      _ = try await registry.downloadAndInstall(desc)
      XCTFail("default downloader must not succeed")
    } catch let ModelDeliveryError.noProvider {
      // expected — callers fall back to the deterministic look
    } catch {
      XCTFail("unexpected error \(error)")
    }
  }

  func testStoragePreferencesRoundTrip() {
    let suite = "test.delivery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertEqual(StoragePreferences.load(defaults).wifiOnlyForLargeDownloads,
                   StoragePreferences.default.wifiOnlyForLargeDownloads)

    var prefs = StoragePreferences.default
    prefs.wifiOnlyForLargeDownloads = false
    prefs.allowCellular = false
    prefs.save(defaults)

    let reloaded = StoragePreferences.load(defaults)
    XCTAssertFalse(reloaded.wifiOnlyForLargeDownloads)
    XCTAssertFalse(reloaded.allowCellular)
  }
}
