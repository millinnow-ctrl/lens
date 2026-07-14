import CryptoKit
import Foundation

/// LensMood-owned model & Lens-pack delivery.
///
/// The corrected product mandate allows the internet — but **only** for
/// LensMood's own model/recipe/entitlement delivery, never third-party
/// per-image inference. This file is the delivery seam: manifest → download →
/// verify → install → account → remove/rollback. It is deliberately
/// **provider-based and inert by default**: with no CDN configured yet, the
/// default downloader honestly reports `.unavailable` (it never fabricates
/// progress or pretends a photo is "processing" while a model is fetched). A
/// real `URLSession`-backed downloader drops in later without touching callers.
///
/// Integrity is real today: `ModelVerifier` uses CryptoKit SHA-256, and
/// installation refuses any asset whose digest doesn't match its descriptor.

// MARK: - Records

/// A model installed on disk. Persisted in the registry index.
struct InstalledModel: Codable, Equatable {
  let modelID: String
  let version: Int
  let installedBytes: Int64
  let sha256: String
  let installedAt: Date
}

/// Lifecycle state of a deliverable model, surfaced to the UI so it can show
/// "Download" / progress / "Installed" / "Update" accurately.
enum ModelStatus: Equatable {
  case notInstalled
  case downloading(progress: Double)   // 0…1, only when a real transfer is live
  case installing
  case installed(version: Int)
  case updateAvailable(installed: Int, latest: Int)
  case failed(reason: String)
  case unavailable(reason: String)     // no provider / offline / not yet published
}

enum ModelDeliveryError: LocalizedError, Equatable {
  case noProvider
  case checksumMismatch(expected: String, actual: String)
  case insufficientStorage(needBytes: Int64, freeBytes: Int64)
  case notInstalled(String)
  case ioError(String)

  var errorDescription: String? {
    switch self {
    case .noProvider: return "No model source is configured yet."
    case let .checksumMismatch(expected, actual): return "Model integrity check failed (\(actual) ≠ \(expected))."
    case let .insufficientStorage(need, free): return "Not enough storage: need \(need) bytes, \(free) free."
    case let .notInstalled(id): return "Model \(id) is not installed."
    case let .ioError(m): return m
    }
  }
}

// MARK: - Integrity

enum ModelVerifier {
  /// Lowercase hex SHA-256 of the bytes.
  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func verify(_ data: Data, expected: String) -> Bool {
    // Case-insensitive compare; empty `expected` means "unverified stub" and is
    // rejected so a real descriptor can never ship without a digest.
    guard !expected.isEmpty else { return false }
    return sha256(data).caseInsensitiveCompare(expected) == .orderedSame
  }
}

// MARK: - Download preferences

/// User-facing delivery preferences (Settings → Storage). Persisted in
/// UserDefaults; no image content, purely transport choices.
struct StoragePreferences {
  var wifiOnlyForLargeDownloads: Bool
  var allowCellular: Bool
  /// Above this size a download waits for Wi-Fi when `wifiOnlyForLargeDownloads`.
  var largeDownloadThresholdBytes: Int64

  static let `default` = StoragePreferences(
    wifiOnlyForLargeDownloads: true,
    allowCellular: true,
    largeDownloadThresholdBytes: 75 * 1024 * 1024
  )

  private enum Keys {
    static let wifiOnly = "lensmood.delivery.wifiOnlyLarge"
    static let cellular = "lensmood.delivery.allowCellular"
    static let threshold = "lensmood.delivery.largeThreshold"
  }

  static func load(_ defaults: UserDefaults = .standard) -> StoragePreferences {
    guard defaults.object(forKey: Keys.wifiOnly) != nil else { return .default }
    return StoragePreferences(
      wifiOnlyForLargeDownloads: defaults.bool(forKey: Keys.wifiOnly),
      allowCellular: defaults.bool(forKey: Keys.cellular),
      largeDownloadThresholdBytes: defaults.object(forKey: Keys.threshold) as? Int64
        ?? StoragePreferences.default.largeDownloadThresholdBytes
    )
  }

  func save(_ defaults: UserDefaults = .standard) {
    defaults.set(wifiOnlyForLargeDownloads, forKey: Keys.wifiOnly)
    defaults.set(allowCellular, forKey: Keys.cellular)
    defaults.set(largeDownloadThresholdBytes, forKey: Keys.threshold)
  }
}

// MARK: - Downloader

/// Fetches a model asset. Concrete impls are pausable/resumable/cancellable via
/// their own handles; the protocol exposes just the terminal fetch here.
protocol ModelDownloading {
  /// Returns the local file URL of the downloaded (unverified) asset.
  func fetch(_ descriptor: RefinementModelDescriptor) async throws -> URL
}

/// The default, honest provider: no CDN is configured, so it always reports
/// `.noProvider`. Swapped for a URLSession downloader once a manifest host
/// exists. Guarantees the app never fakes a download.
struct UnavailableModelDownloader: ModelDownloading {
  func fetch(_ descriptor: RefinementModelDescriptor) async throws -> URL {
    throw ModelDeliveryError.noProvider
  }
}

