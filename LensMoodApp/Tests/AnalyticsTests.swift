import XCTest
@testable import LensMood

/// Pins the event taxonomy and the privacy invariant: analytics carries only
/// ids/counts/flags — never image content or long strings.
final class AnalyticsTests: XCTestCase {
  func testEventNamesAndProperties() {
    XCTAssertEqual(AnalyticsEvent.appOpened.name, "app_opened")
    XCTAssertEqual(AnalyticsEvent.developFinished(lookID: "film-noir", ms: 1200).name, "develop_finished")
    XCTAssertEqual(
      AnalyticsEvent.developFinished(lookID: "film-noir", ms: 1200).properties,
      ["look_id": "film-noir", "ms": "1200"]
    )
    XCTAssertEqual(AnalyticsEvent.favoriteToggled(on: true).properties, ["on": "true"])
    XCTAssertEqual(AnalyticsEvent.photoShared.properties, [:])
  }

  func testPropertiesAreNeverContentSized() {
    let events: [AnalyticsEvent] = [
      .appOpened, .developStarted(lookID: "x"), .developFinished(lookID: "x", ms: 1),
      .photoSaved(lookID: "x"), .photoShared, .favoriteToggled(on: false),
      .paywallViewed(surface: "post_value"),
    ]
    for event in events {
      for (_, value) in event.properties {
        XCTAssertLessThan(value.count, 64, "\(event.name) property looks like content, not an id/count")
      }
    }
  }

  func testSinkReceivesLoggedEvents() {
    final class Spy: AnalyticsSink {
      var names: [String] = []
      func log(_ event: AnalyticsEvent) { names.append(event.name) }
    }
    let spy = Spy()
    let previous = Analytics.sink
    Analytics.sink = spy
    defer { Analytics.sink = previous }

    Analytics.log(.photoShared)
    Analytics.log(.photoSaved(lookID: "kodachrome"))
    XCTAssertEqual(spy.names, ["photo_shared", "photo_saved"])
  }
}
