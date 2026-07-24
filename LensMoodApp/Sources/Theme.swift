import SwiftUI
import UIKit

/// Loose photographic resources (camcorder cover, print surface plates) are
/// bundled outside the asset catalog, and XcodeGen may place them at the
/// bundle root or under images/ depending on how the group resolves — probe
/// both before falling back to the caller's procedural stand-in.
enum BundleMedia {
  static func image(_ name: String) -> UIImage? {
    if let direct = UIImage(named: name) { return direct }
    for ext in ["jpg", "png"] {
      for subdirectory in [nil, "images", "images/art", "art"] {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
          return UIImage(contentsOfFile: url.path)
        }
      }
    }
    return nil
  }

  static func videoURL(_ name: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: "mp4")
      ?? Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "video")
  }
}

extension Color {
  init(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var hexValue: UInt64 = 0
    Scanner(string: value).scanHexInt64(&hexValue)
    let red: UInt64
    let green: UInt64
    let blue: UInt64
    switch value.count {
    case 6:
      (red, green, blue) = ((hexValue >> 16) & 0xFF, (hexValue >> 8) & 0xFF, hexValue & 0xFF)
    default:
      (red, green, blue) = (128, 128, 128)
    }
    self.init(
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255
    )
  }
}

/// Ocean darkroom palette — the owner-approved identity, ported 1:1 from the
/// reference app (`lensmood-native/src/theme/colors.ts`). Cool gray-white
/// paper, crisp white cards, one calm ocean-teal accent. The photograph stays
/// the loudest color in the room.
enum Theme {
  static let paper = Color(hex: "#EEF2F5")
  static let surface = Color(hex: "#FFFFFF")
  static let ink = Color(hex: "#17242D")
  static let inkSoft = Color(hex: "#586974")
  static let fog = Color(hex: "#6E7C86")
  static let hairline = Color(hex: "#E1E7EC")
  static let accent = Color(hex: "#0E7487")
  static let accentMid = Color(hex: "#1C8397")
  static let accentLight = Color(hex: "#39A6BB")
  static let clay = Color(hex: "#0C5568")
  static let clayDeep = Color(hex: "#083C4A")
  static let viewfinder = Color(hex: "#141A1F")
  static let viewfinderChrome = Color(hex: "#8A96A0")
  static let recRed = Color(hex: "#E1251B")

  /// glossy ocean fill — the primary action (reference `gradients.brandFill`)
  static let brandFill = LinearGradient(
    colors: [Color(hex: "#128AA0"), Color(hex: "#0C5E70")],
    startPoint: .top, endPoint: .bottom
  )
  /// deep teal → ocean → bright teal (reference `gradients.brandText`)
  static let brandText = LinearGradient(
    colors: [Color(hex: "#0C6376"), Color(hex: "#0F7D92"), Color(hex: "#2EA0B3")],
    startPoint: .leading, endPoint: .trailing
  )

  static let pagePadding: CGFloat = 14
  static let controlHeight: CGFloat = 52
  static let cardRadius: CGFloat = 18

  /// Elevation — three tiers, one scale. Depth is meaning here, not
  /// decoration: how far a surface sits from the page says what kind of thing
  /// it is. Before this scale existed the app had a single `deep:` boolean, so
  /// hierarchy read almost entirely through hairline strokes and a floating
  /// dock carried the same weight as a static card.
  ///
  /// The two existing values are preserved exactly (`.resting` is the old
  /// `oceanCardShadow()`, `.floating` the old `oceanCardShadow(deep: true)`),
  /// so every owner-approved card keeps its reference elevation to the pixel.
  /// `.well` is the new tier.
  enum Elevation {
    /// recessed — a stage the page is cut into: the photograph's dark
    /// surround, the print stage. A well does not lift, so it casts only a
    /// tight contact shade that seats it against the paper.
    case well
    /// resting — cards, mounts and panels that sit on the page
    case resting
    /// floating — surfaces genuinely off the page: the dock, transient
    /// chrome like the saved tick, and the hero objects a page is built around
    case floating

    var shadowOpacity: Double {
      switch self {
      case .well: return 0.06
      case .resting: return 0.10
      case .floating: return 0.28
      }
    }

    var shadowRadius: CGFloat {
      switch self {
      case .well: return 4
      case .resting: return 10
      case .floating: return 14
      }
    }

    var shadowOffsetY: CGFloat {
      switch self {
      case .well: return 1
      case .resting: return 4
      case .floating: return 8
      }
    }
  }
}

