import ImageIO
import UIKit

/// On-disk persistence for the developed Library so it survives relaunch, and a
/// memory guard: frames are stored downsized (≤`maxEdge`) as JPEG, and `load()`
/// decodes only a grid-tier thumbnail per frame (ImageIO downsample, ≤480 px) —
/// the stored 2048 px frame is decoded on demand via `DevelopedAsset.loadFullImage()`
/// when a detail view, print, or save actually needs it.
///
/// Only the *developed* frame is persisted — the original `source` is transient
/// (used during in-camera review) and is never written. `Stock` is
/// reconstructed from its stable id via `Stock.find`.
struct StoredAsset: Codable {
  let id: UUID
  let stockID: String
  let decisions: [String]
  let createdAt: Date
  let favorite: Bool

  init(id: UUID, stockID: String, decisions: [String], createdAt: Date, favorite: Bool) {
    self.id = id
    self.stockID = stockID
    self.decisions = decisions
    self.createdAt = createdAt
    self.favorite = favorite
  }

  // backward-compatible: index files written before favorites lack the key
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    stockID = try c.decode(String.self, forKey: .stockID)
    decisions = try c.decode([String].self, forKey: .decisions)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
  }
}

enum LibraryStore {
  /// Tests point this at a temp directory; production uses Application Support.
  static var directoryOverride: URL?

  private static let maxEdge: CGFloat = 2048
  private static let jpegQuality: CGFloat = 0.9

  private static var dir: URL {
    let base = directoryOverride ?? FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LensMoodLibrary", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }

  private static var indexURL: URL { dir.appendingPathComponent("index.json") }
  private static func imageURL(_ id: UUID) -> URL {
    dir.appendingPathComponent("\(id.uuidString).jpg")
  }

  /// Where a frame's stored 2048 px JPEG lives (or will live once its queued
  /// write lands) — used when a session asset demotes to the stored tier.
  static func frameURL(for id: UUID) -> URL {
    imageURL(id)
  }

  // MARK: - Index

  static func loadIndex() -> [StoredAsset] {
    guard let data = try? Data(contentsOf: indexURL),
          let list = try? JSONDecoder().decode([StoredAsset].self, from: data)
    else { return [] }
    return list
  }

  private static func writeIndex(_ list: [StoredAsset]) {
    guard let data = try? JSONEncoder().encode(list) else { return }
    try? data.write(to: indexURL, options: .atomic)
  }

  // MARK: - High-level

  /// Persisted assets, newest first, with `Stock` reconstructed by id.
  /// Two-tier: only a grid thumbnail is decoded per frame; the stored 2048 px
  /// JPEG stays on disk behind `imageURL` for on-demand decode.
  static func load() -> [DevelopedAsset] {
    loadIndex()
      .sorted { $0.createdAt > $1.createdAt }
      .compactMap { entry in
        let url = imageURL(entry.id)
        guard let thumbnail = decodeThumbnail(at: url) else { return nil }
        return DevelopedAsset(
          id: entry.id,
          thumbnail: thumbnail,
          imageURL: url,
          stock: Stock.find(entry.stockID),
          decisions: entry.decisions,
          createdAt: entry.createdAt,
          favorite: entry.favorite
        )
      }
  }

  /// ImageIO downsample: decode the stored JPEG straight to the grid tier
  /// (long edge ≤ `DevelopedAsset.thumbnailEdge`) without ever materializing
  /// the full 2048 px bitmap in memory.
  private static func decodeThumbnail(at url: URL) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: DevelopedAsset.thumbnailEdge,
    ] as [CFString: Any] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }

  /// All writes run on one serial utility queue: develop taps stay hitch-free
  /// (the 2048px downscale + JPEG encode used to run on the main thread), and
  /// serial ordering keeps persist→prune sequences race-free.
  private static let ioQueue = DispatchQueue(label: "app.lensmood.library-io", qos: .utility)

  /// Test hook: block until every queued write has landed on disk.
  static func waitForWrites() {
    ioQueue.sync {}
  }

  /// Write one asset's developed frame + index entry (idempotent per id).
  /// Only session assets carry the full frame; a loaded/demoted asset's frame
  /// of record is already this store's JPEG, so persisting it is a no-op.
  static func persist(_ asset: DevelopedAsset) {
    guard let frame = asset.image else { return }
    ioQueue.async {
      if let data = downscaled(frame).jpegData(compressionQuality: jpegQuality) {
        try? data.write(to: imageURL(asset.id), options: .atomic)
      }
      var index = loadIndex().filter { $0.id != asset.id }
      index.append(StoredAsset(
        id: asset.id,
        stockID: asset.stock.id,
        decisions: asset.decisions,
        createdAt: asset.createdAt,
        favorite: asset.favorite
      ))
      writeIndex(index)
    }
  }

  /// Flip a stored asset's favorite flag in place (no image rewrite).
  static func setFavorite(id: UUID, favorite: Bool) {
    ioQueue.async {
      let updated = loadIndex().map { entry -> StoredAsset in
        guard entry.id == id else { return entry }
        return StoredAsset(
          id: entry.id, stockID: entry.stockID, decisions: entry.decisions,
          createdAt: entry.createdAt, favorite: favorite
        )
      }
      writeIndex(updated)
    }
  }

  static func delete(id: UUID) {
    ioQueue.async {
      try? FileManager.default.removeItem(at: imageURL(id))
      writeIndex(loadIndex().filter { $0.id != id })
    }
  }

  /// Drop any on-disk frames whose ids are no longer kept in memory (the roll
  /// is capped, so trimmed frames should not linger on disk).
  static func prune(keeping ids: [UUID]) {
    ioQueue.async {
      let keep = Set(ids)
      for entry in loadIndex() where !keep.contains(entry.id) {
        try? FileManager.default.removeItem(at: imageURL(entry.id))
      }
      writeIndex(loadIndex().filter { keep.contains($0.id) })
    }
  }

  // MARK: - Helpers

  /// Bound a frame's longest edge so stored/reloaded bitmaps stay memory-safe.
  private static func downscaled(_ image: UIImage) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxEdge else { return image }
    let scale = maxEdge / longest
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
