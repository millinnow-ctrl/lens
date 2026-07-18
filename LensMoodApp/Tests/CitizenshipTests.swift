import XCTest
@testable import LensMood

/// iOS-citizenship logic pins: the widget's camera-of-the-day rotation and
/// the lensmood:// deep-link contract are pure functions — locked here with a
/// fixed calendar so neither the simulator's locale nor its time zone can
/// move the schedule, and the URL vocabulary shared by the widgets and the
/// app can never drift apart silently.
final class CitizenshipTests: XCTestCase {
  /// fixed gregorian/UTC/en_US_POSIX calendar (same idiom as RollTests)
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  // MARK: Camera of the day

  func testCameraOfTheDayFollowsDayOfYearModulo() {
    // Jan 1 is day-of-year 1 → index 1; Jan 17 → 17; Jan 18 wraps to 0
    XCTAssertEqual(CameraOfTheDay.index(on: date(2026, 1, 1), calendar: calendar), 1)
    XCTAssertEqual(CameraOfTheDay.index(on: date(2026, 1, 17), calendar: calendar), 17)
    XCTAssertEqual(CameraOfTheDay.index(on: date(2026, 1, 18), calendar: calendar), 0)
    XCTAssertEqual(
      CameraOfTheDay.stock(on: date(2026, 1, 1), calendar: calendar).id,
      Stock.all[1].id
    )
  }

  func testCameraOfTheDayIsDeterministicWithinADay() {
    let morning = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 0, minute: 1))!
    let night = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 23, minute: 59))!
    XCTAssertEqual(
      CameraOfTheDay.stock(on: morning, calendar: calendar).id,
      CameraOfTheDay.stock(on: night, calendar: calendar).id
    )
  }

  func testCameraOfTheDayCoversAllEighteenCamerasInEighteenDays() {
    var seen = Set<String>()
    for offset in 0..<Stock.all.count {
      let day = calendar.date(byAdding: .day, value: offset, to: date(2026, 3, 1))!
      seen.insert(CameraOfTheDay.stock(on: day, calendar: calendar).id)
    }
    XCTAssertEqual(seen.count, Stock.all.count)
  }

  func testCameraOfTheDayChangesAcrossConsecutiveDays() {
    let today = CameraOfTheDay.stock(on: date(2026, 7, 18), calendar: calendar)
    let tomorrow = CameraOfTheDay.stock(on: date(2026, 7, 19), calendar: calendar)
    XCTAssertNotEqual(today.id, tomorrow.id)
  }

  // MARK: Deep links

  func testDeepLinkRoundTripsForEveryCamera() throws {
    for stock in Stock.all {
      let url = try XCTUnwrap(DeepLink.developURL(for: stock.id))
      XCTAssertEqual(DeepLink.parse(url), .develop(stockID: stock.id))
    }
  }

  func testDeepLinkRejectsForeignAndMalformedURLs() throws {
    let rejected = [
      "lensmood://develop/not-a-camera",
      "lensmood://develop/",
      "lensmood://develop",
      "lensmood://library",
      "https://develop/polaroid",
      "lensmood://",
    ]
    for candidate in rejected {
      let url = try XCTUnwrap(URL(string: candidate))
      XCTAssertNil(DeepLink.parse(url), "should reject \(candidate)")
    }
  }

  func testDeepLinkToleratesSchemeAndHostCase() throws {
    let url = try XCTUnwrap(URL(string: "LENSMOOD://DEVELOP/polaroid"))
    XCTAssertEqual(DeepLink.parse(url), .develop(stockID: "polaroid"))
  }

  @MainActor
  func testDeepLinkRoutesToCamerasTabWithPendingStock() throws {
    let model = AppModel(environment: ["LENSMOOD_TAB": "library"])
    XCTAssertEqual(model.selectedTab, .library)
    model.open(url: try XCTUnwrap(URL(string: "lensmood://develop/tokyo-neon")))
    XCTAssertEqual(model.selectedTab, .cameras)
    XCTAssertEqual(model.pendingStock?.id, "tokyo-neon")
    XCTAssertNil(model.pendingDevelopImage)
  }

  @MainActor
  func testForeignURLLeavesRoutingUntouched() throws {
    let model = AppModel(environment: ["LENSMOOD_TAB": "library"])
    model.open(url: try XCTUnwrap(URL(string: "lensmood://develop/not-a-camera")))
    XCTAssertEqual(model.selectedTab, .library)
    XCTAssertNil(model.pendingStock)
  }

  // MARK: Copy hygiene for sources outside Sources/

  /// The extension targets compile from ShareExtension/ and Widgets/, which
  /// the Sources/ sweep in FilmEngineTests never visits — hold them to the
  /// same standard.
  func testExtensionSourcesKeepCopyHygiene() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let forbiddenPattern = #"(?i)\b(ai|artificial intelligence|machine learning)\b"#
    for folder in ["ShareExtension", "Widgets"] {
      let directory = projectRoot.appendingPathComponent(folder)
      let enumerator = try XCTUnwrap(
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
      )
      var scanned = 0
      for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertNil(
          source.range(of: forbiddenPattern, options: .regularExpression),
          "Visible product source contains forbidden labeling in \(fileURL.lastPathComponent)"
        )
        scanned += 1
      }
      XCTAssertGreaterThan(scanned, 0, "\(folder)/ should contain Swift sources")
    }
  }
}
