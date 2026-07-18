import XCTest
@testable import LensMood

/// The Library's story structure: developed frames group into monthly rolls,
/// newest roll first, newest frame first inside each roll, each sleeve named
/// like a film artifact ("JULY 2026 · 14 EXPOSURES"). Grouping is pure logic
/// (`Roll.group`), pinned here with a fixed calendar so month names and
/// boundaries are deterministic.
final class RollTests: XCTestCase {
  /// fixed gregorian/UTC/en_US_POSIX calendar so labels never depend on the
  /// simulator's locale or time zone
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private func plate() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 8, height: 10)).image { ctx in
      UIColor.blue.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 10))
    }
  }

  private func asset(stockID: String = "leica-street", createdAt: Date) -> DevelopedAsset {
    let img = plate()
    return DevelopedAsset(
      image: img, source: img,
      stock: Stock.find(stockID),
      decisions: ["Available light held"],
      createdAt: createdAt
    )
  }

  func testGroupsByCalendarMonthNewestRollFirst() {
    let july = asset(createdAt: date(2026, 7, 12))
    let juneA = asset(createdAt: date(2026, 6, 3))
    let juneB = asset(createdAt: date(2026, 6, 28))
    let december = asset(createdAt: date(2025, 12, 31))

    let rolls = Roll.group([juneA, december, july, juneB], calendar: calendar)

    XCTAssertEqual(rolls.map(\.id), ["2026-07", "2026-06", "2025-12"])
    XCTAssertEqual(rolls.map(\.exposureCount), [1, 2, 1])
  }

  func testFramesInsideRollAreNewestFirst() {
    let early = asset(createdAt: date(2026, 7, 2))
    let late = asset(createdAt: date(2026, 7, 30))
    let middle = asset(createdAt: date(2026, 7, 15))

    let rolls = Roll.group([early, late, middle], calendar: calendar)

    XCTAssertEqual(rolls.count, 1)
    XCTAssertEqual(rolls[0].assets.map(\.id), [late.id, middle.id, early.id])
  }

  func testSleeveLabelReadsLikeFilmArtifact() {
    let rolls = Roll.group(
      [asset(createdAt: date(2026, 7, 1)), asset(createdAt: date(2026, 7, 20))],
      calendar: calendar
    )
    XCTAssertEqual(rolls.first?.title, "JULY 2026")
    XCTAssertEqual(rolls.first?.sleeveLabel, "JULY 2026 · 2 EXPOSURES")
  }

  func testSingleFrameRollUsesSingularExposure() {
    let rolls = Roll.group([asset(createdAt: date(2026, 1, 9))], calendar: calendar)
    XCTAssertEqual(rolls.first?.sleeveLabel, "JANUARY 2026 · 1 EXPOSURE")
  }

  func testMonthBoundaryFallsOnCalendarMonths() {
    // last instant of June vs first of July — one minute apart, two rolls
    let endOfJune = asset(createdAt: calendar.date(
      from: DateComponents(year: 2026, month: 6, day: 30, hour: 23, minute: 59)
    )!)
    let startOfJuly = asset(createdAt: calendar.date(
      from: DateComponents(year: 2026, month: 7, day: 1, hour: 0, minute: 0)
    )!)

    let rolls = Roll.group([endOfJune, startOfJuly], calendar: calendar)
    XCTAssertEqual(rolls.map(\.id), ["2026-07", "2026-06"])
  }

  func testEmptyLibraryYieldsNoRolls() {
    XCTAssertTrue(Roll.group([], calendar: calendar).isEmpty)
  }

  /// rolls must regroup identically after relaunch: `createdAt` round-trips
  /// through LibraryStore's on-disk index, so a persisted frame lands back in
  /// the same monthly sleeve
  func testRollGroupingSurvivesPersistenceRoundTrip() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-rolltests-\(UUID().uuidString)", isDirectory: true)
    LibraryStore.directoryOverride = tempDir
    defer {
      LibraryStore.directoryOverride = nil
      try? FileManager.default.removeItem(at: tempDir)
    }

    let julyFrame = asset(createdAt: date(2026, 7, 12))
    let juneFrame = asset(createdAt: date(2026, 6, 5))
    LibraryStore.persist(julyFrame)
    LibraryStore.persist(juneFrame)

    let rolls = Roll.group(LibraryStore.load(), calendar: calendar)
    XCTAssertEqual(rolls.map(\.id), ["2026-07", "2026-06"])
    XCTAssertEqual(rolls.first?.assets.first?.id, julyFrame.id)
    XCTAssertEqual(rolls.first?.assets.first?.stock.id, "leica-street")
    XCTAssertEqual(rolls.first?.assets.first?.decisions, ["Available light held"])
  }
}
