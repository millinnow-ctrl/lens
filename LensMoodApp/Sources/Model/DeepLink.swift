import Foundation

/// The `lensmood://` URL vocabulary — the contract between the widgets and
/// the app. Parsing is pure and strict: any URL that is not a known route,
/// or that names a camera the rail does not carry, returns nil so callers
/// never route on garbage.
enum DeepLink: Equatable {
  /// lensmood://develop/<stockID> — land on the Cameras tab and push that
  /// camera's develop view (the `AppModel.pendingStock` hand-off idiom).
  case develop(stockID: String)

  static let scheme = "lensmood"

  static func parse(_ url: URL) -> DeepLink? {
    guard url.scheme?.lowercased() == scheme else { return nil }
    guard url.host?.lowercased() == "develop" else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }
    guard let stockID = components.first,
          Stock.all.contains(where: { $0.id == stockID })
    else { return nil }
    return .develop(stockID: stockID)
  }

  /// The widget-facing builder — always round-trips through `parse`
  /// (pinned in CitizenshipTests).
  static func developURL(for stockID: String) -> URL? {
    URL(string: "\(scheme)://develop/\(stockID)")
  }
}
