import UIKit

/// A small, bounded cache of finished lens renders for the current photo, so
/// switching back to a lens the user already viewed is instant instead of a full
/// re-develop (the audit's dominant lens-browsing cost: every switch re-runs the
/// whole `FilmEngine` pipeline).
///
/// Keyed by (photo session, lens, proxy edge, intensity bucket) so a cached
/// entry is only reused for an identical render request. Bounded by count;
/// `NSCache` also evicts automatically under memory pressure.
final class PreviewCache {
  static let shared = PreviewCache()

  private let cache = NSCache<NSString, CachedRender>()

  init(countLimit: Int = 24, totalCostBytes: Int = 192 * 1024 * 1024) {
    cache.countLimit = countLimit
    // byte-cost bound as well as count: 24 × 2048px renders would otherwise
    // rely entirely on memory-pressure eviction
    cache.totalCostLimit = totalCostBytes
  }

  func render(forKey key: String) -> CachedRender? {
    cache.object(forKey: key as NSString)
  }

  func insert(_ render: CachedRender, forKey key: String) {
    let pixelWidth = Int(render.image.size.width * render.image.scale)
    let pixelHeight = Int(render.image.size.height * render.image.scale)
    cache.setObject(render, forKey: key as NSString, cost: pixelWidth * pixelHeight * 4)
  }

  func removeAll() {
    cache.removeAllObjects()
  }

  /// Stable cache key. `photo` is a per-import session id so a new photo never
  /// collides with a prior one; `intensityPercent` buckets the strength slider
  /// so near-identical strengths share a render.
  static func key(photo: UUID, lens: String, edge: Int, intensityPercent: Int) -> String {
    "\(photo.uuidString)|\(lens)|\(edge)|\(intensityPercent)"
  }
}

/// A finished render worth caching: the developed image plus the analysis-
/// derived decision notes it produced (so a cache hit restores the full editor
/// state, not just the pixels).
final class CachedRender {
  let image: UIImage
  let decisions: [String]

  init(image: UIImage, decisions: [String]) {
    self.image = image
    self.decisions = decisions
  }
}
