import Foundation

/// A roll is one calendar month of developed photographs. The Library reads
/// like a box of film sleeves: newest roll first, newest frame first inside
/// each sleeve, every sleeve named like a film artifact
/// ("JULY 2026 · 14 EXPOSURES").
///
/// Pure grouping logic lives here (no UIKit) so it is unit-testable with an
/// injected `Calendar`; `GalleryView` only renders the result.
struct Roll: Identifiable {
  /// stable per-month id ("2026-07") so section identity survives reloads
  let id: String
  /// the first instant of the roll's month (ordering anchor)
  let monthStart: Date
  /// the sleeve's artifact name, e.g. "JULY 2026"
  let title: String
  /// the roll's frames, newest first
  let assets: [DevelopedAsset]

  var exposureCount: Int { assets.count }

  /// the full sleeve caption, e.g. "JULY 2026 · 14 EXPOSURES"
  var sleeveLabel: String {
    "\(title) · \(exposureCount) \(exposureCount == 1 ? "EXPOSURE" : "EXPOSURES")"
  }

  /// Group developed frames into monthly rolls, newest month first; frames
  /// inside each roll are newest first. An empty library yields no rolls.
  static func group(_ assets: [DevelopedAsset], calendar: Calendar = .current) -> [Roll] {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    if let locale = calendar.locale { formatter.locale = locale }
    // standalone month name + year — the sleeve reads like a printed label
    formatter.dateFormat = "LLLL yyyy"

    var byMonth: [Date: [DevelopedAsset]] = [:]
    for asset in assets {
      let components = calendar.dateComponents([.year, .month], from: asset.createdAt)
      guard let monthStart = calendar.date(from: components) else { continue }
      byMonth[monthStart, default: []].append(asset)
    }

    return byMonth
      .sorted { $0.key > $1.key }
      .map { monthStart, frames in
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        return Roll(
          id: String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0),
          monthStart: monthStart,
          title: formatter.string(from: monthStart).uppercased(with: formatter.locale),
          assets: frames.sorted { $0.createdAt > $1.createdAt }
        )
      }
  }
}
