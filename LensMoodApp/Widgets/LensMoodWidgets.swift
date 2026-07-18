import SwiftUI
import WidgetKit

// LensMood on the Home and Lock Screen (WidgetKit + SwiftUI): "Camera of the
// day" — a deterministic daily rotation through the 18-camera rail
// (`CameraOfTheDay`, day-of-year % 18). Deliberately self-contained: camera
// metadata + gradients only, no photographs and no shared container, so the
// widgets need no App Groups and no entitlements at all. Tapping any family
// deep-links into the app: lensmood://develop/<stockID>.

// MARK: - Timeline

struct CameraDayEntry: TimelineEntry {
  let date: Date
  let stock: Stock
}

struct CameraDayProvider: TimelineProvider {
  func placeholder(in context: Context) -> CameraDayEntry {
    CameraDayEntry(date: Date(), stock: CameraOfTheDay.stock(on: Date()))
  }

  func getSnapshot(in context: Context, completion: @escaping (CameraDayEntry) -> Void) {
    completion(placeholder(in: context))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CameraDayEntry>) -> Void) {
    // one entry now, then one per midnight for a week; WidgetKit re-asks at
    // the end of the window (`.atEnd`)
    let calendar = Calendar.current
    let now = Date()
    let today = calendar.startOfDay(for: now)
    var entries = [CameraDayEntry(date: now, stock: CameraOfTheDay.stock(on: now))]
    for offset in 1..<7 {
      guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
      entries.append(CameraDayEntry(date: day, stock: CameraOfTheDay.stock(on: day)))
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

// MARK: - iOS 16/17 background shim

private extension View {
  /// iOS 17 requires `containerBackground(for: .widget)`; iOS 16 (the floor)
  /// draws the same background directly.
  @ViewBuilder
  func widgetSurface<S: ShapeStyle>(_ style: S) -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(style, for: .widget)
    } else {
      background(style)
    }
  }

  /// iOS 17 supplies system content margins; iOS 16 widgets pad themselves.
  @ViewBuilder
  func legacyWidgetPadding(_ length: CGFloat = 14) -> some View {
    if #available(iOS 17.0, *) {
      self
    } else {
      padding(length)
    }
  }
}

// MARK: - Home-Screen families

struct CameraDayHomeView: View {
  // not `private`: that would drag the synthesized memberwise init down to
  // private and hide it from the widget declarations below
  @Environment(\.widgetFamily) var family
  let entry: CameraDayEntry

  private var stock: Stock { entry.stock }

  /// the camera's signature gradient swatch, straight from Stock metadata
  private var swatch: LinearGradient {
    LinearGradient(
      colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  var body: some View {
    Group {
      if family == .systemMedium { medium } else { small }
    }
    .legacyWidgetPadding()
    .widgetSurface(Theme.surface)
    .widgetURL(DeepLink.developURL(for: stock.id))
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(swatch)
        .overlay(
          Image(systemName: stock.symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        )
        .frame(maxHeight: .infinity)
      Text("CAMERA OF THE DAY")
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .tracking(1.0)
        .foregroundStyle(Theme.fog)
      Text(stock.name)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text(stock.tagline)
        .font(.system(size: 10))
        .foregroundStyle(Theme.inkSoft)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Camera of the day: \(stock.name). \(stock.tagline)")
  }

  private var medium: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(swatch)
        .frame(width: 96)
        .overlay(
          VStack(spacing: 8) {
            Image(systemName: stock.symbol)
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(.white.opacity(0.92))
              .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Text(stock.exif)
              .font(.system(size: 7, weight: .semibold, design: .monospaced))
              .foregroundStyle(.white.opacity(0.85))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .padding(.horizontal, 4)
          }
        )
      VStack(alignment: .leading, spacing: 4) {
        TechnicalLabel(text: "Camera of the day")
        Text(stock.name)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(stock.tagline)
          .font(.system(size: 12))
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(2)
        Spacer(minLength: 0)
        HStack(spacing: 4) {
          Image(systemName: "camera.aperture")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.accent)
          Text(stock.bestFor)
            .font(.system(size: 10))
            .foregroundStyle(Theme.fog)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Camera of the day: \(stock.name). \(stock.tagline). Best for \(stock.bestFor)")
  }
}

// MARK: - Lock Screen / StandBy accessory families (iOS 16 WidgetKit)

struct CameraDayAccessoryView: View {
  @Environment(\.widgetFamily) var family
  let entry: CameraDayEntry

  var body: some View {
    Group {
      if family == .accessoryRectangular {
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 3) {
            Image(systemName: "camera.aperture")
              .font(.system(size: 10, weight: .semibold))
            Text("LENSMOOD")
              .font(.system(size: 10, weight: .semibold, design: .monospaced))
              .tracking(0.8)
          }
          Text(entry.stock.name)
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
          Text("Camera of the day")
            .font(.system(size: 11))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        // accessoryCircular: the aperture glyph on the system's soft plate
        ZStack {
          AccessoryWidgetBackground()
          Image(systemName: "camera.aperture")
            .font(.system(size: 22, weight: .medium))
        }
      }
    }
    .widgetSurface(Color.clear)
    .widgetURL(DeepLink.developURL(for: entry.stock.id))
    .accessibilityLabel("LensMood camera of the day: \(entry.stock.name)")
  }
}

// MARK: - Widget declarations

struct CameraOfTheDayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "LensMoodCameraOfTheDay",
      provider: CameraDayProvider()
    ) { entry in
      CameraDayHomeView(entry: entry)
    }
    .configurationDisplayName("Camera of the Day")
    .description("A different film camera every day — tap to develop with it.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct CameraOfTheDayAccessoryWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "LensMoodCameraOfTheDayAccessory",
      provider: CameraDayProvider()
    ) { entry in
      CameraDayAccessoryView(entry: entry)
    }
    .configurationDisplayName("LensMood")
    .description("Today's camera at a glance.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}

@main
struct LensMoodWidgetBundle: WidgetBundle {
  var body: some Widget {
    CameraOfTheDayWidget()
    CameraOfTheDayAccessoryWidget()
  }
}