// MARK: - Registry

/// Actor coordinating installed-model state, storage accounting, verification,
/// and removal. Single source of truth for "what's on disk". Network fetching
/// is delegated to the injected `ModelDownloading`.
actor ModelRegistry {
  static let shared = ModelRegistry()

  private let fileManager = FileManager.default
  private let directoryOverride: URL?
  private var downloader: ModelDownloading
  private var index: [String: InstalledModel] = [:]
  private var loaded = false

  init(directoryOverride: URL? = nil, downloader: ModelDownloading = UnavailableModelDownloader()) {
    self.directoryOverride = directoryOverride
    self.downloader = downloader
  }

  /// Swap the transport (e.g. install a real URLSession downloader at launch).
  func setDownloader(_ new: ModelDownloading) { downloader = new }

  // MARK: Storage layout

  private var modelsDirectory: URL {
    let base = directoryOverride
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("LensMood/Models", isDirectory: true)
    if !fileManager.fileExists(atPath: base.path) {
      try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }
    return base
  }

  private var indexURL: URL { modelsDirectory.appendingPathComponent("index.json") }
  private func assetURL(_ modelID: String, version: Int) -> URL {
    modelsDirectory.appendingPathComponent("\(modelID)-v\(version).mlmodelc", isDirectory: false)
  }

  private func loadIndexIfNeeded() {
    guard !loaded else { return }
    loaded = true
    guard let data = try? Data(contentsOf: indexURL),
          let decoded = try? JSONDecoder().decode([String: InstalledModel].self, from: data) else { return }
    index = decoded
  }

  private func persistIndex() {
    guard let data = try? JSONEncoder().encode(index) else { return }
    try? data.write(to: indexURL, options: .atomic)
  }

  // MARK: Queries

  func installed() -> [InstalledModel] {
    loadIndexIfNeeded()
    return index.values.sorted { $0.installedAt > $1.installedAt }
  }

  func totalBytesOnDisk() -> Int64 {
    loadIndexIfNeeded()
    return index.values.reduce(0) { $0 + $1.installedBytes }
  }

  func status(for descriptor: RefinementModelDescriptor?) -> ModelStatus {
    guard let descriptor else { return .notInstalled }
    loadIndexIfNeeded()
    guard let have = index[descriptor.modelID] else { return .notInstalled }
    if have.version < descriptor.version {
      return .updateAvailable(installed: have.version, latest: descriptor.version)
    }
    return .installed(version: have.version)
  }

  func isInstalled(_ modelID: String, atLeast version: Int) -> Bool {
    loadIndexIfNeeded()
    guard let have = index[modelID] else { return false }
    return have.version >= version
  }

  // MARK: Mutations

  /// Install an already-downloaded asset: verify digest, account bytes, move
  /// into place, and record it. Rejects a checksum mismatch outright — a corrupt
  /// or tampered model never installs.
  @discardableResult
  func install(assetAt localURL: URL, descriptor: RefinementModelDescriptor, now: Date = Date()) throws -> InstalledModel {
    loadIndexIfNeeded()
    let data = try Data(contentsOf: localURL)
    guard ModelVerifier.verify(data, expected: descriptor.sha256) else {
      throw ModelDeliveryError.checksumMismatch(expected: descriptor.sha256, actual: ModelVerifier.sha256(data))
    }
    let dest = assetURL(descriptor.modelID, version: descriptor.version)
    if fileManager.fileExists(atPath: dest.path) { try? fileManager.removeItem(at: dest) }
    do {
      try fileManager.copyItem(at: localURL, to: dest)
    } catch {
      throw ModelDeliveryError.ioError("install copy failed: \(error.localizedDescription)")
    }
    let record = InstalledModel(
      modelID: descriptor.modelID,
      version: descriptor.version,
      installedBytes: Int64(data.count),
      sha256: descriptor.sha256,
      installedAt: now
    )
    index[descriptor.modelID] = record
    persistIndex()
    return record
  }

  /// Download (via the injected provider) then install. Throws `.noProvider`
  /// under the default downloader — callers fall back to the deterministic look.
  @discardableResult
  func downloadAndInstall(_ descriptor: RefinementModelDescriptor, now: Date = Date()) async throws -> InstalledModel {
    let localURL = try await downloader.fetch(descriptor)
    return try install(assetAt: localURL, descriptor: descriptor, now: now)
  }

  /// Remove a model's on-disk asset. Does NOT revoke ownership/entitlement — a
  /// purchased Lens can always be re-downloaded (per the mandate).
  func remove(_ modelID: String) throws {
    loadIndexIfNeeded()
    guard let have = index[modelID] else { throw ModelDeliveryError.notInstalled(modelID) }
    let asset = assetURL(modelID, version: have.version)
    if fileManager.fileExists(atPath: asset.path) {
      do { try fileManager.removeItem(at: asset) }
      catch { throw ModelDeliveryError.ioError("remove failed: \(error.localizedDescription)") }
    }
    index[modelID] = nil
    persistIndex()
  }
}
