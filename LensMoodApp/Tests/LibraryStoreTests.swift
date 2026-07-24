import XCTest
@testable import LensMood

/// The developed Library must survive relaunch. These pin the on-disk
/// persistence round-trip (save → load), downsizing, capping/prune, and delete,
/// using an isolated temp directory so nothing touches real Application Support.
final class LibraryStoreTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-librarystore-tests-\(UUID().uuidString)", isDirectory: true)
    LibraryStore.directoryOverride = tempDir
  }

  override func tearDown() {
    LibraryStore.directoryOverride = nil
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    super.tearDown()
  }

  private func plate(_ color: UIColor, size: CGSize = CGSize(width: 300, height: 400)) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { ctx in
      color.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }

  private func asset(stockID: String = "film-noir", createdAt: Date = Date()) -> DevelopedAsset {
    let img = plate(.blue)
    return DevelopedAsset(
      image: img, source: img,
      stock: Stock.find(stockID),
      decisions: ["Color removed completely", "Blacks allowed to fall"],
      createdAt: createdAt
    )
  }

  func testPersistThenLoadRoundTrips() {
    let a = asset()
    LibraryStore.persist(a)
    LibraryStore.waitForWrites()

    let loaded = LibraryStore.load()
    XCTAssertEqual(loaded.count, 1)
    let first = try? XCTUnwrap(loaded.first)
    XCTAssertEqual(first?.id, a.id)
    XCTAssertEqual(first?.stock.id, "film-noir")
    XCTAssertEqual(first?.decisions, a.decisions)
    // two-tier: only the thumbnail is resident; the stored frame is decoded
    // on demand from imageURL
    XCTAssertNil(first?.image, "loaded frames must not hold the full bitmap in memory")
    XCTAssertNotNil(first?.imageURL)
    XCTAssertNotNil(first?.loadFullImage())
  }

  func testLoadReturnsNewestFirst() {
    let older = asset(createdAt: Date(timeIntervalSince1970: 1_000))
    let newer = asset(createdAt: Date(timeIntervalSince1970: 2_000))
    LibraryStore.persist(older)
    LibraryStore.waitForWrites()
    LibraryStore.persist(newer)
    LibraryStore.waitForWrites()

    let loaded = LibraryStore.load()
    XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
  }

  func testDeleteRemovesEntryAndFile() {
    let a = asset()
    LibraryStore.persist(a)
    LibraryStore.waitForWrites()
    XCTAssertEqual(LibraryStore.loadIndex().count, 1)

    LibraryStore.delete(id: a.id)
    LibraryStore.waitForWrites()
    XCTAssertTrue(LibraryStore.load().isEmpty)
    XCTAssertTrue(LibraryStore.loadIndex().isEmpty)
  }

  func testPruneDropsFramesNotKept() {
    let keep = asset()
    let drop = asset()
    LibraryStore.persist(keep)
    LibraryStore.waitForWrites()
    LibraryStore.persist(drop)
    LibraryStore.waitForWrites()

    LibraryStore.prune(keeping: [keep.id])
    LibraryStore.waitForWrites()
    XCTAssertEqual(LibraryStore.load().map(\.id), [keep.id])
  }

  func testFavoriteFlagPersistsAndToggles() {
    let a = asset()
    LibraryStore.persist(a)
    LibraryStore.waitForWrites()
    XCTAssertEqual(LibraryStore.load().first?.favorite, false)

    LibraryStore.setFavorite(id: a.id, favorite: true)
    LibraryStore.waitForWrites()
    XCTAssertEqual(LibraryStore.load().first?.favorite, true)
    XCTAssertEqual(LibraryStore.loadIndex().count, 1, "toggling must not duplicate the entry")
  }

  func testStoredFrameIsDownsizedToBound() {
    // a frame larger than the 2048 cap must come back within bounds
    let big = plate(.red, size: CGSize(width: 4000, height: 3000))
    let a = DevelopedAsset(image: big, source: big, stock: Stock.find("kodachrome"), decisions: [])
    LibraryStore.persist(a)
    LibraryStore.waitForWrites()

    let loaded = try? XCTUnwrap(LibraryStore.load().first)
    let full = loaded?.loadFullImage()
    XCTAssertNotNil(full)
    let longest = max(full?.size.width ?? 0, full?.size.height ?? 0)
    XCTAssertLessThanOrEqual(longest, 2048 + 1)
  }

  func testLoadedThumbnailIsGridTierBounded() {
    // load() must decode only the grid tier: ≤480 px long edge, pixel-true
    let big = plate(.green, size: CGSize(width: 1600, height: 1200))
    let a = DevelopedAsset(image: big, source: big, stock: Stock.find("kodachrome"), decisions: [])
    LibraryStore.persist(a)
    LibraryStore.waitForWrites()

    let loaded = try? XCTUnwrap(LibraryStore.load().first)
    let thumb = loaded?.thumbnail
    let longest = max(
      (thumb?.size.width ?? 0) * (thumb?.scale ?? 1),
      (thumb?.size.height ?? 0) * (thumb?.scale ?? 1)
    )
    XCTAssertGreaterThan(longest, 0)
    XCTAssertLessThanOrEqual(longest, DevelopedAsset.thumbnailEdge + 1)
  }

  func testSessionAssetBuildsBoundedThumbnailAndKeepsFullFrame() {
    // a just-developed asset keeps its full frame in memory AND carries a
    // grid-tier thumbnail built at creation
    let big = plate(.yellow, size: CGSize(width: 900, height: 600))
    let a = DevelopedAsset(image: big, source: big, stock: Stock.find("polaroid"), decisions: [])
    XCTAssertNotNil(a.image)
    XCTAssertNotNil(a.source)
    XCTAssertNil(a.imageURL)
    let longest = max(a.thumbnail.size.width * a.thumbnail.scale,
                      a.thumbnail.size.height * a.thumbnail.scale)
    XCTAssertLessThanOrEqual(longest, DevelopedAsset.thumbnailEdge + 1)
  }

  func testDemotedAssetDropsBitmapsButKeepsFrameOnDisk() {
    // once a newer frame arrives, an older session asset demotes: bitmaps
    // released, frame of record readable from the store's JPEG
    let a = asset()
    LibraryStore.persist(a)
    LibraryStore.waitForWrites()

    let demoted = a.demotedToStored()
    XCTAssertEqual(demoted.id, a.id)
    XCTAssertNil(demoted.image)
    XCTAssertNil(demoted.source)
    XCTAssertEqual(demoted.imageURL, LibraryStore.frameURL(for: a.id))
    XCTAssertNotNil(demoted.loadFullImage())
  }
}
