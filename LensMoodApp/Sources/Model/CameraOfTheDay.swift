import Foundation

/// The Home-Screen widget's daily pick: a deterministic rotation through all
/// 18 cameras, keyed to the calendar day of the year. Pure logic — same date
/// in, same camera out — so the widget timeline, the deep link it emits, and
/// the unit tests all agree without any shared state (and therefore without
/// App Groups).
enum CameraOfTheDay {
  /// day-of-year % camera-count: consecutive days walk the rail in order and
  /// the whole set returns every 18 days.
  static func index(on date: Date, calendar: Calendar = .current) -> Int {
    let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    return dayOfYear % Stock.all.count
  }

  static func stock(on date: Date, calendar: Calendar = .current) -> Stock {
    Stock.all[index(on: date, calendar: calendar)]
  }
}
