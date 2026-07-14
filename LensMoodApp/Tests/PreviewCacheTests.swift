import UIKit
import XCTest
@testable import LensMood

/// Pins the preview cache contract: deterministic keys, hit/miss/clear, and that
/// a cached render restores both pixels and decision notes.
final class PreviewCacheTests: XCTestCase {

  private func swatch() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
      UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
  }

  func testKeyIsStableAndDistinct() {
    let photo = UUID()
    let a = PreviewCache.key(photo: photo, lens: "polaroid", edge: 1024, intensityPercent: 100)
    let b = PreviewCache.key(photo: photo, lens: "polaroid", edge: 1024, intensityPercent: 100)
    let c = PreviewCache.key(photo: photo, lens: "film-noir", edge: 1024, intensityPercent: 100)
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  func testInsertHitMissAndClear() {
    let cache = PreviewCache(countLimit: 8)
    let key = PreviewCache.key(photo: UUID(), lens: "kodachrome", edge: 1024, intensityPercent: 90)

    XCTAssertNil(cache.render(forKey: key), "cold miss")

    cache.insert(CachedRender(image: swatch(), decisions: ["Reds held dense"]), forKey: key)
    let hit = cache.render(forKey: key)
    XCTAssertNotNil(hit)
    XCTAssertEqual(hit?.decisions, ["Reds held dense"])
    XCTAssertEqual(hit?.image.size, CGSize(width: 4, height: 4))

    cache.removeAll()
    XCTAssertNil(cache.render(forKey: key), "miss after clear")
  }
}
