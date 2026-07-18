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
    XCTAssertNotNil(first?.image)
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
    let longest = max(loaded?.image.size.width ?? 0, loaded?.image.size.height ?? 0)
    XCTAssertLessThanOrEqual(longest, 2048 + 1)
  }
}
