import Foundation

/// Privacy-conscious, vendor-agnostic product analytics seam.
///
/// Only event names, look ids, counts, and durations are ever logged — **never
/// the photo, image content, or any personal data**. The default sink is a
/// no-op (there is no backend yet, and the app ships zero networking); a real
/// provider can be dropped in behind `AnalyticsSink` without touching call
/// sites. Adding any networked provider must also update
/// `Resources/PrivacyInfo.xcprivacy`.
enum AnalyticsEvent {
  case appOpened
  case developStarted(lookID: String)
  case developFinished(lookID: String, ms: Int)
  case photoSaved(lookID: String)
  case photoShared
  case favoriteToggled(on: Bool)
  case paywallViewed(surface: String)

  /// Stable, business-oriented event name (snake_case).
  var name: String {
    switch self {
    case .appOpened: return "app_opened"
    case .developStarted: return "develop_started"
    case .developFinished: return "develop_finished"
    case .photoSaved: return "photo_saved"
    case .photoShared: return "photo_shared"
    case .favoriteToggled: return "favorite_toggled"
    case .paywallViewed: return "paywall_viewed"
    }
  }

  /// Non-identifying properties only (ids/counts/durations/flags).
  var properties: [String: String] {
    switch self {
    case .appOpened, .photoShared:
      return [:]
    case let .developStarted(lookID):
      return ["look_id": lookID]
    case let .developFinished(lookID, ms):
      return ["look_id": lookID, "ms": String(ms)]
    case let .photoSaved(lookID):
      return ["look_id": lookID]
    case let .favoriteToggled(on):
      return ["on": on ? "true" : "false"]
    case let .paywallViewed(surface):
      return ["trigger_surface": surface]
    }
  }
}

protocol AnalyticsSink {
  func log(_ event: AnalyticsEvent)
}

/// The shipping default: does nothing (no backend, no networking). Prints in
/// DEBUG so the taxonomy is inspectable while developing.
struct NoopAnalyticsSink: AnalyticsSink {
  func log(_ event: AnalyticsEvent) {
    #if DEBUG
    print("analytics · \(event.name) \(event.properties)")
    #endif
  }
}

/// The single entry point call sites use; swap `sink` to attach a provider.
enum Analytics {
  static var sink: AnalyticsSink = NoopAnalyticsSink()
  static func log(_ event: AnalyticsEvent) { sink.log(event) }
}