/// The camera instrument world, wearing the app's ocean identity: the same
/// cool charcoal family as the viewfinder wells, frosted-glass controls (grey,
/// not dead black, so the screen reads brighter), and the brand's teal as the
/// single "selected" accent — no warm cast anywhere. The photograph in the
/// viewfinder stays the loudest thing on the screen.
enum CameraTheme {
  static let bg = Color(hex: "#12181D")     // ocean charcoal surround (kin to Theme.viewfinder)
  static let panel = Color(hex: "#1A2228")  // control surface
  static let line = Color(hex: "#2C363E")   // hairline
  static let gold = Color(hex: "#39A6BB")   // brand teal "selected" accent (Theme.accentLight)
  static let goldHi = Color(hex: "#5FC3D6")
  static let text = Color(hex: "#EDF1F4")   // primary light ink
  static let dim = Color(hex: "#93A0A9")    // secondary label (dim, so the teal selection pops)
  static let faint = Color(hex: "#6B7780")  // tertiary label
}

extension View {
  /// the reference app's soft card elevation, now spoken as a three-tier
  /// scale (`Theme.Elevation`) rather than a single boolean. The ink is the
  /// reference's shadow color; only opacity, radius and offset move.
  func oceanCardShadow(_ level: Theme.Elevation = .resting) -> some View {
    shadow(
      color: Color(hex: "#02070A").opacity(level.shadowOpacity),
      radius: level.shadowRadius, x: 0, y: level.shadowOffsetY
    )
  }

  /// the original boolean idiom, kept so no call site has to change to keep
  /// its exact pixels: `deep: true` is `.floating`, `deep: false` is
  /// `.resting`. Deliberately has no default argument, so the bare
  /// `oceanCardShadow()` resolves unambiguously to the tiered form above.
  func oceanCardShadow(deep: Bool) -> some View {
    oceanCardShadow(deep ? .floating : .resting)
  }
}

// MARK: - Dynamic Type

/// Dynamic Type for the app's fixed-size typography. A plain
/// `Font.system(size:)` never follows the user's type setting, which left the
/// whole app static. This modifier keeps the exact approved point size at the
/// default content size (Large) and scales it from there with
/// `@ScaledMetric(relativeTo:)` — the supported API for scaling an arbitrary
/// base size along a text style's curve.
private struct ScaledSystemFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: Font.Weight
  private let design: Font.Design

  init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    self.weight = weight
    self.design = design
  }

  func body(content: Content) -> some View {
    content.font(.system(size: size, weight: weight, design: design))
  }
}

extension View {
  /// `.font(.system(size:weight:design:))`, but alive to Dynamic Type.
  /// `relativeTo` picks the scaling curve — pass the text style whose default
  /// point size sits closest to `size` (largeTitle 34 · title 28 · title2 22 ·
  /// title3 20 · body 17 · callout 16 · subheadline 15 · footnote 13 ·
  /// caption 12 · caption2 11). Where the fixed size exactly equals a style's
  /// default, prefer the semantic style itself (e.g. `.font(.footnote)`).
  func scaledFont(
    size: CGFloat,
    weight: Font.Weight = .regular,
    design: Font.Design = .default,
    relativeTo style: Font.TextStyle = .body
  ) -> some View {
    modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
  }
}

struct InstrumentButtonStyle: ButtonStyle {
  enum Kind {
    case primary
    case secondary
    case quiet
  }

  let kind: Kind
  // custom ButtonStyles get no automatic disabled dimming — read it and quiet
  // the control ourselves, so a disabled Save/Share reads as unavailable
  // instead of full-vibrancy-but-dead (the app's quiet visual language)
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      // 15pt semibold at the default size; subheadline's curve carries it up
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Theme.controlHeight)
      .background(background(pressed: configuration.isPressed))
      .clipShape(Capsule())
      .overlay {
        if kind == .secondary {
          Capsule().stroke(Theme.hairline, lineWidth: 1)
        }
      }
      .contentShape(Capsule())
      .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.5)
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }

  @ViewBuilder
  private func background(pressed: Bool) -> some View {
    switch kind {
    case .primary: Theme.brandFill.opacity(pressed ? 0.9 : 1)
    case .secondary: Theme.surface
    case .quiet: Color.clear
    }
  }

  private var foreground: Color {
    switch kind {
    case .primary: return .white
    case .secondary, .quiet: return Theme.ink
    }
  }
}

struct InstrumentPanel<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.hairline, lineWidth: 1)
      )
      // a panel is a resting card, and now says so. It used to separate from
      // the paper on a hairline alone, which is why depth carried no meaning
      // anywhere it was used.
      .oceanCardShadow(.resting)
  }
}

struct TechnicalLabel: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .scaledFont(size: 10, weight: .semibold, design: .monospaced, relativeTo: .caption2)
      .tracking(1.4)
      .foregroundStyle(Theme.fog)
      .accessibilityLabel(text)
  }
}
